--[[--
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
--]]--

local db = require "db"
local assert = require "luassert"

--------------------------------------------------------------------------------
-- Unit test for DB

describe("High-level SQLite Abstraction", function()
	describe("can be interrupted", function()
		it("can be stopped", function()
			assert.is_true(db.stop())
			assert.is_falsy(db.stop())
		end)
		
		it("can be started", function()
			assert.is_true(db.start())
			assert.is_falsy(db.start())
		end)
		
		it("can be restarted", function()
			assert.is_true(db.restart())
			assert.is_true(db.stop())
			assert.is_true(db.restart())
		end)
	end)
	
	local url1 = "@TEST_CLAIM1@"
	local url2 = "@TEST_CLAIM2@"
	local url3 = "@TEST_CLAIM3@"
	
	describe("supporting claims", function()
		it("should be able to insert claims", function()
			assert.is_truthy(db.claims.new(url1))
			assert.is_truthy(db.claims.new(url2))
			assert.is_truthy(db.claims.new(url3))
			assert.are_equal(db.claims.new(url1), 0)
		end)
		
		pending "Need to implement and test claim deletion"
		
		it("should be able to get the data of claims", function()
			assert.is_truthy(db.claims.get_data(url1))
			-- Make sure the data gotten is correct.
			local data_1a = db.claims.get_data(url1)
			assert.are_equal(data_1a.lbry_perm_uri, url1)
			-- Checks support for the numeric indices.
			local data_1n = db.claims.get_data(url1, true)
			assert.are_equal(data_1n[2], url1)
			-- Checks if two URLs have different data.
			local data_2n = db.claims.get_data(url2, true)
			assert.are_not_equal(data_1n[1], data_2n[1])
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
			assert.is_truthy(db.claims.upvote(url1, 1))
			local stats_1a_2 = db.claims.get_data(url1)
			local stats_2a_2 = db.claims.get_data(url2)
			-- Check to see if it was upvoted once.
			assert.are_equal(stats_1a_2.upvotes,
			                 stats_1a_1.upvotes + 1)
			-- Make sure 'url2' stats wasn't affected.
			assert.are_equal(stats_2a_2.upvotes,
			                 stats_2a_1.upvotes)
			-- Upvote the claim three times, to check for multi-
			--   upvoting.
			assert.is_truthy(db.claims.upvote(url1, 3))
			local stats_1a_3 = db.claims.get_data(url1)
			-- Check to see if it was upvoted three times.
			assert.are_equal(stats_1a_3.upvotes,
			                 stats_1a_2.upvotes + 3)
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
			assert.is_truthy(db.claims.downvote(url1, 1))
			local stats_1a_2 = db.claims.get_data(url1)
			local stats_2a_2 = db.claims.get_data(url2)
			-- Check to see if it was downvoted once.
			assert.are_equal(stats_1a_2.downvotes,
			                 stats_1a_1.downvotes + 1)
			-- Make sure 'url2' stats wasn't affected.
			assert.are_equal(stats_2a_2.downvotes,
			                 stats_2a_1.downvotes)
			-- Downvote the claim three times, to check for multi-
			--   downvoting.
			assert.is_truthy(db.claims.downvote(url1, 3))
			local stats_1a_3 = db.claims.get_data(url1)
			-- Check to see if it was downvoted three times.
			assert.are_equal(stats_1a_3.downvotes,
			                 stats_1a_2.downvotes + 3)
		end)
		
		it("should be able to get the URI for a claim from the index",
		   function()
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
		
		-- This will come when LBRY wallet syncing is introduced.
		pending "Need to implement claim deletion"
	end)
	
	describe("supporting comments", function()
		-- A placeholder for the ID of Comment N.
		local com1id, com2id, com3id, com4id
		-- The message and poster for Comment N.
		local com1mes, com1pos = "@TEST_MESSAGE1@", "@TEST_POSTER1@"
		local com2mes, com2pos = "@TEST_MESSAGE2@", "@TEST_POSTER2@"
		local com3mes, com3pos = "@TEST_MESSAGE3@", "@TEST_POSTER3@"
		local com4mes, com4pos = "@TEST_MESSAGE4@", com2pos
		
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
			-- Upvote comment 1 five times.
			com1_newup = db.comments.upvote(com1id, 5)
			-- Make sure the returned value reflects that.
			assert.are_equal(com1_oldup + 6, com1_newup)
			-- Get comment 1's data again.
			local com1a_new = db.comments.get_data(com1id)
			-- Make sure the upvotes in the database reflects the
			--   new upvotes.
			assert.are_equal(com1a.upvotes + 6, com1a_new.upvotes)
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
			-- Downvote comment 2 five times.
			com2_newdown = db.comments.downvote(com2id, 5)
			-- Make sure the returned value reflects that.
			assert.are_equal(com2_olddown + 6, com2_newdown)
			-- Get comment 2's data again.
			local com2a_new = db.comments.get_data(com2id)
			-- Make sure the downvotes in the database reflects the
			--   new downvotes.
			assert.are_equal(com2a.downvotes + 6,
			                 com2a_new.downvotes)
		end)
		
		it("should be able to get all comments from a claim", function()
			-- All test claims should have exactly one top-level
			--   comment.
			assert.is_equal(1, #db.claims.get_comments(url1))
			assert.is_equal(1, #db.claims.get_comments(url2))
			assert.is_equal(1, #db.claims.get_comments(url3))
		end)
		
		-- These will come when LBRY wallet syncing is introduced.
		pending("Need to check for comment deletion when parent " ..
		        "claim is deleted")
		pending "Need to implement edits"
		pending "Need to implement deletion"
	end)
end)
