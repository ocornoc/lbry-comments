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
-- Unit test for mutexes

local new_mutex = require "mutex"
local assert = require "luassert"
local ngx = require "ngx"

--------------------------------------------------------------------------------

local state1, state2, state3
local mutex1, mutex2, mutex3

-- Tests for the constructor function for mutexes.
describe("The mutex constructor", function()
	-- Make sure that the mutex constructor actually works.
	it("should be able to create new mutexes", function()
		-- The constructor shouldn't throw errors when called.
		assert.has_no.errors(function()
			mutex1 = new_mutex()
			mutex2 = new_mutex()
			mutex3 = new_mutex()
		end)
		
		-- The mutex Lua type should be a table.
		assert.is_equal("table", type(mutex1))
		assert.is_equal("table", type(mutex2))
		assert.is_equal("table", type(mutex3))
		
		-- The `mutex.__type` field should be "mutex".
		assert.is_equal("mutex", mutex1.__type)
		assert.is_equal("mutex", mutex2.__type)
		assert.is_equal("mutex", mutex3.__type)
	end)
end)

-- Tests for any mutex object, competing or not.
-- A competing mutex is a mutex that is attempting to enter its critical
-- section, such as vying for control of a file handle. A noncompeting mutex is
-- a mutex that isn't waiting for its turn to enter its critical section.
-- Some tests relating to states, IDs, flags, and entering/exiting a critical
-- section can't be done on a noncompeting mutex, as the behaviour of a mutex
-- changes somewhat when it becomes competitive.
describe("A mutex object", function()
	-- Make sure we can get the flag state of a mutex.
	it("should be able to get its state", function()
		-- Getting the state shouldn't throw errors.
		assert.has_no.errors(function()
			state1 = mutex1:get_state()
			state2 = mutex2:get_state()
			state3 = mutex3:get_state()
		end)
		
		-- The returned flag state should be a table.
		assert.is_equal("table", type(state1))
		assert.is_equal("table", type(state2))
		assert.is_equal("table", type(state3))
		
		-- The returned flag state should equal the private state field.
		assert.are_equal(state1, mutex1.__flag_state)
		assert.are_equal(state2, mutex2.__flag_state)
		assert.are_equal(state3, mutex3.__flag_state)
	end)
	
	-- The default state of a mutex should be constant.
	it("should have a predictable default state", function()
		-- The default state should be the same as {0}.
		assert.is_same({0}, state1)
		assert.is_same({0}, state2)
		assert.is_same({0}, state3)
		
		-- The default state shouldn't be recycled.
		-- Make sure each state refers to a unique table.
		assert.is_not_equal(state1, state2)
		assert.is_not_equal(state1, state3)
		assert.is_not_equal(state2, state1)
		assert.is_not_equal(state2, state3)
		assert.is_not_equal(state3, state1)
		assert.is_not_equal(state3, state2)
	end)
	
	-- Mutexes should be able to "register" with other mutexes. Registering
	-- a mutex means to switch its state to that of another mutex. Mutexes
	-- must be registered with eachother (ie, being registered to the same
	-- state) in order to compete for a resource. If two mutexes aren't
	-- registered with eachother, they should be unaware of eachother and
	-- won't be able to compete with each other.
	it("should be able to register with other mutexes", function()
		-- Create some temporary test mutexes.
		
		-- We need a temporary mutex to hold mutex1's old state.
		-- We're essentially barrel-shifting the mutexes and states.
		-- mutex1 --> state2; mutex2 --> state3; mutex3 --> state1;
		-- This will be undone at the end via reverse shifting.
		local temp_mutex_1 = new_mutex()
		local temp_mutex_2 = new_mutex()
		-- We also check to make sure that old states properly remove
		-- old entries.
		local temp_old_state = temp_mutex_1:get_state()
		
		-- Make sure we can register mutexes without causing errors.
		assert.has_no.errors(function()
			temp_mutex_2:register_with(temp_mutex_1)
			temp_mutex_1:register_with(mutex1)
			mutex1:register_with(mutex2)
			mutex2:register_with(mutex3)
			mutex3:register_with(temp_mutex_1)
		end)
		
		-- Make sure we successfully barrel-shifted the states.
		assert.are_equal(state1, mutex3:get_state())
		assert.are_equal(state2, mutex1:get_state())
		assert.are_equal(state3, mutex2:get_state())
		assert.is_same({nil, 0}, temp_old_state)
		
		-- Now for the undo step:
		-- mutex1 --> state1; mutex2 --> state2; mutex3 --> state3;
		assert.has_no.errors(function()
			mutex3:register_with(mutex2)
			mutex2:register_with(mutex1)
			mutex1:register_with(temp_mutex_1)
			temp_mutex_1:register_with(temp_mutex_2)
		end)
		
		-- Make sure we undid the barrel-shifting.
		assert.are_equal(state1, mutex1:get_state())
		assert.are_equal(state2, mutex2:get_state())
		assert.are_equal(state3, mutex3:get_state())
		assert.are_equal(temp_old_state, temp_mutex_1:get_state())
		
		-- Make sure the states are in the expected (original) state.
		assert.is_same({0, 0}, temp_old_state)
		assert.is_same({0}, state1)
		assert.is_same({0}, state2)
		assert.is_same({0}, state3)
	end)
	
	-- An individual, noncompeting mutex should be able to "minimize" its
	-- ID. This means that it changes its ID to that of the smallest open
	-- ID that is >= 1, or keeps its original ID if that is already the
	-- smallest possible.
	it("should be able to compress its state", function()
		-- Create some temporary mutexes so that we don't mess up our
		-- pre-existing states and mutexes.
		local temp_mutex_1 = new_mutex()
		local temp_mutex_2 = new_mutex():register_with(temp_mutex_1)
		local temp_mutex_3 = new_mutex():register_with(temp_mutex_1)
		local temp_mutex_4 = new_mutex():register_with(temp_mutex_1)
		local temp_mutex_5 = new_mutex()
		local temp_state_1 = temp_mutex_1:get_state()
		local temp_state_2 = temp_mutex_5:get_state()
		assert.is_same({0, 0, 0, 0}, temp_state_1)
		assert.is_same({0}, temp_state_2)
		
		-- Make sure it doesn't error from calling alone
		assert.has_no.errors(function()
			temp_mutex_5:compress_state()
		end)
		-- The states should remain unchanged.
		assert.is_same({0, 0, 0, 0}, temp_state_1)
		assert.is_same({0}, temp_state_2)
		
		temp_mutex_1:register_with(temp_mutex_5)
		temp_mutex_2:register_with(temp_mutex_5)
		temp_mutex_3:register_with(temp_mutex_5)
		assert.is_same({nil, nil, nil, 0}, temp_state_1)
		assert.is_same({0, 0, 0, 0}, temp_state_2)
		temp_mutex_4:compress_state()
		assert.is_same({0}, temp_state_1)
		assert.is_same({0, 0, 0, 0}, temp_state_2)
		
		temp_mutex_1:register_with(temp_mutex_4)
		assert.is_same({0, 0}, temp_state_1)
		assert.is_same({0, nil, 0, 0}, temp_state_2)
		temp_mutex_3:compress_state()
		assert.is_same({0, 0}, temp_state_1)
		assert.is_same({0, 0, 0}, temp_state_2)
	end)
	
	-- Mutexes should be able to get their ID.
	it("should be able to get its ID", function()
		-- We basically make some temporary mutexes and mess around with
		-- their states, making sure their IDs remain consistent.
		local temp_mutex_1 = new_mutex()
		local temp_mutex_2 = new_mutex()
		local temp_mutex_3 = new_mutex()
		local temp_mutex_4 = new_mutex()
		local temp_mutex_5 = new_mutex()
		
		local id1, id2, id3, id4, id5, idtable
		
		-- Make sure errors aren't thrown from calling the function.
		local function set_ids()
			id1 = temp_mutex_1:get_id()
			id2 = temp_mutex_2:get_id()
			id3 = temp_mutex_3:get_id()
			id4 = temp_mutex_4:get_id()
			id5 = temp_mutex_5:get_id()
			
			idtable = {id1, id2, id3, id4, id5}
		end
		
		assert.has_no.errors(set_ids)
		assert.are_same({1, 1, 1, 1, 1}, idtable)
		
		temp_mutex_1:register_with(temp_mutex_2)
		temp_mutex_3:register_with(temp_mutex_4)
		set_ids()
		assert.are_same({2, 1, 2, 1, 1}, idtable)
		
		temp_mutex_2:register_with(temp_mutex_3)
		temp_mutex_4:register_with(temp_mutex_5)
		set_ids()
		assert.are_same({2, 3, 2, 2, 1}, idtable)
		
		temp_mutex_1:register_with(temp_mutex_2)
		temp_mutex_3:register_with(temp_mutex_4)
		set_ids()
		assert.are_same({1, 3, 3, 2, 1}, idtable)
		
		temp_mutex_2:register_with(temp_mutex_3)
		temp_mutex_4:register_with(temp_mutex_5)
		set_ids()
		assert.are_same({1, 4, 3, 2, 1}, idtable)
	end)
	
	-- Mutexes should be able to get their flag status.
	it("should be able to get its flag", function()
		-- Create two temporary mutexes.
		local temp_mutex_1 = new_mutex()
		local temp_mutex_2 = new_mutex()
		
		local flag1, flag2, flagtable
		
		-- Make sure getting the flags doesn't error, and populate the
		-- relevant variables.
		local function set_flags()
			flag1 = temp_mutex_1:get_flag()
			flag2 = temp_mutex_2:get_flag()
			
			flagtable = {flag1, flag2}
		end
		
		assert.has_no.errors(set_flags)
		assert.are_same({0, 0}, flagtable)
		
		temp_mutex_1:register_with(temp_mutex_2)
		set_flags()
		assert.are_same({0, 0}, flagtable)
	end)
end)

