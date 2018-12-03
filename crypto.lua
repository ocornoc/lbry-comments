local ffi = require "ffi"
local bit = require "bit"

-------------------------------------------------------------------------------
-- Options

-- The path to the file containing the keypair generation seed
local kseedfile_path = "seed"

-------------------------------------------------------------------------------
-- Declarations

local sodium = assert(ffi.load("sodium", false))

ffi.cdef[[
 // core.h
int sodium_init(void) __attribute__ ((warn_unused_result));

 // crypto_sign_ed25519.h
struct crypto_sign_ed25519ph_state;
size_t crypto_sign_ed25519ph_statebytes(void);
size_t crypto_sign_ed25519_bytes(void);
size_t crypto_sign_ed25519_seedbytes(void);
size_t crypto_sign_ed25519_publickeybytes(void);
size_t crypto_sign_ed25519_secretkeybytes(void);
size_t crypto_sign_ed25519_messagebytes_max(void);
int crypto_sign_ed25519_detached(unsigned char *sig,
                                 unsigned long long *siglen_p,
                                 const unsigned char *m,
                                 unsigned long long mlen,
                                 const unsigned char *sk)
            __attribute__ ((nonnull(1, 3)));
int crypto_sign_ed25519_seed_keypair(unsigned char *pk, unsigned char *sk,
                                     const unsigned char *seed)
            __attribute__ ((nonnull));
int crypto_sign_ed25519ph_init(struct crypto_sign_ed25519ph_state *state)
            __attribute__ ((nonnull));
int crypto_sign_ed25519ph_update(struct crypto_sign_ed25519ph_state *state,
                                 const unsigned char *m,
                                 unsigned long long mlen)
            __attribute__ ((nonnull));
int crypto_sign_ed25519ph_final_create(struct crypto_sign_ed25519ph_state *state,
                                       unsigned char *sig,
                                       unsigned long long *siglen_p,
                                       const unsigned char *sk)
            __attribute__ ((nonnull));

 // utils.h
size_t sodium_base64_encoded_len(const size_t bin_len, const int variant);
char *sodium_bin2base64(char * const b64, const size_t b64_maxlen,
                        const unsigned char * const bin, const size_t bin_len,
                        const int variant) __attribute__ ((nonnull));
int sodium_mlock(void * const addr, const size_t len)
            __attribute__ ((nonnull));
int sodium_munlock(void * const addr, const size_t len)
            __attribute__ ((nonnull));
void *sodium_malloc(const size_t size)
            __attribute__ ((malloc));
void sodium_free(void *ptr);
int sodium_mprotect_noaccess(void *ptr) __attribute__ ((nonnull));
int sodium_mprotect_readonly(void *ptr) __attribute__ ((nonnull));
int sodium_mprotect_readwrite(void *ptr) __attribute__ ((nonnull));
]]

-- crypto_sign_ed25519.h macros and size definitions
local sign_statebytes  = tonumber(sodium.crypto_sign_ed25519ph_statebytes())
local sign_bytes       = tonumber(sodium.crypto_sign_ed25519_bytes())
local sign_seedbytes   = tonumber(sodium.crypto_sign_ed25519_seedbytes())
local sign_pkbytes     = tonumber(sodium.crypto_sign_ed25519_publickeybytes())
local sign_skbytes     = tonumber(sodium.crypto_sign_ed25519_secretkeybytes())

-- utils.h Base64 variants
-- "_np" means "no padding"
local b64_original     = 1
local b64_original_np  = 3
local b64_urlsafe      = 5
local b64_urlsafe_np   = 7

assert(sodium.sodium_init() == 0, "libsodium failed to initialize")

-------------------------------------------------------------------------------
-- Padding

-- This is a very basic zero-padding function. It won't truncate the result.
local function zeropad_loose(str, to_len)
	local pad_needed = to_len - str:len()
	
	if pad_needed > 0 then
		return str .. ("\000"):rep(pad_needed)
	else
		return str
	end
end

-- This is a very basic zero-padding function. It truncates the result.
local function zeropad_strict(str, to_len)
	local pad_needed = to_len - str:len()
	
	if pad_needed > 0 then
		return str .. ("\000"):rep(pad_needed)
	elseif pad_needed < 0 then
		return str:sub(1, 32)
	else
		return str
	end
end

-------------------------------------------------------------------------------
-- Safe allocation of specific types.

-- Uses sodium's malloc (secure memory) in order to safely allocated C objects.
-- Returns a pointer of given type 'p_type' of size 'size'.
local function sod_unsafe_gc(p_type, size)
	local new_p = ffi.new(p_type, sodium.sodium_malloc(size))
	ffi.gc(new_p, sodium.sodium_free)
	
	return new_p
end

-- A more safe version of 'sod_unsafe_gc', as it will scream in agony if the
--   pointer returns as NULL.
local function sod_gc(p_type, size)
	local new_p = sod_unsafe_gc(p_type, size)
	assert(tonumber(new_p) ~= 0, "Failed to allocate pointer of type '" ..
	       p_type .. "' and size '" .. tonumber(size) .. "'")
	
	return new_p
