local load = require("tests.load")

describe("Deaths", function()
  local Deaths
  before_each(function() Deaths = load().Deaths end)

  it("don't count in a battleground", function()
    assert.is_false(Deaths.counts("pvp"))
  end)

  it("don't count in an arena", function()
    assert.is_false(Deaths.counts("arena"))
  end)

  it("count in the open world, dungeons, raids and anywhere else", function()
    for _, instanceType in ipairs({ "none", "party", "raid", "scenario", "delve" }) do
      assert.is_true(Deaths.counts(instanceType), instanceType)
    end
  end)

  it("count when the instance type can't be read", function()
    assert.is_true(Deaths.counts(nil))
  end)
end)

describe("Deaths.record", function()
  local Deaths, record
  before_each(function()
    Deaths = load().Deaths
    record = { deaths = 0 }
  end)

  local function die(instanceType) Deaths.record(record, "PLAYER_DEAD", true, instanceType or "none") end

  it("counts a death", function()
    die()
    assert.equal(1, record.deaths)
  end)

  it("counts a death once when the game says so twice, as with a pet out", function()
    die()
    die()
    assert.equal(1, record.deaths)
  end)

  it("counts a death once across a release to a ghost", function()
    die()
    Deaths.record(record, "PLAYER_ALIVE", true)
    die()
    assert.equal(1, record.deaths)
  end)

  it("counts the next death after coming back to life", function()
    die()
    Deaths.record(record, "PLAYER_ALIVE", false)
    die()
    assert.equal(2, record.deaths)
  end)

  it("counts the next death after a ghost comes back to life", function()
    die()
    Deaths.record(record, "PLAYER_ALIVE", true)
    Deaths.record(record, "PLAYER_UNGHOST", false)
    die()
    assert.equal(2, record.deaths)
  end)

  it("keeps a counted death across a reload while still dead", function()
    die()
    local saved = { deaths = record.deaths, deathCounted = record.deathCounted }
    record = saved
    die()
    assert.equal(1, record.deaths)
  end)

  it("doesn't count a death in a battleground or arena", function()
    die("pvp")
    Deaths.record(record, "PLAYER_ALIVE", false)
    die("arena")
    assert.equal(0, record.deaths)
  end)

  it("leaves the count alone on other events", function()
    die()
    Deaths.record(record, "PLAYER_XP_UPDATE", false)
    die()
    assert.equal(1, record.deaths)
  end)
end)
