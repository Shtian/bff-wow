local load = require("tests.load")

local function newDeps(db)
  local deps = {
    sent = {},
    events = {},
    db = db or {},
    clock = 1000,
    random = math.random,
    initialLogin = true,
    maxLevel = 60,
  }
  deps.now = function() return deps.clock end
  deps.link = { send = function(message) deps.sent[#deps.sent + 1] = message end }
  deps.listener = function(...) deps.events[#deps.events + 1] = { ... } end
  return deps
end

local function character(overrides)
  local c = {
    guid = "Player-1-0000AAAA",
    name = "Thrallbane",
    classFilename = "WARRIOR",
    level = 24,
    xp = 1200,
    maxXp = 2000,
    zone = "Stranglethorn Vale",
    deaths = 3,
  }
  for k, v in pairs(overrides or {}) do c[k] = v end
  return c
end

-- Each alt's name, classFilename and level.
local function alts(row)
  local result = {}
  for i, alt in ipairs(row.alts) do
    result[i] = { name = alt.name, classFilename = alt.classFilename, level = alt.level }
  end
  return result
end

local function countEvents(deps, name)
  local n = 0
  for _, e in ipairs(deps.events) do
    if e[1] == name then n = n + 1 end
  end
  return n
end

describe("Your own Character", function()
  it("shows no rows before anything is known", function()
    local core = load().Core.new(newDeps())
    assert.same({}, core:rows())
  end)

  it("shows the Character being played as one row", function()
    local core = load().Core.new(newDeps())
    core:updateOwn(character())

    local rows = core:rows()
    assert.equal(1, #rows)
    local row = rows[1]
    assert.equal("Thrallbane", row.name)
    assert.equal("WARRIOR", row.classFilename)
    assert.equal(24, row.level)
    assert.equal(1200, row.xp)
    assert.equal(2000, row.maxXp)
    assert.equal("Stranglethorn Vale", row.zone)
    assert.same({}, row.alts)
  end)

  it("fires changed when the Character changes, and only then", function()
    local deps = newDeps()
    local core = load().Core.new(deps)

    core:updateOwn(character())
    assert.equal(1, countEvents(deps, "changed"))

    deps.clock = deps.clock + 5
    core:updateOwn(character())
    assert.equal(1, countEvents(deps, "changed"))

    core:updateOwn(character({ level = 25, xp = 10, maxXp = 2100 }))
    assert.equal(2, countEvents(deps, "changed"))
    assert.equal(25, core:rows()[1].level)

    core:updateOwn(character({ level = 25, xp = 10, maxXp = 2100, zone = "Booty Bay" }))
    assert.equal(3, countEvents(deps, "changed"))
    assert.equal("Booty Bay", core:rows()[1].zone)
  end)

  it("gives rows that are copies, not the record itself", function()
    local core = load().Core.new(newDeps())
    core:updateOwn(character())

    local row = core:rows()[1]
    row.level = 99
    row.alts[1] = "junk"

    assert.equal(24, core:rows()[1].level)
    assert.same({}, core:rows()[1].alts)
  end)

  it("survives a reload", function()
    local db = {}
    local first = load().Core.new(newDeps(db))
    first:updateOwn(character())
    local before = first:rows()

    local second = load().Core.new(newDeps(db))
    assert.same(before, second:rows())
  end)

  it("keeps the same Member id across Characters on the account", function()
    local db = {}
    local deps = newDeps(db)
    local first = load().Core.new(deps)
    first:updateOwn(character())
    local memberId = first:rows()[1].memberId
    assert.is_string(memberId)

    -- Relog onto another Character.
    local relog = newDeps(db)
    relog.clock = deps.clock + 60
    local second = load().Core.new(relog)
    second:updateOwn(character({ guid = "Player-1-0000BBBB", name = "Healbot", classFilename = "PRIEST", level = 5 }))

    local rows = second:rows()
    assert.equal(1, #rows)
    assert.equal(memberId, rows[1].memberId)
    assert.equal("Healbot", rows[1].name)
    assert.same({ { name = "Thrallbane", classFilename = "WARRIOR", level = 24 } }, alts(rows[1]))
  end)

  it("gives each new account a different Member id", function()
    local a = load().Core.new(newDeps())
    local b = load().Core.new(newDeps())
    a:updateOwn(character())
    b:updateOwn(character())
    assert.are_not.equal(a:rows()[1].memberId, b:rows()[1].memberId)
  end)

  it("keys Characters by GUID, so a renamed Character stays one Character", function()
    local deps = newDeps()
    local core = load().Core.new(deps)
    core:updateOwn(character())
    deps.clock = deps.clock + 60
    core:updateOwn(character({ name = "Thrallbane", guid = "Player-1-0000BBBB", level = 5 }))
    deps.clock = deps.clock + 60
    core:updateOwn(character({ name = "Renamed" }))

    local rows = core:rows()
    assert.equal("Renamed", rows[1].name)
    assert.equal(24, rows[1].level)
    assert.same({ { name = "Thrallbane", classFilename = "WARRIOR", level = 5 } }, alts(rows[1]))
  end)

  it("shows the Character just switched to, even if nothing about it changed", function()
    local db = {}
    local deps = newDeps(db)
    local core = load().Core.new(deps)
    core:updateOwn(character())
    deps.clock = deps.clock + 60
    core:updateOwn(character({ guid = "Player-1-0000BBBB", name = "Healbot", level = 5 }))

    local relog = newDeps(db)
    relog.clock = deps.clock + 60
    local again = load().Core.new(relog)
    again:updateOwn(character())

    assert.equal("Thrallbane", again:rows()[1].name)
  end)

  it("refuses a Character without a GUID", function()
    local core = load().Core.new(newDeps())
    assert.has_error(function() core:updateOwn(character({ guid = false })) end)
  end)
end)
