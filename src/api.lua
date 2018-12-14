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

--------------------------------------------------------------------------------
-- The public-facing API for LBRY-Comments.
-- @module api
-- @alias api
-- @copyright 2018 Grayson Burton and Oleg Silkin
-- @license GNU AGPLv3
-- @author Grayson Burton

--------------------------------------------------------------------------------

local db = require "db"
local json = require "cjson"
local api = {}
local error_code = {}

local api_VERSION = "0.4.0"

--------------------------------------------------------------------------------
-- Helpers
-- @section helpers
-- @local

--- Returns part of a JSON-RPC error response object.
-- WARNING: will *not* throw if a type is wrong.
-- @tparam string message The concise error descriptor or reason.
-- @tparam[opt=-32602] int code The error code.
-- @treturn table The partial JSON-RPC error response, not yet JSON-encoded.
-- @usage make_error("Dude, did you just keyspam?")  --> table
-- @usage make_error("Nerds beware!", 20)     --> table
local function make_error(message, code)
	return {
		code = code or -32602,
		message = message,
	}
end

--- Returns whether the given URI is acceptable.
-- In order to ease server load, all given LBRY claim URIs must be full-length
-- permanent claim-id URIs. This allows the server to not have to resolve claims
-- and to not have to check for claim URI outbidding. More info at:
--
-- https://github.com/lbryio/lbry.tech/blob/master/documents/resources/uri.md
-- @tparam string uri The URI to validate.
-- @treturn boolean Whether or not the URI is acceptable.
-- @usage valid_perm_uri("lbry://one")  --> false
-- @usage
-- valid_perm_uri("lbry://lolkris#53ecfd214b62f38b1bec9849b7a69127b30cd26c")
-- --> true
local function valid_perm_uri(uri)
	local success = uri:match("^lbry://[%w%-]+#([%da-f]+)$")
	
	if success then
		return success:len() == 40
	else
		return false
	end
end

--------------------------------------------------------------------------------
-- Error Codes
-- @section errcodes

--- A table of predefined error codes.
-- @table error_code

--- An unknown or very miscellaneous error.
-- Value: -1
error_code.UNKNOWN = -1
--- An internal error.
-- Value: -32603
error_code.INTERNAL = -32603
--- Invalid parameters.
-- Value: -32602
error_code.INVALID_PARAMS = -32602
--- Invalid claim URI.
-- Value: 1
error_code.INVALID_URI = 1

--------------------------------------------------------------------------------
-- Miscellaneous API
-- @section pubapimisc

--- Returns the string "pong".
-- This function is hyper-optimized and uses a lot of very high-level computer
-- science techniques in order to produce the output it does.
-- @treturn string "pong"
-- @usage {"jsonrpc": "2.0", "method": "ping", "id": 1} -> [server]
-- [server] -> {"jsonrpc": "2.0", "id": 1, "result": "pong"}
function api.ping()
	return "pong"
end

--- Returns the status and versions of the server components.
-- @treturn table status
--
-- `status.is_running` is a boolean, always `true`.
--
-- `status.is_db_running` is a boolean, describing whether the database is
-- currently running.
--
-- `status.api_version` is a string, representing the SemVer 2.0.0 version
-- of the API.
--
-- `status.db_version` is a string, representing the SemVer 2.0.0 version
-- of the database.
-- @usage {"jsonrpc": "2.0", "method": "status", "id": 1} -> [server]
-- [server] -> {"jsonrpc": "2.0", "id": 1, "result": {
-- 	"is_running": true,
-- 	"is_db_running": true,
-- 	"api_version": "0.0.0",
-- 	"db_version": "0.0.3"
-- }}
function api.status()
	return {
		is_running = true,
		is_db_running = db.is_running(),
		api_version = api_VERSION,
		db_version = db._VERSION,
	}
end

--------------------------------------------------------------------------------
-- Claim API
-- @section pubapiclaim

