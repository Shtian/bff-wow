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

describe("Deaths counted once", function()
  local Deaths, characterDB
  before_each(function()
    Deaths = load().Deaths
    characterDB = { deaths = 0 }
  end)

  local function die(instanceType) Deaths.died(characterDB, instanceType or "none") end
  local function releaseToGhost() Deaths.checkAlive(characterDB, true) end
  local function comeBackToLife() Deaths.checkAlive(characterDB, false) end

  it("counts a death", function()
    die()
    assert.equal(1, characterDB.deaths)
  end)

  it("counts a death once when the game says so twice, as with a pet out", function()
    die()
    die()
    assert.equal(1, characterDB.deaths)
  end)

  it("counts a death once across a release to a ghost", function()
    die()
    releaseToGhost()
    die()
    assert.equal(1, characterDB.deaths)
  end)

  it("counts the next death after coming back to life", function()
    die()
    comeBackToLife()
    die()
    assert.equal(2, characterDB.deaths)
  end)

  it("counts the next death after a ghost comes back to life", function()
    die()
    releaseToGhost()
    comeBackToLife()
    die()
    assert.equal(2, characterDB.deaths)
  end)

  it("keeps a counted death across a reload while still dead", function()
    die()
    characterDB = { deaths = characterDB.deaths, deathCounted = characterDB.deathCounted }
    releaseToGhost()
    die()
    assert.equal(1, characterDB.deaths)
  end)

  it("doesn't count a death in a battleground or arena", function()
    die("pvp")
    comeBackToLife()
    die("arena")
    assert.equal(0, characterDB.deaths)
  end)
end)
