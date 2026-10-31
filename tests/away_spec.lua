local load = require("tests.load")

-- A character table for FakeNet, at the given level.
local function playing(name, level, extra)
  local character = {
    guid = "Player-0-" .. name, name = name, classFilename = "WARRIOR",
    level = level or 10, xp = 0, maxXp = 1000, zone = "Elwynn Forest", deaths = 0,
  }
  for k, v in pairs(extra or {}) do character[k] = v end
  return character
end

-- A net with the given clients logged in and in one Crew, settled. levels
-- maps a name to the level it plays.
local function crew(names, levels)
  local ns = load()
  local net = ns.FakeNet.new()
  local clients = {}
  for i, name in ipairs(names) do
    local level = levels and levels[name]
    clients[i] = net:add(name, { character = playing(name, level) }):login()
  end
  local code = clients[1]:join()
  for i = 2, #clients do clients[i]:join(code) end
  net:run(40)
  return net, clients, code
end

-- The awaySummary events the client's Core fired.
local function summaries(client)
  local list = {}
  for _, event in ipairs(client.events) do
    if event[1] == "awaySummary" then list[#list + 1] = event[2] end
  end
  return list
end

local function chatLines(client)
  local lines = {}
  for _, event in ipairs(client.events) do
    if event[1] == "feedEntry" then lines[#lines + 1] = event[2].text end
  end
  return lines
end

-- The first Character's level range in a summary's first Member.
local function levels(summary)
  local character = summary.members[1].characters[1]
  return { from = character.from, level = character.level }
end

-- Logs the client back in with a clean event list.
local function relog(net, client)
  client.events = {}
  client:login()
  net:run(40)
end

describe("While you were away", function()
  it("condenses missed dings and deaths per Character, once, with no chat lines", function()
    local net, clients = crew({ "Ann", "Bob", "Cid" }, { Ann = 22 })
    local a, c = clients[1], clients[3]

    c:logout()
    net:run(5)
    a:play({ level = 23 })
    net:run(5)
    a:play({ level = 24, deaths = 1 })
    net:run(5)
    a:play({ deaths = 2 })
    net:run(5)

    relog(net, c)
    local all = summaries(c)
    assert.equal(1, #all)
    local summary = all[1]
    assert.equal(2, summary.count)
    assert.equal(1, #summary.members)
    local ann = summary.members[1]
    assert.equal(a.memberId, ann.memberId)
    assert.equal("Ann", ann.displayName)
    assert.equal("Ann", ann.main)
    assert.equal("WARRIOR", ann.classFilename)
    assert.same({
      { name = "Ann", main = true, from = 22, level = 24, deaths = 2 },
    }, ann.characters)
    assert.same({}, ann.highlights)
    assert.same({}, chatLines(c))
    assert.equal(0, c.core:feed().unseen)

    net:run(60)
    assert.equal(1, #summaries(c))
  end)

  it("never shows after a /reload", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    b.core:setChatLines(false)
    b.core:setToasts(false)
    a:play({ level = 11 })
    net:run(3)

    b.events = {}
    b:reload()
    net:run(60)
    assert.same({}, summaries(b))
    assert.equal(1, b.core:feed().unseen)
  end)

  it("waits while the link is down", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    b:logout()
    net:run(5)
    a:play({ level = 11 })
    net:run(5)

    b.events = {}
    b:lockdown(true)
    b:login()
    net:run(60)
    assert.same({}, summaries(b))

    b:lockdown(false)
    net:run(40)
    assert.equal(1, #summaries(b))
    assert.same({ from = 10, level = 11 }, levels(summaries(b)[1]))
  end)

  it("starts settling over when the link drops before it settles", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    b:logout()
    net:run(5)
    a:play({ level = 11 })
    net:run(5)

    b.events = {}
    a:lockdown(true)
    b:login()
    net:run(5)
    b:lockdown(true)
    a:lockdown(false)
    net:run(60)
    assert.same({}, summaries(b))

    b:lockdown(false)
    net:run(40)
    assert.equal(1, #summaries(b))
    assert.same({ from = 10, level = 11 }, levels(summaries(b)[1]))
  end)

  it("takes in entries that arrive while settling", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    b:logout()
    net:run(5)

    b.events = {}
    b:login()
    net:run(3)
    a:play({ level = 11 })
    net:run(40)
    assert.equal(1, #summaries(b))
    assert.same({ from = 10, level = 11 }, levels(summaries(b)[1]))
    assert.same({}, chatLines(b))
  end)

  it("shows nothing when nothing is unseen", function()
    local net, clients = crew({ "Ann", "Bob" })
    local b = clients[2]
    b:logout()
    net:run(5)

    relog(net, b)
    assert.same({}, summaries(b))
  end)

  it("leaves your own entries out", function()
    local net, clients = crew({ "Ann", "Bob" })
    local b = clients[2]
    b:logout()
    net:run(5)
    b.character.level = 11

    relog(net, b)
    assert.same({}, summaries(b))
  end)

  it("isn't shown with the popup setting off, and the entries stay unseen", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    assert.is_true(b.core:isAwayPopupOn())
    local changed = b:count("changed")
    b.core:setAwayPopup(false)
    assert.is_false(b.core:isAwayPopupOn())
    assert.equal(changed + 1, b:count("changed"))
    b.core:setAwayPopup(false)
    assert.equal(changed + 1, b:count("changed"))

    b:logout()
    net:run(5)
    a:play({ level = 11 })
    net:run(5)

    relog(net, b)
    assert.is_false(b.core:isAwayPopupOn())
    assert.same({}, summaries(b))
    assert.equal(1, b.core:feed().unseen)
    assert.same({}, chatLines(b))
  end)

  it("orders Members by recent activity, and highlights max level, joined and left", function()
    local net, clients, code = crew({ "Ann", "Bob", "Cid", "Dee" }, { Ann = 58, Bob = 30 })
    local a, b, c, d = clients[1], clients[2], clients[3], clients[4]

    d:logout()
    net:run(5)
    a:play({ level = 60 })
    net:run(5)
    c.core:leaveCrew()
    net:run(5)
    b:play({ deaths = 1 })
    net:run(5)
    local eve = net:add("Eve"):login()
    eve:join(code)
    net:run(40)

    relog(net, d)
    local members = summaries(d)[1].members
    local names = {}
    for i, member in ipairs(members) do names[i] = member.displayName end
    assert.same({ "Eve", "Bob", "Cid", "Ann" }, names)
    assert.same({ { kind = "joined", text = "Eve joined the Crew" } }, members[1].highlights)
    assert.same({}, members[1].characters)
    assert.same({ { name = "Bob", main = true, deaths = 1 } }, members[2].characters)
    assert.same({ { kind = "left", text = "Cid left the Crew" } }, members[3].highlights)
    assert.same({
      { name = "Ann", main = true, from = 58, level = 60, maxLevel = true },
    }, members[4].characters)
    assert.same({ { kind = "maxLevel", text = "Ann reached max level!" } }, members[4].highlights)
    assert.equal(4, summaries(d)[1].count)
  end)

  it("names Alts and new Characters, with the Main first", function()
    local net, clients = crew({ "Ann", "Bob" }, { Ann = 18 })
    local a, b = clients[1], clients[2]
    local thrall = a.character.guid
    a.core:setMain(thrall)
    a.character = playing("Jaina", 10, { guid = "Player-0-Jaina", classFilename = "MAGE" })
    a:play()
    net:run(5)

    b:logout()
    net:run(5)
    a:play({ level = 12, deaths = 1 })
    net:run(5)
    a.character = playing("Rexxar", 5, { guid = "Player-0-Rexxar", classFilename = "HUNTER" })
    a:play()
    net:run(5)
    a:play({ level = 7 })
    net:run(5)
    a.character = playing("Ann", 20, { guid = thrall })
    a:play()
    net:run(5)

    relog(net, b)
    local ann = summaries(b)[1].members[1]
    assert.equal("Ann", ann.main)
    assert.same({
      { name = "Ann", main = true, from = 18, level = 20 },
      { name = "Jaina", from = 10, level = 12, deaths = 1 },
      { name = "Rexxar", new = true, level = 7 },
    }, ann.characters)
  end)
end)