--- Returns the data associated with a claim.
-- @tparam table params The table of parameters.
--
-- `params.uri`: A string containing a full-length permanent LBRY claim URI.
-- If the URI isn't valid/acceptable, the function will return with an
-- `error_code.INVALID_URI` response.
-- @treturn[1] table The data associated with that URI, if the URI has data.
--
-- Fields:
--
-- `claim_index`: An int holding the index of the claim.
--
-- `lbry_perm_uri`: The represented permanent LBRY claim's URI. Includes the
-- "lbry://".
--
-- `add_time`: An int representing the time of the row's insertion into the
-- database, stored as UTC Epoch seconds.
--
-- `upvotes`: An int representing the amount of upvotes for that claim.
--
-- `downvotes`: An int representing the amount of downvotes for that claim.
--
-- @treturn[2] NULL There is no associated data.
-- @usage {"jsonrpc": "2.0", "method": "get_claim_data", "id": 1, "params": {
-- 	"uri": "lbry://lolkris#53ecfd214b62f38b1bec9849b7a69127b30cd26c"
-- }} -> [server]
-- [server] -> {"jsonrpc": "2.0", "id": 1, "result": {
--  "claim_index": 1,
--  "lbry_perm_uri": lbry://lolkris#53ecfd214b62f38b1bec9849b7a69127b30cd26c",
--  "add_time": 1544759333,
--  "upvotes": 0,
--  "downvotes": 0
-- }}
function api.get_claim_data(params)
	if type(params.uri) ~= "string" then
		return nil, make_error"'uri' must be a string"
	elseif not valid_perm_uri(params.uri) then
		return nil, make_error("'uri' unacceptable form",
		                       error_code.INVALID_URI)
	end
	
	local data, err_msg = db.claims.get_data(params.uri)
	
	if data and not err_msg then
		return data
	elseif err_msg == "claim doesnt exist" then
		return json.null
	elseif err_msg then
		return nil, make_error(err_msg, error_code.INTERNAL)
	else
		ngx.log(ngx.ERR, "weird error [get_claim_data]")
		return nil, make_error("unknown", error_code.UNKNOWN)
	end
end

--- Upvotes a claim and returns the new total amount of upvotes.
-- @tparam table params The table of parameters.
--
-- `params.uri`: A string containing a full-length permanent LBRY claim URI.
-- If the URI isn't valid/acceptable, the function will return with an
-- `error_code.INVALID_URI` response.
-- @treturn int The new total amount of upvotes.
-- @usage {"jsonrpc": "2.0", "method": "upvote_claim", "id": 1, "params": {
-- 	"uri": "lbry://lolkris#53ecfd214b62f38b1bec9849b7a69127b30cd26c"
-- }} -> [server]
-- [server] -> {"jsonrpc": "2.0", "id": 1, "result": 5}
function api.upvote_claim(params)
	if type(params.uri) ~= "string" then
		return nil, make_error"'uri' must be a string"
	elseif not valid_perm_uri(params.uri) then
		return nil, make_error("'uri' unacceptable form",
		                       error_code.INVALID_URI)
	end
	
	-- We get the data for the claim to tell if it exists. If it doesn't
	-- exist in the database, we create it on-demand.
	local _, err_msg = db.claims.get_data(params.uri)
	
	if err_msg == "uri doesnt exist" then
		local success, err_msg = db.claims.new(params.uri)
		
		if not success then 
			if err_msg then
				return nil, make_error(err_msg,
				                       error_code.INTERNAL)
			else
				return nil, make_error("unknown",
				                       error_code.UNKNOWN)
			end
		end
	elseif err_msg then
		return nil, make_error(err_msg, error_code.INTERNAL)
	end
	
	local total, err_msg = db.claims.upvote(params.uri)
	
	if total and not err_msg then
		return total
	elseif err_msg then
		return nil, make_error(err_msg, error_code.INTERNAL)
	else
		ngx.log(ngx.ERR, "weird error [upvote_claim]: (" .. total ..
		        ", " .. err_msg .. ")")
		return nil, make_error("unknown", error_code.UNKNOWN)
	end
end

