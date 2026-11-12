-- Record versions and what a DIGEST lists aren't visible through Core's
-- interface, so these check the Ledger directly. What peers send because
-- of them is checked through Core (roster_spec, sync_spec).
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

describe("A removed Member", function()
  local function ledgerWith(records)
    local ledger = load().Ledger.new({ memberId = "me000000" }, function() return 5000 end, math.random)
    for _, record in ipairs(records) do ledger:merge(record, record.id) end
    return ledger
  end

  local function record(id, version)
    return { id = id, version = version, displayName = id, characters = {} }
  end

  it("is listed in the DIGEST with the version last seen", function()
    local ledger = ledgerWith({ record("bob00000", 300), record("cid00000", 200) })
    ledger:remove("bob00000")
    local versions, partial = ledger:digest(10)
    assert.same({ bob00000 = 300, cid00000 = 200 }, versions)
    assert.is_false(partial)
    assert.equal(300, ledger:version("bob00000"))
    assert.is_nil(ledger:record("bob00000"))
  end)

  it("takes turns with the held records inside the limit", function()
    local ledger = ledgerWith({ record("aaa00000", 1), record("bbb00000", 2), record("ccc00000", 3) })
    ledger:remove("bbb00000")
    local first, partial, last = ledger:digest(2)
    assert.same({ aaa00000 = 1, bbb00000 = 2 }, first)
    assert.is_true(partial)
    local second = ledger:digest(2, last)
    assert.same({ ccc00000 = 3, aaa00000 = 1 }, second)
  end)

  it("refuses a newer copy but notes its version", function()
    local ledger = ledgerWith({ record("bob00000", 300) })
    ledger:remove("bob00000")
    assert.is_false(ledger:merge(record("bob00000", 400), "cid00000"))
    assert.is_nil(ledger:record("bob00000"))
    assert.equal(400, ledger:version("bob00000"))
    assert.is_false(ledger:merge(record("bob00000", 350), "cid00000"))
    assert.equal(400, ledger:version("bob00000"))
    assert.is_false(ledger:merge({ id = "bob00000", version = "x" }, "cid00000"))
    assert.equal(400, ledger:version("bob00000"))
  end)

  it("removed before versions were kept is listed with 0", function()
    local ledger = ledgerWith({ record("cid00000", 200) })
    ledger.db.removed.bob00000 = { displayName = "Bob" }
    assert.same({ bob00000 = 0, cid00000 = 200 }, (ledger:digest(10)))
    ledger:merge(record("bob00000", 300), "cid00000")
    assert.same({ bob00000 = 300, cid00000 = 200 }, (ledger:digest(10)))
  end)

  it("is fetched again once re-added", function()
    local ledger = ledgerWith({ record("bob00000", 300) })
    ledger:remove("bob00000")
    ledger:readd("bob00000")
    assert.equal(0, ledger:version("bob00000"))
    assert.same({}, (ledger:digest(10)))
    assert.is_true(ledger:merge(record("bob00000", 300), "cid00000"))
  end)
end)