end

-------------------------------------------------------------------------------
-- Base64

-- Returns the length of the Base64-encoded version of an amount of bytes
--   'size' and optional variant 'variant' (defaults to b64_original).
local function b64_len(size, variant)
	variant = variant or b64_original
	assert(type(variant) == "number",
	       "'variant' must be a 'b64_*' variant")
	assert(variant == b64_original or variant == b64_original_np or
	       variant == b64_urlsafe  or variant == b64_urlsafe_np,
	       "'variant' isn't a recognized variant option")
	
	return tonumber(sodium.sodium_base64_encoded_len(size, variant))
end

-- Returns a string containing the Base64-encoded version of string 'message'
--   using optional variant 'variant' (defaults to b64_original). Must be
--   given 'message_len' IFF 'message' isn't a Lua string.
local function b64_encode(message, message_len, variant)
	variant = variant or b64_original
	assert(type(message) == "string" or type(message_len) == "number",
	       "'message' wasn't a Lua string but 'message_len' wasn't a " ..
	       "valid length")
	if type(message) == "string" and not message_len then
		message_len = message:len()
	end
	
	-- We don't have to write an assert for 'variant' being a number
	--   because b64_len already has one. ;)
	local encoded_len = b64_len(message_len, variant)
	local encoded_msg = sod_gc("unsigned char * const", encoded_len)
	sodium.sodium_bin2base64(encoded_msg, encoded_len, message,
	                         message_len, variant)
	
	return ffi.string(encoded_msg, encoded_len)
end

-------------------------------------------------------------------------------
-- Keypair setup

-- Our public and secret keys.
local pk = sod_gc("unsigned char *", sign_pkbytes)
local sk = sod_gc("unsigned char *", sign_skbytes)
-- Our seed for the keypair generation.
local kseed = sod_gc("unsigned char *", sign_seedbytes)

-- Get the kseed file and copy the seed to kseed.
local kseedfile = assert(io.open(kseedfile_path, "rb"))
-- The seed will be the first 32 bytes of the file. If there are less than that,
-- the result gets zero-padded.
local kseedfile_data = assert(kseedfile:read(sign_seedbytes))
kseedfile_data = zeropad_strict(kseedfile_data, sign_seedbytes)
kseedfile:close()
ffi.copy(kseed, kseedfile_data, sign_seedbytes)
kseedfile_data = nil

-- Generate the keypair from the seed.
assert(sodium.crypto_sign_ed25519_seed_keypair(pk, sk, kseed) == 0,
       "Failed to generate keypair")
-- Make sure we can and are enforcing memory security for the keys and seeds.
assert(sodium.sodium_mprotect_readonly(pk) == 0,
       "Couldn't RO-protect the public key")
assert(sodium.sodium_mprotect_noaccess(sk) == 0,
       "Couldn't full-protect the secret key")
-- We want to disable access to kseed while we wait for the garbage collector
-- to clean it up. We don't need (and therefore really don't want) the seed
-- hanging around.
assert(sodium.sodium_mprotect_noaccess(kseed) == 0,
       "Couldn't full-protect the key seed")
kseed = nil

if _G.crypto_lib_print then
	print("Generated keypair from seed.")

	-- Print the Base64 of the public key.
	print("Public key (Base64): " .. b64_encode(pk, sign_pkbytes))
end

-------------------------------------------------------------------------------
-- Signing setup

local _M = {}
local ull_size = ffi.sizeof(ffi.new("unsigned long long", 0))

-------------------------------------------------------------------------------
-- Ed25519ph state object for high-level multipart signing

-- If it starts with "__", it's meant for private usage, as usual.
local sign_state_mt = {}
-- Prototypes and default values
local sign_state_proto = {}
-- !!! PRIVATE STUFF !!!
-- Allows for a prototype.
sign_state_mt.__index = sign_state_proto

-- Disallows setting of values not in the prototype.
function sign_state_mt.__newindex(self, k, v)
	-- We check explicitly for nil rather than using truthiness because
	--   the prototype value could be false.
	if sign_state_proto[k] ~= nil then
		rawset(self, k, v)
	else
		error "You cannot arbitrarily set values in a sign object"
	end
end

-- Just a non-nil value to hold the place of the state.
sign_state_proto.__state = 1
-- A value describing whether the state is initialized.
sign_state_proto.__state_is_init = false

-- Creates and initializes new state object.
function sign_state_proto.__new_state(self)
	self.__state = sod_gc("struct crypto_sign_ed25519ph_state *",
	                      sign_statebytes)
	
	
	local success = sodium.crypto_sign_ed25519ph_init(self.__state)
	assert(success == 0, "Failed to initialize Ed25519ph state")
	
	self.__state_is_init = true
end

-- Updates the state object with some text.
-- self.__state must be initialized and created and not finalized.
function sign_state_proto.__upd_state(self, message)
	assert(type(message) == "string",
	       "Got a " .. type(message) .. ", need a string")
	assert(self.__state_is_init,
	       "State attempted update but isn't initialized")
	
	local success = sodium.crypto_sign_ed25519ph_update(
	                 self.__state,
			 message,
			 message:len()
			)
	
	assert(success == 0, "Failed to update signing object.")
