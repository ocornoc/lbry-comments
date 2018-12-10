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

return function()
	local resp_pipe = assert(io.popen[[bash -c "echo \"\$(cd \"\$(dirname \"\${BASH_SOURCE[0]}\")\" && pwd)\""]])
	local resp = assert(resp_pipe:read"*a")
	resp_pipe:close()
	
	ngx.say(resp)
end
