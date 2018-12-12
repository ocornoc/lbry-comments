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

local api_VERSION = "0.0.0"

--------------------------------------------------------------------------------
-- Helpers
-- @section helpers
-- @local

--- This returns a JSON-RPC error response object.
-- `id` can be `nil`, JSON `NULL`, a number, or a string.
-- WARNING: will *not* throw if the type is wrong.
-- @tparam string message The concise error descriptor or reason.
-- @tparam[opt=-32600] int code The error code.
-- @param[opt=null] id The ID of the error's recipient.
-- @treturn table The JSON-RPC error response object, not yet JSON-encoded.
-- @usage make_error("Dude, did you just keyspam?")  --> table
-- @usage make_error("Nerds beware!", 20, "bob")     --> table
local function make_error(message, code, id)
	return {
		jsonrpc = "2.0",
		error = {
			code = code or -32600,
			message = message,
		},
		id = id or json.null,
	}
end

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

--------------------------------------------------------------------------------

return api
