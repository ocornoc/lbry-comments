--[[
This file is part of LBRY-Comments.

LBRY-Comments provides a simple network database for commenting.
Copyright (C) 2018 Grayson Burton and Oleg Silkin

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as
published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]

--------------------------------------------------------------------------------
-- A high-level wrapper around libsodium.
-- @module crypto
-- @alias _M
-- @copyright 2018 Grayson Burton and Oleg Silkin
-- @license GNU AGPLv3
-- @author Grayson Burton

-----------------------------------------DEPS------------------------------------

local ffi = require "ffi"

---------------------------------------------------------------------------------
-- Options
-- @section options
-- @local

--- The path to the file containing the keypair generation seed.
-- Relative to the master directory.
-- @local
local kseedfile_rpath = "seed"

-----------------------------------------DECS------------------------------------

--- A list of functions for interfacing with libsodium.
-- @table sodium
-- @local
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
int crypto_sign_ed25519ph_final_verify(struct crypto_sign_ed25519ph_state *state,
                                       const unsigned char *sig,
                                       const unsigned char *pk)
            __attribute__ ((warn_unused_result)) __attribute__ ((nonnull));

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

--- Constants.
-- @section constants
-- @local

--- The number of bytes in an Ed25519/ph state.
-- Should equal 208, excluding padding.
local sign_statebytes  = tonumber(sodium.crypto_sign_ed25519ph_statebytes())
--- The number of bytes in an Ed25519/ph signature.
-- Should equal 64.
local sign_bytes       = tonumber(sodium.crypto_sign_ed25519_bytes())
--- The number of bytes in an Ed25519/ph seed.
-- Should equal 32.
local sign_seedbytes   = tonumber(sodium.crypto_sign_ed25519_seedbytes())
--- The number of bytes in an Ed25519/ph public key.
-- Should equal 32.
local sign_pkbytes     = tonumber(sodium.crypto_sign_ed25519_publickeybytes())
--- The number of bytes in an Ed25519/ph secret key.
-- Should equal 64.
local sign_skbytes     = tonumber(sodium.crypto_sign_ed25519_secretkeybytes())

-- libsodium returns -1 on failure, 0 on success, and 1 if it's already been
--  initialized.
assert(sodium.sodium_init() ~= -1, "libsodium failed to initialize")

--- The path to the key seed file.
local kseedfile_path = _G.toppath .. "/" .. kseedfile_rpath

--------------------------------------------------------------------------------
-- Padding
-- @section padding
-- @local

--- This is a very basic zeropadding function.
-- This function will *not* truncate the result if `to_len` is smaller than the
-- length of `str`.
-- @tparam string str The string to zeropad.
-- @tparam number to_len The length to pad to.
-- @treturn string The input zeropadded to `to_len`.
-- @usage zeropad_loose("hello", 7) --> "hello\0\0"
-- @usage zeropad_loose("hello", 4) --> "hello"
local function zeropad_loose(str, to_len)
	local pad_needed = to_len - str:len()
	
	if pad_needed > 0 then
		return str .. ("\000"):rep(pad_needed)
	else
		return str
	end
end

--- This is a very basic zero-padding function.
-- This function *will* truncate the result if `to_len` is smaller than the
-- length of `str`.
-- @tparam string str The string to zeropad.
-- @tparam number to_len The length to pad to.
-- @treturn string The input zeropadded to `to_len`.
-- @usage zeropad_strict("hello", 7) --> "hello\0\0"
-- @usage zeropad_strict("hello", 4) --> "hell"
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

--------------------------------------------------------------------------------
-- Safe allocation
-- @section allocation
-- @local

--- Uses sodium's malloc in order to safely allocate C objects.
-- Returns a pointer of type `p_type` of size `size`.
-- @warning It doesn't check if the allocation failed.
-- @tparam string p_type The C type of the pointer.
-- @tparam int size The size of the data being pointed to, in bytes.
-- @treturn pointer A garbage-collected pointer.
-- @see sod_gc
-- @usage sod_unsafe_gc("const char *", 20)
local function sod_unsafe_gc(p_type, size)
	local new_p = ffi.new(p_type, sodium.sodium_malloc(size))
	ffi.gc(new_p, sodium.sodium_free)
	
	return new_p
end

--- Uses sodium's malloc in order to safely allocate C objects.
-- Returns a pointer of type `p_type` of size `size`.
-- @raise Throws when it fails to allocate the pointer.
-- @tparam string p_type The C type of the pointer.
-- @tparam int size The size of the data being pointed to, in bytes.
-- @treturn pointer A safe garbage-collected pointer.
-- @usage sod_gc("const char *", 20)
local function sod_gc(p_type, size)
	local new_p = sod_unsafe_gc(p_type, size)
	assert(tonumber(new_p) ~= 0, "Failed to allocate pointer of type '" ..
	       p_type .. "' and size '" .. tonumber(size) .. "'")
	
	return new_p
end

--------------------------------------------------------------------------------
-- Base64
-- @section base64
-- @local

--- Specifies the base64 "original" variant.
local b64_original     = 1
--- Specifies the base64 "original" variant with no padding.
local b64_original_np  = 3
--- Specifies the base64 "urlsafe" variant.
local b64_urlsafe      = 5
--- Specifies the base64 "urlsafe" variant with no padding.
local b64_urlsafe_np   = 7

--- Returns the length of the Base64-encoded string.
-- The length will differ given different `size` and `variant` inputs.
-- @raise Throws if `variant` isn't a variant.
-- @tparam int size The size (in bytes) of the string to encode.
-- @tparam[opt=b64_original] variant variant The Base64 variant to use.
-- @treturn int The amount of bytes required to store the encoded input.
-- @see b64_original, b64_original_np, b64_urlsafe, b64_urlsafe_np
-- @usage b64_len(("hello"):len(), b64_urlsafe) --> 9
-- @usage b64_len(30) --> 41
local function b64_len(size, variant)
	variant = variant or b64_original
	assert(type(variant) == "number",
	       "'variant' must be a 'b64_*' variant")
	assert(variant == b64_original or variant == b64_original_np or
	       variant == b64_urlsafe  or variant == b64_urlsafe_np,
	       "'variant' isn't a recognized variant option")
	
	return tonumber(sodium.sodium_base64_encoded_len(size, variant))
end

--- Encodes a string into Base64.
-- It uses libsodium to perform the encoding.
-- @raise Throws if `variant` isn't a variant.
-- @tparam string message The message to encode.
-- @tparam[opt=b64_original] variant variant The variant of Base64.
-- @treturn string The encoded message.
-- @usage b64_encode_str("sup dog", b64_urlsafe_np) --> "c3VwIGRvZw"
-- @usage b64_encode_str("hello") --> "aGVsbG8="
local function b64_encode_str(message, variant)
	variant = variant or b64_original
	assert(type(message) == "string", "'message' wasn't a string")
	
	-- We don't have to write an assert for 'variant' being a number
	--   because b64_len already has one. ;)
	local encoded_len = b64_len(message:len(), variant)
	local encoded_msg = sod_gc("unsigned char * const", encoded_len)
	sodium.sodium_bin2base64(encoded_msg, encoded_len, message,
	                         message:len(), variant)
	
	return ffi.string(encoded_msg, encoded_len)
