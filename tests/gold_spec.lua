local load = require("tests.load")

local GOLD = 10000 -- copper

-- A net with the given clients logged in and in one Crew, settled.
local function crew(names)
  local ns = load()
  local net = ns.FakeNet.new()
  local clients = {}
  for i, name in ipairs(names) do clients[i] = net:add(name):login() end
  local code = clients[1]:join()
  for i = 2, #clients do clients[i]:join(code) end
  net:run(40)
  return net, clients, ns
end

-- The number of entries in the client's feed().
local function feedSize(client)
  local n = 0
  for _, day in ipairs(client.core:feed().days) do n = n + #day.entries end
  return n
end

-- The messages `name` put on the wire since `from` (an index into net.wire).
local function sentBy(net, from, name)
  local messages = {}
  for i = from + 1, #net.wire do
    if net.wire[i].from == name then messages[#messages + 1] = net.wire[i] end
  end
  return messages
end

describe("Gold", function()
  it("sends a gold-only change only along with the next send", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    a:play({ money = 5 * GOLD, level = 11 })
    net:run(2)
    local events = a:count("changed")
    local mark = #net.wire
    a:play({ money = 6 * GOLD })
    assert.is_true(a:count("changed") > events)
    net:run(30)
    assert.same({}, sentBy(net, mark, "Ann"))
    assert.equal(5 * GOLD, b:rowFor(a).money)

    -- It rides along with the next send.
    a:play({ deaths = 1 })
    net:run(2)
    assert.equal(6 * GOLD, b:rowFor(a).money)
  end)

  it("reaches the rest of the Crew on the right Character, shown and Alt", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    a:play({ money = 12 * GOLD, level = 11 })
    net:run(2)
    a:play({ guid = "Player-0-AnnAlt", name = "Annalt", level = 5, money = 3 * GOLD })
    net:run(2)

    local row = b:rowFor(a)
    assert.equal("Annalt", row.name)
    assert.equal(3 * GOLD, row.money)
    assert.equal(1, #row.alts)
    assert.equal("Ann", row.alts[1].name)
    assert.equal(12 * GOLD, row.alts[1].money)
  end)

  it("leaves money out for a Character whose client never shared it", function()
    local net, clients, ns = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    a:play({ level = 11 })
    net:run(2)
    local row = b:rowFor(a)
    assert.equal(11, row.level)
    assert.is_nil(row.money)
    assert.is_nil(ns.Core.goldText(row.money))
  end)

  it("adds no Feed entry", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    a:play({ money = 1 * GOLD, level = 11 })
    net:run(2)
    local own, theirs = feedSize(a), feedSize(b)
    a:play({ money = 900 * GOLD })
    a:play({ level = 12 })
    net:run(2)
    assert.equal(900 * GOLD, b:rowFor(a).money)
    -- Only the ding.
    assert.equal(own + 1, feedSize(a))
    assert.equal(theirs + 1, feedSize(b))
  end)

  it("shows whole gold, floored, with thousands separators", function()
    local Core = load().Core
    assert.equal("Gold: 1,234", Core.goldText(12345678))
    assert.equal("Gold: 0", Core.goldText(9999))
    assert.equal("Gold: 0", Core.goldText(0))
    assert.equal("Gold: 999", Core.goldText(999 * GOLD + 9999))
    assert.equal("Gold: 1,000", Core.goldText(1000 * GOLD))
    assert.equal("Gold: 1,234,567", Core.goldText(1234567 * GOLD))
    assert.is_nil(Core.goldText(nil))
  end)
end)
