
--[[
-- Stopping and starting the database.
assert(database.db.restart())
assert(not database.db.start())
assert(database.db.stop())
assert(database.db.start())

-- Adding claims.
assert(database.claims.new "lbry://@TEST_CLAIM1@")
assert(database.claims.new "lbry://@TEST_CLAIM2@")
assert(database.claims.new "lbry://@TEST_CLAIM3@")

-- Getting claim data.
assert(database.claims.get_data "lbry://@TEST_CLAIM2@")
assert(database.claims.get_data "lbry://@TEST_CLAIM3@")
assert(not database.claims.get_data "lbry://@TEST_CLAIM4@")

-- Test that get_uri and get_data give consistent results.
local claim_1_data = assert(database.claims.get_data "lbry://@TEST_CLAIM1@")
local claim_data_uri = assert(database.claims.get_uri(claim_1_data.claim_index))
assert(claim_data_uri == "lbry://@TEST_CLAIM1@")
]]