end

--- Encodes a pointer's data into Base64.
-- It uses libsodium to perform the encoding.
-- @raise Throws if `variant` isn't a variant.
-- @tparam pointer message The message to encode.
-- @tparam int message_len The length of the message in bytes.
-- @tparam[opt=b64_original] variant variant The variant of Base64.
-- @treturn string The encoded message.
-- @usage b64_encode_ptr(my_pointer, data_len, b64_original_np)
local function b64_encode_ptr(message, message_len, variant)
	variant = variant or b64_original
	assert(type(message_len) == "number", "'message_len' wasn't a number")
	
	-- We don't have to write an assert for 'variant' being a number
	--   because b64_len already has one. ;)
	local encoded_len = b64_len(message_len, variant)
	local encoded_msg = sod_gc("unsigned char * const", encoded_len)
	sodium.sodium_bin2base64(encoded_msg, encoded_len, message,
	                         message_len, variant)
	
	return ffi.string(encoded_msg, encoded_len)
end

--------------------------------------------------------------------------------

--- The public key.
-- This is protected as read-only using libsodium's secure memory.
-- @within Constants
local pk = sod_gc("unsigned char *", sign_pkbytes)
--- The secret key.
-- This is protected as no-access using libsodium's secure memory. Rarely, in
-- functions that need it, it is briefly read-only.
-- @within Constants
local sk = sod_gc("unsigned char *", sign_skbytes)
--- Our seed for the keypair generation.
-- This is protected as no-access using libsodium's secure memory. Rarely, in
-- functions that need it, it is briefly read-only.
-- @within Constants
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
	print("Public key (Base64): " .. b64_encode_ptr(pk, sign_pkbytes))
