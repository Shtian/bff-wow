local load = require("tests.load")

-- Item IDs from the list (docs/research/fishing-catches.md).
local SMALLFISH = 6291
local AHI = 16967
local TASTYFISH = 19807
local SUMMER_BASS = 13756
local SHOE = 271647

-- A net with the given clients logged in and in one Crew, settled.
local function crew(names, options)
  local ns = load()
  local net = ns.FakeNet.new(options)
  local clients = {}
  for i, name in ipairs(names) do clients[i] = net:add(name):login() end
  local code = clients[1]:join()
  for i = 2, #clients do clients[i]:join(code) end
  net:run(40)
  return net, clients, ns
end

-- A catch as Catches.read gives it: each item ID once, in Westfall.
local function catch(...)
  local items = {}
  for i = 1, select("#", ...) do items[i] = { itemId = select(i, ...), quantity = 1 } end
  return { items = items, zone = "Westfall", subzone = "The Jansen Stead", mapId = 1436 }
end

-- The first n counted types' item IDs that are everyday fish.
local function fish(ns, n)
  local ids = {}
  for _, t in ipairs(ns.Catches.TYPES) do
    if t.kind == "fish" and not t.extra and #ids < n then ids[#ids + 1] = t.itemId end
  end
  return ids
end

-- Catches n everyday types, and lets the record reach the Crew (a catch
-- alone waits for the next send; a level goes out now).
local function catchTypes(net, client, ns, n)
  client.core:caught(catch(unpack(fish(ns, n))))
  client:play({ level = client.character.level + 1 })
  net:run(5)
end

