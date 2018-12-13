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
	it("should be able to return the public key", function()
		-- Get the public key and make sure it's a string.
		assert.is_equal("string", type(crypto.get_pubkey()))
		-- Make sure the public key is 32 bytes long.
		assert.is_equal(32, crypto.get_pubkey():len())
		-- Make sure the public key doesn't change between runs of the
		--   function.
		assert.are_equal(crypto.get_pubkey(), crypto.get_pubkey())
	end)
	
	it("should be able to sign single strings", function()
		-- Tests whether it returns anything.
		assert.is_truthy(crypto.get_sig "Hello world")
		-- Tests whether that anything is a string.
		assert.is_equal("string", type(crypto.get_sig "*insert joke*"))
		-- Tests whether the length of that string is 64 bytes.
		assert.is_equal(64, crypto.get_sig("test string woo"):len())
	end)
	
	it("should be able to sign multipart strings", function()
		-- Signing OBject.
		local sob = crypto.new_sign_object()
		-- Make sure it was made.
		assert.is_truthy(sob)
		-- Make sure I can insert stuff.
		assert.is_truthy(sob:insert "part one")
		-- See if 'sob' returns itself.
		assert.are_equal(sob, sob:insert "part two")
		-- The signature of 'sob'.
		local sig = sob:get_signature()
		-- Make sure the signature happened.
		assert.is_truthy(sig)
		-- See if it is a string.
		assert.is_equal("string", type(sig))
		-- Make sure the string is 64 bytes long.
		assert.is_equal(64, sig:len())
	end)
end)
