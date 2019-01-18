-- This file is itself not part of the LBRY-Comments project. It is licensed
-- under the Expat MIT license defined below.

--[[
Expat MIT License:

Copyright 2018 Grayson Burton and Oleg Silken

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
]]

--------------------------------------------------------------------------------
-- A high-level mutex class using Szymanski's Algorithm.
-- @classmod mutex
-- @alias mc_prototypes
-- @copyright 2018 Grayson Burton and Oleg Silkin
-- @license Expat MIT
-- @author Grayson Burton

local ngx = require "ngx"
local mutex_class = {}
local mc_prototypes = {}

--------------------------------------------------------------------------------

mutex_class.__index = mc_prototypes

function mutex_class.__new_index(self, k, v)
	if mc_prototypes[k] ~= nil and v ~= nil then
		rawset(self, k, v)
	elseif v ~= nil then
		error "You cannot arbitrarily set values in a mutex object"
	end
end

--------------------------------------------------------------------------------

local function check_for_flag_entry(self)
	return self.__flag_state ~= nil and self.__flag_state[self.__id] ~= nil
end

local ngx_sleep = ngx.sleep

local function microsleep()
	return ngx.sleep(0)
end

local function register_assert(self)
	assert(check_for_flag_entry(self), "mutex not registered to a state")
end

-- finds the smallest key >= 1 that is nil.
local function min_open_key(state)
	for i = 1, math.huge do
		if state[i] == nil then
			return i
		end
	end
end

-- finds the smallest key >= 1 that is nil and 1 away from a key that isn't nil
local function min_open_key_around(state)
	local min = math.huge
	
	if state[1] == nil and state[2] then
		return 1
	end
	
	for k,_ in pairs(state) do
		if state[k - 1] == nil and k > 1 then
			min = math.min(min, k - 1)
		elseif state[k + 1] == nil then
			min = math.min(min, k + 1)
		end
	end
	
	return min
end

local function critical_assert(self)
	register_assert(self)
	assert(
		self.__flag_state[self.__id] == 4,
		"mutex not in critical section"
	)
end

local function indifferent_assert(self)
	register_assert(self)
	assert(
		self.__flag_state[self.__id] == 0,
		"mutex spinning for control"
	)
end

--------------------------------------------------------------------------------

local function szymanski_spincondition_1(state)
	for _,v in pairs(state) do
		if v > 2 then
			return false
		end
	end
	
	return true
end

local function szymanski_any_flag_but_me(state, flag, myid)
	for k,v in pairs(state) do
		if k ~= myid and v == flag then
			return true
		end
	end
	
	return false
end

local function szymanski_spincondition_2(state, myid)
	return szymanski_any_flag_but_me(state, 4, myid)
end

local function szymanski_spincondition_3(state, myid)
	for k,v in pairs(state) do
		if v > 1 and myid >= k then
			return true
		end
	end
	
	return false
end

local function szymanski_spincondition_4(state, myid)
	for k,v in pairs(state) do
		if (v > 1 and v ~= 4) and myid >= k then
			return false
		end
	end
	
	return true
end

local function szymanski_entry(mutex)
	local id = mutex.__id
	local state = mutex.__flag_state
	
	state[id] = 1
	
	while not szymanski_spincondition_1(state) do
		microsleep()
	end
	
	state[id] = 3
	
	if szymanski_any_flag_but_me(state, 1, id) then
		state[id] = 2
		
		while not szymanski_spincondition_2(state, id) do
			microsleep()
		end
	end
	
	state[id] = 4
	
	while not szymanski_spincondition_3(state, id) do
		microsleep()
	end
end

local function szymanski_exit(mutex)
	local id = mutex.__id
	local state = mutex.__flag_state
	
	while not szymanski_spincondition_4(state, id) do
		microsleep()
	end
	
	state[id] = 0
end

--------------------------------------------------------------------------------

--- The type of the object.
-- The string "mutex".
mc_prototypes.__type = "mutex"
--- The flag state that the mutex belongs to.
-- Is a potentially sparse array with unsigned integer keys >= 1 holding weak
-- references to mutexes. Each entry is a value between (inclusively) 0 and 4.
-- @local
mc_prototypes.__flag_state = setmetatable({}, {__mode = "v"})
--- The ID in the flag state that refers to this mutex object.
-- Is an unsigned integer >= 1 that can be used to index @{__flag_state}.
-- @local
mc_prototypes.__id = 1
mc_prototypes.__flag_state[mc_prototypes.__id] = 0

--- Returns the ID of the mutex.
-- The returned ID is an unsigned int >= 1 that can be used in this object's
-- flag state to refer to its flag.
-- @treturn int The ID.
-- @usage my_cool_mutex:get_id()  --> 20
function mc_prototypes:get_id()
	register_assert(self)
	
	return self.__id
end

--- Returns the flag of the mutex.
-- @treturn int The flag of the mutex.
-- @usage local my_mutex = new_mutex()
-- my_mutex:get_flag()  --> 0
-- my_mutex:enter()
-- my_mutex:get_flag()  --> 4
-- my_mutex:exit()
-- my_mutex:get_flag()  --> 0
-- @see get_state
function mc_prototypes:get_flag()
	register_assert(self)
	
	return self.__flag_state[self.__id]
end

