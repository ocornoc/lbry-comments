local sql_driver = require "luasql.sqlite3"
local crypto = require "crypto"
local sql = sql_driver.sqlite3()
-- No networking components are actually used
local sock = require "socket"
local mime = require "mime"
-- For publishing backups
-- Only used for debug
local inspect = require "inspect"

-- Follows SemVer 2.0.0
-- https://semver.org/spec/v2.0.0.html
local DB_VERSION = "0.0.0"

-- The path to the database, relative to the script.
local db_path = "accoutrements.db"

-------------------------------------------------------------------------------
-- Helper functions

-- Returns the UTC Unix Epoch time in seconds as an integer.
local function get_unix_time()
	return math.floor(sock.gettime())
end

-- Given a string, returns the Base64-encoded version of it.
local function b64_encode(plain_str)
	return (mime.b64(plain_str))
end

-- Given a Base64-encoded string, returns the plain version of it. The return
--   string is the largest section from the start of the input that can be
--   decoded. It stops at the first undecodable symbol(s).
local function b64_decode(encoded_str)
	return (mime.unb64(encoded_str))
end

-- Given a table, returns whether it is empty.
local function is_empty_table(t)
	for _,_ in pairs(t) do
		return false
	end
	
	return true
end

-------------------------------------------------------------------------------
-- Setting up connections and tables

local accouts = assert(sql:connect(db_path))
assert(accouts:setautocommit(true))

-- Contains all of the claims that have comments attached.
-- claim_index:   The index of the claim.
-- lbry_perm_uri: The permanent LBRY claim URI being represented. Includes the
--                  "lbry://". If a row with a non-unique URI is inserted, it is
--                  automatically ignored.
-- add_time:      An int representing the time of database addition. Count as
--                  UTC Unix Epoch seconds. Must be >= 0.
-- u/d votes:     All upvotes and downvotes for a claim. Both must be >= 0.
--                  Both default to 0.
assert(accouts:execute[[
CREATE TABLE IF NOT EXISTS claims (
	claim_index   INTEGER PRIMARY KEY,
	lbry_perm_uri TEXT    NOT NULL UNIQUE  ON CONFLICT IGNORE,
	add_time      INTEGER NOT NULL CHECK (add_time >= 0),
	upvotes       INTEGER NOT NULL DEFAULT 0 CHECK (upvotes >= 0),
	downvotes     INTEGER NOT NULL DEFAULT 0 CHECK (downvotes >= 0) );
]])

-- Contains all of the comments.
-- comm_index:  The index of the comment. Basically a unique identifier.
-- claim_index: The index of the claim (in claims) that the comment belongs to.
-- poster_name: The username or moniker used by the poster. Must not be "".
--                Defaults to "A Cool LBRYian".
-- parent_com:  The index of the comment that this is a reply to. If null, it
--                is not a reply.
-- post_time:   An int representing the time of posting. Counted as UTC Unix
--                Epoch seconds. Must be >= 0.
-- message:     The body of the comment. Must not be "".
-- u/d votes:   All upvotes and downvotes for the comment specifically. Both
--                must be >= 0. Both default to 0.
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

-- Tracks all of the previous database backups.
-- backup_index:  The index of the backup. Unique.
-- creation_time: An int representing the time of creation. Counted as UTC Unix
--                  Epoch seconds. Must be >= 0.
-- totalcomments: An int representing the amount of comments stored up to and
--                  including that backup. Must be >= 0.
-- totalclaims:   An int representing the amount of claims stored up to and
--                  including that backup. Must be >= 0.
-- lbry_perm_uri: The permanent LBRY URI (including "lbry://") that the backup
--                  is uploaded to. Is unique. Aborts and screams in agony if
--                  you attempt to insert a row with the same URI.
-- size_kb:       An int representing the size of the backup in KiB (2^10),
--                  floored. Must be >= 0.
assert(accouts:execute[[
CREATE TABLE IF NOT EXISTS backups (
	backup_index  INTEGER PRIMARY KEY,
	creation_time INTEGER NOT NULL UNIQUE CHECK (creation_time >= 0),
	totalcomments INTEGER NOT NULL CHECK (totalcomments >= 0),
	totalclaims   INTEGER NOT NULL CHECK (totalclaims >= 0),
--	lbry_perm_uri TEXT    NOT NULL UNIQUE ON CONFLICT ABORT,
	size_kb       INTEGER NOT NULL CHECK (size_kb >= 0) );
]])

-- An escaped, Base64-encoded version of the public key.
local pubkey_b64 = accouts:escape(b64_encode(crypto:get_pubkey()))
-- The UTC Unix Epoch time in seconds of the last backup's creation.
local last_backup_time = 0
-- The minimum amount of seconds between backups, as to prevent backup spam.
local minimum_backup_time = 3600

