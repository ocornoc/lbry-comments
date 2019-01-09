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

local db = require "db"
local assert = require "luassert"

--------------------------------------------------------------------------------
-- Unit test for DB

describe("The entire database", function()
	it("is on by default", function()
		assert.is_true(db.is_running())
	end)
	
	it("can be stopped", function()
		assert.is_true(db.stop())
		assert.is_falsy(db.is_running())
	end)
	
	it("can be restarted", function()
		assert.is_true(db.restart())
		assert.is_true(db.stop())
		assert.is_true(db.restart())
	end)
	
	it("can be restarted twice in a row", function()
		assert.is_true(db.restart())
		assert.is_true(db.restart())
	end)
	
	it("can be started", function()
		db.stop()
		assert.is_true(db.start())
		assert.is_true(db.is_running())
	end)
	
	it("can't be stopped twice in a row", function()
		db.start()
		assert.is_true(db.stop())
		assert.is_falsy(db.stop())
	end)
	
	it("can't be started twice in a row", function()
		db.stop()
		assert.is_true(db.start())
		assert.is_falsy(db.start())
	end)
end)

local url1 = "@TEST_CLAIM1@"
local url2 = "@TEST_CLAIM2@"
local url3 = "@TEST_CLAIM3@"
-- A fake URI specifically created with the assumption data will never be there.
local url_bad = "@TEST_CLAIM_BAD@"
-- A value to make sure only strings are allowed as URLs.
local url_nonstring = 123123
-- A fake ID specifically created with the assumption data will never be there.
local claimid_bad = -1
-- Values to make sure only ints are allowed as Claim IDs.
local claimid_nonnum = "wowzers"
local claimid_nonint = math.pi
-- A placeholder for the ID of Comment N.
local com1id, com2id, com3id, com4id, com5id
-- A fake ID specifically created with the assumption data will never be there.
local comid_bad = -1
-- Values to check type correctness of comment IDs.
local comid_nonnum = "sah dude"
local comid_nonint = 1.25
-- The message and poster for Comment N.
local com1mes, com1pos = "@TEST_MESSAGE1@", "@TEST_POSTER1@"
local com2mes, com2pos = "@TEST_MESSAGE2@", "@TEST_POSTER2@"
local com3mes, com3pos = "@TEST_MESSAGE3@", "@TEST_POSTER3@"
local com4mes, com4pos = "@TEST_MESSAGE4@", com2pos
local com5mes, com5pos = "@TEST_MESSAGE5@", com1pos
-- A purposefully-malformed message and postername.
local commes_bad, compos_bad = "\t\t\n\f  \t\f", "\t\t\n\f  \t\f"
-- Values to make sure only strings are allowed as messages and posternames.
local commes_nonstring, compos_nonstring = 12321, 45654

