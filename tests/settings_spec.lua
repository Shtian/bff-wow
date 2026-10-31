local load = require("tests.load")

-- A character table for FakeNet, at the given level.
local function playing(name, level)
  return {
    guid = "Player-0-" .. name, name = name, classFilename = "WARRIOR",
    level = level or 10, xp = 0, maxXp = 1000, zone = "Elwynn Forest", deaths = 0,
  }
end

-- A net with the given clients logged in and in one Crew, settled.
local function crew(names)
  local ns = load()
  local net = ns.FakeNet.new()
  local clients = {}
  for i, name in ipairs(names) do
    clients[i] = net:add(name, { character = playing(name) }):login()
  end
  local code = clients[1]:join()
  for i = 2, #clients do clients[i]:join(code) end
  net:run(40)
  return net, clients
end

describe("Settings", function()
  it("spreads a new display name to other Members, and redraws your own views", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]

    local before = a:count("changed")
    assert.is_true(a.core:setDisplayName("Annie"))
    assert.equal(before + 1, a:count("changed"))
    assert.equal("Annie", a.core:rows()[1].displayName)

    net:run(5)
    assert.equal("Annie", b:rowFor(a).displayName)
  end)

  it("fires nothing when the display name stays the same", function()
    local _, clients = crew({ "Ann" })
    local a = clients[1]
    local before = a:count("changed")
    assert.is_true(a.core:setDisplayName("  " .. a.core:displayName() .. " "))
    assert.equal(before, a:count("changed"))
  end)

  it("fires changed only when chat lines or the popup actually change", function()
    local _, clients = crew({ "Ann" })
    local a = clients[1]
    local before = a:count("changed")
    a.core:setChatLines(true)
    a.core:setAwayPopup(true)
    assert.equal(before, a:count("changed"))
    a.core:setChatLines(false)
    a.core:setAwayPopup(false)
    assert.equal(before + 2, a:count("changed"))
  end)

  it("counts what's new in the Feed, for the minimap tooltip when the popup is off", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    b.core:setChatLines(false)
    b.core:setAwayPopup(false)
    assert.equal(0, b.core:unseen())

    a:play({ level = 11 })
    net:run(3)
    a:play({ level = 12 })
    net:run(3)
    assert.equal(2, b.core:unseen())

    b.core:feedSeen()
    assert.equal(0, b.core:unseen())
  end)
end)