-------------------------------------------------------------------------------
-- Other helper functions

-- Returns the number of claim rows, or nil and an error message.
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

-- Returns the number of comments, or nil and an error message.
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

-- Inserts a new backup into the backup table given the name and the backup size
--   in KiB. Returns 'true' on success or nil and an error message on failure.
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
	
	-- Now, to insert it into the database.
	local _, err_msg = accouts:execute([[
	 INSERT INTO backups(creation_time, totalcomments, totalclaims, size_kb)
	 VALUES (]] .. get_unix_time() .. ", " .. com_count .. ", " ..
	 claim_count .. ", " .. size .. ");")
	
	return not err_msg or nil, err_msg
end

-------------------------------------------------------------------------------
-- High-level interactions

-- All of these automatically sanitize their inputs automatically. Don't pre-
--   sanitize. All of these will return nil and an error message if there is
--   some failure.
local _M = {_VERSION = DB_VERSION, db = {}, claims = {}, comments = {}}

-------------------------------------------------------------------------------
-- Database interactions

-- A local variable determining if the database is running. If it isn't
--   runnning, most API functions will error.
local running = true

-- Returns whether the database is running.
function _M.db.is_running()
	return running
end

-- Returns true if the database was stopped, nil and an error message
--   otherwise.
function _M.db.stop()
	if running then
		local result, err_msg = accouts:close()
		
		if result then
			running = false
			
			return true
		else
			return nil, "There are still cursors open"
		end
	else
		return nil, "The database is already stopped"
	end
end

-- Returns true if the database was started, nil and an error message
--   otherwise.
function _M.db.start()
	if running then
		return nil, "The database is already started"
	else
		accouts = sql:connect(db_path)
		running = true
		
		return true
	end
end

-- Returns true if the database was restarted, nil and an error message
--   otherwise.
function _M.db.restart()
	if running then
		local result, err_msg = _M.db.stop()
		
		if not result then
			return result, err_msg
		else
			return _M.db.start()
		end
	else
		return _M.db.start()
	end
end

-- Creates a backup of the database and 'true' if successful, otherwise nil and
--   an error message.
function _M.db.backup()
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
	
	local bk_file, err_msg = io.open(file_name, "w+b")
	
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
	bk_file:write(b64_encode(sig_obj:sign()))
	
	bk_file:flush()
	
	-- Returns the index position (byte #) of the last byte of the file. AKA
	--   it returns the size of the file in KiB, rounded up.
	local bk_size = math.ceil(bk_file:seek"end" / 1024)
	bk_file:close()
	
	local success, err_msg = new_backup_entry(bk_size)
	
	curs:close()
	
	return success, err_msg
end

-------------------------------------------------------------------------------
-- Claim interactions

-- Adds a claim to the "claims" SQL table. If the claim is already in the
--   database, this is a no-op. Returns 1 if the claim was added, 0 if the
--   claim was already present, or nil and an error string if there was a
--   problem.
function _M.claims.new(claim_uri)
	return accouts:execute(
	 "INSERT INTO claims (lbry_perm_uri, add_time) VALUES ('" ..
	 accouts:escape(claim_uri) .. "', " .. get_unix_time() .. ");"
	)
end

-- Returns the data for the row containing a given claim URI. If int_ind ==
--   true, then the indices are integers rather than alphanumeric. int_ind is
--   optional.
function _M.claims.get_data(claim_uri, int_ind)
	if type(claim_uri) ~= "string" then
		return nil, "The claim URI needs to be a string, is a " ..
		            type(claim_uri) .. "."
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
		return nil, "The claim URI '" .. claim_uri ..
			    "' does not exist."
	end
end

-- Adds a given amount of upvotes to the row containing the given claim URI. It
--   returns the final amount of upvotes. If the times to upvote isn't given, it
--   upvotes once. times must be an integer, and is optional.
function _M.claims.upvote(claim_uri, times)
	if times == nil then
		times = 1
	elseif type(times) ~= "number" then
		return nil, "The times to upvote needs to be a number, is a " ..
		            type(times) .. "."
	elseif times % 1 ~= 0 then
		return nil, "The times to upvote is fractional, not an integer."
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

-- Adds a given amount of downvotes to the row containing the given claim URI.
-- It returns the final amount of downvotes. If the times to downvote isn't
-- given, it downvotes once. times must be an integer, and is optional.
function _M.claims.downvote(claim_uri, times)
	if times == nil then
		times = 1
	elseif type(times) ~= "number" then
		return nil, "The times to downvote needs to be a number, " ..
		            "is a " .. type(times) .. "."
	elseif times % 1 ~= 0 then
		return nil, "The times to downvote is fractional, not an " ..
		            "integer."
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

-------------------------------------------------------------------------------
-- Comment interactions



-------------------------------------------------------------------------------
-- Goodbye!

return _M
