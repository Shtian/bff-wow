local load = require("tests.load")
local beforeRulesets = require("tests.before_rulesets")

local NORMAL = { realmName = "", recordId = 15, faction = "Alliance", serverId = "6939", name = "Normal" }
local NORMAL_HORDE = { realmName = "", recordId = 15, faction = "Horde", serverId = "6939", name = "Normal" }
local PVP = { realmName = "", recordId = 14, faction = "Alliance", serverId = "6856", name = "PvP" }
local OUTLAND = { realmName = "Outland", recordId = 8, faction = "Alliance", serverId = "6939" }
local OUTLAND_HORDE = { realmName = "Outland", recordId = 8, faction = "Horde", serverId = "6939" }
local RP = { realmName = "", recordId = 16, faction = "Alliance", serverId = "6944", name = "Roleplay" }

local function character(serverId, name)
  return {
    guid = ("Player-%s-%s"):format(serverId, name), name = name, classFilename = "WARRIOR",
    level = 10, xp = 0, maxXp = 1000, zone = "Elwynn Forest", deaths = 0,
  }
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

local SEPARATE = "BFF keeps a separate Crew for each Ruleset and faction."
local ASK = SEPARATE .. " It can't tell which one your Crew from before belongs to. Is this where your Crew is?"

local function hint(where)
  return ("%s Yours is on %s: log in a Character there to see it, or start a new Crew on this Ruleset, or join one.")
    :format(SEPARATE, where)
end
local DAY = 24 * 60 * 60