end

-- Finalizes the state object and returns the signature.
-- self.__state must be initialized and created and not finalized.
function sign_state_proto.__fin_state(self)
	assert(self.__state_is_init,
	       "State attempted finalization but isn't initialized")
	-- Allow our secret key to be read.
	assert(sodium.sodium_mprotect_readonly(sk) == 0,
	       "Couldn't RO-protect the secret key")
	
	local sig = sod_gc("unsigned char *", sign_bytes)
	local sig_len = sod_gc("unsigned long long *", ull_size)
	assert(sodium.crypto_sign_ed25519ph_final_create(
	        self.__state,
		sig,
		sig_len,
		sk
	      ) == 0, "Failed to get the signature from Ed25519ph state")
	-- Re-protect the secret key.
	assert(sodium.sodium_mprotect_noaccess(sk) == 0,
	       "Couldn't full-protect the secret key")
	
	-- We've got to signal that the state is invalid now.
	self.__state_is_init = false
	self.__state = 1
	-- We have to cast sig_len because it is actually a void pointer, not
	-- a ULL pointer.
	local length = tonumber(ffi.new("unsigned long long *", sig_len)[0])
	return ffi.string(sig, length)
end

-- Given a Lua string signature 'sig' that is 'sign_bytes' long, returns whether
--   the public key used in the object and the signature verify the text that
--   has been inserted into the object. The object will require re-init.
function sign_state_proto.__ver_state(self, sig)
	assert(type(sig) == "string", "'sig' must be a string, but is a '" ..
	       type(sig) .. "'")
	assert(sig:len() == sign_bytes, "'sig' must be " .. sign_bytes ..
	       " bytes long, but is " .. sig:len() .. " bytes long")
	
	-- Lua strings can't be implicitly converted to pointers of non-const
	--   chars, so we have to copy the string ourselves.
	local sig_copy = sod_gc("unsigned char *", sign_bytes)
	ffi.copy(sig_copy, sig, sign_bytes)
	
	return crypto_sign_ed25519ph_final_verify(
	        self.__state,
		sig_copy,
		pk
	       ) == 0
end

-- !!! PUBLIC STUFF !!!

-- Returns whether the state is initialized.
function sign_state_proto.is_initialized(self)
	return self.__is_state_init
end
-- An alias for the above function.
sign_state_proto.is_init = sign_state_proto.is_initialized

-- Returns the object with the state initialized. DOES NOT COPY. If the state
--   is already initialized, it doesn't reset it.
function sign_state_proto.initialize(self)
	if not self:is_initialized() then
		self:__new_state()
	end

	return self
end
-- An alias for the above function.
sign_state_proto.init = sign_state_proto.initialize

-- Returns the object with the state force-initialized. DOES NOT COPY.
function sign_state_proto.reset(self)
	self:__new_state()
	
	return self
end

-- Returns the object with the state updated to have new text inserted. DOES
--   NOT COPY.
function sign_state_proto.insert(self, message)
	self:__upd_state(message)
	
	return self
end

-- Returns the signature of the object. Automatically reinitializes it.
function sign_state_proto.get_signature(self)
	local result = self:__fin_state()
	self:init()
	
	return result
end
-- An alias for the above function.
sign_state_proto.sign = sign_state_proto.get_signature

-- Given a Lua string signature 'sig' that is 'sign_bytes' long, returns whether
--   the public key used in the object and the signature verify the text that
--   has been inserted into the object. Automatically reinitializes the object.
function sign_state_proto.verify(self, sig)
	local result = self:__ver_state(sig)
	self:init()
	
	return result
end

-- Constructor for the high-level signing object. Automatically initializes it.
function _M.new_sign_object()
	return setmetatable({}, sign_state_mt):init()
end

-------------------------------------------------------------------------------
-- Signing functions

-- Returns the signature of a message.
function _M.sign(message)
	-- message must be a string.
	assert(type(message) == "string",
	       "Got a " .. type(message) .. ", need a string")
	-- Allow our secret key to be read.
	assert(sodium.sodium_mprotect_readonly(sk) == 0,
	       "Couldn't RO-protect the secret key")
	-- Allocate space for the signature and its length.
	local sig = sod_gc("unsigned char *", sign_bytes)
	local sig_len = sod_gc("unsigned long long *", ull_size)
	assert(sodium.crypto_sign_ed25519_detached(sig, sig_len, message,
	                                           message:len(), sk) == 0,
	       "Failed to sign a message")
	-- Re-protect the secret key.
	assert(sodium.sodium_mprotect_noaccess(sk) == 0,
	       "Couldn't full-protect the secret key")
	
	-- We have to cast sig_len because it is actually a void pointer, not
	-- a ULL pointer.
	local length = tonumber(ffi.new("unsigned long long *", sig_len)[0])
	return ffi.string(sig, length)
end

-- Returns the public key.
function _M.get_pubkey()
	return ffi.string(pk, sign_pkbytes)
end

-------------------------------------------------------------------------------
-- Goodbye!

return _M
