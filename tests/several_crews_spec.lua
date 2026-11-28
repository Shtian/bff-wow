local load = require("tests.load")

local NORMAL = { realmName = "", recordId = 15, faction = "Alliance", serverId = "6939", name = "Normal" }
local PVP = { realmName = "", recordId = 14, faction = "Alliance", serverId = "6856", name = "PvP" }

local function character(name)
  return {
    guid = "Player-6939-" .. name, name = name, classFilename = "WARRIOR",
    level = 10, xp = 0, maxXp = 1000, zone = "Elwynn Forest", deaths = 0,
  }
end

local function as(client, name, facts)
  if client.core then client:logout() end
  client.character = character(name)
  client.ruleset = facts or NORMAL
  return client:login()
end

local function labels(list)
  local result = {}
  for i, row in ipairs(list) do result[i] = row.label end
  return result
end

local function keysOf(map)
  local keys = {}
  for key in pairs(map) do keys[#keys + 1] = key end
  table.sort(keys)
  return keys
end

local function idOf(client, label)
  for _, row in ipairs(client.core:crews().list) do
    if row.label == label then return row.id end
  end
  for _, row in ipairs(client.core:crews().left) do
    if row.label == label then return row.id end
  end
  error("no Crew " .. label)
end

describe("Several Crews on one Ruleset and faction", function()
  local ns, net, ann, bob, cat, codeA, codeB, annIds

  before_each(function()
    ns = load()
    net = ns.FakeNet.new({ channels = true })
    ann = net:add("Ann", { ruleset = NORMAL, character = character("Ann") }):login()
    bob = net:add("Bob", { ruleset = NORMAL, character = character("Bob") }):login()
    cat = net:add("Cat", { ruleset = NORMAL, character = character("Cat") }):login()
    codeA = ann:join()
    annIds = { ann.memberId }
    bob:join(codeA)
    net:run(20)
    assert(ann.core:startAnother())
    codeB = ann:join()
    annIds[2] = ann.memberId
    cat:join(codeB)
    net:run(20)
  end)

  local function annRow(client)
    for _, row in ipairs(client.core:rows()) do
      if row.memberId == annIds[1] or row.memberId == annIds[2] then return row end
    end
    return nil
  end

  local function annCharacters(client)
    local row = annRow(client)
    local played = {}
    if not row then return played end
    played[row.name] = row.lastSeen
    for _, alt in ipairs(row.alts) do played[alt.name] = alt.lastPlayed end
    return played
  end

  describe("with one Crew", function()
    it("shows the Crew menu in the header, with nothing else new", function()
      local net1 = ns.FakeNet.new({ channels = true })
      local dan = net1:add("Dan", { ruleset = NORMAL, character = character("Dan") }):login()
      dan:join()
      local crews = dan.core:crews()
      assert.is_true(crews.header)
      assert.is_nil(crews.alsoIn)
      assert.is_nil(crews.picker)
      assert.equal(1, #crews.list)
    end)

    it("is used by a new Character", function()
      local net1 = ns.FakeNet.new({ channels = true })
      local dan = net1:add("Dan", { ruleset = NORMAL, character = character("Dan") }):login()
      local code = dan:join()
      as(dan, "Danalt")
      assert.equal(code, dan.core:crew().code)
    end)
  end)

  describe("at login", function()
    it("keeps the Crew the Character played last", function()
      as(ann, "Ann")
      assert.equal(codeB, ann.core:crew().code)
    end)

    it("asks a new Character who it's playing with, and remembers the answer", function()
      as(ann, "Annalt")
      assert.is_nil(ann.core:crew())
      local crews = ann.core:crews()
      assert.equal("Who is Annalt playing with?", crews.picker)
      assert.same({ "Bob", "Cat" }, labels(crews.list))
      assert.equal(codeA, (ann.core:switchCrew(idOf(ann, "Bob"))).code)
      as(ann, "Annalt")
      assert.equal(codeA, ann.core:crew().code)
      as(ann, "Ann")
      assert.equal(codeB, ann.core:crew().code)
    end)

    it("names when each Crew was last played", function()
      net:run(3600)
      as(ann, "Annalt")
      local rows = ann.core:crews().list
      assert.equal("last played 1h ago", rows[1].lastPlayed)
      assert.equal("last played 1m ago", rows[2].lastPlayed)
    end)
  end)

  describe("switching", function()
    it("names the current Crew in the header", function()
      assert.is_true(ann.core:crews().header)
      assert.is_true(ann.core:crews().current.current)
      assert.equal("Cat", ann.core:crews().current.label)
    end)

    it("changes the channel and the panel, leaving the Crew it leaves untouched", function()
      local inB = annCharacters(cat)
      local inA = keysOf(annCharacters(bob))
      local channelB = ann.core:channel().channel
      ann:switchCrew(idOf(ann, "Bob"))
      net:run(20)
      assert.equal(codeA, ann.core:crew().code)
      assert.are_not.equal(channelB, ann.core:channel().channel)
      assert.truthy(ann:rowFor(bob))
      assert.is_nil(ann:rowFor(cat))
      assert.same(inA, keysOf(annCharacters(bob)))
      assert.same(inB, annCharacters(cat))
    end)

    it("shows you offline to the other Crew, not left", function()
      ann:switchCrew(idOf(ann, "Bob"))
      net:run(20)
      local row = annRow(cat)
      assert.truthy(row)
      assert.is_false(row.online)
    end)

    it("keeps the Character in every Crew it has played in", function()
      ann:switchCrew(idOf(ann, "Bob"))
      net:run(20)
      as(ann, "Ann")
      assert.equal(codeA, ann.core:crew().code)
      assert.truthy(annCharacters(cat).Ann)
      assert.truthy(annCharacters(bob).Ann)
    end)

    it("is refused during messaging lockdown, with the reason", function()
      ann:lockdown(true)
      local crews = ann.core:crews()
      assert.is_true(crews.locked)
      assert.equal("Can't switch Crew right now. The game blocks addon messages in combat and instances.",
        crews.lockedText)
      assert.same({ nil, "lockdown" }, { ann.core:switchCrew(idOf(ann, "Bob")) })
      assert.same({ nil, "lockdown" }, { ann.core:startAnother() })
      assert.same({ nil, "lockdown" }, { ann.core:startCrew("Ann") })
      assert.same({ nil, "lockdown" }, { ann.core:joinCrew(codeA, "Ann") })
      assert.equal(codeB, ann.core:crew().code)
      ann:lockdown(false)
      assert.is_nil(ann.core:crews().locked)
      assert.equal(codeA, (ann.core:switchCrew(idOf(ann, "Bob"))).code)
    end)

    it("waits for a pending leave to finish", function()
      ann:lockdown(true)
      ann.core:leaveCrew()
      assert.is_true(ann.core:crew().leaving)
      assert.equal("Can't switch Crew until your leave finishes.", ann.core:crews().lockedText)
      assert.same({ nil, "leaving" }, { ann.core:switchCrew(idOf(ann, "Bob")) })
      assert.same({ nil, "leaving" }, { ann.core:startAnother() })
      assert.same({ nil, "leaving" }, { ann.core:startCrew("Ann") })
      assert.same({ nil, "leaving" }, { ann.core:joinCrew(codeA, "Ann") })
    end)

    it("refuses a Crew that isn't yours here", function()
      assert.same({ nil, "unknownCrew" }, { ann.core:switchCrew("nope") })
    end)

    it("names your other Crews, and when they last synced", function()
      net:run(7200)
      assert.equal("Also in: Bob · last synced 2h ago", ann.core:crews().alsoIn)
    end)

    it("joins a Crew you're already in by switching to it", function()
      assert(ann.core:startAnother())
      assert.equal(codeA, (ann.core:joinCrew(codeA, "Ann")).code)
      assert.equal(2, #ann.core:crews().list)
    end)
  end)

  describe("its label", function()
    it("defaults to the other Members' names", function()
      local net1 = ns.FakeNet.new({ channels = true })
      local names = { "Dan", "eve", "Finn", "Gus" }
      local clients = {}
      for i, name in ipairs(names) do
        clients[i] = net1:add(name, { ruleset = NORMAL, character = character(name) }):login()
      end
      local code = clients[1]:join()
      for i = 2, #clients do clients[i]:join(code) end
      net1:run(30)
      assert.equal("eve, Finn +1", clients[1].core:crews().current.label)
    end)

    it("is renamed locally and cut short for the header", function()
      assert(ann.core:renameCrew("  The Thursday raid group  "))
      local current = ann.core:crews().current
      assert.equal("The Thursday raid group", current.label)
      assert.equal("The Thursday raid…", current.headerLabel)
      assert.is_true(current.renamed)
      net:run(20)
      assert.is_nil(cat.core:crews().current.label:find("Thursday"))
      assert(ann.core:renameCrew(""))
      assert.equal("Cat", ann.core:crews().current.label)
      assert.same({ nil, "invalidLabel" }, { ann.core:renameCrew(string.rep("x", 33)) })
    end)
  end)

  describe("starting or joining another", function()
    it("switches to the new Crew and keeps the one you were in", function()
      assert(ann.core:startAnother())
      assert.is_nil(ann.core:crew())
      assert.equal("Who is Ann playing with?", ann.core:crews().picker)
      local codeC = ann:join()
      assert.equal(codeC, ann.core:crew().code)
      local own = ann.core:rows()[1]
      assert.equal("Ann", own.displayName)
      assert.same({}, own.alts)
      assert.equal(3, #ann.core:crews().list)
      as(ann, "Ann")
      assert.equal(codeC, ann.core:crew().code)
    end)

    it("starts one straight from inside a Crew, keeping that Crew", function()
      local codeC = ann:join()
      assert.equal(codeC, ann.core:crew().code)
      assert.equal("Ann", ann.core:rows()[1].displayName)
      assert.equal(3, #ann.core:crews().list)
      net:run(20)
      assert.is_false(annRow(cat).online)
      assert.is_nil(annRow(cat).left)
    end)

    it("joins one straight from inside a Crew", function()
      local dan = net:add("Dan", { ruleset = NORMAL, character = character("Dan") }):login()
      local codeD = dan:join()
      ann:join(codeD)
      net:run(20)
      assert.equal(codeD, ann.core:crew().code)
      assert.same({ "Bob", "Cat", "Dan" }, labels(ann.core:crews().list))
    end)
  end)

  describe("leaving", function()
    it("keeps the Crew in Left Crews, and its Characters get the picker", function()
      ann.core:leaveCrew()
      net:run(5)
      assert.is_nil(ann.core:crew())
      local notices = {}
      for _, e in ipairs(ann.events) do
        if e[1] == "notice" then notices[#notices + 1] = e end
      end
      assert.same({ "notice", "leftCrew", { crew = "Cat" } }, notices[#notices])
      local crews = ann.core:crews()
      assert.same({ "Bob" }, labels(crews.list))
      assert.same({ "Cat" }, labels(crews.left))
      assert.equal("left 0m ago", crews.left[1].leftText)
      as(ann, "Ann")
      assert.is_nil(ann.core:crew())
      assert.equal("Who is Ann playing with?", ann.core:crews().picker)
    end)

    it("keeps several left Crews, and rejoins or deletes each", function()
      ann.core:leaveCrew()
      net:run(5)
      ann:switchCrew(idOf(ann, "Bob"))
      ann.core:leaveCrew()
      net:run(5)
      assert.same({ "Bob", "Cat" }, labels(ann.core:crews().left))
      assert.equal(codeB, (ann.core:rejoinCrew(idOf(ann, "Cat"))).code)
      ann:noteMemberId()
      net:run(20)
      assert.equal(annIds[2], ann.memberId)
      assert.truthy(ann:rowFor(cat))
      assert.truthy(annRow(cat))
      assert.same({ "Bob" }, labels(ann.core:crews().left))
      assert(ann.core:deleteLeftCrew(idOf(ann, "Bob")))
      assert.same({}, ann.core:crews().left)
      assert.same({ nil, "unknownCrew" }, { ann.core:deleteLeftCrew("nope") })
    end)

    it("rejoins a left Crew from inside another Crew", function()
      ann.core:leaveCrew()
      net:run(5)
      ann:switchCrew(idOf(ann, "Bob"))
      assert.equal(codeB, (ann.core:rejoinCrew(idOf(ann, "Cat"))).code)
      assert.same({ "Bob", "Cat" }, labels(ann.core:crews().list))
    end)
  end)

  describe("next to Crews on other Rulesets", function()
    it("drops a Character played on another Ruleset from every Crew here", function()
      as(ann, "Annrp")
      ann:switchCrew(idOf(ann, "Cat"))
      net:run(20)
      assert.truthy(annCharacters(cat).Annrp)
      as(ann, "Annrp", PVP)
      as(ann, "Ann")
      net:run(20)
      assert.is_nil(annCharacters(cat).Annrp)
      assert.truthy(annCharacters(cat).Ann)
    end)
  end)

  describe("the move from one Crew per Ruleset", function()
    local function oldLayout(db)
      for _, entry in pairs(db.rulesets) do
        entry.active = entry.crews[1] or entry.blank
        entry.left = entry.left[1]
        entry.crews, entry.lastUsed, entry.blank = nil, nil, nil
      end
    end

    it("keeps the active Crew, the left Crew and their Characters", function()
      local net1 = ns.FakeNet.new({ channels = true })
      local dan = net1:add("Dan", { ruleset = NORMAL, character = character("Dan") }):login()
      local eve = net1:add("Eve", { ruleset = NORMAL, character = character("Eve") }):login()
      local old = dan:join()
      eve:join(old)
      net1:run(20)
      dan.core:leaveCrew()
      net1:run(5)
      local code = dan:join()
      local id = dan.memberId
      as(dan, "Danalt")
      as(dan, "Dan")
      dan:logout()
      oldLayout(dan.db)
      dan:login()
      assert.equal(code, dan.core:crew().code)
      assert.equal(id, dan.memberId)
      local left = dan.core:crews().left
      assert.same({ "Eve" }, labels(left))
      assert(dan.core:startAnother())
      dan:join()
      as(dan, "Danalt")
      assert.equal(code, dan.core:crew().code)
      as(dan, "Dannew")
      assert.is_truthy(dan.core:crews().picker)
      assert.equal(old, (dan.core:rejoinCrew(left[1].id)).code)
    end)

    it("keeps a Ruleset with no Crew empty", function()
      local net1 = ns.FakeNet.new({ channels = true })
      local dan = net1:add("Dan", { ruleset = NORMAL, character = character("Dan") }):login()
      dan:logout()
      oldLayout(dan.db)
      dan:login()
      assert.is_nil(dan.core:crew())
      assert.same({}, dan.core:crews().list)
      assert.is_nil(dan.core:crews().picker)
    end)
  end)
end)