describe("A Crew saved before Rulesets", function()
  local ns, net

  before_each(function()
    ns = load()
    net = ns.FakeNet.new({ channels = true })
  end)

  local function savedCrew(options)
    options = options or {}
    local OldCore = beforeRulesets()
    local ann = net:add("Ann", { Core = OldCore, character = character("6939", "Ann") }):login()
    local code = ann:join()
    local bob
    if not options.alone then
      bob = net:add("Bob", { Core = OldCore, character = character(options.bobServer or "6939", "Bob") }):login()
      bob:join(code)
    end
    for _, extra in ipairs(options.alts or {}) do ann.core:updateOwn(extra) end
    if options.main then assert(ann.core:setMain(options.main)) end
    if options.paused then ann.core:setPaused(true) end
    ann.core:updateOwn(character("6939", "Ann"))
    net:run(30)
    ann:logout()
    ann.Core = nil
    if bob and options.bobOffline then bob:logout() end
    return ann, bob, code, ann.memberId
  end

  local function unplaceable()
    local ann, _, code, annId = savedCrew({ alone = true })
    net.clock = net.clock + 31 * DAY
    return ann, code, annId
  end

  local function downgrade(client)
    if client.core then client:logout() end
    client.Core = beforeRulesets()
    return client:login()
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

    it("tells an alt on another Ruleset where the Crew is without asking, and names its Ruleset later", function()
      local ann, _, code = savedCrew({ bobOffline = true })
      on(ann, PVP, character("6856", "Pvpann"))
      assert.is_nil(ann.core:crew())
      assert.same({ hint = hint("Ann's Ruleset") }, ann.core:elsewhere())
      on(ann, NORMAL, character("6939", "Ann"))
      assert.equal(code, ann.core:crew().code)
      on(ann, PVP, character("6856", "Pvpann"))
      assert.is_nil(ann.core:crew())
      assert.same({ hint = hint("Normal (Alliance)") }, ann.core:elsewhere())
    end)

    it("names the realm and says realm where the game has realms", function()
      local ann = savedCrew({ bobOffline = true })
      on(ann, OUTLAND, character("6939", "Ann"))
      on(ann, OUTLAND_HORDE, character("6939", "Hordeann"))
      assert.same({
        hint = "BFF keeps a separate Crew for each realm and faction. "
          .. "Yours is on Outland (Alliance): log in a Character there to see it, "
          .. "or start a new Crew on this realm, or join one.",
        offer = "Your Crew on Outland (Alliance) hasn't heard from anyone yet. "
          .. "If your friends play this faction, bring it here.",
      }, ann.core:elsewhere())
    end)

    it("isn't placed by your own alt on another Ruleset", function()
      local ann = savedCrew({ bobOffline = true, alts = { character("6944", "Rpann") } })
      on(ann, RP, character("6944", "Rpann"))
      assert.is_nil(ann.core:crew())
      assert.same({ hint = hint("Ann's Ruleset") }, ann.core:elsewhere())
    end)

    it("goes where your Main is when you're alone in the Crew", function()
      local ann, _, code = savedCrew({ alone = true, alts = { character("6856", "Pvpann") },
        main = "Player-6939-Ann" })
      on(ann, PVP, character("6856", "Pvpann"))
      assert.is_nil(ann.core:crew())
      assert.same({ hint = hint("Ann's Ruleset") }, ann.core:elsewhere())
      on(ann, NORMAL, character("6939", "Second"))
      assert.equal(code, ann.core:crew().code)
      assert.is_true(ann.core:ruleset().provisional)
    end)

    it("asks where it is when friends play only where you have no Characters", function()
      local ann, _, code = savedCrew({ bobOffline = true, bobServer = "0" })
      on(ann, NORMAL, character("6939", "Ann"))
      assert.is_nil(ann.core:crew())
      assert.same({ ask = ASK }, ann.core:elsewhere())
      assert.equal(code, ann.core:placeCrewHere().code)
    end)

    it("asks where it is when neither friends nor a Main place it", function()
      local ann = unplaceable()
      on(ann, PVP, character("6856", "Pvpann"))
      assert.is_nil(ann.core:crew())
      assert.same({ ask = ASK }, ann.core:elsewhere())
    end)

    it("is offered on the other faction while provisional, and not once a Member is heard", function()
      local ann, bob = savedCrew({ bobOffline = true })
      on(ann, NORMAL_HORDE, character("6939", "Hordeann"))
      assert.is_true(ann.core:ruleset().provisional)
      on(ann, NORMAL, character("6939", "Ann"))
      assert.is_nil(ann.core:crew())
      assert.equal("Your Crew on Normal (Horde) hasn't heard from anyone yet. If your friends play this faction, "
        .. "bring it here.", ann.core:elsewhere().offer)
      on(ann, NORMAL_HORDE, character("6939", "Hordeann"))
      bob:login()
      net:run(30)
      assert.is_false(ann.core:ruleset().provisional)
      on(ann, NORMAL, character("6939", "Ann"))
      assert.is_nil(ann.core:elsewhere().offer)
    end)

    it("runs once and leaves the old saved Crew for an older BFF", function()
      local ann, bob, code = savedCrew()
      on(ann, NORMAL, character("6939", "Ann"))
      ann:play({ level = 12 })
      net:run(30)
      assert.equal(12, bob:rowFor(ann).level)
      on(ann, PVP, character("6856", "Pvpann"))
      assert.same({ hint = hint("Normal (Alliance)") }, ann.core:elsewhere())
      downgrade(ann)
      assert.equal(code, ann.core:crew().code)
    end)

    it("carries Appear offline with the Crew", function()
      local ann = savedCrew({ bobOffline = true, paused = true })
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

    it("writes the placing and its confirmation to the sync log", function()
      local ann, bob = savedCrew({ bobOffline = true })
      on(ann, NORMAL, character("6939", "Ann"))
      local lines = {}
      ann.core:setTrace(function(line)
        if line:match("^ruleset") then lines[#lines + 1] = line end
      end)
      bob:login()
      net:run(30)
      assert.same({
        "ruleset mode:15:Alliance placed the Crew saved before Rulesets here (provisional)",
        "ruleset mode:15:Alliance confirmed by a Member",
      }, lines)
    end)

    it("leaves a Crew you had left behind to an older BFF", function()
      local ann, bob, code = savedCrew()
      bob:logout()
      downgrade(ann)
      ann.core:leaveCrew()
      net:run(30)
      ann:logout()
      ann.Core = nil
      on(ann, NORMAL, character("6939", "Ann"))
      assert.is_nil(ann.core:crew())
      assert.same({}, ann.core:elsewhere())
      downgrade(ann)
      assert(ann.core:joinCrew(code, "Ann"))
      assert.truthy(ann:rowFor(bob))
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
      assert.equal(hint("Ann's Ruleset (Alliance)"), ann.core:elsewhere().hint)
    end)

    it("names every Ruleset where you have a Crew", function()
      local ann = savedCrew({ bobOffline = true })
      on(ann, NORMAL, character("6939", "Ann"))
      on(ann, PVP, character("6856", "Pvpann"))
      assert(ann.core:startCrew("Ann"))
      on(ann, RP, character("6944", "Rpann"))
      assert.equal(SEPARATE .. " Yours are on PvP (Alliance) and Normal (Alliance): log in a Character there to see them,"
        .. " or start a new Crew on this Ruleset, or join one.", ann.core:elsewhere().hint)
    end)

    it("says nothing when you have no Crew anywhere else", function()
      local ann = on(net:add("Ann", { character = character("6856", "Pvpann") }), PVP)
      assert.same({}, ann.core:elsewhere())
    end)

    it("asks once, and placing it here brings the Crew with your Member id", function()
      local ann, code, annId = unplaceable()
      on(ann, PVP, character("6856", "Pvpann"))
      local before = crewChanges(ann)
      assert.equal(code, ann.core:placeCrewHere().code)
      ann:noteMemberId()
      assert.equal(before + 1, crewChanges(ann))
      assert.same({}, ann.core:elsewhere())
      assert.is_false(ann.core:ruleset().provisional)
      assert.equal(annId, ownRow(ann).memberId)
      assert.same({ "Player-6856-Pvpann" }, guidsIn(ownRow(ann)))
      on(ann, PVP, character("6856", "Pvpann"))
      assert.equal(code, ann.core:crew().code)
      on(ann, NORMAL, character("6939", "Ann"))
      assert.is_nil(ann.core:crew())
      assert.same({ hint = hint("PvP (Alliance)") }, ann.core:elsewhere())
    end)

    it("remembers a start fresh, and still asks on another Ruleset", function()
      local ann, code = unplaceable()
      on(ann, PVP, character("6856", "Pvpann"))
      local before = crewChanges(ann)
      assert.is_true(ann.core:startFresh())
      assert.equal(before + 1, crewChanges(ann))
      assert.same({}, ann.core:elsewhere())
      on(ann, PVP, character("6856", "Pvpann"))
      assert.same({}, ann.core:elsewhere())
      local fresh = assert(ann.core:startCrew("Ann"))
      assert.are_not.equal(code, fresh.code)
      on(ann, NORMAL, character("6939", "Ann"))
      assert.equal(ASK, ann.core:elsewhere().ask)
      assert.equal(code, ann.core:placeCrewHere().code)
    end)

    it("won't place or start fresh in a Crew, or with nothing to ask about", function()
      local ann = savedCrew({ bobOffline = true })
      on(ann, PVP, character("6856", "Pvpann"))
      assert.same({ nil, "notWaiting" }, { ann.core:placeCrewHere() })
      assert.same({ nil, "notWaiting" }, { ann.core:startFresh() })
      on(ann, NORMAL, character("6939", "Ann"))
      assert.same({ nil, "inCrew" }, { ann.core:placeCrewHere() })
      assert.same({ nil, "inCrew" }, { ann.core:startFresh() })
      on(ann, PVP, character("6856", "Pvpann"))
      assert.same({ nil, "notWaiting" }, { ann.core:placeCrewHere() })
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
      assert.same({}, ann.core:elsewhere())
      bob:login()
      ann:play({ level = 13 })
      net:run(30)
      assert.equal(13, bob:rowFor(ann).level)
      on(ann, NORMAL_HORDE, character("6939", "Hordeann"))
      assert.is_nil(ann.core:crew())
      assert.same({ hint = hint("Normal (Alliance)") }, ann.core:elsewhere())
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
      local ann = unplaceable()
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
      ann.core:placeCrewHere()
      assert.same({
        "ruleset mode:14:Alliance started fresh, leaving the Crew saved before Rulesets",
        "ruleset mode:16:Alliance placed the Crew saved before Rulesets here (asked)",
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
    it("drops other Rulesets' Characters when it's placed, for your friends on an older BFF too", function()
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
    it("syncs a client on BFF 2.18.0 and a moved one with the same Member ids", function()
      local ann, bob, _, annId = savedCrew()
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
