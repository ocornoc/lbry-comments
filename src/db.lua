--[[
This file is part of LBRY-Comments.

LBRY-Comments provides a simple network database for commenting.
Copyright (C) 2018 Grayson Burton and Oleg Silkin

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
-- A wrapper around SQLite3 providing the high-level interface of the backend.
-- @module db
-- @alias _M
-- @copyright 2018 Grayson Burton and Oleg Silkin
-- @license GNU AGPLv3
-- @author Grayson Burton

--------------------------------------------------------------------------------
-- Options
-- @section options
-- @local

--- The path to the database, relative to the top path.
local db_rpath = "accoutrements.db"

--- The path to the directory containing backups, relative to the top path.
-- Will be created if not existing.
local backup_rpath = "backups"

--------------------------------------------------------------------------------
-- Constants
-- @section constants
-- @local

--- Uses LuaFileSystem for its directory creation.
local lfs = require "lfs"

--- Uses luasql.sqlite3.
local sql_driver = require "luasql.sqlite3"
--- Uses crypto.
local crypto = require "crypto"
--- @{sql_driver} requires this setup.
-- No idea why to be honest, but whatever.
local sql = sql_driver.sqlite3()
--- Uses ngx.
local ngx = require "ngx"

--- Version of the API.
-- Follows SemVer 2.0.0
-- https://semver.org/spec/v2.0.0.html
local DB_VERSION = "1.0.2"

--- The UTC Unix Epoch time in seconds of the last backup's creation.
local last_backup_time = 0
--- The minimum amount of seconds between backups.
-- This exists to put a hard stop to any form of backup spam, whether from
-- internal error or external maliciousness.
local minimum_backup_time = 3600

--- The path to the database.
local db_path = _G.toppath .. "/" .. db_rpath

--- The path to the backups folder.
-- It is created dynamically if it doesn't exist.
local backup_path = _G.toppath .. "/" .. backup_rpath

-- Here, we test if it exists, and create it if it doesn't.
do
	-- The directory file.
	local backupdirf = io.open(backup_path, "rb")
	
	if backupdirf then
		-- The directory already exists.
		backupdirf:close()
	else
		assert(lfs.mkdir(backup_path))
	end
end

--------------------------------------------------------------------------------
-- Helper Functions
-- @section helpers
-- @local

--- Returns the Epoch time.
-- The time is the amount of seconds since the UTC Unix Epoch.
-- @treturn int
-- @usage get_unix_time()
local function get_unix_time()
	return ngx.time()
end

--- Encodes a string in Base64.
-- @tparam string plain_str The string to encode.
-- @treturn string The encoded input.
-- @see b64_decode
-- @usage b64_encode("hello") --> "aGVsbG8="
local function b64_encode(plain_str)
	return ngx.encode_base64(plain_str)
end

--- Decodes a Base64-encoded string.
-- The return string is the decoded string on success, or nil on error.
-- @tparam string encoded_str The encoded input.
-- @treturn[1] string The decoded output.
-- @treturn[2] nil If the input isn't well-formed.
-- @see b64_encode
-- @usage b64_decode("aGVsbG8=") --> "hello"
local function b64_decode(encoded_str)
	return ngx.decode_base64(plain_str)
end

--- Returns whether a table is empty.
-- This also takes into account non-integer indices.
-- @tparam table t The table to check.
-- @treturn bool
-- @usage is_empty_table({}) --> true
-- @usage is_empty_table({5}) --> false
local function is_empty_table(t)
	for _,_ in pairs(t) do
		return false
	end
	
	return true
end

--------------------------------------------------------------------------------
-- accouts
-- @section accouts
-- @local

--- The connection to the database.
-- It (and its fields) aren't Lua tables, but rather SQL tables. Usually, when
-- a condition such as "must" is listed, it means that the SQL table is setup to
-- throw a constraint error if that condition isn't satisfied. All entries
-- should be considered `NOT NULL` (unable to be `null`) unless otherwise
-- specified.
-- @table accouts
-- @local
-- @field claims The table of claims.
-- @field comments The table of comments.
-- @field backups The table of backups.
local accouts = assert(sql:connect(db_path))
assert(accouts:setautocommit(true))

--- The table of claims.
-- This contains all of the claims "tracked" in the database.
-- @table accouts.claims
-- @local
-- @field claim_index An int holding the index of the claim.
-- @field lbry_perm_uri The represented permanent LBRY claim's URI. Includes the
-- "lbry://". If a row with a non-unique URI is inserted, it is silently ignored
-- and treated as a no-op.
-- @field add_time An int representing the time of the row's insertion into the
-- database, stored as UTC Epoch seconds. Must be >= 0.
-- @field upvotes An int representing the amount of upvotes for that claim. Must
-- be >= 0, defaults to 0.
-- @field downvotes An int representing the amount of downvotes for that claim.
-- Must be >= 0, defaults to 0.
assert(accouts:execute[[
CREATE TABLE IF NOT EXISTS claims (
	claim_index   INTEGER PRIMARY KEY,
	lbry_perm_uri TEXT    NOT NULL UNIQUE  ON CONFLICT IGNORE,
	add_time      INTEGER NOT NULL CHECK (add_time >= 0),
	upvotes       INTEGER NOT NULL DEFAULT 0 CHECK (upvotes >= 0),
	downvotes     INTEGER NOT NULL DEFAULT 0 CHECK (downvotes >= 0) );
]])

--- The table of comments.
-- This contains all of the comments in the database.
-- @table accouts.comments
-- @local
-- @field comm_index An int holding the index of the comment.
-- @field claim_index An int holding the index of the claims that this is a
-- comment on. It must be a real claim index and will throw if it isn't. Also,
-- when the claim that this comment is attached to is deleted or updated
-- (moved), this value will change, too. If deletion, the comment will get
-- automatically deleted.
-- @field poster_name A string holding the name of the poster. Must not == ""
-- and defaults to "A Cool LBRYian".
-- @field parent_com A potentially-`null` int holding the index to another
-- comment. If this field is `null`, then this comment is a "TLC" (top-level
-- comment, a comment that isn't a reply). If it does holder a value, then the
-- value is the index of the comment that this is a reply to. If the commen that
-- is referenced in this value is updated (moved), then this value automatically
-- updates to reflect that. If the parent comment is deleted, this reply is
-- automatically deleted too.
-- @field post_time An int representing the time of the row's insertion into the
-- database, stored as UTC Epoch seconds. Must be >= 0.
-- @field message A string holding the body of the comment. Must not == "".
-- @field upvotes An int representing the amount of upvotes for that comment.
-- Must be >= 0, defaults to 0.
-- @field downvotes An int representing the amount of downvotes for that
-- comment. Must be >= 0, defaults to 0.
-- @see accouts.claims
assert(accouts:execute[[
CREATE TABLE IF NOT EXISTS comments (
	comm_index    INTEGER PRIMARY KEY,
	claim_index   INTEGER NOT NULL REFERENCES claims(claim_index) ON DELETE CASCADE ON UPDATE CASCADE,
	poster_name   TEXT    NOT NULL DEFAULT 'A Cool LBRYian' CHECK (poster_name != ''),
	parent_com    INTEGER REFERENCES comments(comm_index) ON DELETE CASCADE ON UPDATE CASCADE,
	post_time     INTEGER NOT NULL CHECK (post_time >= 0),
	message       TEXT    NOT NULL CHECK (message != ''),
	upvotes       INTEGER NOT NULL DEFAULT 0 CHECK (upvotes >= 0),
	downvotes     INTEGER NOT NULL DEFAULT 0 CHECK (downvotes >= 0) );
]])

--- Tracks all of the previous database backups.
-- @table accouts.backups
-- @local
-- @field backup_index An int holding the index of the backup.
-- @field creation_time An int representing the time of the row's insertion
-- into the database, stored as UTC Epoch seconds. Must be >= 0.
-- @field totalcomments An int representing the total number of comments in the
-- backup. Must be >= 0.
-- @field totalclaims An int representing the total number of claims in the
-- backup. Must be >= 0.
-- @field lbry_perm_uri A string holding the permanent LBRY URI of the claim
-- that this backup is stored at. CURRENTLY DISABLED AND NOT STORED.
-- @field size_kb An int representing the total size of the backup in KiB. The
-- value is rounded up. Must be >= 0.
assert(accouts:execute[[
CREATE TABLE IF NOT EXISTS backups (
	backup_index  INTEGER PRIMARY KEY,
	creation_time INTEGER NOT NULL UNIQUE CHECK (creation_time >= 0),
	totalcomments INTEGER NOT NULL CHECK (totalcomments >= 0),
	totalclaims   INTEGER NOT NULL CHECK (totalclaims >= 0),
--	lbry_perm_uri TEXT    NOT NULL UNIQUE ON CONFLICT ABORT,
	size_kb       INTEGER NOT NULL CHECK (size_kb >= 0) );
]])

--- An escaped, Base64-encoded version of the public key.
-- @within Constants
local pubkey_b64 = accouts:escape(b64_encode(crypto:get_pubkey()))

--------------------------------------------------------------------------------
-- Helper Functions
-- @section helpers
-- @local

--- Returns the number of claims stored.
-- @treturn[1] int The number of claims.
-- @treturn[2] nil On error.
-- @treturn[2] string The error message.
local function get_claim_num()
	local curs, err_msg = accouts:execute[[
	 SELECT COUNT(*) FROM claims;
	]]
	
	if err_msg then
		return nil, err_msg
	end
	
	local claim_count = curs:fetch()
	curs:close()
	
	return claim_count
end

--- Returns the number of comments stored.
-- @treturn[1] int The number of comments.
-- @treturn[2] nil On error.
-- @treturn[2] string The error message.
local function get_comment_num()
	local curs, err_msg = accouts:execute[[
	 SELECT COUNT(*) FROM comments;
	]]
	
	if err_msg then
		return nil, err_msg
	end
	
	local comment_count = curs:fetch()
	curs:close()
	
	return comment_count
end

-- Uploads the backup to LBRY using LuaBRY.
-- TODO: Wait until much closer to public release to implement this.
local function upload_backup(...)
	return true
end

--- Inserts a new backup into @{accouts.backups}.
-- @tparam int size The rounded-up size of the backup in KiB.
-- @treturn[1] bool `true` on success.
-- @treturn[2] nil On error.
-- @treturn[2] string The error message.
local function new_backup_entry(size)
	-- We need the count of all of the claims and comments in the database.
	local claim_count, err_msg = get_claim_num()
	
	if err_msg then
		return nil, err_msg
	end
	
	local com_count, err_msg = get_comment_num()
	
	if err_msg then
		return nil, err_msg
	end
	
	local time = get_unix_time()
	
	-- Now, to insert it into the database.
	local _, err_msg = accouts:execute([[
	 INSERT INTO backups(creation_time, totalcomments, totalclaims, size_kb)
	 VALUES (]] .. time .. ", " .. com_count .. ", " .. claim_count ..
	 ", " .. size .. ");")
	
	if err_msg then
		return nil, err_msg
	else
		last_backup_time = time
		
		return true
	end
end

--- Returns the ID of the latest comment in @{accouts.comments}.
-- @treturn[1] int The comment ID
-- @treturn[2] nil On error.
-- @treturn[2] string The error message.
local function get_latest_comment()
	local curs, err_msg = accouts:execute[[
	SELECT last_insert_rowid();
	]]
	
	if err_msg then
		return nil, err_msg
	end
	
	local results, err_msg = curs:fetch()
	curs:close()
	
	if not results or err_msg then
		return results, err_msg
	else
		return results
	end
end

--------------------------------------------------------------------------------
-- db
-- @section db

local _M = {
	_VERSION = DB_VERSION,
	claims = {},
	comments = {}
}

--------------------------------------------------------------------------------

--- A boolean that is `true` only if @{accouts} is active.
-- If it isn't `true`, many public functions will error.
-- @local
local running = true

--- Returns whether the database is running.
-- @treturn bool
-- @usage db.is_running()
function _M.is_running()
	return running
end

--- Stops the database.
-- Will return an error if the database is already stopped.
-- @treturn[1] bool `true` on success.
-- @treturn[2] nil On error.
-- @treturn[2] string The error message.
-- @see restart
-- @usage db.stop()
function _M.stop()
	if running then
		local result, err_msg = accouts:close()
		
		if result then
			running = false
			
			return true
		else
			return nil, "cursors open"
		end
	else
		return nil, "already stopped"
	end
end

--- Starts the database.
-- Will return an error if the database is already started.
-- @treturn[1] bool `true` on success.
-- @treturn[2] nil On error.
-- @treturn[2] string The error message.
-- @see restart
-- @usage db.start()
function _M.start()
	if running then
		return nil, "already started"
	else
		accouts = sql:connect(db_path)
		running = true
		
		return true
	end
end

--- Retarts the database.
-- Will guaranteed put the database into a "running" state.
-- @treturn[1] bool `true` on success.
-- @treturn[2] nil On error.
-- @treturn[2] string The error message.
-- @usage db.restart()
function _M.restart()
	if running then
		local result, err_msg = _M.stop()
		
		if not result then
			return result, err_msg
		else
			return _M.start()
		end
	else
		return _M.start()
	end
end

--- Creates a backup of the database.
-- @treturn[1] bool `true` on success.
-- @treturn[2] nil On error.
-- @treturn[2] string The error message.
-- @usage db.backup()
function _M.backup()
	local time = get_unix_time()
	
	if time - last_backup_time <= minimum_backup_time then
		return nil, "Minimum time between backups is " ..
		            minimum_backup_time .. "s, it's only been" ..
		            time - last_backup_time .. "s."
	end
	
	local file_name = time .. "_" .. (diff and "diff" or "full") ..
	                  ".db.backup"
	
	local db_file, err_msg = io.open(db_path, "rb")
	
	if err_msg then
		return nil, err_msg
	end
	
	local bk_file, err_msg = io.open(backup_path .. file_name, "w+b")
	
	if err_msg then
		db_file:close()
		
		return nil, err_msg
	end
	
	-- We open a cursor to, in theory, lock claims, comments, and backups as
	-- read-only.
	local curs, err_msg = accouts:execute[[
	 SELECT _rowid_ FROM claims UNION ALL
	 SELECT _rowid_ FROM comments;
	]]
	
	if err_msg then
		return nil, err_msg
	end
	
	-- 32 KiB
	local chunk_size = 32768
	-- Signature object
	local sig_obj = crypto.new_sign_object()
	
	-- :read(0) returns an empty string if there is stuff left or nil if
	--   we are at the end of the file, so we can use it to stop our loop.
	while db_file:read(0) do
		local chunk = db_file:read(chunk_size)
		sig_obj:insert(chunk)
		bk_file:write(chunk)
	end
	-- Now that we've copied the database file, we can close it.
	db_file:close()
	
	-- Write 80 "="s on a new line at the end, followed by the signature on
	--   the next line.
	bk_file:write("\n" .. ("="):rep(80) .. "\n")
	bk_file:write(b64_encode(sig_obj:get_sig()))
	
	bk_file:flush()
	
	-- Returns the index position (byte #) of the last byte of the file. AKA
	--   it returns the size of the file in KiB, rounded up.
	local bk_size = math.ceil(bk_file:seek"end" / 1024)
	bk_file:close()
	
	local success, err_msg = new_backup_entry(bk_size)
	
	curs:close()
	
	return success, err_msg
end

--------------------------------------------------------------------------------
-- db.claims
-- @section claims

--- Inserts a new claim into the claims database.
-- If the claim is already in the database, it doesn't error.
-- @function new
-- @tparam string claim_uri The permanent LBRY URI of the claim.
-- @treturn[1] int `1` if it was added, `0` if it was already preset.
-- @treturn[2] nil On error.
-- @treturn[2] string The error message.
-- @usage db.claims.new("lbry://cool_example")
function _M.claims.new(claim_uri)
	return accouts:execute(
	 "INSERT INTO claims (lbry_perm_uri, add_time) VALUES ('" ..
	 accouts:escape(claim_uri) .. "', " .. get_unix_time() .. ");"
	)
end

--- Returns the data for a given claim.
-- If `int_ind == true`, then the data is an array rather than having
-- alphanumeric keys.
-- @function get_data
-- @tparam string claim_uri The permanent LBRY URI of the claim.
-- @tparam[opt=false] bool int_ind 
-- @treturn[1] table The data of the given claim.
-- @treturn[2] nil On error.
-- @treturn[2] string The error message.
-- @usage db.claims.get_data("lbry://cool_example") --> table
-- @usage db.claims.get_data("lbry://another_one", true) --> table
function _M.claims.get_data(claim_uri, int_ind)
	if type(claim_uri) ~= "string" then
		return nil, "uri not string"
	end
	
	local curs, err_msg = accouts:execute(
	 "SELECT * FROM claims WHERE lbry_perm_uri = '" ..
	 accouts:escape(claim_uri) .. "';"
	)
	
	if not curs or err_msg then
		return curs, err_msg
	end
	
	local results = {}
	-- In order to specify alphanumeric/int keys, we have to give a table
	--   parameter to "fetch".
	--   https://keplerproject.github.io/luasql/manual.html#cursor_object
	curs:fetch(results, (int_ind and "n") or "a")
	curs:close()
	
	-- If results is empty, then the claim doesn't exist in the SQL DB.
	if not is_empty_table(results) then
		return results
	else
		return nil, "uri doesnt exist"
	end
end

--- Upvotes a claim and returns the new total.
-- If `times` isn't given, it defaults to `1`. 
-- @function upvote
-- @tparam string claim_uri The permanent LBRY URI of the claim.
-- @tparam[opt=1] int times The amount of times to upvote.
-- @treturn[1] int The total amount of upvotes.
-- @treturn[2] nil On error.
-- @treturn[2] string The error message.
-- @usage db.claims.upvote("lbry://cool_example") --> int
-- @usage db.claims.upvote("lbry://cool_example", 3) --> int
function _M.claims.upvote(claim_uri, times)
	if times == nil then
		times = 1
	elseif type(times) ~= "number" then
		return nil, "times not number"
	elseif times % 1 ~= 0 then
		return nil, "times not int"
	end
	
	local data, err_msg = _M.claims.get_data(claim_uri)
	
	if not data or err_msg then
		return data, err_msg
	end
	
	local _, err_msg = accouts:execute(
	 "UPDATE claims SET upvotes = " .. times + data.upvotes ..
	 " WHERE lbry_perm_uri = '" .. data.lbry_perm_uri .. "';"
	)
	
	if err_msg then
		return nil, err_msg
	else
		return times + data.upvotes
	end
end

--- Downvotes a claim and returns the new total.
-- If `times` isn't given, it defaults to `1`. 
-- @function downvote
-- @tparam string claim_uri The permanent LBRY URI of the claim.
-- @tparam[opt=1] int times The amount of times to downvote.
-- @treturn[1] int The total amount of downvotes.
-- @treturn[2] nil On error.
-- @treturn[2] string The error message.
-- @usage db.claims.downvote("lbry://cool_example") --> int
-- @usage db.claims.downvote("lbry://cool_example", 3) --> int
function _M.claims.downvote(claim_uri, times)
	if times == nil then
		times = 1
	elseif type(times) ~= "number" then
		return nil, "times not number"
	elseif times % 1 ~= 0 then
		return nil, "times not int"
	end
	
	local data, err_msg = _M.claims.get_data(claim_uri)
	
	if not data or err_msg then
		return data, err_msg
	end
	
	local _, err_msg = accouts:execute(
	 "UPDATE claims SET downvotes = " .. times + data.downvotes ..
	 " WHERE lbry_perm_uri = '" .. data.lbry_perm_uri .. "';"
	)
	
	if err_msg then
		return nil, err_msg
	else
		return times + data.downvotes
	end
end

--- Returns the URI from a claim index.
-- @function get_uri
-- @tparam int claim_index The claim index.
-- @treturn[1] string The URI associated with the index.
-- @treturn[2] nil On error.
-- @treturn[2] string The error message.
-- @usage db.claims.downvote(20) --> a LBRY URI
function _M.claims.get_uri(claim_index)
	if type(claim_index) ~= "number" then
		return nil, "index not number"
	end
	
	local curs, err_msg = accouts:execute(
	 "SELECT lbry_perm_uri FROM claims WHERE claim_index = " ..
	 claim_index .. ";"
	)
	
	if err_msg then
		return nil, err_msg
	end
	
	local results = curs:fetch()
	curs:close()
	
	if results then
		return results
	else
		return nil, "uri not found"
	end
end

--- Returns the TLCs for a claim.
-- A "TLC" is a "top-level comment", IE a comment that isn't a reply.
-- If `int_ind == true`, then each comment's data is an array rather than having
-- alphanumeric keys.
-- @function get_comments
-- @tparam string claim_uri The permanent LBRY URI of the claim.
-- @tparam[opt=false] bool int_ind 
-- @treturn[1] table An array of comments' data.
-- @treturn[2] nil On error.
-- @treturn[2] string The error message.
-- @usage db.claims.get_comments("lbry://cool_example") --> table
-- @usage db.claims.get_comments("lbry://another_one", true) --> table
function _M.claims.get_comments(claim_uri, int_ind)
	-- We don't need to sanitize 'claim_uri' because get_data does.
	local claim_data, err_msg = _M.claims.get_data(claim_uri)
	
	if err_msg then
		return nil, err_msg
	end
	
	local claim_index = claim_data.claim_index
	
	if not claim_index or type(claim_index) ~= "number" then
		return nil, "weird data"
	end
	
	local curs, err_msg = accouts:execute(
	 "SELECT * FROM comments WHERE parent_com IS NULL AND claim_index = " ..
	 claim_index .. ";"
	)
	
	if err_msg then
		return nil, err_msg
	end
	
	local results = {}
	local com_data = {}
	int_ind = (int_ind and "n") or "a"
	
	while curs:fetch(com_data, int_ind) do
		table.insert(results, com_data)
		com_data = {}
	end
	
	curs:close()
	
	return results
end

--------------------------------------------------------------------------------
-- db.comments
-- @section comments

--- Inserts a new TLC into the comments database.
-- A "TLC" is a "top-level comment", IE a comment that isn't a reply.
-- @function new
-- @tparam string claim_uri The permanent LBRY URI of the claim to comment on.
-- @tparam string poster The name of the poster.
-- @tparam string message The message of the comment.
-- @treturn[1] int The comment ID now associated with this comment.
-- @treturn[2] nil On error.
-- @treturn[2] string The error message.
-- @usage db.comments.new("lbry://cool_example", "my_username", "nice vid!")
function _M.comments.new(claim_uri, poster, message)
	local claim_data, err_msg = _M.claims.get_data(claim_uri)
	
	-- If there is an error, 
	if err_msg then
		-- and the error is that the claim doesn't exist in the DB,
		if err_msg == "uri doesnt exist" then
			-- try creating the claim dynamically.
			local result, err_msg = _M.claims.new(claim_uri)
			-- If that doesn't work, just give up.
			if err_msg then
				return nil, "failed on-demand claim"
			-- Otherwise, retry now that you've created the claim.
			else
				return _M.comments.new(claim_uri, poster,
				                       message)
			end
		-- Otherwise, just give up.
		else
			return nil, err_msg
		end
	end
	
	-- 'message' must be a string and mustn't be empty nor only whitespace.
	if type(message) ~= "string" then
		return nil, "message not string"
	elseif message:gsub("^%s+", ""):gsub("%s+$", "") == "" then
		return nil, "message only whitespace"
	end
	
	-- 'poster' must be a string and mustn't be empty nor only whitespace.
	if type(poster) ~= "string" then
		return nil, "poster not string"
	elseif poster:gsub("^%s+", ""):gsub("%s+$", "") == "" then
		return nil, "poster only whitespace"
	end
	
	local claim_index = claim_data.claim_index
	local poster_name = accouts:escape(poster:gsub("^%s+", "")
	                                         :gsub("%s+$", ""))
	local post_time = get_unix_time()
	-- We strip all beginning and ending whitespace from 'message'.
	message = accouts:escape(message:gsub("^%s+", ""):gsub("%s+$", ""))
	
	local _, err_msg = accouts:execute(
	 "INSERT INTO comments (claim_index, poster_name, post_time," ..
	 " message) VALUES (" .. claim_index .. ", '" .. poster_name .. "', " ..
	 post_time .. ", '" .. message .. "');"
	)
	
	if err_msg then
		return nil, err_msg
	else
		return get_latest_comment()
	end
end

--- Inserts a new reply into the comments database.
-- @function new_reply
-- @tparam int parent_id The ID of the comment that this is a reply to.
-- @tparam string poster The name of the poster.
-- @tparam string claim_uri The message of the comment.
-- @treturn[1] int The comment ID now associated with this comment.
-- @treturn[2] nil On error.
-- @treturn[2] string The error message.
-- @usage db.comments.reply(20, "my_username", "funny! :)")
function _M.comments.new_reply(parent_id, poster, message)
	-- We don't need to sanitize 'parent_id' because get_data does for us.
	local parent_data, err_msg = _M.comments.get_data(parent_id)
	
	if err_msg then
		return nil, err_msg
	end
	
	-- 'message' must be a string and mustn't be empty nor only whitespace.
	if type(message) ~= "string" then
		return nil, "message not string"
	elseif message:gsub("^%s+", ""):gsub("%s+$", "") == "" then
		return nil, "message only whitespace"
	end
	
	-- 'poster' must be a string and mustn't be empty nor only whitespace.
	if type(poster) ~= "string" then
		return nil, "poster not string"
	elseif poster:gsub("^%s+", ""):gsub("%s+$", "") == "" then
		return nil, "poster only whitespace"
	end
	
	local claim_index = parent_data.claim_index
	local poster_name = accouts:escape(poster:gsub("^%s+", "")
	                                         :gsub("%s+$", ""))
	local post_time = get_unix_time()
	-- We strip all beginning and ending whitespace from 'message'.
	message = accouts:escape(message:gsub("^%s+", ""):gsub("%s+$", ""))
	
	local _, err_msg = accouts:execute(
	 "INSERT INTO comments (claim_index, poster_name, parent_com, " ..
	 "post_time, message) VALUES (" .. claim_index .. ", '" ..
	 poster_name .. "', " .. parent_id .. ", " .. post_time .. ", '" ..
	 message .. "');"
	)
	
	if err_msg then
		return nil, err_msg
	else
		return get_latest_comment()
	end
end

--- Returns the data for a given comment.
-- If `int_ind == true`, then the data is an array rather than having
-- alphanumeric keys.
-- @function get_data
-- @tparam int comment_id The ID of the comment to get data of.
-- @tparam[opt=false] bool int_ind 
-- @treturn[1] table The data of the given claim.
-- @treturn[2] nil On error.
-- @treturn[2] string The error message.
-- @usage db.comments.get_data(20) --> table
-- @usage db.comments.get_data(21, true) --> table
function _M.comments.get_data(comment_id, int_ind)
	if type(comment_id) ~= "number" then
		return nil, "id not number"
	end
	
	local curs, err_msg = accouts:execute(
	 "SELECT * FROM comments WHERE comm_index = '" .. comment_id .. "';"
	)
	
	if not curs or err_msg then
		return curs, err_msg
	end
	
	local results = {}
	-- In order to specify alphanumeric/int keys, we have to give a table
	--   parameter to "fetch".
	--   https://keplerproject.github.io/luasql/manual.html#cursor_object
	curs:fetch(results, (int_ind and "n") or "a")
	curs:close()
	
	-- If results is empty, then the comment doesn't exist in the SQL DB.
	if not is_empty_table(results) then
		return results
	else
		return nil, "comment doesnt exist"
	end
end

--- Returns the replies to a comment.
-- If `int_ind == true`, then each comment's data is an array rather than having
-- alphanumeric keys.
-- @function get_replies
-- @tparam int comment_id The ID of the comment to get replies of.
-- @tparam[opt=false] bool int_ind
-- @treturn[1] table An array of the replies' data.
-- @treturn[2] nil On error.
-- @treturn[2] string The error message.
-- @usage db.comments.get_replies(20) --> table
-- @usage db.comments.get_replies(21, true) --> table
function _M.comments.get_replies(comment_id, int_ind)
	if type(comment_id) ~= "number" then
		return nil, "id not number"
	end
	
	-- We fetch the parent comment data in order to check if the comment is
	--   actually in the database.
	local comment, err_msg = _M.comments.get_data(comment_id)
	
	if err_msg then
		return nil, err_msg
	end
	
	local curs, err_msg = accouts:execute(
	 "SELECT * FROM comments WHERE parent_com = '" .. comment_id .. "';"
	)
	
	if not curs or err_msg then
		return curs, err_msg
	end
	
	-- We need a buffer variable 'latest_results' to store the result of the
	--   search.
	local results = {}
	local latest_results
	int_ind = (int_ind and "n") or "a"
	
	repeat
		latest_results = curs:fetch(latest_results, int_ind)
		table.insert(results, latest_results)
	until not latest_results
	
	curs:close()
	
	return results
end

--- Upvotes a comment and returns the new total.
-- If `times` isn't given, it defaults to `1`. 
-- @function upvote
-- @tparam int comment_id The ID of the comment to upvote.
-- @tparam[opt=1] int times The amount of times to upvote.
-- @treturn[1] int The total amount of upvotes.
-- @treturn[2] nil On error.
-- @treturn[2] string The error message.
-- @usage db.comments.upvote(20) --> int
-- @usage db.comments.upvote(123, 3) --> int
function _M.comments.upvote(comment_id, times)
	if times == nil then
		times = 1
	elseif type(times) ~= "number" then
		return nil, "times not number"
	elseif times % 1 ~= 0 then
		return nil, "times not int"
	end
	
	local data, err_msg = _M.comments.get_data(comment_id)
	
	if not data or err_msg then
		return data, err_msg
	elseif data.comm_index ~= comment_id then
		print("In preparation for this bug, I have added a debug " ..
		      "print statement. This should NEVER happen, and if " ..
		      "it does, panic immediately. Or file a bug report.")
		return nil, "comm_index ~= comment_id"
	end
	
	local _, err_msg = accouts:execute(
	 "UPDATE comments SET upvotes = " .. times + data.upvotes ..
	 " WHERE comm_index = '" .. comment_id .. "';"
	)
	
	if err_msg then
		return nil, err_msg
	else
		return times + data.upvotes
	end
end

--- Downvotes a comment and returns the new total.
-- If `times` isn't given, it defaults to `1`. 
-- @function downvote
-- @tparam int comment_id The ID of the comment to downvote.
-- @tparam[opt=1] int times The amount of times to downvote.
-- @treturn[1] int The total amount of downvotes.
-- @treturn[2] nil On error.
-- @treturn[2] string The error message.
-- @usage db.comments.downvote(20) --> int
-- @usage db.comments.downvote(123, 3) --> int
function _M.comments.downvote(comment_id, times)
	if times == nil then
		times = 1
	elseif type(times) ~= "number" then
		return nil, "times not number"
	elseif times % 1 ~= 0 then
		return nil, "times not int"
	end
	
	local data, err_msg = _M.comments.get_data(comment_id)
	
	if not data or err_msg then
		return data, err_msg
	elseif data.comm_index ~= comment_id then
		print("In preparation for this bug, I have added a debug " ..
		      "print statement. This should NEVER happen, and if " ..
		      "it does, panic immediately. Or file a bug report.")
		return nil, "comm_index ~= comment_id"
	end
	
	local _, err_msg = accouts:execute(
	 "UPDATE comments SET downvotes = " .. times + data.downvotes ..
	 " WHERE comm_index = '" .. comment_id .. "';"
	)
	
	if err_msg then
		return nil, err_msg
	else
		return times + data.downvotes
	end
end

--------------------------------------------------------------------------------

return _M