describe("The claim database", function()
	it("should be able to insert claims", function()
		assert.is_truthy(db.claims.new(url1))
		assert.is_truthy(db.claims.new(url2))
		assert.is_truthy(db.claims.new(url3))
		assert.are_equal(db.claims.new(url1), 0)
	end)
	
	pending "Need to implement and test claim deletion"
	
	it("should be able to get the data of claims", function()
		assert.is_truthy(db.claims.get_data(url1))
		assert.is_truthy(db.claims.get_data(url2))
		assert.is_truthy(db.claims.get_data(url3))
		
		local data_1a = db.claims.get_data(url1)
		local data_2a = db.claims.get_data(url2)
		local data_3a = db.claims.get_data(url3)
		assert.are_equal(url1, data_1a.lbry_perm_uri)
		assert.are_equal(url2, data_2a.lbry_perm_uri)
		assert.are_equal(url3, data_3a.lbry_perm_uri)
	end)
	
	it("should be able to get int-indexed data of claims", function()
		assert.is_truthy(db.claims.get_data(url1, true))
		assert.is_truthy(db.claims.get_data(url2, true))
		assert.is_truthy(db.claims.get_data(url3, true))
		
		local data_1n = db.claims.get_data(url1, true)
		local data_2n = db.claims.get_data(url2, true)
		local data_3n = db.claims.get_data(url3, true)
		assert.are_equal(url1, data_1n[2])
		assert.are_equal(url2, data_2n[2])
		assert.are_equal(url3, data_3n[2])
	end)
	
	it("shouldn't have equal data in different URIs", function()
		local data_1a = db.claims.get_data(url1)
		local data_2a = db.claims.get_data(url2)
		
		assert.are_not_equal(
			data_1a.claim_index,
			data_2a.claim_index
		)
		assert.are_not_equal(
			data_1a.lbry_perm_uri,
			data_2a.lbry_perm_uri
		)
	end)
	
	it("shouldn't be able to get claim data for bad claims", function()
		local success, err_msg = db.claims.get_data(url_bad)
		assert.is_falsy(success)
		assert.is_equal("uri doesnt exist", err_msg)
		local success, err_msg = db.claims.get_data(url_nonstring)
		assert.is_falsy(success)
		assert.is_equal("uri not string", err_msg)
	end)
	
	it("should be able to upvote claims", function()
		-- 'stats_1a_1' is the stats of 'url1' prior to being
		--   upvoted. We'll use it to compare.
		local stats_1a_1 = db.claims.get_data(url1)
		-- 'stats_2a_1' is the stats of 'url2' prior to 'url1'
		--   being upvoted. Used to check that only 'url1' is
		--   being upvoted.
		local stats_2a_1 = db.claims.get_data(url2)
		-- Upvote the claim once.
		assert.is_truthy(db.claims.upvote(url1))
		local stats_1a_2 = db.claims.get_data(url1)
		local stats_2a_2 = db.claims.get_data(url2)
		-- Check to see if it was upvoted once.
		assert.are_equal(stats_1a_2.upvotes,
				 stats_1a_1.upvotes + 1)
		-- Make sure 'url2' stats wasn't affected.
		assert.are_equal(stats_2a_2.upvotes,
				 stats_2a_1.upvotes)
	end)
	
	it("should be able to multi-upvote claims", function()
		local stats_1a_1 = db.claims.get_data(url1)
		-- Upvote the claim three times, to check for multi-
		--   upvoting.
		assert.is_truthy(db.claims.upvote(url1, 3))
		local stats_1a_2 = db.claims.get_data(url1)
		-- Check to see if it was upvoted three times.
		assert.are_equal(stats_1a_2.upvotes,
				 stats_1a_1.upvotes + 3)
	end)
	
	it("should be able to downvote claims", function()
		-- 'stats_1a_1' is the stats of 'url1' prior to being
		--   downvoted. We'll use it to compare.
		local stats_1a_1 = db.claims.get_data(url1)
		-- 'stats_2a_1' is the stats of 'url2' prior to 'url1'
		--   being downvoted. Used to check that only 'url1' is
		--   being downvoted.
		local stats_2a_1 = db.claims.get_data(url2)
		-- Downvote the claim once.
		assert.is_truthy(db.claims.downvote(url1))
		local stats_1a_2 = db.claims.get_data(url1)
		local stats_2a_2 = db.claims.get_data(url2)
		-- Check to see if it was downvoted once.
		assert.are_equal(stats_1a_2.downvotes,
				 stats_1a_1.downvotes + 1)
		-- Make sure 'url2' stats wasn't affected.
		assert.are_equal(stats_2a_2.downvotes,
				 stats_2a_1.downvotes)
	end)
	
	it("should be able to multi-downvote claims", function()
		local stats_1a_1 = db.claims.get_data(url1)
		-- Downvote the claim three times, to check for multi-
		--   downvoting.
		assert.is_truthy(db.claims.downvote(url1, 3))
		local stats_1a_2 = db.claims.get_data(url1)
		-- Check to see if it was downvoted three times.
		assert.are_equal(stats_1a_2.downvotes,
				 stats_1a_1.downvotes + 3)
	end)
	
	it("should error when voting on mistyped claim IDs", function()
		local success, err_msg
		
		-- Test single-upvote.
		success, err_msg = db.claims.upvote(url_nonstring)
		assert.is_falsy(success)
		assert.is_equal("uri not string", err_msg)
		-- Test single-downvote.
		success, err_msg = db.claims.downvote(url_nonstring)
		assert.is_falsy(success)
		assert.is_equal("uri not string", err_msg)
		
		-- Test multi-upvote.
		success, err_msg = db.claims.upvote(url_nonstring, 2)
		assert.is_falsy(success)
		assert.is_equal("uri not string", err_msg)
		-- Test multi-downvote.
		success, err_msg = db.claims.downvote(url_nonstring, 2)
		assert.is_falsy(success)
		assert.is_equal("uri not string", err_msg)
	end)
	
	it("should error when voting on nonexistent comments", function()
		local success, err_msg
		
		-- Test single-upvote.
		success, err_msg = db.claims.upvote(url_bad)
		assert.is_falsy(success)
		assert.is_equal("uri doesnt exist", err_msg)
		-- Test single-downvote.
		success, err_msg = db.claims.downvote(url_bad)
		assert.is_falsy(success)
		assert.is_equal("uri doesnt exist", err_msg)
		
		-- Test multi-upvote.
		success, err_msg = db.claims.upvote(url_bad, 2)
		assert.is_falsy(success)
		assert.is_equal("uri doesnt exist", err_msg)
		-- Test multi-downvote.
		success, err_msg = db.claims.downvote(url_bad, 2)
		assert.is_falsy(success)
		assert.is_equal("uri doesnt exist", err_msg)
	end)
	
	it("should error when votes aren't typed correctly", function()
		local function test_func(f)
			local success, err_msg = f(url3, "woah")
			assert.is_falsy(success)
			assert.is_equal("times not number", err_msg)
			success, err_msg = f(url3, 1.1)
			assert.is_falsy(success)
			assert.is_equal("times not int", err_msg)
		end
		
		test_func(db.claims.upvote)
		test_func(db.claims.downvote)
	end)
	
	it("should be able to extrapolate the URI from the ID", function()
		-- Get the stats and claim_index for 'url3'
		local url3_stats = db.claims.get_data(url3)
		assert.is_truthy(url3_stats)
		local url3_id = url3_stats.claim_index
		assert.is_truthy(url3_id)
		-- Check if the extrap'd URL from the ID is equal to
		--  'url3'.
		local extrap_url3 = db.claims.get_uri(url3_id)
		assert.are_equal(extrap_url3, url3)
	end)
	
	it("should error when getting URI from mistyped ID", function()
		local success, err_msg
		
		success, err_msg = db.claims.get_uri(claimid_nonnum)
		assert.is_falsy(success)
		assert.is_equal("index not number", err_msg)
		
		success, err_msg = db.claims.get_uri(claimid_nonint)
		assert.is_falsy(success)
		assert.is_equal("index not int", err_msg)
	end)
	
	it("shouldn't be able to extrapolate the URI from a fake ID", function()
		local success, err_msg = db.claims.get_uri(claimid_bad)
		assert.is_falsy(success)
		assert.is_equal("uri not found", err_msg)
	end)
	
	-- This will come when LBRY wallet syncing is introduced.
	pending "Need to implement claim deletion"
end)