--- Downvotes a claim and returns the new total amount of downvotes.
-- @tparam table params The table of parameters.
--
-- `params.uri`: A string containing a full-length permanent LBRY claim URI.
-- If the URI isn't valid/acceptable, the function will return with an
-- `error_code.INVALID_URI` response.
-- @treturn int The new total amount of downvotes.
-- @usage {"jsonrpc": "2.0", "method": "downvote_claim", "id": 1, "params": {
-- 	"uri": "lbry://lolkris#53ecfd214b62f38b1bec9849b7a69127b30cd26c"
-- }} -> [server]
-- [server] -> {"jsonrpc": "2.0", "id": 1, "result": 5}
function api.downvote_claim(params)
	if type(params.uri) ~= "string" then
		return nil, make_error"'uri' must be a string"
	elseif not valid_perm_uri(params.uri) then
		return nil, make_error("'uri' unacceptable form",
		                       error_code.INVALID_URI)
	end
	
	-- We get the data for the claim to tell if it exists. If it doesn't
	-- exist in the database, we create it on-demand.
	local _, err_msg = db.claims.get_data(params.uri)
	
	if err_msg == "uri doesnt exist" then
		local success, err_msg = db.claims.new(params.uri)
		
		if not success then 
			if err_msg then
				return nil, make_error(err_msg,
				                       error_code.INTERNAL)
			else
				return nil, make_error("unknown",
				                       error_code.UNKNOWN)
			end
		end
	elseif err_msg then
		return nil, make_error(err_msg, error_code.INTERNAL)
	end
	
	local total, err_msg = db.claims.downvote(params.uri)
	
	if total and not err_msg then
		return total
	elseif err_msg then
		return nil, make_error(err_msg, error_code.INTERNAL)
	else
		ngx.log(ngx.ERR, "weird error [downvote_claim]: (" .. total ..
		        ", " .. err_msg .. ")")
		return nil, make_error("unknown", error_code.UNKNOWN)
	end
end

--- Gets the URI of a claim given its claim index.
-- @tparam table params The table of parameters.
--
-- `params.claim_index` A signed int holding the index of the claim.
-- @treturn[1] string The full-length permanent LBRY URI associated with the
-- provided index.
-- @treturn[2] NULL If there is no URI associated with the provided claim index.
-- @usage {"jsonrpc": "2.0", "method": "get_claim_uri", "id": 1, "params": {
-- 	"claim_index": 1
-- }} -> [server]
-- [server] -> {"jsonrpc": "2.0", "id": 1,
-- 	"result": "lbry://lolkris#53ecfd214b62f38b1bec9849b7a69127b30cd26c"
-- }
function api.get_claim_uri(params)
	if type(params.claim_index) ~= "number" then
		return nil, make_error"'claim_index' must be a number"
	elseif params.claim_index % 1 ~= 0 then
		return nil, make_error"'claim_index' must be an int"
	end
	
	local uri, err_msg = db.claims.get_uri(params.claim_index)
	
	if uri and not err_msg then
		return uri
	elseif err_msg == "uri not found" then
		return json.null
	elseif err_msg then
		return nil, make_error(err_msg, error_code.INTERNAL)
	else
		ngx.log(ngx.ERR, "weird error [get_claim_uri]: (" .. total ..
		        ", " .. err_msg .. ")")
		return nil, make_error("unknown", error_code.UNKNOWN)
	end
end

--- Returns all top-level comments on a claim.
-- @tparam table params The table of parameters.
--
-- `params.uri`: A string containing a full-length permanent LBRY claim URI.
-- If the URI isn't valid/acceptable, the function will return with an
-- `error_code.INVALID_URI` response.
-- @treturn[1] table An array of top-level comments.
--
-- Fields for each comment:
--
-- `comm_index`: An int holding the index of the comment.
--
-- `claim_index`: An int holding the index of the claims that this is a
-- comment on.
--
-- `poster_name`: A string holding the name of the poster.
--
-- `parent_com`: An int holding the `comment_index` field of another comment
-- object that is the parent of this comment. Because these comments are always
-- top-level comments, the field is omitted (`nil`).
--
-- `post_time`: An int representing the time of the row's insertion into the
-- database, stored as UTC Epoch seconds.
--
-- `message`: A string holding the body of the comment.
--
-- `upvotes`: An int representing the amount of upvotes for that comment.
--
-- `downvotes`: An int representing the amount of downvotes for that
-- comment.
--
-- @treturn[2] NULL The claim is not in the database.
-- @usage {"jsonrpc": "2.0", "method": "get_claim_comments", "id": 1,
--  "params": {
-- 	"uri": "lbry://lolkris#53ecfd214b62f38b1bec9849b7a69127b30cd26c"
-- }} -> [server]
-- [server] -> {"jsonrpc": "2.0", "id": 1, "result": [...]}
function api.get_claim_comments(params)
	if type(params.uri) ~= "string" then
		return nil, make_error"'uri' must be a string"
	elseif not valid_perm_uri(params.uri) then
		return nil, make_error("'uri' unacceptable form",
		                       error_code.INVALID_URI)
	end
	
	local tlcs, err_msg = db.claims.get_comments(params.uri)
	
	if err_msg == "uri doesnt exist" then
		return json.null
	elseif err_msg then
		return nil, make_error(err_msg, error_code.INTERNAL)
	else
		return tlcs
	end
