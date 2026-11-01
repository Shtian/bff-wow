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

-- The newest entry with this text.
local function entry(client, text)
  for _, candidate in ipairs(entries(client)) do
    if candidate.text == text then return candidate end
  end
  error(("%s has no entry %q"):format(client.name, text))
end

-- Who reacted to an entry, by name ("You" for yourself), in order.
local function reactors(client, text)
  local names = {}
  for i, reactor in ipairs(entry(client, text).reactors) do
    names[i] = reactor.you and "You" or reactor.name
  end
  return names
end

local function react(client, text)
  return client.core:react(entry(client, text).key)
end

local function events(client, name)
  local list = {}
  for _, event in ipairs(client.events) do
    if event[1] == name then list[#list + 1] = event[2] end
  end
  return list
end

local function reactionTexts(client)
  local texts = {}
  for i, news in ipairs(events(client, "reaction")) do texts[i] = news.text end
  return texts
end

local function noticed(summary)
  local texts = {}
  for i, line in ipairs(summary.noticed) do texts[i] = line.text end
  return texts
end

-- Logs the client back in with a clean event list.
local function relog(net, client)
  client.events = {}
  client:login()
  net:run(40)
end

local function ownReactions(client)
  return client.db.records[client.memberId].reactions or {}
end

describe("Reactions", function()
  it("tell the owner at their next login, and show on everyone's entry", function()
    local net, clients = crew({ "Ann", "Bob", "Cid" }, { Ann = 23 })
    local a, b, c = clients[1], clients[2], clients[3]
    a:play({ level = 24 })
    net:run(3)
    a:logout()
    net:run(5)

    assert.equal("cheer", entry(b, "Ann dinged 24").reaction)
    assert.is_true(entry(b, "Ann dinged 24").canReact)
    assert.is_true(react(b, "Ann dinged 24"))
    assert.same({ "You" }, reactors(b, "Ann dinged 24"))
    assert.is_true(entry(b, "Ann dinged 24").reacted)
    net:run(5)
    assert.same({ "Bob" }, reactors(c, "Ann dinged 24"))

    relog(net, a)
    local summary = events(a, "awaySummary")[1]
    assert.same({ "Bob cheered your ding to 24" }, noticed(summary))
    assert.same({}, summary.members)
    assert.same({ "Bob" }, reactors(a, "You dinged 24"))
    assert.equal(0, a.core:unseen())
    assert.same({}, reactionTexts(a))
  end)

  it("are keyed by what happened, so collapsed entries meet the owner's", function()
    local net, clients = crew({ "Ann", "Bob", "Cid" }, { Ann = 22 })
    local a, b, c = clients[1], clients[2], clients[3]
    c:logout()
    net:run(5)
    a:play({ level = 23 })
    net:run(3)
    react(b, "Ann dinged 23")
    net:run(3)
    a:play({ level = 24 })
    net:run(3)

    relog(net, c)
    local collapsed = entry(c, "Ann dinged 24")
    assert.equal(22, collapsed.from)
    assert.same({ "Bob" }, reactors(c, "Ann dinged 24"))
    assert.is_true(react(c, "Ann dinged 24"))
    assert.same({ "Bob", "You" }, reactors(c, "Ann dinged 24"))
    net:run(5)

    assert.same({ "Bob" }, reactors(a, "You dinged 23"))
    assert.same({ "Cid" }, reactors(a, "You dinged 24"))
    assert.same({ "Bob cheered your ding to 23", "Cid cheered your ding to 24" }, reactionTexts(a))
  end)

  it("land on one entry whichever version of the record each Member got", function()
    local net, clients = crew({ "Ann", "Bob", "Cid" })
    local a, b, c = clients[1], clients[2], clients[3]
    c:lockdown(true)
    a:play({ level = 11 })
    net:run(3)
    a:play({ zone = "Westfall" })
    net:run(15)
    c:lockdown(false)
    net:run(10)

    react(b, "Ann dinged 11")
    react(c, "Ann dinged 11")
    net:run(5)
    assert.same({ "Bob", "Cid" }, reactors(a, "You dinged 11"))
  end)

  it("show once the entry is made, when they arrive first", function()
    local net, clients = crew({ "Ann", "Bob", "Cid" })
    local a, b, c = clients[1], clients[2], clients[3]
    net.drop = function(_, from, to) return from == "Ann" and to == "Cid" end
    a:play({ level = 11 })
    net:run(3)
    react(b, "Ann dinged 11")
    net:run(5)
    assert.equal(1, #entries(c))
    assert.equal("You joined the Crew", entries(c)[1].text)

    net.drop = nil
    c:refused()
    net:run(10)
    assert.same({ "Bob" }, reactors(c, "Ann dinged 11"))
  end)

  it("fire one news item each while you're online, and are seen as they do", function()
    local net, clients = crew({ "Ann", "Bob", "Cid" })
    local a, b, c = clients[1], clients[2], clients[3]
    a:play({ level = 11 })
    net:run(3)
    react(b, "Ann dinged 11")
    react(c, "Ann dinged 11")
    net:run(5)

    local news = events(a, "reaction")
    assert.equal(2, #news)
    assert.equal("Bob cheered your ding to 11", news[1].text)
    assert.equal("cheer", news[1].reaction)
    assert.equal("Bob", news[1].name)
    assert.equal("cheered your ding to 11", news[1].phrase)
    assert.equal(news[1].entryKey, news[2].entryKey)
    assert.equal(0, a.core:unseen())
  end)

  it("stay unseen with chat lines and toasts off, and count as new", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    a.core:setChatLines(false)
    a.core:setToasts(false)
    a:play({ level = 11 })
    net:run(3)
    react(b, "Ann dinged 11")
    net:run(5)

    assert.same({}, events(a, "reaction"))
    assert.equal(1, a.core:unseen())
    assert.is_false(entry(a, "You dinged 11").seen)
    a.core:feedSeen()
    assert.equal(0, a.core:unseen())
    assert.is_true(entry(a, "You dinged 11").seen)
  end)

  it("bring up While you were away by themselves, newest first", function()
    local net, clients = crew({ "Ann", "Bob", "Cid", "Dee", "Eve", "Fay" }, { Ann = 20 })
    local a = clients[1]
    a:play({ level = 21 })
    net:run(3)
    a:play({ deaths = 1 })
    net:run(3)
    a:logout()
    net:run(5)
    for i = 2, 6 do
      react(clients[i], "Ann dinged 21")
      net:run(2)
    end
    react(clients[2], "Ann died")
    net:run(5)

    relog(net, a)
    assert.same({
      "Bob paid respects (Ann died)",
      "Bob, Cid, Dee and 2 others cheered your ding to 21",
    }, noticed(events(a, "awaySummary")[1]))
  end)

  it("welcome a Member who joined, and name it on their own joined entry", function()
    local net, clients, _, code = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    local d = net:add("Dee", { character = playing("Dee") }):login()
    d:join(code)
    net:run(40)
    assert.same({ "You joined the Crew" }, (function()
      local texts = {}
      for i, e in ipairs(entries(d)) do texts[i] = e.text end
      return texts
    end)())
    assert.is_false(entry(d, "You joined the Crew").canReact)
    d:logout()
    net:run(5)

    assert.equal("welcome", entry(a, "Dee joined the Crew").reaction)
    react(a, "Dee joined the Crew")
    net:run(2)
    react(b, "Dee joined the Crew")
    net:run(5)

    relog(net, d)
    local summary = events(d, "awaySummary")[1]
    assert.same({ "Ann and Bob welcomed you" }, noticed(summary))
    assert.same({}, summary.members)
  end)

  it("name an Alt's events and new Characters", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    a.core:setMain(a.character.guid)
    a.character = playing("Jaina", 1, { guid = "Player-0-Jaina", classFilename = "MAGE" })
    a:play()
    net:run(3)
    a:play({ level = 2 })
    net:run(3)
    a:play({ deaths = 1 })
    net:run(3)
    react(b, "Ann has a new Character: Jaina (Mage)")
    react(b, "Ann's Alt Jaina dinged 2")
    react(b, "Ann's Alt Jaina died")
    net:run(5)
    assert.same({
      "Bob cheered your new Character Jaina",
      "Bob cheered your Alt Jaina's ding to 2",
      "Bob paid respects (Jaina died)",
    }, reactionTexts(a))
  end)

  it("are kept 50 at a time in the record, while the owner keeps them all", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    for deaths = 1, 51 do
      a:play({ deaths = deaths })
      net:run(3)
      local death = entries(b)[1]
      assert.equal(deaths, death.key.n)
      assert.is_true(b.core:react(death.key))
      net:run(3)
    end

    assert.equal(50, #ownReactions(b))
    local oldest = entries(a)[51]
    assert.equal("death", oldest.kind)
    assert.equal(1, #oldest.reactors)
  end)

  it("are kept for 30 days in the record, pruned at the next write", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    a:play({ level = 11 })
    net:run(3)
    react(b, "Ann dinged 11")
    net:run(3)
    net:step(net:now() + 29 * DAY)
    b:play({ zone = "Duskwood" })
    assert.equal(1, #ownReactions(b))
    net:step(net:now() + 2 * DAY)
    assert.equal(1, #ownReactions(b))
    b:play({ zone = "Westfall" })
    assert.equal(0, #ownReactions(b))
  end)

  it("give a new Member no news, and ignore those for entries they don't have", function()
    local net, clients, _, code = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    a:play({ level = 11 })
    net:run(3)
    react(b, "Ann dinged 11")
    net:run(5)

    local d = net:add("Dee", { character = playing("Dee") }):login()
    d:join(code)
    net:run(40)
    a:play({ level = 12 })
    net:run(5)
    assert.equal(0, d.core:unseen())
    assert.same({}, events(d, "reaction"))
    assert.same({}, reactors(d, "Ann dinged 12"))
  end)

  it("reach the owner once the reacting Member's lockdown clears", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    a:play({ level = 11 })
    net:run(3)
    b:lockdown(true)
    assert.is_true(react(b, "Ann dinged 11"))
    assert.same({ "You" }, reactors(b, "Ann dinged 11"))
    net:run(10)
    assert.same({}, reactors(a, "You dinged 11"))

    b:lockdown(false)
    net:run(5)
    assert.same({ "Bob" }, reactors(a, "You dinged 11"))
  end)

  it("are hidden from a Removed Member, whose entries can't be reacted to", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    a:play({ level = 11 })
    b:play({ level = 11 })
    net:run(3)
    react(b, "Ann dinged 11")
    net:run(5)
    local key = entry(a, "Bob dinged 11").key

    assert.is_true(a.core:removeMember(b.memberId))
    assert.same({}, reactors(a, "You dinged 11"))
    assert.equal(0, a.core:unseen())
    assert.is_false(a.core:react(key))
  end)

  it("ignore your own entries, left entries and ones you already gave", function()
    local net, clients = crew({ "Ann", "Bob", "Cid" })
    local a, b, c = clients[1], clients[2], clients[3]
    a:play({ level = 11 })
    net:run(3)
    c.core:leaveCrew()
    net:run(3)

    assert.is_false(entry(a, "You dinged 11").canReact)
    assert.is_false(react(a, "You dinged 11"))
    assert.is_nil(entry(b, "Cid left the Crew").key)
    assert.is_false(b.core:react({ memberId = c.memberId, kind = "left" }))
    assert.is_false(b.core:react("nonsense"))

    local changed = b:count("changed")
    assert.is_true(react(b, "Ann dinged 11"))
    assert.equal(changed + 1, b:count("changed"))
    assert.is_false(react(b, "Ann dinged 11"))
    assert.equal(changed + 1, b:count("changed"))
    assert.equal(1, #ownReactions(b))
  end)

  it("are cleared from your record when you leave", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    a:play({ level = 11 })
    net:run(3)
    react(b, "Ann dinged 11")
    net:run(3)
    b.core:leaveCrew()
    net:run(3)
    assert.equal(0, #ownReactions(b))
  end)

  it("keep records from older clients and with malformed items", function()
    local net, clients, ns = crew({ "Ann", "Bob" })
    local a = clients[1]
    a:play({ level = 11 })
    net:run(3)
    local own = entry(a, "You dinged 11")
    assert.same({ memberId = a.memberId, guid = a.character.guid, kind = "ding", n = 11 }, own.key)

    local function send(id, reactions)
      a.core:received(ns.Codec.encode({
        type = "DATA", from = id,
        records = { {
          id = id, version = net:now(), displayName = id, joinedAt = 1,
          characters = {}, reactions = reactions,
        } },
      }))
    end
    send("olderone")
    send("garbled1", { "junk", { m = 5 }, { m = a.memberId, g = a.character.guid, k = "d", n = 11, t = net:now() } })
    send("garbled2", "junk")
    for _, id in ipairs({ "olderone", "garbled1", "garbled2" }) do
      assert.is_table(a.core.ledger:record(id))
    end
    -- First sight is a silent baseline, but the Reaction still shows.
    assert.same({ "garbled1" }, reactors(a, "You dinged 11"))
    assert.equal(0, a.core:unseen())
  end)
end)