local function entries(client, kind)
  local list = {}
  for _, day in ipairs(client.core:feed().days) do
    for _, entry in ipairs(day.entries) do
      if entry.kind == kind then list[#list + 1] = entry end
    end
  end
  return list
end

local function texts(client, kind)
  local list = {}
  for i, entry in ipairs(entries(client, kind)) do list[i] = entry.text end
  return list
end

local function live(client, kind)
  local list = {}
  for _, event in ipairs(client.events) do
    if event[1] == "feedEntry" and event[2].kind == kind then list[#list + 1] = event[2] end
  end
  return list
end

local function row(client)
  for _, r in ipairs(client.core:goals()) do
    if r.track == "catches" then return r end
  end
end

local function shelf(client)
  local list = {}
  for _, trophy in ipairs(client.core:trophies().shelf) do
    if trophy.track == "catches" then list[#list + 1] = trophy end
  end
  return list
end

describe("The types caught track", function()
  it("has steps at 10, 20, 30, 40 and every type", function()
    local Goals = load().Goals
    assert.same({ 10, 20, 30, 40, 46 }, Goals.rungs("catches", 46, 60))
    assert.equal(46, Goals.nextRung("catches", 40, 60))
    assert.is_nil(Goals.nextRung("catches", 46, 60))
  end)

  it("shows on the Goals tab, counting types towards the next step", function()
    local net, clients, ns = crew({ "Ana", "Bob" })
    catchTypes(net, clients[1], ns, 3)
    local r = row(clients[2])
    assert.equal("Types of fish caught", r.title)
    assert.equal(3, r.value)
    assert.equal(10, r.goal)
  end)

  it("counts a type once, whoever caught it, and never Extras or unlisted catches", function()
    local net, clients, ns = crew({ "Ana", "Bob" })
    catchTypes(net, clients[1], ns, 2)
    clients[2].core:caught(catch(SMALLFISH, SUMMER_BASS, TASTYFISH, SHOE))
    clients[2]:play({ level = 12 })
    net:run(5)
    assert.equal(2, row(clients[1]).value)
  end)

  it("makes one gold goal entry, a Live event and a trophy on reaching a step", function()
    local net, clients, ns = crew({ "Ana", "Bob" })
    catchTypes(net, clients[1], ns, 10)
    for _, client in ipairs(clients) do
      assert.same({ "The Crew has caught 10 types of fish" }, texts(client, "goal"))
      assert.is_true(entries(client, "goal")[1].highlight)
      assert.equal(1, #live(client, "goal"))
    end
    local trophies = shelf(clients[2])
    assert.equal(1, #trophies)
    assert.equal("10 types", trophies[1].label)
    assert.equal("uncommon", trophies[1].quality)
    assert.is_true(trophies[1].fresh)
  end)

  it("makes one entry for the highest step when several are crossed", function()
    local net, clients, ns = crew({ "Ana", "Bob" })
    catchTypes(net, clients[1], ns, 25)
    assert.same({ "The Crew has caught 20 types of fish" }, texts(clients[2], "goal"))
    assert.equal(2, #shelf(clients[2]))
  end)

  it("words the last step as every type, and is then complete", function()
    local net, clients, ns = crew({ "Ana", "Bob" })
    local all = {}
    for _, t in ipairs(ns.Catches.TYPES) do
      if not t.extra then all[#all + 1] = t.itemId end
    end
    clients[1].core:caught(catch(unpack(all)))
    clients[1]:play({ level = 12 })
    net:run(5)
    assert.same({ "The Crew has caught every type of fish" }, texts(clients[2], "goal"))
    assert.is_true(row(clients[2]).complete)
    assert.equal("Every type", shelf(clients[2])[1].label)
  end)

  it("shows a step reached while you were away under Crew goals", function()
    local net, clients, ns = crew({ "Ana", "Bob" })
    clients[2]:logout()
    net:run(5)
    catchTypes(net, clients[1], ns, 10)
    clients[2].events = {}
    clients[2]:login()
    net:run(40)
    local summary
    for _, event in ipairs(clients[2].events) do
      if event[1] == "awaySummary" then summary = event[2] end
    end
    assert.equal("The Crew has caught 10 types of fish", summary.goals[1].text)
  end)

  describe("the silent baseline", function()
    it("keeps catches already in the Crew quiet when you join", function()
      local ns = load()
      local net = ns.FakeNet.new()
      local ana = net:add("Ana"):login()
      local code = ana:join()
      net:run(40)
      catchTypes(net, ana, ns, 12)
      local bob = net:add("Bob"):login()
      bob:join(code)
      net:run(40)
      assert.same({}, texts(bob, "goal"))
      local trophies = shelf(bob)
      assert.equal(1, #trophies)
      assert.is_false(trophies[1].fresh)
    end)

    -- A client whose baseline was taken before the track shipped.
    local function beforeTheTrack(client)
      client.db.goals.reached.catches = nil
      client.db.goals.quiet.catches = nil
    end

    it("keeps a Crew's catches quiet when the track ships, even ones that arrive in the first sync", function()
      local net, clients, ns = crew({ "Ana", "Bob" })
      catchTypes(net, clients[1], ns, 12)
      local bob = clients[2]
      bob:logout()
      net:run(5)
      catchTypes(net, clients[1], ns, 22)
      beforeTheTrack(bob)
      bob.db.feed = {}
      bob:login()
      net:run(40)
      assert.same({}, texts(bob, "goal"))
      local trophies = shelf(bob)
      assert.equal(2, #trophies)
      assert.is_false(trophies[1].fresh)
    end)

    it("still takes it when a reload comes before sync settles", function()
      local net, clients, ns = crew({ "Ana", "Bob" })
      catchTypes(net, clients[1], ns, 12)
      local bob = clients[2]
      bob:logout()
      beforeTheTrack(bob)
      bob.db.feed = {}
      bob:login()
      bob:reload()
      net:run(40)
      assert.same({}, texts(bob, "goal"))
      assert.equal(1, #shelf(bob))
    end)

    it("makes steps after it news", function()
      local net, clients, ns = crew({ "Ana", "Bob" })
      catchTypes(net, clients[1], ns, 12)
      local bob = clients[2]
      bob:logout()
      beforeTheTrack(bob)
      bob.db.feed = {}
      bob:login()
      net:run(40)
      catchTypes(net, clients[1], ns, 20)
      assert.same({ "The Crew has caught 20 types of fish" }, texts(bob, "goal"))
    end)
  end)
end)

-- Catches something and sends it now, as a level does.
local function send(net, client, ...)
  client.core:caught(catch(...))
  client:play({ level = client.character.level + 1 })
  net:run(5)
end

local function summaryOf(client)
  for _, event in ipairs(client.events) do
    if event[1] == "awaySummary" then return event[2] end
  end
end

describe("Rare finds", function()
  it("makes a Cheer-able Feed entry and a Live event for the Crew's first Nat Pagle fish", function()
    local net, clients = crew({ "Ana", "Bob" })
    send(net, clients[1], AHI)
    local entry = entries(clients[2], "rareFind")[1]
    assert.equal("Ana caught Feralas Ahi", entry.text)
    assert.is_true(entry.canReact)
    assert.equal("cheer", entry.reaction)
    assert.is_false(entry.highlight)
    assert.equal(1, #live(clients[2], "rareFind"))
  end)

  it("does the same for a contest fish, though it never counts", function()
    local net, clients = crew({ "Ana", "Bob" })
    send(net, clients[1], TASTYFISH)
    assert.same({ "Ana caught Speckled Tastyfish" }, texts(clients[2], "rareFind"))
    assert.equal(0, row(clients[2]).value)
  end)

  it("words your own, and makes no Live event of it", function()
    local net, clients = crew({ "Ana", "Bob" })
    send(net, clients[1], AHI)
    local entry = entries(clients[1], "rareFind")[1]
    assert.equal("You caught Feralas Ahi", entry.text)
    assert.is_false(entry.canReact)
    assert.equal(0, #live(clients[1], "rareFind"))
  end)

  it("goes out at once, without waiting for the next send", function()
    local net, clients = crew({ "Ana", "Bob" })
    clients[1].core:caught(catch(AHI))
    net:run(5)
    assert.same({ "Ana caught Feralas Ahi" }, texts(clients[2], "rareFind"))
  end)

  it("names an Alt as the Feed does", function()
    local net, clients = crew({ "Ana", "Bob" })
    clients[1].core:setMain("Player-0-Ana")
    clients[1]:play({ guid = "Player-0-Alt", name = "Jaina", level = 5 })
    clients[1].core:caught(catch(AHI))
    net:run(5)
    assert.same({ "Ana's Alt Jaina caught Feralas Ahi" }, texts(clients[2], "rareFind"))
  end)

  it("takes the item's name, colour, icon and edge from the game when it's cached", function()
    local edge = { 0.12, 1, 0 }
    local net, clients = crew({ "Ana", "Bob" }, {
      looks = { [AHI] = { text = "|cff1eff00Feralas Ahi|r", icon = 133890, edge = edge } },
    })
    send(net, clients[1], AHI)
    local entry = entries(clients[2], "rareFind")[1]
    assert.equal("Ana caught |cff1eff00Feralas Ahi|r", entry.text)
    assert.equal(133890, entry.icon)
    assert.same(edge, entry.edge)
  end)

  it("reaches the catcher as a Cheer, however many clients made the entry", function()
    local net, clients = crew({ "Ana", "Bob" })
    send(net, clients[1], AHI)
    local entry = entries(clients[2], "rareFind")[1]
    assert.is_truthy(clients[2].core:react(entry.key))
    clients[2]:play({ level = 12 })
    net:run(5)
    local news
    for _, event in ipairs(clients[1].events) do
      if event[1] == "reaction" then news = event[2] end
    end
    assert.equal("Bob cheered your Feralas Ahi", news.text)
    assert.equal(1, #entries(clients[1], "rareFind")[1].reactors)
  end)

  it("is only the Crew's first: a second Member's catch is no news", function()
    local net, clients = crew({ "Ana", "Bob", "Cid" })
    send(net, clients[1], AHI)
    send(net, clients[2], AHI)
    for _, client in ipairs(clients) do assert.equal(1, #entries(client, "rareFind")) end
  end)

  it("makes no second entry for a catch of the same fish", function()
    local net, clients = crew({ "Ana", "Bob" })
    send(net, clients[1], AHI)
    send(net, clients[1], AHI)
    assert.equal(1, #entries(clients[2], "rareFind"))
    assert.equal(1, #entries(clients[1], "rareFind"))
  end)

  it("makes nothing of everyday first catches or unlisted catches", function()
    local net, clients = crew({ "Ana", "Bob" })
    send(net, clients[1], SMALLFISH, SHOE, SUMMER_BASS)
    for _, client in ipairs(clients) do
      for _, day in ipairs(client.core:feed().days) do
        for _, entry in ipairs(day.entries) do
          assert.is_nil(entry.text:find("caught"), entry.text)
        end
      end
    end
  end)

  it("keeps a Member's catches quiet on first sight", function()
    local ns = load()
    local net = ns.FakeNet.new()
    local ana = net:add("Ana"):login()
    local code = ana:join()
    net:run(40)
    send(net, ana, AHI)
    local bob = net:add("Bob"):login()
    bob:join(code)
    net:run(40)
    assert.same({}, texts(bob, "rareFind"))
  end)

  it("makes no own entry outside a Crew", function()
    local ns = load()
    local net = ns.FakeNet.new()
    local ana = net:add("Ana"):login()
    ana.core:caught(catch(AHI))
    assert.same({}, texts(ana, "rareFind"))
  end)
end)

describe("While you were away, for Catches", function()
  -- Bob away while Ana and Cid fish; Bob's next login's summary.
  local function away(fishing)
    local net, clients, ns = crew({ "Bob", "Ana", "Cid" })
    local bob = clients[1]
    bob:logout()
    net:run(5)
    fishing(net, clients[2], clients[3], ns)
    bob.events = {}
    bob:login()
    net:run(40)
    return summaryOf(bob), bob
  end

  it("counts others' new types, most first", function()
    local summary = away(function(net, ana, cid, ns)
      local ids = fish(ns, 4)
      send(net, cid, ids[1], ids[2], ids[3])
      send(net, ana, ids[4])
    end)
    assert.equal("4 new types caught (Cid 3, Ana 1)", summary.catches[1].text)
  end)

  it("words one type alone", function()
    local summary = away(function(net, ana) send(net, ana, SMALLFISH) end)
    assert.equal("1 new type caught (Ana 1)", summary.catches[1].text)
  end)

  it("shows with nothing else to show", function()
    local summary = away(function(net, ana)
      ana.core:caught(catch(SMALLFISH))
      net:run(310)
    end)
    assert.equal(1, #summary.catches)
  end)

  it("leaves out Extras and unlisted catches", function()
    local summary = away(function(net, ana) send(net, ana, SUMMER_BASS, SHOE) end)
    assert.is_nil(summary and summary.catches[1])
  end)

  it("leaves out types the Crew had before you logged out", function()
    local net, clients = crew({ "Bob", "Ana" })
    local bob, ana = clients[1], clients[2]
    send(net, ana, SMALLFISH)
    bob:logout()
    net:run(5)
    send(net, ana, SMALLFISH)
    bob.events = {}
    bob:login()
    net:run(40)
    local summary = summaryOf(bob)
    assert.is_nil(summary and summary.catches[1])
  end)

  it("never counts your own", function()
    local net, clients = crew({ "Bob", "Ana" })
    local bob, ana = clients[1], clients[2]
    bob:logout()
    net:run(5)
    net.clock = net.clock + 60
    send(net, ana, 6303)
    bob:login()
    bob.events = {}
    bob.core:caught(catch(SMALLFISH))
    net:run(40)
    assert.equal("1 new type caught (Ana 1)", summaryOf(bob).catches[1].text)
  end)

  it("gives a rare find you missed its own line, with a Cheer", function()
    local summary = away(function(net, ana) send(net, ana, TASTYFISH) end)
    local line = summary.catches[1]
    assert.equal("Ana caught Speckled Tastyfish", line.text)
    assert.is_truthy(line.cheer)
    assert.equal(1, #summary.catches)
  end)

  it("lists a rare find under the count when it's a counted type", function()
    local summary = away(function(net, ana) send(net, ana, AHI, SMALLFISH) end)
    assert.equal("2 new types caught (Ana 2)", summary.catches[1].text)
    assert.equal("Ana caught Feralas Ahi", summary.catches[2].text)
  end)

  it("shows nothing on a first login ever, with no logout to count from", function()
    local ns = load()
    local net = ns.FakeNet.new()
    local ana = net:add("Ana"):login()
    local code = ana:join()
    net:run(40)
    send(net, ana, SMALLFISH)
    local db = {}
    local bob = net:add("Bob", { db = db }):login()
    bob:join(code)
    net:run(40)
    assert.is_nil(summaryOf(bob))
  end)
end)