--- Returns the flag state of the mutex.
-- A flag state is a potentially-spare array of flags. A flag is a value between
-- (inclusively) 0 and 4. If the flag is 0, then the mutex isn't competing. If
-- the flag is 4, then the mutex has won the competition and is now in its
-- critical section. Otherwise, the mutex is in the process of competing for a
-- turn to execute its critical section.
-- @treturn table The flag state that the mutex belongs to.
-- @usage local my_mutex1, my_mutex2 = new_mutex(), new_mutex()
-- local state = my_mutex1:register_with(my_mutex2):get_state()  --> table
function mc_prototypes:get_state()
	return self.__flag_state
end

--- Signals that the mutex wants to enter its critical section.
-- This changes its flag to `1` (see @{get_flag}) and the mutex (thread) is
-- blocked until it can gain control of the mutex. Rather than busy-waiting, it
-- tells the ngx thread scheduler to move on to another thread.
-- @raise "`mutex spinning for control`" if the mutex is already waiting to get
-- its turn for entering its critical section.
-- @treturn nil
-- @usage local my_mutex = new_mutex()
-- my_mutex:enter()
-- print("im in my critical section, mah!")
-- my_mutex:exit()
-- @see exit
function mc_prototypes:enter()
	indifferent_assert(self)
	
	return szymanski_entry(self)
end

--- Signals that the mutex is done with its critical section.
-- The mutex blocks momentarily and then exits from the critical section,
-- setting its flag to `0`. This releases the mutex.
-- @raise "`mutex not in critical section`" if the mutex isn't in its critical
-- section already.
-- @treturn nil
-- @usage local my_mutex = new_mutex()
-- my_mutex:enter()
-- print("im in my critical section, mah!")
-- my_mutex:exit()
-- @see exit
function mc_prototypes:exit()
	critical_assert(self)
	
	return szymanski_exit(self)
end

--- Enters its critical section and executes a function.
-- The mutex blocks until it can enter its critical section, then executes the
-- function with the given arguments. Once that is complete, the mutex exits its
-- critical section and returns the results of the function in a table.
-- @raise "`mutex spinning for control`" if the mutex is already waiting to get
-- its turn for entering its critical section.
-- @tparam function func The function to call in the critical section.
-- @param[opt] ... Any arguments to pass to the function `func` when it is
-- called.
-- @treturn tab The results from the function call.
-- @usage local my_mutex = new_mutex()
-- local function my_func(i) return i ^ 2 end
-- my_mutex:call_when_safe(my_func, 5)  --> {25}
function mc_prototypes:call_when_safe(func, ...)
	self:enter()
	local results = {func(...)}
	self:exit()
	
	return results
end

--- Registers this mutex with another mutex's state.
-- When a mutex is registered with another mutex's state, they can both compete
-- for the ability to enter their critical section. If two mutexes are
-- registered with different states, they'll be unaware of each other and they
-- can't actually mutually exclude each other. They must be in the same state.
-- 
-- If the other mutex shares the same state as this mutex, nothing really
-- happens.
-- @tparam mutex other_mutex The mutex whose state this mutex will register
-- with.
-- @treturn mutex self
-- @usage local mutex1, mutex2 = new_mutex(), new_mutex()
-- mutex1:register_with(mutex2):enter()
-- print "Now we're in our critical section, mutex2 must wait for us to finish."
-- mutex1:exit()
-- @see get_state
function mc_prototypes:register_with(other_mutex)
	register_assert(other_mutex)
	
	if self.__flag_state ~= other_mutex.__flag_state then
		self.__flag_state[self.__id] = nil
		self.__flag_state = other_mutex.__flag_state
		self.__id = min_open_key_around(self.__flag_state)
		self.__flag_state[self.__id] = 0
	end
	
	return self
end

--- Registers the mutex with a fresh, empty flag state.
-- Also, the flag is set to `0` (ie, the mutex is forced out of its critical
-- section). Don't use this on a mutex in its critical section.
-- @treturn mutex self
-- @usage local mutex1, mutex2 = new_mutex(), new_mutex()
-- mutex1:register_with(mutex2)
-- print "I'm in the same state as mutex2!"
-- mutex1:new_state()
-- print "Now I'm in my own state!"
function mc_prototypes:new_state()
	self.__flag_state[self.__id] = nil
	self.__flag_state = setmetatable({}, {__mode = "v"})
	self.__id = 1
	self.__flag_state[self.__id] = 0
	
	return self
end

--- Changes the ID to the minimum positive available ID.
-- The ID will be an int >= 1. If the minimum positive available ID is larger
-- than the current ID (ie, the mutex already has the smallest ID it can get),
-- the ID isn't changed.
-- @treturn mutex self
-- @usage local mutex1, mutex2 = new_mutex(), new_mutex()
-- mutex1:register_with(mutex2)
-- mutex2:new_state()
-- print(mutex1:get_id())                   --> 2
-- print(mutex1:compress_state():get_id())  --> 1
function mc_prototypes:compress_state()
	indifferent_assert(self)
	
	local oldid, flag_state = self.__id, self.__flag_state
	local newid = min_open_key(flag_state)
	self.__flag_state[newid] = 0
	
	if newid >= oldid then
		flag_state[newid] = nil
	else
		flag_state[oldid] = nil
		self.__id = newid
	end
	
	return self
end

-------------------------------------------------------------------------------

return function()
	return setmetatable({}, mutex_class):new_state()
end
