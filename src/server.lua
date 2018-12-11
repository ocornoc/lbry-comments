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
-- An OpenResty frontend for db.lua.
-- All JSON-RPC interactions are supposed to use JSON-RPC 2.0 over HTTP.
-- https://www.simple-is-better.org/json-rpc/transport_http.html
-- That JSON-RPC 2.0 over HTTP specification is referred to as "JRPC-HTTP" here
-- sometimes.
-- @module server
-- @copyright 2018 Grayson Burton and Oleg Silkin
-- @license GNU AGPLv3
-- @author Grayson Burton

--------------------------------------------------------------------------------
-- Global Variables
-- @section globals
-- @local

--- The path to the project directory.
_G.toppath = ngx.config.prefix()
--- The path to the "src" subdirectory.
_G.srcpath = _G.toppath .. "/src"

--------------------------------------------------------------------------------

package.path = package.path .. ";" .. _G.srcpath .. "/?.lua"

local db = require "db"
local json = require "cjson"

--------------------------------------------------------------------------------
-- jrpc
-- @section jrpc
-- @local

local jrpc = {}

--- Returns whether the input is a valid JSON-RPC batch request.
-- Doesn't work for single requests.
-- @tparam table tab The decoded JSON table.
-- @treturn[1] bool `true` if it is valid.
-- @treturn[2] nil If it isn't valid.
-- @treturn[2] string An explanation of what caused it not to be valid.
-- @usage jrpc.is_valid_batch_req{jsonrpc = "2.0", {method = "help"}}  --> true
-- @usage jrpc.is_valid_batch_req{jsonrpc = "2.0", method = "help"}    --> false
function jrpc.is_valid_batch_req(tab)
	local success, err_msg
	
	for k,v in ipairs(tab) do
		success, err_msg = jrpc.is_valid_req(v)
		
		if not success then
			return nil, err_msg
		end
	end
	
	return true
end

--- Returns whether the input is a valid JSON-RPC request.
-- Doesn't work for batch requests.
-- @tparam table tab The decoded JSON table.
-- @treturn[1] bool `true` if it is valid.
-- @treturn[2] nil If it isn't valid.
-- @treturn[2] string An explanation of what caused it not to be valid.
-- @usage jrpc.is_valid_req{jsonrpc = "2.0", method = "help"}  --> true
function jrpc.is_valid_req(tab)
	if type(tab.method) ~= "string" then
		return nil, "method not a string"
	elseif tab.params ~= nil and type(tab.params) ~= "table" then
		return nil, "params not nil nor table"
	elseif type(tab.id) ~= "string" and
	       type(tab.id) ~= "number" and
	       tab.id ~= nil then
		return nil, "id not nil nor string nor number"
	else
		return true
	end
end

--- Returns whether the input is valid JSON-RPC.
-- Only works for JSON-RPC 2.0 requests.
-- @tparam table tab The decoded JSON table.
-- @treturn[1] bool `true` if it is valid.
-- @treturn[2] nil If it isn't valid.
-- @treturn[2] string An explanation of what caused it not to be valid.
-- @usage jrpc.is_valid{jsonrpc = "2.0", method = "help"}  --> true
-- @usage jrpc.is_valid{jsonrpc = "1.0", method = "help"}  --> false
function jrpc.is_valid(tab)
	if tab.jsonrpc ~= "2.0" then
		return nil, "unsupported version"
	elseif tab.method == nil then
		return jrpc.is_valid_batch_req(tab)
	else
		return jrpc.is_valid_req(tab)
	end
end

--------------------------------------------------------------------------------
-- Helpers
-- @section helpers
-- @local

--- Gets the body of the request.
-- @raise
-- @treturn string
local function get_body_data()
	ngx.req.read_body()
	
	local body_data = ngx.req.get_body_data()
	
	if not body_data then
		local body_path = ngx.req.get_body_file()
		
		if not body_path then
			ngx.log(ngx.ERR, "Couldn't get req. body")
			
			return ngx.exit(ngx.ERROR)
		end
		
		local handle = io.open(body_path, "rb")
		body_data = handle:read"*a"
		handle:close()
	end
	
	return body_data
end

--------------------------------------------------------------------------------
-- Method handlers
-- @section methods
-- @local

--- Handles the "GET" method.
-- The "GET" method isn't supported. Follows from JRPC-HTTP.
local function method_get()
	ngx.header["Allow"] = "POST"
	
	return ngx.exit(ngx.HTTP_NOT_ALLOWED)
end

--- Handles the "HEAD" method.
-- It's just a call to @{method_get}.
local function method_head()
	return method_get()
end

--- Handles the "POST" method.
local function method_post()
	local headers, err_msg = ngx.req.get_headers()
	
	if err_msg == "truncated" then
		-- If the request headers are too big, just bail.
		-- OpenResty doesn't support Status 431.
		return ngx.exit(ngx.ERROR)
	-- If no "Accept" header field, it's assumed to equal "Content-Type".
	elseif headers["Accept"] ~= nil and
	       headers["Accept"] ~= "*/*" and
	       headers["Accept"] ~= "application/*" and
	       headers["Accept"] ~= "application/json" then
		-- We only generate JSON.
		return ngx.exit(ngx.HTTP_NOT_ACCEPTABLE)
	elseif headers["Content-Type"] ~= "application/json" then
		-- We only can accept JSON.
		-- OpenResty doesn't support Status 415.
		return ngx.exit(ngx.ERROR)
	end
	
	local body = get_body_data()
	
	return ngx.say(body)
end

--------------------------------------------------------------------------------

return function()
	local method = ngx.req.get_method()
	
	if method == "GET" then
		return method_get()
	elseif method == "HEAD" then
		return method_head()
	elseif method == "POST" then
		return method_post()
	else
		ngx.log(ngx.ERR, "Method '" .. method .. "' slipped through.")
		
		return ngx.say"You discovered a bug! Email the owners, please."
	end
end