end

--------------------------------------------------------------------------------
-- Comment API
-- @section pubapicomment

--- Creates a top-level comment and returns its ID.
-- WARNING: The function db.comments.new causes a data race! Make sure to spit
-- on the devs until they fix it.
-- @tparam table params The table of parameters.
--
-- `params.uri`: A string containing a full-length permanent LBRY claim URI.
-- If the URI isn't valid/acceptable, the function will return with an
-- `error_code.INVALID_URI` response.
--
-- `params.poster`: A string containing the username or moniker of the poster.
-- The string, after having all beginning and end whitespace stripped, must be
-- at least 2 bytes long and less than 128 bytes long.
--
-- `params.message`: A string containing the message or body of the comment. The
-- body, after having all beginning and end whitespace stripped, must be at
-- least 2 bytes long and less than 65536 bytes long.
-- @treturn int The ID of the comment.
-- @usage {"jsonrpc": "2.0", "method": "comment", "id": 1,
--  "params": {
-- 	"uri": "lbry://lolkris#53ecfd214b62f38b1bec9849b7a69127b30cd26c",
-- 	"poster": "A really cool dude",
-- 	"message": "Wow, great video!"
-- }} -> [server]
-- [server] -> {"jsonrpc": "2.0", "id": 1, "result": 14}
function api.comment(params)
	if type(params.uri) ~= "string" then
		return nil, make_error"'uri' must be a string"
	elseif not valid_perm_uri(params.uri) then
		return nil, make_error("'uri' unacceptable form",
		                       error_code.INVALID_URI)
	elseif type(params.poster) ~= "string" then
		return nil, make_error"'poster' must be a string"
	elseif params.poster:gsub("^%s+", ""):gsub("%s+$", "") == "" then
		return nil, make_error"'poster' only whitespace"
	elseif type(params.message) ~= "string" then
		return nil, make_error"'message' must be a string"
	elseif params.message:gsub("^%s+", ""):gsub("%s+$", "") == "" then
		return nil, make_error"'message' only whitespace"
	end
	
	-- Strip head-and-tail whitespace from poster and message.
	params.poster = params.poster:gsub("^%s+", ""):gsub("%s+$", "")
	params.message = params.message:gsub("^%s+", ""):gsub("%s+$", "")
	
	if params.poster:len() > 127 then
		return nil, make_error"'poster' too long"
	elseif params.poster:len() < 2 then
		return nil, make_error"'poster' too short"
	elseif params.message:len() > 65535 then
		return nil, make_error"'message' too long"
	elseif params.message:len() < 2 then
		return nil, make_error"'message' too short"
	end
	
	local id, err_msg = db.comments.new(params.uri, params.poster,
	                                    params.message)
	
	if id and not err_msg then
		return id
	elseif err_msg then
		return nil, make_error(err_msg, error_code.INTERNAL)
	else
		return nil, make_error("unknown", error_code.UNKNOWN)
	end
end