end

--------------------------------------------------------------------------------

--- The crypto library public interface.
-- @section crypto
local _M = {}
local ull_size = ffi.sizeof(ffi.new("unsigned long long", 0))

--------------------------------------------------------------------------------

--- Ed25519ph state objects for high-level multipart signing.
-- @type sign_state
-- @alias sign_state

local sign_state = {}

-- If it starts with "__", it's meant for private usage, as usual.
local sign_state_mt = {}

-- !!! PRIVATE STUFF !!!
-- Allows for a prototype.
sign_state_mt.__index = sign_state

-- Disallows setting of values not in the prototype.
function sign_state_mt.__newindex(self, k, v)
	-- We check explicitly for nil rather than using truthiness because
	--   the prototype value could be false.
	if sign_state[k] ~= nil then
		rawset(self, k, v)
	else
		error "You cannot arbitrarily set values in a sign object"
	end
end

-- A pointer to the underlying libsodium state that @{sign_state} abstracts.
sign_state.__state = 1
-- A value describing whether the state is initialized.
sign_state.__state_is_init = false

--- Resets the object's state.
-- @lfunction __new_state
-- @treturn nil
-- @usage sign_obj:__new_state()
function sign_state.__new_state(self)
	self.__state = sod_gc("struct crypto_sign_ed25519ph_state *",
	                      sign_statebytes)
	
	
	local success = sodium.crypto_sign_ed25519ph_init(self.__state)
	assert(success == 0, "Failed to initialize Ed25519ph state")
	
	self.__state_is_init = true
end

--- Updates the state object with some text.
-- self.__state must be initialized and created and not finalized.
-- @tparam string message The text to insert.
-- @lfunction __upd_state
-- @treturn nil
-- @usage sign_obj:__upd_state("hello")
function sign_state.__upd_state(self, message)
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

--- Finalizes the state object and returns the signature.
-- self.__state must be initialized and created and not finalized.
-- @lfunction __fin_state
-- @treturn string The signature of the state.
-- @usage sign_obj:__fin_state()
function sign_state.__fin_state(self)
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

--- Verifies a signature against the object, finalizing it.
-- Given a Lua string signature that is 64 long, returns whether the public key
-- used in the object and the signature verify the text that has been inserted
-- into the object. The object will require re-init.
-- @lfunction __ver_state
-- @tparam string sig The signature to verify.
-- @treturn bool `true` if it verifies successfully, `false` otherwise.
-- @usage sign_obj:__ver_state(my_sig)
function sign_state.__ver_state(self, sig)
	assert(type(sig) == "string", "'sig' must be a string, but is a '" ..
	       type(sig) .. "'")
	assert(sig:len() == sign_bytes, "'sig' must be " .. sign_bytes ..
	       " bytes long, but is " .. sig:len() .. " bytes long")
	
	-- Lua strings can't be implicitly converted to pointers of non-const
	--   chars, so we have to copy the string ourselves.
	local sig_copy = sod_gc("unsigned char *", sign_bytes)
	ffi.copy(sig_copy, sig, sign_bytes)
	
	return sodium.crypto_sign_ed25519ph_final_verify(
	        self.__state,
		sig_copy,
		pk
	       ) == 0
