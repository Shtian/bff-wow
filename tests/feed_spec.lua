local load = require("tests.load")

local DAY = 24 * 60 * 60

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
local function crew(names, levels, netOptions)
  local ns = load()
  local net = ns.FakeNet.new(netOptions)
  local clients = {}
  for i, name in ipairs(names) do
    local level = levels and levels[name]
    clients[i] = net:add(name, { character = playing(name, level) }):login()
  end
  local code = clients[1]:join()
  for i = 2, #clients do clients[i]:join(code) end
  net:run(40)
  return net, clients, ns, code
end

-- Every entry in the client's feed(), newest first.
local function entries(client)
  local all = {}
  for _, day in ipairs(client.core:feed().days) do
    for _, entry in ipairs(day.entries) do all[#all + 1] = entry end
  end
  return all
end

-- The texts of the client's entries, leaving out the "You joined the Crew"
-- every joining client has.
local function texts(client)
  local result = {}
  for _, entry in ipairs(entries(client)) do
    if not (entry.own and entry.kind == "joined") then result[#result + 1] = entry.text end
  end
  return result
end

-- The texts of the feedEntry events the client's Core fired.
local function chatLines(client)
  local lines = {}
  for _, event in ipairs(client.events) do
    if event[1] == "feedEntry" then lines[#lines + 1] = event[2].text end
  end
  return lines
end

describe("The Feed", function()
  it("collapses missed dings and deaths into one entry each, with no chat line while settling", function()
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

    c.events = {}
    c:login()
    net:run(40)
    assert.same({ "Ann died 2 times", "Ann dinged 24" }, texts(c))
    local ding = entries(c)[2]
    assert.equal("ding", ding.kind)
    assert.equal(22, ding.from)
    assert.equal(24, ding.level)
    assert.equal(2, entries(c)[1].count)
    -- While you were away showed them instead.
    assert.equal(0, c.core:feed().unseen)
    assert.same({}, chatLines(c))
  end)

  it("prints one chat line per live entry once settled, and marks it seen", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]

    a:play({ level = 11 })
    net:run(3)
    a:play({ deaths = 1 })
    net:run(3)
    assert.same({ "Ann dinged 11", "Ann died" }, chatLines(b))
    assert.same({ "Ann died", "Ann dinged 11" }, texts(b))
    assert.equal(0, b.core:feed().unseen)
    for _, entry in ipairs(entries(b)) do assert.is_true(entry.seen) end
  end)

  it("starts chat lines once sync has been quiet for 10 seconds after login", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]

    b:logout()
    net:run(5)
    b:login()
    net:run(3)
    a:play({ level = 11 })
    net:run(3)
    assert.same({}, chatLines(b))

    net:run(15)
    a:play({ level = 12 })
    net:run(3)
    assert.same({ "Ann dinged 12" }, chatLines(b))
    -- The ding from settling went into While you were away.
    assert.equal(0, b.core:feed().unseen)
  end)

  it("makes only a max level entry for a jump that reaches max level", function()
    local net, clients = crew({ "Ann", "Bob" }, { Ann = 59 })
    local a, b = clients[1], clients[2]

    a:play({ level = 60 })
    net:run(3)
    assert.same({ "Ann reached max level!" }, texts(b))
    assert.equal("maxLevel", entries(b)[1].kind)
    assert.same({ "You reached max level!" }, texts(a))
  end)

  it("makes no ding for a level above your own max level", function()
    local net, clients = crew({ "Ann", "Bob" }, { Ann = 60 }, { maxLevel = 70 })
    local a, b = clients[1], clients[2]
    -- Bob is behind on a patch: his max level is lower.
    b:logout()
    net.maxLevel = 60
    b:login()
    net:run(40)

    a:play({ level = 61 })
    net:run(3)
    assert.same({}, texts(b))
    assert.equal(61, b:rowFor(a).level)
  end)

  it("keeps first sight of a Member silent, but says when one joins after you", function()
    local net, clients, _, code = crew({ "Ann", "Bob", "Cid" }, { Ann = 30, Bob = 45 })
    local a, b, c = clients[1], clients[2], clients[3]
    c:logout()
    net:run(60)

    local d = net:add("Dee", { character = playing("Dee", 12) }):login()
    d:join(code)
    net:run(40)
    assert.same({}, texts(d))
    local own = entries(d)[1]
    assert.equal("You joined the Crew", own.text)
    assert.is_true(own.own and own.seen)
    assert.same({ "Dee joined the Crew" }, texts(a))
    assert.same({ "Dee joined the Crew" }, texts(b))
    assert.same({ "Dee joined the Crew" }, chatLines(a))

    -- Cid was in the Crew before Dee, so Dee's first sight of Cid is silent.
    c:login()
    net:run(40)
    assert.same({}, texts(d))
    assert.same({ "Dee joined the Crew" }, texts(c))
    assert.is_table(d:rowFor(c))
  end)

  it("says when a known Member leaves and rejoins", function()
    local net, clients, _, code = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]

    b.core:leaveCrew()
    net:run(3)
    assert.same({ "Bob left the Crew" }, texts(a))
    assert.same({}, texts(b))

    b:join(code)
    net:run(40)
    assert.same({ "Bob joined the Crew", "Bob left the Crew" }, texts(a))
  end)

  it("names a new Character and an Alt's events", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    local main = a.character.guid

    a.character = playing("Jaina", 1, { guid = "Player-0-Jaina", classFilename = "MAGE" })
    a:play()
    net:run(3)
    assert.same({ "Ann has a new Character: Jaina (Mage)" }, texts(b))
    assert.same({ "You have a new Character: Jaina (Mage)" }, texts(a))
    assert.equal("newCharacter", entries(b)[1].kind)
    assert.equal(1, entries(b)[1].level)

    a.core:setMain(main)
    a:play({ level = 2 })
    net:run(3)
    assert.equal("Ann's Alt Jaina dinged 2", texts(b)[1])
    assert.equal("Your Alt Jaina dinged 2", texts(a)[1])
  end)

  it("keeps your own events seen and out of chat", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a = clients[1]

    a:play({ level = 11, deaths = 2 })
    net:run(3)
    assert.same({ "You died 2 times", "You dinged 11" }, texts(a))
    assert.is_true(entries(a)[1].own)
    assert.equal(0, a.core:feed().unseen)
    assert.same({}, chatLines(a))
  end)

  it("gives a ding that arrives after lockdown one chat line, and no unseen entry", function()
    local net, clients = crew({ "Ann", "Bob", "Cid" })
    local a, c = clients[1], clients[3]

    c:lockdown(true)
    a:play({ level = 11 })
    net:run(5)
    assert.same({}, texts(c))
    c:lockdown(false)
    net:run(10)
    assert.same({ "Ann dinged 11" }, chatLines(c))
    assert.equal(0, c.core:feed().unseen)
  end)

  it("leaves entries unseen when chat lines and toasts are off", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]

    assert.is_true(b.core:isChatLinesOn())
    b.core:setChatLines(false)
    assert.is_false(b.core:isChatLinesOn())
    b.core:setToasts(false)
    a:play({ level = 11 })
    net:run(3)
    assert.same({}, chatLines(b))
    assert.same({ "Ann dinged 11" }, texts(b))
    assert.equal(1, b.core:feed().unseen)

    b:reload()
    assert.is_false(b.core:isChatLinesOn())
    assert.is_false(b.core:isToastsOn())
  end)

  it("still prints chat lines right after a reload", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]

    b:reload()
    a:play({ level = 11 })
    net:run(3)
    assert.same({ "Ann dinged 11" }, chatLines(b))
  end)

  it("marks everything seen when the Feed tab opens", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    b.core:setChatLines(false)
    b.core:setToasts(false)
    a:play({ level = 11 })
    net:run(3)

    local changed = b:count("changed")
    b.core:feedSeen()
    assert.equal(0, b.core:feed().unseen)
    assert.is_true(entries(b)[1].seen)
    assert.equal(changed + 1, b:count("changed"))
    b.core:feedSeen()
    assert.equal(changed + 1, b:count("changed"))
  end)

  it("drops a Removed Member's entries, and makes no joined entry on re-adding them", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    net:run(5)
    local d = net:add("Dee"):login()
    d:join(a.core:crew().code)
    net:run(40)
    assert.same({ "Dee joined the Crew" }, texts(b))

    assert.is_true(b.core:removeMember(d.memberId))
    assert.same({}, texts(b))
    b.core:readdMember(d.memberId)
    net:run(10)
    assert.is_table(b:rowFor(d))
    assert.same({}, texts(b))
  end)

  it("wipes the log when you leave the Crew", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    a:play({ level = 11 })
    net:run(3)

    b.core:leaveCrew()
    net:run(1)
    assert.same({}, texts(b))
  end)

  it("makes no entry when a crash lowers the death count", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    a:play({ deaths = 2 })
    net:run(3)

    a:play({ deaths = 1 })
    net:run(3)
    assert.equal(1, b:rowFor(a).deaths)
    assert.same({ "Ann died 2 times" }, texts(b))
    assert.same({ "You died 2 times" }, texts(a))
  end)

  it("groups entries by day, newest first", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    a:play({ level = 11 })
    net:run(3)
    net:step(net:now() + DAY)
    a:play({ level = 12 })
    net:run(3)

    local feed = b.core:feed()
    assert.equal(2, #feed.days)
    assert.equal(0, feed.days[1].daysAgo)
    assert.equal(1, feed.days[2].daysAgo)
    assert.equal("Ann dinged 12", feed.days[1].entries[1].text)
    assert.equal("Ann dinged 11", feed.days[2].entries[1].text)
  end)

  it("keeps entries for 30 days", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    a:play({ level = 11 })
    net:run(3)

    net:step(net:now() + 29 * DAY)
    assert.equal(1, #texts(b))
    net:step(net:now() + 2 * DAY)
    assert.same({}, texts(b))
  end)

  it("keeps at most 200 entries", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    for deaths = 1, 205 do
      a:play({ deaths = deaths })
      net:run(1)
    end
    net:run(2)

    local all = texts(b)
    assert.equal(200, #all)
    assert.equal("Ann died", all[1])
  end)
end)