describe("A competing mutex object", function()
	-- We have 5 temporary mutexes for the scenario and one that we're
	-- actively testing.
	local temp_mutex_1
	local temp_mutex_2
	local temp_mutex_3
	local temp_mutex_4
	local temp_mutex_5
	local temp_state
	local test_mutex
	local test_state
	-- We have these canary mutexes and states to attempt to make sure that
	-- changes in one mutex or state don't affect others. We also keep a
	-- backup of every canary in case the variable itself got affected.
	local canary_mutex, canary_mutex_backup
	local canary_state, canary_state_backup
	-- A table of threads.
	local threads = {}
	
	local function setup_scenario()
		temp_mutex_1 = new_mutex()
		temp_mutex_2 = new_mutex():register_with(temp_mutex_1)
		temp_mutex_3 = new_mutex():register_with(temp_mutex_1)
		temp_mutex_4 = new_mutex():register_with(temp_mutex_1)
		temp_mutex_5 = new_mutex():register_with(temp_mutex_1)
		test_mutex = new_mutex()
		canary_mutex = new_mutex()
		canary_mutex_backup = canary_mutex
		
		temp_state = temp_mutex_1:get_state()
		test_state = test_mutex:get_state()
		canary_state = canary_mutex:get_state()
		canary_state_backup = canary_state
	end
	
	-- Clean threads.
	local function clean_threads()
		for k,v in pairs(threads) do
			ngx.thread.kill(v)
			threads[k] = nil
		end
		
		threads = {}
	end
	
	-- Waits for all threads to finish.
	local function wait_on_threads()
		for k,v in pairs(threads) do
			ngx.thread.wait(v)
		end
	end
	
	-- Before each test, setup the test scenario and clean up threads.
	before_each(function()
		setup_scenario()
		clean_threads()
	end)
	
	-- After each test, make sure the canaries weren't dirtied and clean up
	-- threads.
	after_each(function()
		clean_threads()
		
		-- Make sure the backup variables are the same as the originals.
		assert.are_equal(canary_mutex, canary_mutex_backup)
		assert.are_equal(canary_state, canary_state_backup)
		-- Make sure that the canary state is still the default.
		assert.are_same(new_mutex():get_state(), canary_state)
		-- Make sure that the canary mutex is still the default.
		assert.are_same(new_mutex(), canary_mutex)
		-- Check that canary mutex's state matches the canary_state
		-- variable.
		assert.are_equal(canary_state, canary_mutex:get_state())
	end)
	
	-- Mutex objects should be able to enter competitions and exit
	-- competiions.
	it("should be able to enter/exit its competition", function()
		local unsafe_table = {}
		local ready = false
		
		local function test_function(my_mutex, number)
			return function()
				while not ready do
					ngx.sleep(0)
				end
				
				my_mutex:enter()
				unsafe_table[#unsafe_table + 1] = number
				my_mutex:exit()
			end
		end
		
		-- Test test_mutex by itself.
		threads[1] = ngx.thread.spawn(test_function(test_mutex, 1))
		ready = true
		wait_on_threads()
		clean_threads()
		assert.are_same({1}, unsafe_table)
		ready = false
		
		-- Register test_mutex with temp_mutex_1.
		test_mutex:register_with(temp_mutex_1)
		
		-- Test this order:
		--  * test_mutex
		ready = false
		threads[1] = ngx.thread.spawn(test_function(test_mutex, 2))
		ready = true
		wait_on_threads()
		clean_threads()
		assert.are_same({1, 2}, unsafe_table)
		ready = false
		
		-- Test this order:
		--  * test_mutex
		--  * temp_mutex_1
		ready = false
		threads[1] = ngx.thread.spawn(test_function(test_mutex, 3))
		threads[2] = ngx.thread.spawn(test_function(temp_mutex_1, 4))
		ready = true
		wait_on_threads()
		clean_threads()
		assert.are_same({1, 2, 3, 4}, unsafe_table)
		ready = false
		
		-- Test this order:
		--  * temp_mutex_1
		--  * test_mutex
		ready = false
		threads[1] = ngx.thread.spawn(test_function(temp_mutex_1, 5))
		threads[2] = ngx.thread.spawn(test_function(test_mutex, 6))
		ready = true
		wait_on_threads()
		clean_threads()
		assert.are_same({1, 2, 3, 4, 5, 6}, unsafe_table)
		ready = false
	end)
	
	-- Test the safe(r) call function.
	it("should be able to enter/exit safely", function()
		local unsafe_table = {}
		local ready1, ready2 = false, false
		
		-- Make test_mutex register with temp_mutex_1.
		-- Then, make temp_mutex_1 wait on test_mutex to finish.

		local function thread1_func()
			while not ready1 do
				ngx.sleep(0)
			end
			
			test_mutex:enter()
			ready2 = true
			unsafe_table[#unsafe_table + 1] = 1
			ngx.sleep(0.05)
			test_mutex:exit()
		end
		
		local function thread2_func()
			while not ready2 do
				ngx.sleep(0)
			end
			
			temp_mutex_1:call_when_safe(function(number)
				unsafe_table[#unsafe_table + 1] = number
			end, 2)
			
			ready2 = false
		end
		
		test_mutex:register_with(temp_mutex_1)
		
		-- Test this order:
		--  * test_mutex
		--  * temp_mutex_1
		ready1 = false
		threads[1] = ngx.thread.spawn(thread1_func)
		threads[2] = ngx.thread.spawn(thread2_func)
		ready1 = true
		wait_on_threads()
		clean_threads()
		assert.are_same({1, 2}, unsafe_table)
		ready1 = false
		
		-- Test this order:
		--  * temp_mutex_1
		--  * test_mutex
		ready1 = false
		threads[1] = ngx.thread.spawn(thread2_func)
		threads[2] = ngx.thread.spawn(thread1_func)
		ready1 = true
		wait_on_threads()
		clean_threads()
		assert.are_same({1, 2, 1, 2}, unsafe_table)
		ready1 = false
	end)
	
	-- When a mutex object is competing, it shouldn't be able to re-enter
	-- the comeptition.
	it("shouldn't be able to enter while competing", function()
		local muts = {
			test_mutex, temp_mutex_1, temp_mutex_2,
			temp_mutex_3, temp_mutex_4, temp_mutex_5
		}
		
		for _,v in ipairs(muts) do
			assert.has_no.errors(function()
				v:enter()
			end)
			
			assert.has.errors(function()
				v:enter()
			end)
			
			assert.has_no.errors(function()
				v:exit()
			end)
		end
	end)
	
	-- When a mutex object isn't competing, it shouldn't be able to exit the
	-- competition.
	it("shouldn't be able to exit when not competing", function()
		local muts = {
			test_mutex, temp_mutex_1, temp_mutex_2,
			temp_mutex_3, temp_mutex_4, temp_mutex_5
		}
		
		for _,v in ipairs(muts) do
			assert.has.error(function()
				v:exit()
			end)
		end
	end)
	
	-- While competing, a mutex object shouldn't be able to compress its ID.
	it("shouldn't be able to compress its id", function()
		local muts = {
			test_mutex, temp_mutex_1, temp_mutex_2,
			temp_mutex_3, temp_mutex_4, temp_mutex_5
		}
		
		for _,v in ipairs(muts) do
			assert.has_no.error(function()
				v:enter()
			end)
			
			assert.has.error(function()
				v:compress_state()
			end)
			
			assert.has_no.error(function()
				v:exit()
			end)
		end
	end)
end)
