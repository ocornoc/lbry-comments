--[[
This file is part of LBRY-Comments.

LBRY-Comments provides a simple network database for commenting.
Copyright (C) 2018 Grayson Burton and Oleg Silken

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

local crypto = require "crypto"
local assert = require "luassert"

--------------------------------------------------------------------------------
-- Unit test for crypto.lua

describe("crypto.lua", function()
	local message = "hello world! how are you?"
	local fail_message = "why doesnt this get verified?"
	local fail_sig = ("this signature is made to fail!!"):rep(2)
	local fail_pubkey = "this public key is made to fail!"
	local pubkey, sig
	
	it("should be able to return the public key", function()
		-- Get the public key and make sure it's a string.
		pubkey = crypto.get_pubkey()
		assert.is_equal("string", type(pubkey))
		-- Make sure the public key is 32 bytes long.
		assert.is_equal(32, pubkey:len())
		-- Make sure the public key doesn't change between runs of the
		--   function.
		assert.are_equal(pubkey, crypto.get_pubkey())
	end)
	
	it("should be able to sign single strings", function()
		-- Tests whether it returns anything.
		assert.is_truthy(crypto.get_sig "Hello world")
		-- Tests whether that anything is a string.
		assert.is_equal("string", type(crypto.get_sig "*insert joke*"))
		-- Tests whether the length of that string is 64 bytes.
		assert.is_equal(64, crypto.get_sig("test string woo"):len())
		-- Store `message`'s signature.
		sig = assert.is_truthy(crypto.get_sig(message))
	end)
	
	it("should be able to verify signatures", function()
		assert.is_true(crypto.verify_sig(message, sig))
		assert.is_true(crypto.verify_any_sig(
			message,
			sig,
			pubkey
		))
	end)
	
	it("shouldn't be able to falsely verify signatures", function()
		assert.is_false(crypto.verify_sig(fail_message, sig))
		assert.is_false(crypto.verify_sig(fail_message, fail_sig))
		assert.is_false(crypto.verify_sig(message, fail_sig))
		assert.is_false(crypto.verify_any_sig(
			fail_message, sig, pubkey
		))
		assert.is_false(crypto.verify_any_sig(
			message, fail_sig, pubkey
		))
		assert.is_false(crypto.verify_any_sig(
			fail_message, fail_sig, pubkey
		))
		assert.is_false(crypto.verify_any_sig(
			message, sig, fail_pubkey
		))
		assert.is_false(crypto.verify_any_sig(
			fail_message, sig, fail_pubkey
		))
		assert.is_false(crypto.verify_any_sig(
			message, fail_sig, fail_pubkey
		))
		assert.is_false(crypto.verify_any_sig(
			fail_message, fail_sig, fail_pubkey
		))
	end)
end)

-- For testing signing objects specifically.
describe("sign objects", function()
	local fail_message = "why doesnt this get verified?"
	local fail_sig = ("this signature is made to fail!!"):rep(2)
	local fail_pubkey = "this public key is made to fail!"
	local testtext0 = "hello "
	local testtext1 = "world "
	local testtext2 = ("cool!"):rep(100)
	-- Signing Object, signature, and public key
	local sob, sig, pubkey
	
	pubkey = assert.is_truthy(crypto.get_pubkey())
	
	it("should be able to create signing objects", function()
		sob = assert.is_truthy(crypto.new_sign_object())
	end)
	
	it("should be able to insert text", function()
		assert.are_equal(sob, sob:insert(testtext0))
		assert.are_equal(sob, sob:insert(testtext1))
		assert.are_equal(sob, sob:insert(testtext2))
	end)
	
	it("should be able to sign multipart strings", function()
		-- Make sure the signature happened.
		sig = assert.is_truthy(sob:get_signature())
		-- See if it is a string.
		assert.is_equal("string", type(sig))
		-- Make sure the string is 64 bytes long.
		assert.is_equal(64, sig:len())
	end)
	
	it("should be able to reuse signing objects", function()
		sob:reset()
		assert.are_equal(sob, sob:insert(testtext0))
		assert.are_equal(sob, sob:insert(testtext1))
		assert.are_equal(sob, sob:insert(testtext2))
	end)
	
	it("should be able to verify signatures", function()
		sob:reset()
		assert.are_equal(sob, sob:insert(testtext0))
		assert.are_equal(sob, sob:insert(testtext1))
		assert.are_equal(sob, sob:insert(testtext2))
		assert.is_true(sob:verify(sig))
		assert.are_equal(sob, sob:insert(testtext0))
		assert.are_equal(sob, sob:insert(testtext1))
		assert.are_equal(sob, sob:insert(testtext2))
		assert.is_true(sob:verify_any(sig, pubkey))
	end)
	
	it("should have equal signatures across diff. chunk sizes", function()
		sob:reset()
		-- Try with testtext0 and testtext1 concatenated.
		assert.are_equal(sob, sob:insert(testtext0 .. testtext1))
		assert.are_equal(sob, sob:insert(testtext2))
		assert.are_equal(sig, sob:get_signature())
		-- Try with testtext1 and testtext2 concatenated.
		assert.are_equal(sob, sob:insert(testtext0))
		assert.are_equal(sob, sob:insert(testtext1 .. testtext2))
		assert.are_equal(sig, sob:get_signature())
		-- Try all concatenated.
		assert.are_equal(sob, sob:insert(
			testtext0 .. testtext1 .. testtext2
		))
		assert.are_equal(sig, sob:get_signature())
	end)
	
	local full_testtext = testtext0 .. testtext1 .. testtext2
	
	it("shouldn't be able to falsely verify signatures", function()
		sob:reset()
		assert.is_false(sob:insert(full_testtext):verify(
			fail_sig
		))
		assert.is_false(sob:insert(fail_message):verify(
			sig
		))
		assert.is_false(sob:insert(fail_message):verify_any(
			sig, pubkey
		))
		assert.is_false(sob:insert(full_testtext):verify_any(
			fail_sig, pubkey
		))
		assert.is_false(sob:insert(fail_message):verify_any(
			fail_sig, pubkey
		))
		assert.is_false(sob:insert(full_testtext):verify_any(
			sig, fail_pubkey
		))
		assert.is_false(sob:insert(fail_message):verify_any(
			sig, fail_pubkey
		))
		assert.is_false(sob:insert(full_testtext):verify_any(
			fail_sig, fail_pubkey
		))
		assert.is_false(sob:insert(fail_message):verify_any(
			fail_sig, fail_pubkey
		))
	end)
end)