--- Creates a reply and returns its ID.
-- WARNING: The function db.comments.new_reply causes a data race! Make sure to
-- spit on the devs until they fix it.
-- @tparam table params The table of parameters.
--
-- `params.parent_id`: An int containing the comment ID of the comment that this
-- reply is intended to be a reply to.
--
-- `params.poster`: A string containing the username or moniker of the poster.
-- The string, after having all beginning and end whitespace stripped, must be
-- at least 2 bytes long and less than 128 bytes long.
--
-- `params.message`: A string containing the message or body of the comment. The
-- body, after having all beginning and end whitespace stripped, must be at
-- least 2 bytes long and less than 65536 bytes long.
-- @treturn int The ID of the reply.
-- @usage {"jsonrpc": "2.0", "method": "reply", "id": 1,
--  "params": {
-- 	"parent_id": 243,
-- 	"poster": "A really cool dude",
-- 	"message": "Wow, great video!"
-- }} -> [server]
-- [server] -> {"jsonrpc": "2.0", "id": 1, "result": 511}
function api.reply(params)
	if type(params.parent_id) ~= "number" then
		return nil, make_error"'parent_id' must be a string"
	elseif type(params.poster) ~= "string" then
		return nil, make_error"'poster' must be a string"
	elseif params.poster:gsub("^%s+", ""):gsub("%s+$", "") == "" then
		return nil, make_error"'poster' only whitespace"
	elseif type(params.message) ~= "string" then
		return nil, make_error"'message' must be a string"
	elseif params.message:gsub("^%s+", ""):gsub("%s+$", "") == "" then
		return nil, make_error"'message' only whitespace"
	end
	
	-- Strip head-and-tail whitespace from poster and message.
	params.poster = params.poster:gsub("^%s+", ""):gsub("%s+$", "")
	params.message = params.message:gsub("^%s+", ""):gsub("%s+$", "")
	
	if params.poster:len() > 127 then
		return nil, make_error"'poster' too long"
	elseif params.poster:len() < 2 then
		return nil, make_error"'poster' too short"
	elseif params.message:len() > 65535 then
		return nil, make_error"'message' too long"
	elseif params.message:len() < 2 then
		return nil, make_error"'message' too short"
	end
	
	local id, err_msg = db.comments.new_reply(
	                     params.parent_id,
			     params.poster,
	                     params.message
	                    )
	
	if id and not err_msg then
		return id
	elseif err_msg == "comment doesnt exist" then
		return nil, make_error"parent with given id doesnt exist"
	elseif err_msg then
		return nil, make_error(err_msg, error_code.INTERNAL)
	else
		return nil, make_error("unknown", error_code.UNKNOWN)
	end
end

--- Gets the data for a comment object.
-- @tparam table params The table of parameters.
--
-- `params.comm_index`: An int containing the ID of the comment that data is
-- being requested for.
-- @treturn[1] table A comment object.
--
-- Fields:
--
-- `comm_index`: An int holding the index of the comment.
--
-- `claim_index`: An int holding the index of the claims that this is a
-- comment on.
--
-- `poster_name`: A string holding the name of the poster.
--
-- `parent_com`: An int holding the `comment_index` field of another comment
-- object that is the parent of this comment. Because these comments are always
-- top-level comments, the field is omitted (`nil`).
--
-- `post_time`: An int representing the time of the row's insertion into the
-- database, stored as UTC Epoch seconds.
--
-- `message`: A string holding the body of the comment.
--
-- `upvotes`: An int representing the amount of upvotes for that comment.
--
-- `downvotes`: An int representing the amount of downvotes for that
-- comment.
--
-- @treturn[2] NULL The comment is not in the database.
-- @usage {"jsonrpc": "2.0", "method": "get_comment_data", "id": 1,
--  "params": {
-- 	"comm_index": 1,
-- }} -> [server]
-- [server] -> {"jsonrpc": "2.0", "id": 1, "result": {
--  "comm_index": 1,
--  "claim_index": 1,
--  "poster_name": "cool",
--  "parent_com": null,
--  "post_time": 1544759333,
--  "message": "whats up dude?",
--  "upvotes": 0,
--  "downvotes": 0
-- }}
function api.get_comment_data(params)
	if type(params.comm_index) ~= "number" then
		return nil, make_error"'comm_index' must be an int"
	elseif params.comm_index % 1 ~= 0 then
		return nil, make_error"'comm_index' must be an int"
	end
	
	local data, err_msg = db.comments.get_data(params.comm_index)
	
	if data and not err_msg then
		return data
	elseif err_msg == "comment doesnt exist" then
		return json.null
	elseif err_msg then
		return nil, make_error(err_msg, error_code.INTERNAL)
	else
		ngx.log(ngx.ERR, "weird error [get_comment_data]")
		return nil, make_error("unknown", error_code.UNKNOWN)
	end
end

--------------------------------------------------------------------------------

return api
