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

local api_VERSION = "0.0.0"

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
-- API
-- @section pubapi

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

--- Returns the data associated with a claim.
-- @tparam table args The table of arguments.
--
-- `args.uri` A string containing a full-length permanent LBRY claim URI.
-- If the URI isn't valid/acceptable, the function will return with an
-- `error_code.INVALID_URI` response.
-- @treturn[1] table The data associated with that URI, if the URI has data.
-- @treturn[2] NULL There is no associated data.
-- @usage {"jsonrpc": "2.0", "method": "get_claim_data", "id": 1, "params": {
-- 	"uri": "lbry://lolkris#53ecfd214b62f38b1bec9849b7a69127b30cd26c"
-- }} -> [server]
-- [server] -> {"jsonrpc": "2.0", "id": 1, "result": {...}}
function api.get_claim_data(args)
	if type(args.uri) ~= "string" then
		return nil, make_error"'uri' must be a string"
	elseif not valid_perm_uri(args.uri) then
		return nil, make_error("'uri' unacceptable form",
		                       error_code.INVALID_URI)
	end
	
	local data, err_msg = db.claims.get_data(args.uri)
	
	if data and not err_msg then
		return data
	elseif err_msg == "claim doesnt exist" then
		return json.null
	elseif err_msg then
		return nil, make_error(err_msg, error_code.INTERNAL)
	else
		return nil, make_error("unknown", error_code.INTERNAL)
	end
end

--------------------------------------------------------------------------------

return api