end

-- !!! PUBLIC STUFF !!!

--- Returns whether the object is initialized.
-- @function is_initialized
-- @treturn bool `true` for initialized, `false` otherwise.
-- @see initialize
-- @usage crypto.new_sign_object():is_initialized() --> true
function sign_state.is_initialized(self)
	return self.__is_state_init
end
--- An alias for @{is_initialized}
-- @function is_init
-- @treturn bool
sign_state.is_init = sign_state.is_initialized

--- Initializes the object and returns it.
-- If the state is already initialized, it does nothing it.
-- @function initialize
-- @treturn sign_state `self`
-- @usage sign_obj:initialize()
function sign_state.initialize(self)
	if not self:is_initialized() then
		self:__new_state()
	end

	return self
end
--- An alias for @{initialize}.
-- @function init
-- @treturn sign_state
sign_state.init = sign_state.initialize

--- Forcefully initializes the object, wiping its state, and returns it.
-- @function reset
-- @treturn sign_state `self`
-- @see initialize, is_initialized
-- @usage sign_obj:insert("hello?"):reset()
function sign_state.reset(self)
	self:__new_state()
	
	return self
end

--- Inserts a message into its state and returns the object.
-- @function insert
-- @raise Throws if `message` isn't a string.
-- @tparam string message The message to insert.
-- @treturn sign_state `self`
-- @usage sign_obj:insert("sup dawg")
function sign_state.insert(self, message)
	self:__upd_state(message)
	
	return self
end


--- Returns the signature of the state and resets it.
-- @function get_signature
-- @treturn string The Ed25519ph of the contents.
-- @see verify
-- @usage sign_obj:reset():insert("get my signature"):get_signature()
function sign_state.get_signature(self)
	local result = self:__fin_state()
	self:init()
	
	return result
end
--- An alias for @{get_signature}.
-- @function get_sig
-- @treturn string
sign_state.get_sig = sign_state.get_signature

--- Given a signature string, returns whether the state verifies it.
-- The signature string must be 64 bytes long and have been made using one of
-- the @{sign_state} objects. Resets the state after.
-- @function verify
-- @tparam string sig The signature to verify. Must be exactly 64 bytes long.
-- @treturn bool `true` if it's verified, `false` otherwise.
-- @see get_signature
-- @usage sign_obj:insert("verify me"):verify(past_signature)
function sign_state.verify(self, sig)
	local result = self:__ver_state(sig)
	self:init()
	
	return result
end

--- crypto
-- @section crypto

--- Constructor for the high-level signing object. 
-- Automatically initializes it.
-- @function new_sign_object
-- @treturn sign_state
-- @usage crypto.new_sign_object()
function _M.new_sign_object()
	return setmetatable({}, sign_state_mt):init()
end

--------------------------------------------------------------------------------

--- Returns the signature of a message.
-- Gives a different result than Ed25519ph signing, as this uses Ed25519.
-- @function get_sig
-- @tparam string message The message to sign.
-- @treturn string The 64 byte signature of `message`.
-- @usage crypto.get_sig("get my signature please")
function _M.get_sig(message)
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

--- Returns the public key.
-- @treturn string The 32 byte public key.
-- @usage crypto.get_pubkey()
function _M.get_pubkey()
	return ffi.string(pk, sign_pkbytes)
end

--------------------------------------------------------------------------------

return _M
