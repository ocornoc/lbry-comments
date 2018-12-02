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

-- export.h macros
-- called "SODIUM_SIZE_MAX" originally
local sodium_size_max = 0ULL - 1

-- crypto_sign_ed25519.h macros and size definitions
local sign_statebytes  = tonumber(sodium.crypto_sign_ed25519ph_statebytes())
local sign_bytes       = tonumber(sodium.crypto_sign_ed25519_bytes())
local sign_seedbytes   = tonumber(sodium.crypto_sign_ed25519_seedbytes())
local sign_pkbytes     = tonumber(sodium.crypto_sign_ed25519_publickeybytes())
local sign_skbytes     = tonumber(sodium.crypto_sign_ed25519_secretkeybytes())
local sign_messagebytes_max = sodium_size_max - sign_bytes

assert(sodium.sodium_init() == 0ULL, "libsodium failed to initialize")

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
local function sod_gc(p_type, size)
	local new_p = ffi.new(p_type, sodium.sodium_malloc(size))
	ffi.gc(new_p, sodium.sodium_free)
	
	return new_p
end

-------------------------------------------------------------------------------
-- Keypair setup

-- Our public and secret keys. Forces use of sodium's secure memory.
local pk = ffi.gc(sodium.sodium_malloc(sign_pkbytes), sodium.sodium_free)
local sk = ffi.gc(sodium.sodium_malloc(sign_skbytes), sodium.sodium_free)
-- Our seed for the keypair generation.
local kseed = ffi.gc(sodium.sodium_malloc(sign_seedbytes), sodium.sodium_free)
-- sodium's malloc returns NULL on failure, so check for a good allocation.
assert(tonumber(pk) ~= 0, "Failed to allocate the public key")
assert(tonumber(sk) ~= 0, "Failed to allocate the secret key")
assert(tonumber(kseed) ~= 0, "Failed to allocate the key seed")

-- Get the kseed file and copy the seed to kseed.
local kseedfile = assert(io.open(kseedfile_path, "rb"))
-- The seed will be the first 32 bytes of the file. If there are less than that,
-- the result gets zero-padded.
local kseedfile_data = zeropad_strict(assert(kseedfile:read(tonumber(sign_seedbytes))), sign_seedbytes)
kseedfile:close()
ffi.copy(kseed, kseedfile_data, sign_seedbytes)
kseedfile_data = nil

-- Generate the keypair from the seed.
assert(sodium.crypto_sign_ed25519_seed_keypair(pk, sk, kseed) == 0, "Failed to generate keypair")
-- Make sure we can and are enforcing memory security for the keys and seeds.
assert(sodium.sodium_mprotect_readonly(pk) == 0, "Couldn't RO-protect the public key")
assert(sodium.sodium_mprotect_noaccess(sk) == 0, "Couldn't full-protect the secret key")
-- We want to disable access to kseed while we wait for the garbage collector
-- to clean it up. We don't need (and therefore really don't want) the seed
-- hanging around.
assert(sodium.sodium_mprotect_noaccess(kseed) == 0, "Couldn't full-protect the key seed")
kseed = nil
print("Generated keypair from seed.")

-- Print the Base64 of the public key.
local pk_b64_bytes = b64_length(sign_pkbytes, b64_original)
local pk_b64 = ffi.gc(sodium.sodium_malloc(pk_b64_bytes), sodium.sodium_free)
assert(tonumber(pk_b64) ~= 0, "Failed to allocate the public key Base64 string")
sodium.sodium_bin2base64(pk_b64, pk_b64_bytes, pk, sign_pkbytes, tonumber(b64_original))
print("Public key (Base64): " .. ffi.string(pk_b64, pk_b64_bytes))
-- We want to disable access to the Base64 key explicitly because we don't know
-- how long it will take the garbage collector to clean it up (without forcing
-- the GC to simply do it now).
assert(sodium.sodium_mprotect_noaccess(pk_b64) == 0, "Couldn't full-protect the public key B64")
pk_b64_bytes = nil
pk_b64 = nil

collectgarbage()
collectgarbage()

-------------------------------------------------------------------------------
-- Signing setup

local _M = {}
local ull_size = ffi.sizeof(ffi.new("unsigned long long", 0))

-------------------------------------------------------------------------------
-- Ed25519ph state object for high-level multipart signing

--[[
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
	print"help"
	caster = ffi.new("struct crypto_sign_ed25519ph_state *", sodium.sodium_malloc(sign_statebytes))
	assert(tonumber(caster) ~= 0,
	       "Failed to allocate Ed25519ph state")
	self.__state = ffi.gc(caster,
	                      sodium.sodium_free)
	
	
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
	
	local sig = ffi.gc(sodium.sodium_malloc(sign_bytes),
	                   sodium.sodium_free)
	local sig_len = ffi.gc(sodium.sodium_malloc(ull_size),
	                       sodium.sodium_free)
	assert(tonumber(sig) ~= 0, "Failed to allocate the signature")
	assert(tonumber(sig_len) ~= 0,
	       "Failed to allocate the signature length")
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

-- Returns the signature of the object. The object will need to be re-init'd.
function sign_state_proto.get_signature(self)
	return self:__fin_state()
end
-- An alias for the above function.
sign_state_proto.sign = sign_state_proto.get_signature

-- Constructor for the high-level signing object. Automatically initializes it.
function _M.new_sign_object()
	return setmetatable({}, sign_state_mt):init()
end]]

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
	local sig = ffi.gc(sodium.sodium_malloc(sign_bytes),
	                   sodium.sodium_free)
	local sig_len = ffi.gc(sodium.sodium_malloc(ull_size),
	                       sodium.sodium_free)
	assert(tonumber(sig) ~= 0, "Failed to allocate the signature")
	assert(tonumber(sig_len) ~= 0,
	       "Failed to allocate the signature length")
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

--print(_M.new_sign_object()
--      :insert"sup"
--      :sign()
--)
--print(_M.new_sign_object():insert"s":insert"u":insert"p":sign())
--print(_M.sign"sup")

return _M
