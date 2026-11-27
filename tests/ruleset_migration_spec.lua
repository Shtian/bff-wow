local load = require("tests.load")

local NORMAL = { realmName = "", recordId = 15, faction = "Alliance", serverId = "6939", name = "Normal" }
local NORMAL_HORDE = { realmName = "", recordId = 15, faction = "Horde", serverId = "6939", name = "Normal" }
local PVP = { realmName = "", recordId = 14, faction = "Alliance", serverId = "6856", name = "PvP" }
local RP = { realmName = "", recordId = 16, faction = "Alliance", serverId = "6944", name = "Roleplay" }

local function character(serverId, name)
  return {
    guid = ("Player-%s-%s"):format(serverId, name), name = name, classFilename = "WARRIOR",
    level = 10, xp = 0, maxXp = 1000, zone = "Elwynn Forest", deaths = 0,
  }
end

local function copy(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for k, v in pairs(value) do result[k] = copy(v) end
  return result
end

local function on(client, facts, played)
  if client.core then client:logout() end
  client.ruleset = facts
  if played then client.character = played end
  return client:login()
end

local function guidsIn(row)
  local guids = {}
  if not row then return guids end
  guids[#guids + 1] = row.guid
  for _, alt in ipairs(row.alts) do guids[#guids + 1] = alt.guid end
  table.sort(guids)
  return guids
end

local function ownRow(client)
  for _, row in ipairs(client.core:rows()) do
    if row.own then return row end
  end
  return nil
end

local function memberIds(client)
  local ids = {}
  for _, row in ipairs(client.core:rows()) do ids[#ids + 1] = row.memberId end
  table.sort(ids)
  return ids
end

local function sorted(list)
  table.sort(list)
  return list
end

describe("A Crew saved before Rulesets", function()
  local ns, net

  before_each(function()
    ns = load()
    net = ns.FakeNet.new({ channels = true })
  end)

  local SLOT_ONLY = { ruleset = true, provisional = true }
  local LAYOUT = { crews = true, rulesets = true, migrated = true }

  local function toOldLayout(client)
    if client.core then client:logout() end
    local slot = ns.Slots.find(client.db, nil)
    local old = {}
    for k, v in pairs(client.db) do
      if not LAYOUT[k] then old[k] = copy(v) end
    end
    for k, v in pairs(slot) do
      if not SLOT_ONLY[k] then old[k] = copy(v) end
    end
    client.db = old
    client.saved = copy(old)
    return client
  end

  local function savedCrew(options)
    options = options or {}
    local ann = net:add("Ann", { character = character("6939", "Ann") }):login()
    local code = ann:join()
    local bob
    if not options.alone then
      bob = net:add("Bob", { character = character("6939", "Bob"), gossip = options.bobGossip }):login()
      bob:join(code)
    end
    for _, extra in ipairs(options.alts or {}) do ann.core:updateOwn(extra) end
    if options.main then assert(ann.core:setMain(options.main)) end
    ann.core:updateOwn(character("6939", "Ann"))
    net:run(30)
    local annId = ann.memberId
    toOldLayout(ann)
    if bob and options.bobOffline then bob:logout() end
    return ann, bob, code, annId
  end

  describe("its move", function()
    it("lands where a friend's Characters are, provisional until a Member is heard", function()
      local ann, bob, code, annId = savedCrew({ bobOffline = true })
      on(ann, NORMAL, character("6939", "Ann"))
      assert.equal(code, ann.core:crew().code)
      assert.equal(annId, ann.memberId)
      assert.is_true(ann.core:ruleset().provisional)
      net:run(30)
      assert.is_true(ann.core:ruleset().provisional)
      bob:login()
      net:run(30)
      assert.is_false(ann.core:ruleset().provisional)
    end)

    it("waits when an alt on another Ruleset logs in first, and says where it went later", function()
      local ann, _, code = savedCrew({ bobOffline = true })
      on(ann, PVP, character("6856", "Pvpann"))
      assert.is_nil(ann.core:crew())
      assert.is_true(ann.core:elsewhere().ask)
      on(ann, NORMAL, character("6939", "Ann"))
      assert.equal(code, ann.core:crew().code)
      on(ann, PVP, character("6856", "Pvpann"))
      assert.is_nil(ann.core:crew())
      assert.same({
        crews = { {
          key = "mode:15:Alliance", name = "Normal", faction = "Alliance", character = "Ann",
          place = "Normal (Alliance)",
        } },
        hint = "Your Crew is on Normal (Alliance).",
      }, ann.core:elsewhere())
    end)

    it("isn't claimed by your own alt on another Ruleset", function()
      local ann = savedCrew({ bobOffline = true, alts = { character("6944", "Rpann") } })
      on(ann, RP, character("6944", "Rpann"))
      assert.is_nil(ann.core:crew())
      assert.is_true(ann.core:elsewhere().ask)
    end)

    it("goes where your Main is when you're alone in the Crew", function()
      local ann, _, code = savedCrew({ alone = true, alts = { character("6856", "Pvpann") },
        main = "Player-6939-Ann" })
      on(ann, PVP, character("6856", "Pvpann"))
      assert.is_nil(ann.core:crew())
      on(ann, NORMAL, character("6939", "Second"))
      assert.equal(code, ann.core:crew().code)
      assert.is_true(ann.core:ruleset().provisional)
    end)

    it("is offered on the other faction while provisional, and not once a Member is heard", function()
      local ann, bob = savedCrew({ bobOffline = true })
      on(ann, NORMAL_HORDE, character("6939", "Hordeann"))
      assert.is_true(ann.core:ruleset().provisional)
      on(ann, NORMAL, character("6939", "Ann"))
      assert.is_nil(ann.core:crew())
      assert.same({ key = "mode:15:Horde", name = "Normal", faction = "Horde", character = "Hordeann",
        place = "Normal (Horde)" }, ann.core:elsewhere().offer)
      on(ann, NORMAL_HORDE, character("6939", "Hordeann"))
      bob:login()
      net:run(30)
      assert.is_false(ann.core:ruleset().provisional)
      on(ann, NORMAL, character("6939", "Ann"))
      assert.is_nil(ann.core:elsewhere().offer)
    end)

    it("runs once and leaves the old saved Crew as it was", function()
      local ann, bob, code = savedCrew()
      local old = copy(ann.db)
      on(ann, NORMAL, character("6939", "Ann"))
      ann:play({ level = 12 })
      net:run(30)
      assert.equal(12, bob:rowFor(ann).level)
      on(ann, PVP, character("6856", "Pvpann"))
      assert.is_nil(ann.core:elsewhere().ask)
      for key, value in pairs(old) do assert.same(value, ann.db[key]) end
      assert.equal(code, ann.db.crew.code)
    end)

    it("carries Appear offline with the Crew", function()
      local ann = savedCrew({ bobOffline = true })
      ann.db.paused = true
      on(ann, NORMAL, character("6939", "Ann"))
      assert.is_true(ann.core:isPaused())
      on(ann, PVP, character("6856", "Pvpann"))
      assert.is_false(ann.core:isPaused())
    end)

    it("still counts as an existing install for What's new", function()
      local ann = savedCrew({ bobOffline = true })
      ann.version = "v2.3.0"
      ann.changelog = "## 2.3.0\n<sub>2026-11-10</sub>\n\n- *(minor)* Something new.\n\n"
        .. "## 2.2.0\n<sub>2026-11-01</sub>\n\n- *(patch)* A fix.\n\n"
      on(ann, NORMAL, character("6939", "Ann"))
      assert.is_true(ann.core:hasNewChanges())
    end)

    it("stays one Crew for the whole account when the game gives no facts", function()
      local ann, _, code = savedCrew({ bobOffline = true, alts = { character("6856", "Pvpann") } })
      on(ann, nil, character("6939", "Ann"))
      assert.equal(code, ann.core:crew().code)
      assert.is_false(ann.core:ruleset().provisional)
      assert.same({ "Player-6856-Pvpann", "Player-6939-Ann" }, guidsIn(ownRow(ann)))
    end)

    it("writes the claim and its confirmation to the sync log", function()
      local ann, bob = savedCrew({ bobOffline = true })
      on(ann, NORMAL, character("6939", "Ann"))
      local lines = {}
      ann.core:setTrace(function(line)
        if line:match("^ruleset") then lines[#lines + 1] = line end
      end)
      bob:login()
      net:run(30)
      assert.same({
        "ruleset mode:15:Alliance took the Crew saved before Rulesets (provisional)",
        "ruleset mode:15:Alliance confirmed by a Member",
      }, lines)
    end)

    it("leaves a Crew you had left behind", function()
      local ann = net:add("Ann", { character = character("6939", "Ann"), db = {
        memberId = "oldannid",
        records = {},
        keptCrew = { code = "K3F9-A2QX", generation = 2, ledger = { records = {} }, feed = {}, goals = {} },
      } })
      on(ann, NORMAL)
      assert.is_nil(ann.core:crew())
      assert.is_nil(ann.core:elsewhere().ask)
      assert.equal("K3F9-A2QX", ann.db.keptCrew.code)
    end)
  end)

  describe("the no-Crew card", function()
    local function crewChanges(client)
      return client:count("crewChanged")
    end

    it("names a Character when the Ruleset's name isn't known", function()
      local ann = savedCrew({ bobOffline = true })
      on(ann, { realmName = "", recordId = 15, faction = "Alliance", serverId = "6939" }, character("6939", "Ann"))
      on(ann, PVP, character("6856", "Pvpann"))
      assert.equal("Your Crew is on Ann's Ruleset (Alliance).", ann.core:elsewhere().hint)
    end)

    it("names every Ruleset where you have a Crew", function()
      local ann = savedCrew({ bobOffline = true })
      on(ann, NORMAL, character("6939", "Ann"))
      on(ann, PVP, character("6856", "Pvpann"))
      assert(ann.core:startCrew("Ann"))
      on(ann, RP, character("6944", "Rpann"))
      assert.equal("Your Crews are on PvP (Alliance) and Normal (Alliance).", ann.core:elsewhere().hint)
    end)

    it("says nothing when you have no Crew anywhere else", function()
      local ann = on(net:add("Ann", { character = character("6856", "Pvpann") }), PVP)
      assert.same({ crews = {} }, ann.core:elsewhere())
    end)

    it("asks once, and claiming it here brings the Crew with your Member id", function()
      local ann, bob, code, annId = savedCrew({ bobOffline = true, alts = { character("6944", "Rpann") } })
      on(ann, PVP, character("6856", "Pvpann"))
      assert.is_true(ann.core:elsewhere().ask)
      local before = crewChanges(ann)
      assert.equal(code, ann.core:claimCrewHere().code)
      ann:noteMemberId()
      assert.equal(before + 1, crewChanges(ann))
      assert.is_nil(ann.core:elsewhere().ask)
      assert.is_false(ann.core:ruleset().provisional)
      assert.equal(annId, ownRow(ann).memberId)
      assert.same({ "Player-6856-Pvpann", "Player-6939-Ann" }, guidsIn(ownRow(ann)))
      bob:login()
      net:run(30)
      assert.same({ "Player-6856-Pvpann", "Player-6939-Ann" }, guidsIn(bob:rowFor(ann)))
      on(ann, PVP, character("6856", "Pvpann"))
      assert.equal(code, ann.core:crew().code)
      on(ann, NORMAL, character("6939", "Ann"))
      assert.is_nil(ann.core:crew())
      assert.equal("Your Crew is on PvP (Alliance).", ann.core:elsewhere().hint)
    end)

    it("remembers a start fresh and leaves the Crew for the Ruleset where it belongs", function()
      local ann, _, code = savedCrew({ bobOffline = true })
      on(ann, PVP, character("6856", "Pvpann"))
      local before = crewChanges(ann)
      assert.is_true(ann.core:startFresh())
      assert.equal(before + 1, crewChanges(ann))
      assert.is_nil(ann.core:elsewhere().ask)
      on(ann, PVP, character("6856", "Pvpann"))
      assert.is_nil(ann.core:elsewhere().ask)
      local fresh = assert(ann.core:startCrew("Ann"))
      assert.are_not.equal(code, fresh.code)
      on(ann, NORMAL, character("6939", "Ann"))
      assert.equal(code, ann.core:crew().code)
    end)

    it("still asks on another Ruleset after a start fresh", function()
      local ann = savedCrew({ bobOffline = true })
      on(ann, PVP, character("6856", "Pvpann"))
      ann.core:startFresh()
      on(ann, RP, character("6944", "Rpann"))
      assert.is_true(ann.core:elsewhere().ask)
    end)

    it("won't claim or start fresh with nothing waiting, or in a Crew", function()
      local ann = savedCrew({ bobOffline = true })
      on(ann, NORMAL, character("6939", "Ann"))
      assert.same({ nil, "inCrew" }, { ann.core:claimCrewHere() })
      assert.same({ nil, "inCrew" }, { ann.core:startFresh() })
      on(ann, PVP, character("6856", "Pvpann"))
      assert.same({ nil, "notWaiting" }, { ann.core:claimCrewHere() })
      assert.same({ nil, "notWaiting" }, { ann.core:startFresh() })
    end)

    it("brings a provisional Crew over from the other faction", function()
      local ann, bob, code, annId = savedCrew({ bobOffline = true })
      on(ann, NORMAL_HORDE, character("6939", "Hordeann"))
      on(ann, NORMAL, character("6939", "Ann"))
      local before = crewChanges(ann)
      assert.equal(code, ann.core:bringCrewHere().code)
      ann:noteMemberId()
      assert.equal(before + 1, crewChanges(ann))
      assert.equal(annId, ownRow(ann).memberId)
      assert.is_false(ann.core:ruleset().provisional)
      assert.same({ crews = {} }, ann.core:elsewhere())
      bob:login()
      ann:play({ level = 13 })
      net:run(30)
      assert.equal(13, bob:rowFor(ann).level)
      on(ann, NORMAL_HORDE, character("6939", "Hordeann"))
      assert.is_nil(ann.core:crew())
      local elsewhere = ann.core:elsewhere()
      assert.equal("Your Crew is on Normal (Alliance).", elsewhere.hint)
      assert.is_nil(elsewhere.offer)
    end)

    it("won't bring over a Crew that isn't on offer", function()
      local ann, bob = savedCrew({ bobOffline = true })
      on(ann, NORMAL_HORDE, character("6939", "Hordeann"))
      bob:login()
      net:run(30)
      on(ann, NORMAL, character("6939", "Ann"))
      assert.same({ nil, "notWaiting" }, { ann.core:bringCrewHere() })
      on(ann, NORMAL_HORDE, character("6939", "Hordeann"))
      assert.same({ nil, "inCrew" }, { ann.core:bringCrewHere() })
    end)

    it("writes the answers to the sync log", function()
      local ann = savedCrew({ bobOffline = true })
      on(ann, PVP, character("6856", "Pvpann"))
      local lines = {}
      ann.core:setTrace(function(line)
        if line:match("^ruleset") then lines[#lines + 1] = line end
      end)
      ann.core:startFresh()
      on(ann, RP, character("6944", "Rpann"))
      ann.core:setTrace(function(line)
        if line:match("^ruleset") then lines[#lines + 1] = line end
      end)
      ann.core:claimCrewHere()
      assert.same({
        "ruleset mode:14:Alliance started fresh, leaving the Crew saved before Rulesets",
        "ruleset mode:16:Alliance took the Crew saved before Rulesets (asked)",
      }, lines)
    end)

    it("refreshes the views when the Ruleset's name arrives", function()
      local ann = on(net:add("Ann", { character = character("6856", "Pvpann") }),
        { realmName = "", recordId = 14, faction = "Alliance", serverId = "6856" })
      local before = ann:count("changed")
      ann.core:rulesetNamed("PvP")
      assert.equal(before + 1, ann:count("changed"))
      ann.core:rulesetNamed("PvP")
      assert.equal(before + 1, ann:count("changed"))
    end)
  end)

  describe("pruning your Characters", function()
    it("drops other Rulesets' Characters on a claim, for your friends too", function()
      local ann, bob = savedCrew({ alts = { character("6856", "Pvpann") }, main = "Player-6856-Pvpann" })
      assert.same({ "Player-6856-Pvpann", "Player-6939-Ann" }, guidsIn(bob:rowFor(ann)))
      on(ann, NORMAL, character("6939", "Ann"))
      assert.same({ "Player-6939-Ann" }, guidsIn(ownRow(ann)))
      assert.is_false(ownRow(ann).mainSet)
      net:run(30)
      assert.same({ "Player-6939-Ann" }, guidsIn(bob:rowFor(ann)))
    end)

    it("keeps Characters on a friend's server", function()
      local ann = savedCrew({ bobOffline = true, alts = { character("6939", "Horde") } })
      on(ann, NORMAL, character("6939", "Ann"))
      assert.same({ "Player-6939-Ann", "Player-6939-Horde" }, guidsIn(ownRow(ann)))
    end)

    it("drops a Character from another Crew's view of you once you play it elsewhere", function()
      local ann = net:add("Ann", { ruleset = NORMAL, character = character("6939", "Ann") }):login()
      local bob = net:add("Bob", { ruleset = NORMAL, character = character("6939", "Bob") }):login()
      bob:join(ann:join())
      net:run(30)
      on(ann, NORMAL_HORDE, character("6939", "Ann"))
      on(ann, NORMAL, character("6939", "Second"))
      assert.same({ "Player-6939-Second" }, guidsIn(ownRow(ann)))
      net:run(30)
      assert.same({ "Player-6939-Second" }, guidsIn(bob:rowFor(ann)))
    end)

    it("drops it from a Crew you left too", function()
      local ann = net:add("Ann", { ruleset = NORMAL, character = character("6939", "Ann") }):login()
      local code = ann:join()
      ann.core:leaveCrew()
      on(ann, NORMAL_HORDE, character("6939", "Ann"))
      on(ann, NORMAL, character("6939", "Second"))
      ann:join(code)
      assert.same({ "Player-6939-Second" }, guidsIn(ownRow(ann)))
    end)
  end)

  describe("with Members on older and newer BFF", function()
    it("syncs an older client and a moved one with the same Member ids", function()
      local legacy = {}
      assert(loadfile("tests/fixtures/legacy_gossip.lua"))("BFF", legacy)
      local ann, bob, _, annId = savedCrew({ bobGossip = legacy.Gossip })
      local bobId = bob.memberId
      on(ann, NORMAL, character("6939", "Ann"))
      ann:play({ level = 14 })
      bob:play({ level = 15 })
      net:run(30)
      assert.equal(annId, ann.memberId)
      assert.same(sorted({ annId, bobId }), memberIds(ann))
      assert.same(sorted({ annId, bobId }), memberIds(bob))
      assert.equal(14, bob:rowFor(ann).level)
      assert.equal(15, ann:rowFor(bob).level)
    end)
  end)
end)
