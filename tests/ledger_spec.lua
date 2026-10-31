-- Record versions aren't visible through Core's interface yet (Gossip will
-- send them), so these check the Ledger directly.
local load = require("tests.load")

local function character(level)
  return {
    guid = "Player-1-0000AAAA", name = "Thrallbane", classFilename = "WARRIOR",
    level = level, xp = 0, maxXp = 100, zone = "Elwynn Forest", deaths = 0,
  }
end

describe("Ledger", function()
  it("versions the own record by the clock", function()
    local clock = 5000
    local ledger = load().Ledger.new({}, function() return clock end, math.random)
    ledger:updateOwn(character(1))
    assert.equal(5000, ledger:own().version)

    clock = 6000
    ledger:updateOwn(character(2))
    assert.equal(6000, ledger:own().version)
  end)

  it("still increases the version for two writes in the same second", function()
    local ledger = load().Ledger.new({}, function() return 5000 end, math.random)
    ledger:updateOwn(character(1))
    ledger:updateOwn(character(2))
    ledger:updateOwn(character(3))
    assert.equal(5002, ledger:own().version)
  end)

  it("never lets the version go back when the clock does", function()
    local clock = 5000
    local db = {}
    load().Ledger.new(db, function() return clock end, math.random):updateOwn(character(1))

    clock = 4000
    local ledger = load().Ledger.new(db, function() return clock end, math.random)
    ledger:updateOwn(character(2))
    assert.equal(5001, ledger:own().version)
  end)

  it("leaves the version alone when nothing changed", function()
    local ledger = load().Ledger.new({}, function() return 5000 end, math.random)
    ledger:updateOwn(character(1))
    ledger:updateOwn(character(1))
    assert.equal(5000, ledger:own().version)
  end)
end)