describe("The comments database", function()
	it("should be able to make new comments", function()
		com1id = db.comments.new(url1, com1pos, com1mes)
		assert.is_truthy(com1id)
		com2id = db.comments.new(url2, com2pos, com2mes)
		assert.is_truthy(com2id)
		com3id = db.comments.new(url3, com3pos, com3mes)
		assert.is_truthy(com3id)
		-- Make comment 4 a reply to comment 3.
		com4id = db.comments.new_reply(com3id, com4pos, com4mes)
		assert.is_truthy(com4id)
		com5id = db.comments.new(url1, com5pos, com5mes)
		assert.is_truthy(com5id)
	end)
	
	it("shouldn't be able to create comments with bad URIs", function()
		local success, err_msg = db.comments.new(
			url_nonstring,
			com1pos,
			com1mes
		)
		assert.is_falsy(success)
		assert.is_equal("uri not string", err_msg)
	end)
	
	it("shouldn't be able to create comments with bad posters", function()
		local success, err_msg = db.comments.new(
			url1,
			compos_nonstring,
			com1mes
		)
		assert.is_falsy(success)
		assert.is_equal("poster not string", err_msg)
		local success, err_msg = db.comments.new(
			url1,
			compos_bad,
			com1mes
		)
		assert.is_falsy(success)
		assert.is_equal("poster only whitespace", err_msg)
	end)
	
	it("shouldn't be able to create comments with bad messages", function()
		local success, err_msg = db.comments.new(
			url1,
			com1pos,
			com1mes_nonstring
		)
		assert.is_falsy(success)
		assert.is_equal("message not string", err_msg)
		local success, err_msg = db.comments.new(
			url1,
			com1pos,
			commes_bad
		)
		assert.is_falsy(success)
		assert.is_equal("message only whitespace", err_msg)
	end)
	
	it("should support getting data of comments", function()
		-- Alphanumeric-key'd data of comment 1.
		local com1a = db.comments.get_data(com1id)
		assert.is_truthy(com1a)
		-- Make sure the gotten data matches with the ID.
		assert.are_equal(com1a.comm_index, com1id)
		-- Integer-key'd data of comments 1 and 3.
		local com1n = db.comments.get_data(com1id, true)
		local com3n = db.comments.get_data(com3id, true)
		assert.is_truthy(com3n)
		assert.is_truthy(com3n)
		-- Make sure the gotten data matches with the ID.
		assert.are_equal(com1n[1], com1id)
		-- Make sure comments 1 and 3 have different claim
		--   indices.
		assert.are_not_equal(com1n[2], com3n[2])
		-- Integer-key'd data of comment 4.
		local com4n = db.comments.get_data(com4id, true)
		assert.is_truthy(com4n)
		-- Makes sure that the parent of comment 4 is comment 3.
		assert.are_equal(com3id, com4n[4])
		-- Makes sure that comment 1 has no parent.
		assert.is_nil(com1n[4])
	end)
	
	it("shouldn't be able to get data of mistyped comment IDs", function()
		local success, err_msg
		
		success, err_msg = db.comments.get_data(comid_nonnum)
		assert.is_falsy(success)
		assert.is_equal("id not number", err_msg)
		
		success, err_msg = db.comments.get_data(comid_nonint)
		assert.is_falsy(success)
		assert.is_equal("id not int", err_msg)
	end)
	
	it("shouldn't be able to get data of nonexistent comments", function()
		local success, err_msg
		
		success, err_msg = db.comments.get_data(comid_bad)
		assert.is_falsy(success)
		assert.is_equal("comment doesnt exist", err_msg)
	end)
	
	it("should support getting replies of a comment", function()
		-- The replies to comment 1.
		local com1res = db.comments.get_replies(com1id)
		assert.are.same(com1res, {})
		-- The replies to comment 3, with integer keys.
		local com3res = db.comments.get_replies(com3id, true)
		assert.are_not.same(com3res, {})
		assert.is_truthy(com3res[1])
		-- The replies to comment 4.
		local com4res = db.comments.get_replies(com4id)
		assert.are.same(com4res, {})
	end)
	
	it("should error when getting replies of bad comments", function()
		local success, err_msg
		
		success, err_msg = db.comments.get_replies(comid_nonnum)
		assert.is_falsy(success)
		assert.is_equal("id not number", err_msg)
		
		success, err_msg = db.comments.get_replies(comid_nonint)
		assert.is_falsy(success)
		assert.is_equal("id not int", err_msg)
	end)
	
	it("shouldn't get replies of nonexistent comments", function()
		local success, err_msg = db.comments.get_replies(comid_bad)
		assert.is_falsy(success)
		assert.is_equal("comment doesnt exist", err_msg)
	end)
	
	it("should be able to upvote comments", function()
		-- Test single upvotes and multi-upvotes.
		-- Alphanumeric-key'd data of comment 1.
		local com1a = db.comments.get_data(com1id)
		assert.is_truthy(com1a)
		-- Get the upvotes for comment 1.
		local com1_oldup = com1a.upvotes
		assert.is_equal("number", type(com1_oldup))
		-- Upvote comment 1 once.
		local com1_newup = db.comments.upvote(com1id)
		-- Make sure the returned value reflects that.
		assert.are_equal(com1_oldup + 1, com1_newup)
	end)
	
	it("should be able to multi-upvote comments", function()
		local com1a = db.comments.get_data(com1id)
		-- Upvote comment 1 five times.
		local com1_newup = db.comments.upvote(com1id, 5)
		-- Make sure the returned value reflects that.
		assert.are_equal(com1a.upvotes + 5, com1_newup)
		-- Get comment 1's data again.
		local com1a_new = db.comments.get_data(com1id)
		-- Make sure the upvotes in the database reflects the
		--   new upvotes.
		assert.are_equal(com1a.upvotes + 5, com1a_new.upvotes)
	end)
	
	it("should be able to downvote comments", function()
		-- Test single downvotes and multi-downvotes.
		-- Alphanumeric-key'd data of comment 2.
		local com2a = db.comments.get_data(com2id)
		assert.is_truthy(com2a)
		-- Get the downvotes for comment 2.
		local com2_olddown = com2a.upvotes
		assert.is_equal("number", type(com2_olddown))
		-- Downvote comment 2 once.
		local com2_newdown = db.comments.downvote(com2id)
		-- Make sure the returned value reflects that.
		assert.are_equal(com2_olddown + 1, com2_newdown)
	end)
	
	it("should be able to multi-downvote comments", function()
		local com1a = db.comments.get_data(com1id)
		-- Downvote comment 1 five times.
		local com1_newdown = db.comments.downvote(com1id, 5)
		-- Make sure the returned value reflects that.
		assert.are_equal(com1a.downvotes + 5, com1_newdown)
		-- Get comment 1's data again.
		local com1a_new = db.comments.get_data(com1id)
		-- Make sure the upvotes in the database reflects the
		--   new downvotes.
		assert.are_equal(com1a.downvotes + 5, com1a_new.downvotes)
	end)
	
	it("should error when voting on mistyped comments", function()
		local success, err_msg
		
		-- Test single-upvote.
		success, err_msg = db.comments.upvote(comid_nonnum)
		assert.is_falsy(success)
		assert.is_equal("id not number", err_msg)
		success, err_msg = db.comments.upvote(comid_nonint)
		assert.is_falsy(success)
		assert.is_equal("id not int", err_msg)
		-- Test single-downvote.
		success, err_msg = db.comments.downvote(comid_nonnum)
		assert.is_falsy(success)
		assert.is_equal("id not number", err_msg)
		success, err_msg = db.comments.downvote(comid_nonint)
		assert.is_falsy(success)
		assert.is_equal("id not int", err_msg)
		
		-- Test multi-upvote.
		success, err_msg = db.comments.upvote(comid_nonnum, 2)
		assert.is_falsy(success)
		assert.is_equal("id not number", err_msg)
		success, err_msg = db.comments.upvote(comid_nonint, 2)
		assert.is_falsy(success)
		assert.is_equal("id not int", err_msg)
		-- Test multi-downvote.
		success, err_msg = db.comments.downvote(comid_nonnum, 2)
		assert.is_falsy(success)
		assert.is_equal("id not number", err_msg)
		success, err_msg = db.comments.downvote(comid_nonint, 2)
		assert.is_falsy(success)
		assert.is_equal("id not int", err_msg)
	end)
	
	it("should error when voting on nonexistent comments", function()
		local success, err_msg
		
		-- Test single-upvote.
		success, err_msg = db.comments.upvote(comid_bad)
		assert.is_falsy(success)
		assert.is_equal("comment doesnt exist", err_msg)
		-- Test single-downvote.
		success, err_msg = db.comments.downvote(comid_bad)
		assert.is_falsy(success)
		assert.is_equal("comment doesnt exist", err_msg)
		
		-- Test multi-upvote.
		success, err_msg = db.comments.upvote(comid_bad, 2)
		assert.is_falsy(success)
		assert.is_equal("comment doesnt exist", err_msg)
		-- Test multi-downvote.
		success, err_msg = db.comments.downvote(comid_bad, 2)
		assert.is_falsy(success)
		assert.is_equal("comment doesnt exist", err_msg)
	end)
	
	it("should error when votes aren't typed correctly", function()
		local function test_func(f)
			local success, err_msg = f(com1id, "woah")
			assert.is_falsy(success)
			assert.is_equal("times not number", err_msg)
			success, err_msg = f(com1id, 1.1)
			assert.is_falsy(success)
			assert.is_equal("times not int", err_msg)
		end
		
		test_func(db.comments.upvote)
		test_func(db.comments.downvote)
	end)
	
	it("should be able to get all comments from a claim", function()
		-- All test claims should have at least one comment, and
		--   url1 should have double url2's and url3's.
		assert.is_not_equal(0, #db.claims.get_comments(url1))
		assert.is_not_equal(0, #db.claims.get_comments(url2))
		assert.is_not_equal(0, #db.claims.get_comments(url3))
		assert.are_equal(2 * #db.claims.get_comments(url2),
				 #db.claims.get_comments(url1))
		-- Test if comments are returned as arrays or objects
		--   when asked for either.
		assert.is_nil(db.claims.get_comments(url1)[1][1])
		assert.truthy(db.claims.get_comments(url1, true)[1][1])
		-- Make sure comments don't overwrite eachother when
		--   listing them.
		--   Addresses issue #6
		--   https://github.com/ocornoc/lbry-comments/issues/6
		assert.are_not_equal(
		 db.claims.get_comments(url1)[1].comm_index,
		 db.claims.get_comments(url1)[2].comm_index
		)
	end)
	
	it("shouldn't be able to get comments from bad claims", function()
		local success, err_msg
		
		success, err_msg = db.claims.get_comments(url_bad)
		assert.is_falsy(success)
		assert.is_equal("uri doesnt exist", err_msg)
		
		success, err_msg = db.claims.get_comments(url_nonstring)
		assert.is_falsy(success)
		assert.is_equal("uri not string", err_msg)
	end)
	
	-- These will come when LBRY wallet syncing is introduced.
	pending("Need to check for comment deletion when parent " ..
		"claim is deleted")
	pending "Need to implement edits"
	pending "Need to implement deletion"
end)
