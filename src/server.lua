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

_G.toppath = ngx.config.prefix()
_G.srcpath = _G.toppath .. "/src"

package.path = package.path .. ";" .. _G.srcpath .. "/?.lua"

local db = require "db"
local json = require "cjson"


local function method_get()
	return ngx.say"get"
end

local function method_head()
	return nil
end

local function method_post()
	return ngx.say"post"
end

return function()
	local method = ngx.req.get_method()
	
	if method == "GET" then
		return method_get()
	elseif method == "HEAD" then
		return method_head()
	elseif method == "POST" then
		return method_post()
	else
		return ngx.say"You discovered a bug! Email the owners, please."
	end
end
