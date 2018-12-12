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
-- An OpenResty frontend for api.lua.
-- All JSON-RPC interactions are supposed to use JSON-RPC 2.0 over HTTP.
--
-- https://www.simple-is-better.org/json-rpc/transport_http.html
--
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
-- @local
_G.toppath = ngx.config.prefix()
--- The path to the "src" subdirectory.
-- @local
_G.srcpath = _G.toppath .. "/src"

--------------------------------------------------------------------------------

package.path = package.path .. ";" .. _G.srcpath .. "/?.lua"

local api = require "api"
local json = require "cjson"
local jrpc = {}

--------------------------------------------------------------------------------
-- JSON-RPC
-- @section jrpcsec
-- @local

--- Returns a JSON-RPC error response object.
-- `id` can be `nil`, JSON `NULL`, a number, or a string.
-- WARNING: will *not* throw if the type is wrong.
-- @tparam string message The concise error descriptor or reason.
-- @tparam[opt=-32600] int code The error code.
-- @param[opt=null] id The ID of the error's recipient.
-- @treturn table The JSON-RPC error response object, not yet JSON-encoded.
-- @local
-- @usage jrpc.make_error("Dude, did you just keyspam?")  --> table
-- @usage jrpc.make_error("Nerds beware!", 20, "bob")     --> table
function jrpc.make_error(message, code, id)
	return {
		jsonrpc = "2.0",
		error = {
			code = code or -32600,
			message = message
		},
		id = id or json.null,
	}
end

--- Dispatches API calls for a batch request.
-- @tparam table tab A JRPC batch request object.
-- @treturn[1] table An array of JRPC responses for the batch of requests.
-- The index of the response object matches the index of the request it is
-- a response to.
-- @treturn[2] table A JRPC error response object if the batch couldn't be
-- started.
-- @local
-- @see jrpc.dispatch_req
function jrpc.dispatch_batch(tab)
	if type(tab) ~= "table" then
		return jrpc.make_error("not an array")
	elseif #tab == 0 then
		return jrpc.make_error("empty array")
	end
	
	local int_index_count = 0
	
	for k,v in pairs(tab) do
		if type(k) == "number" then
			int_index_count = int_index_count + 1
		else
			return jrpc.make_error("not an array")
		end
	end
	
	if int_index_count ~= #tab then
		return jrpc.make_error("sparse array")
	end
	
	local results = {}
	
	for k,v in ipairs(tab) do
		results[k] = jrpc.dispatch_req(v)
	end
	
	return results
end

--- Dispatches an API call for a request.
-- @tparam table tab A JRPC request object.
-- @treturn table The JRPC response object that is associated with the inputted
-- request object.
-- @local
function jrpc.dispatch_req(tab)
	if type(tab) ~= "table" then
		return jrpc.make_error("not a table")
	elseif tab.jsonrpc ~= "2.0" then
		return jrpc.make_error("unsupported version")
	elseif type(tab.method) ~= "string" then
		return jrpc.make_error("method not a string")
	elseif tab.params ~= nil and
	       tab.params ~= json.null and
	       type(tab.params) ~= "table" then
		return jrpc.make_error("params not nil/table/null")
	elseif type(tab.id) ~= "string" and
	       type(tab.id) ~= "number" and
	       tab.id ~= nil and
	       tab.id ~= json.null then
		return jrpc.make_error("id not null/nil/string/number")
	elseif api[tab.method] then
		local result, err = api[tab.method](tab.params)
		
		if tab.id ~= nil and tab.id ~= json.null then
			if result and not err then
				return {
					jsonrpc = "2.0",
					id = tab.id,
					result = result
				}
			else
				return {
					jsonrpc = "2.0",
					id = tab.id,
					error = err,
				}
			end
		end
	else
		return jrpc.make_error("method not found", -32601)
	end
end

--- Dispatches the object according to its type.
-- If the object is a batch request, it gets sent to the appropriate dispatcher.
-- Otherwise, it gets sent to the request dispatcher.
-- @tparam table tab A JRPC request or batch request object.
-- @treturn table The result of the object's associated dispatcher.
-- @local
-- @see jrpc.dispatch_req
-- @see jrpc.dispatch_batch
function jrpc.dispatch(tab)
	if tab.method == nil then
		return jrpc.dispatch_batch(tab)
	else
		return jrpc.dispatch_req(tab)
	end
end

--------------------------------------------------------------------------------
-- Helpers
-- @section helpers
-- @local

--- Gets the body of the request.
-- @raise Will quit with a Status 400 if it can't get the request body.
-- @treturn string
local function get_body_data()
	ngx.req.read_body()
	
	local body_data = ngx.req.get_body_data()
	
	if not body_data then
		local body_path = ngx.req.get_body_file()
		
		if not body_path then
			ngx.log(ngx.ERR, "Couldn't get req. body")
			
			return ngx.exit(ngx.ERR)
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
		return ngx.exit(ngx.ERR)
	-- If no "Accept" header field, it's assumed to equal "Content-Type".
	elseif headers["Accept"] ~= nil and
	       headers["Accept"] ~= "*/*" and
	       headers["Accept"] ~= "application/*" and
	       headers["Accept"] ~= "application/json" then
		-- We only generate JSON.
		return ngx.exit(ngx.HTTP_NOT_ACCEPTABLE)
	elseif headers["Content-Type"] ~= "application/json" then
		-- We only can accept JSON.
		-- OpenResty doesn't support Status 415 *in documentation*.
		-- I accidentally found out that does anyways but I don't
		-- want to depend on it.
		return ngx.exit(ngx.ERR)
	end
	
	local body = get_body_data():gsub("^%s+", ""):gsub("%s+$", "")
	local decoded
	local success, err_msg = pcall(function()
		decoded = json.decode(body)
	end)
	
	if not success then
		return ngx.say(json.encode{
			jsonrpc = "2.0",
			error = {
				code = -32700,
				message = "invalid json, failed to parse",
			},
			id = json.null
		})
	end
	
	local result = jrpc.dispatch(decoded)
	
	if result then
		return ngx.say(json.encode(result))
	end
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
