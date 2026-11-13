local load = require("tests.load")

local DAY = 24 * 60 * 60

-- NPC IDs from the list (docs/research/rare-mobs.md).
local TIMBER = 1132
local RAKSHIRI = 10200
local BROKEN_TOOTH = 2850
local VOLCHAN = 10119
-- Classified rare by the game, but not on the list.
local BJARN = 1130

local function guid(npcId, spawn)
  return ("Creature-0-5250-0-27-%d-%s"):format(npcId, spawn or "00001A2B3C")
end

-- What a secret value is in these tests: any table marked so.
local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
local function isSecret(value) return value == SECRET end

-- A fake of the game's unit and loot API, as Snapshot hands it to the
-- watch. units maps a unit token to { guid, classification, dead,
-- tapDenied, name }; loot is a list of slots, each a list of source GUIDs.
local function fakeApi(state)
  state = state or {}
  state.units = state.units or {}
  local function unit(token) return state.units[token] or {} end
  return {
    unitGUID = function(token) return unit(token).guid end,
    unitName = function(token) return unit(token).name end,
    unitClassification = function(token) return unit(token).classification end,
    unitIsDead = function(token) return unit(token).dead end,
    unitIsTapDenied = function(token) return unit(token).tapDenied end,
    getNumLootItems = function() return state.loot and #state.loot or 0 end,
    getLootSourceInfo = function(slot)
      if state.lootError then error("restricted") end
      local sources = state.loot[slot]
      local values = {}
      for _, source in ipairs(sources) do
        values[#values + 1] = source
        values[#values + 1] = 1
      end
      return unpack(values)
    end,
    zone = function() return state.zone or "Winterspring" end,
    subzone = function() return state.subzone or "Frostfire Hot Springs" end,
    mapId = function() return state.mapId or 1452 end,
    isSecret = isSecret,
  }, state
end

describe("The Rares list", function()
  it("is keyed by NPC ID, with a name, zone and level, in level order", function()
    local ns = load()
    assert.is_true(#ns.Rares.LIST >= 29)
    assert.equal(#ns.Rares.LIST, ns.Rares.TOTAL)
    local seen, last = {}, 0
    for i, rare in ipairs(ns.Rares.LIST) do
      assert.is_number(rare.id)
      assert.is_nil(seen[rare.id], rare.name)
      seen[rare.id] = true
      assert.is_string(rare.name)
      assert.is_string(rare.zone)
      assert.is_number(rare.level)
      assert.is_true(rare.level >= last, rare.name)
      last = rare.level
      assert.equal(i, rare.index)
      assert.equal(rare, ns.Rares.byId(rare.id))
    end
    assert.equal("Rak'shiri", ns.Rares.byId(RAKSHIRI).name)
    assert.equal("Winterspring", ns.Rares.byId(RAKSHIRI).zone)
    assert.equal(57, ns.Rares.byId(RAKSHIRI).level)
    assert.is_true(ns.Rares.byId(VOLCHAN).elite)
    assert.is_falsy(ns.Rares.byId(RAKSHIRI).elite)
  end)

  it("has only mobs the game classifies as rare: no famous elites", function()
    local ns = load()
    -- Mor'Ladim, Gazz'uz, Mother Fang (Elite on Forever), Old Murk-Eye.
    for _, id in ipairs({ 522, 3204, 471, 391 }) do assert.is_nil(ns.Rares.byId(id)) end
  end)

  it("reads the NPC ID from a creature's GUID, obfuscated parts and all", function()
    local ns = load()
    assert.equal(RAKSHIRI, ns.Rares.npcId(guid(RAKSHIRI)))
    assert.equal(RAKSHIRI, ns.Rares.npcId("Creature-0-a1b2-0-27-10200-ffe0"))
    assert.equal(5828, ns.Rares.npcId("Vehicle-0-3783-1-11-5828-00004E0E3B"))
    assert.is_nil(ns.Rares.npcId("Player-1234-0ABCDEF0"))
    assert.is_nil(ns.Rares.npcId("GameObject-0-5250-0-27-180655-0000"))
    assert.is_nil(ns.Rares.npcId(nil))
    assert.is_nil(ns.Rares.npcId(SECRET))
  end)
end)

describe("The rare kill watch", function()
  describe("on loot", function()
    it("finds a listed rare among the loot's sources", function()
      local ns = load()
      local api = fakeApi({ loot = { { guid(RAKSHIRI) }, { guid(RAKSHIRI) } } })
      local kills, info = ns.Rares.watch(api):loot()
      assert.equal(1, #kills)
      assert.equal(RAKSHIRI, kills[1].npcId)
      assert.equal("loot", kills[1].signal)
      assert.equal("Winterspring", kills[1].zone)
      assert.equal("Frostfire Hot Springs", kills[1].subzone)
      assert.equal(1452, kills[1].mapId)
      assert.equal("loot", info.signal)
    end)

    it("finds every listed rare when several corpses are looted at once", function()
      local ns = load()
      local api = fakeApi({ loot = { { guid(RAKSHIRI), guid(TIMBER) }, { guid(4000) } } })
      local kills = ns.Rares.watch(api):loot()
      local ids = {}
      for i, kill in ipairs(kills) do ids[i] = kill.npcId end
      table.sort(ids)
      assert.same({ TIMBER, RAKSHIRI }, ids)
    end)

    it("ignores a mob that isn't a rare", function()
      local ns = load()
      local kills, info = ns.Rares.watch(fakeApi({ loot = { { guid(4000) } } })):loot()
      assert.same({}, kills)
      assert.equal("notRare", info.result)
    end)

    it("keeps an unlisted rare seen while readable as unlisted, with its name", function()
      local ns = load()
      local api, state = fakeApi({
        units = { mouseover = { guid = guid(BJARN), classification = "rare", name = "Bjarn" } },
      })
      local watch = ns.Rares.watch(api)
      watch:see("mouseover")
      state.loot = { { guid(BJARN) } }
      local kills = watch:loot()
      assert.equal(1, #kills)
      assert.equal(BJARN, kills[1].npcId)
      assert.equal("Bjarn", kills[1].name)
      assert.is_true(kills[1].unlisted)
    end)

    it("records nothing, and doesn't error, when a source reads secret", function()
      local ns = load()
      local kills, info = ns.Rares.watch(fakeApi({ loot = { { SECRET } } })):loot()
      assert.same({}, kills)
      assert.same({ "source" }, info.secret)
    end)

    it("records nothing, and doesn't error, when the loot count reads secret or a read errors", function()
      local ns = load()
      local api, state = fakeApi({ loot = { { guid(RAKSHIRI) } } })
      api.getNumLootItems = function() return SECRET end
      assert.same({}, (ns.Rares.watch(api):loot()))
      api = fakeApi({ loot = { { guid(RAKSHIRI) } }, lootError = true })
      local kills, info = ns.Rares.watch(api):loot()
      assert.same({}, kills)
      assert.equal("error", info.result)
      assert.truthy(state)
    end)

    it("leaves where out when it reads secret", function()
      local ns = load()
      local api = fakeApi({ loot = { { guid(RAKSHIRI) } }, zone = SECRET, mapId = SECRET })
      local kill = ns.Rares.watch(api):loot()[1]
      assert.equal(RAKSHIRI, kill.npcId)
      assert.is_nil(kill.zone)
      assert.is_nil(kill.mapId)
    end)
  end)

  describe("when the target dies", function()
    local function rakshiri(changes)
      local unit = { guid = guid(RAKSHIRI), classification = "rare", name = "Rak'shiri", dead = true, tapDenied = false }
      for k, v in pairs(changes or {}) do unit[k] = v end
      return unit
    end

    it("records a listed rare that's dead and was ours to kill", function()
      local ns = load()
      local api = fakeApi({ units = { target = rakshiri() } })
      local kill, info = ns.Rares.watch(api):targetDied()
      assert.equal(RAKSHIRI, kill.npcId)
      assert.equal("target", kill.signal)
      assert.equal("target", info.signal)
    end)

    it("knows a target seen while readable, once its GUID reads secret in combat", function()
      local ns = load()
      local api, state = fakeApi({ units = { target = rakshiri({ dead = false }) } })
      local watch = ns.Rares.watch(api)
      watch:see("target")
      state.units.target = rakshiri({ guid = SECRET })
      assert.equal(RAKSHIRI, watch:targetDied().npcId)
    end)

    it("forgets the target seen once a target is picked that can't be read", function()
      local ns = load()
      local api, state = fakeApi({ units = { target = rakshiri({ dead = false }) } })
      local watch = ns.Rares.watch(api)
      watch:see("target")
      state.units.target = { guid = SECRET, dead = false }
      watch:see("target")
      state.units.target = rakshiri({ guid = SECRET })
      local kill, info = watch:targetDied()
      assert.is_nil(kill)
      assert.equal("unknown", info.result)
    end)

    it("records nothing for a rare tagged by someone outside the group", function()
      local ns = load()
      local kill, info = ns.Rares.watch(fakeApi({ units = { target = rakshiri({ tapDenied = true }) } })):targetDied()
      assert.is_nil(kill)
      assert.equal("tapDenied", info.result)
    end)

    it("records nothing for a rare still alive", function()
      local ns = load()
      local kill, info = ns.Rares.watch(fakeApi({ units = { target = rakshiri({ dead = false }) } })):targetDied()
      assert.is_nil(kill)
      assert.equal("alive", info.result)
    end)

    it("records nothing when dead or tapped reads secret", function()
      local ns = load()
      assert.is_nil((ns.Rares.watch(fakeApi({ units = { target = rakshiri({ dead = SECRET }) } })):targetDied()))
      assert.is_nil((ns.Rares.watch(fakeApi({ units = { target = rakshiri({ tapDenied = SECRET }) } })):targetDied()))
    end)

    it("keeps an unlisted rare the game classifies as rare, with its name", function()
      local ns = load()
      local unit = { guid = guid(BJARN), classification = "rareelite", name = "Bjarn", dead = true, tapDenied = false }
      local kill = ns.Rares.watch(fakeApi({ units = { target = unit } })):targetDied()
      assert.equal(BJARN, kill.npcId)
      assert.equal("Bjarn", kill.name)
      assert.is_true(kill.unlisted)
    end)

    it("records nothing for an unlisted mob that isn't classified rare", function()
      local ns = load()
      local unit = { guid = guid(4000), classification = "elite", name = "Mor'Ladim", dead = true, tapDenied = false }
      local kill, info = ns.Rares.watch(fakeApi({ units = { target = unit } })):targetDied()
      assert.is_nil(kill)
      assert.equal("notRare", info.result)
    end)

    it("records nothing with no target", function()
      local ns = load()
      local kill, info = ns.Rares.watch(fakeApi()):targetDied()
      assert.is_nil(kill)
      assert.equal("unknown", info.result)
    end)
  end)

  describe("on PARTY_KILL", function()
    it("records a listed rare when the target GUID is readable", function()
      local ns = load()
      local kill, info = ns.Rares.watch(fakeApi()):partyKill("Player-0-Ann", guid(RAKSHIRI))
      assert.equal(RAKSHIRI, kill.npcId)
      assert.equal("partyKill", kill.signal)
      assert.equal("partyKill", info.signal)
    end)

    it("records nothing, and doesn't error, when the target GUID is secret", function()
      local ns = load()
      local kill, info = ns.Rares.watch(fakeApi()):partyKill(SECRET, SECRET)
      assert.is_nil(kill)
      assert.equal("secret", info.result)
      assert.same({ "attackerGUID", "targetGUID" }, info.secret)
    end)

    it("keeps an unlisted rare only once it was seen classified rare", function()
      local ns = load()
      local api = fakeApi({ units = { nameplate1 = { guid = guid(BJARN), classification = "rare", name = "Bjarn" } } })
      local watch = ns.Rares.watch(api)
      assert.is_nil((watch:partyKill(nil, guid(BJARN))))
      watch:see("nameplate1")
      assert.equal(BJARN, watch:partyKill(nil, guid(BJARN)).npcId)
    end)
  end)

  it("sees nothing, and doesn't error, when a unit's identity reads secret", function()
    local ns = load()
    local api = fakeApi({ units = { mouseover = { guid = SECRET, classification = "rare", name = SECRET } } })
    local info = ns.Rares.watch(api):see("mouseover")
    assert.equal("secret", info.result)
    assert.same({ "guid" }, info.secret)
  end)
end)

-- A net with the given clients logged in and in one Crew, settled.
local function crew(names)
  local ns = load()
  local net = ns.FakeNet.new()
  local clients = {}
  for i, name in ipairs(names) do clients[i] = net:add(name):login() end
  local code = clients[1]:join()
  for i = 2, #clients do clients[i]:join(code) end
  net:run(40)
  return net, clients, ns, code
end

local function later(net, seconds)
  net:step(net.clock + seconds)
end

local function kill(npcId, extra)
  local k = { npcId = npcId, zone = "Winterspring", subzone = "Everlook", mapId = 1452, signal = "loot" }
  for key, v in pairs(extra or {}) do k[key] = v end
  return k
end

local function rareTrophies(client)
  local list = {}
  for _, trophy in ipairs(client.core:trophies().shelf) do
    if trophy.track == "rareKills" then list[#list + 1] = trophy end
  end
  return list
end

local function texts(client, kind)
  local list = {}
  for _, day in ipairs(client.core:feed().days) do
    for _, entry in ipairs(day.entries) do
      if entry.kind == kind then list[#list + 1] = entry.text end
    end
  end
  return list
end

local function live(client)
  local list = {}
  for _, event in ipairs(client.events) do
    if event[1] == "feedEntry" and event[2].kind == "goal" then list[#list + 1] = event[2].text end
  end
  return list
end

-- How many Rares the Crew has slain now, from the records held.
local function slainNow(client)
  for _, r in ipairs(client.core:goals()) do
    if r.track == "rares" then return r.value or 0 end
  end
end

local function slot(grid, name)
  for _, s in ipairs(grid.slots) do
    if s.name == name then return s end
  end
end

describe("Rare kills", function()
  it("are kept in the own record: the first kill of each, when, where and on which Character", function()
    local net, clients = crew({ "Ann" })
    local a = clients[1]
    assert.is_true(a.core:rareKilled(kill(RAKSHIRI)))
    local at = net.clock
    later(net, DAY)
    assert.is_false(a.core:rareKilled(kill(RAKSHIRI, { zone = "Elsewhere" })))
    local entry = a.core.ledger:own().rares[RAKSHIRI]
    assert.equal(at, entry.t)
    assert.equal("Winterspring", entry.z)
    assert.equal("Everlook", entry.s)
    assert.equal(1452, entry.m)
    assert.equal(a.character.guid, entry.c)
    -- No party list.
    assert.is_nil(entry.p)
  end)

  it("make a Crew trophy, a Feed entry, a toast and a Live event on every client, crediting the killer", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    a.core:rareKilled(kill(RAKSHIRI))
    net:run(5)
    for _, client in ipairs(clients) do
      local trophies = rareTrophies(client)
      assert.equal(1, #trophies)
      local trophy = trophies[1]
      assert.equal(RAKSHIRI, trophy.npcId)
      assert.equal("Rak'shiri", trophy.label)
      assert.equal("Winterspring", trophy.zone)
      assert.equal(57, trophy.level)
      assert.equal("rare", trophy.quality)
      assert.is_true(trophy.fresh)
      assert.matches("^%d+ %a%a%a$", trophy.date)
    end
    assert.equal("You", rareTrophies(a)[1].by)
    assert.equal("Ann", rareTrophies(b)[1].by)
    assert.same({ "You slew Rak'shiri!" }, texts(a, "goal"))
    assert.same({ "Ann slew Rak'shiri!" }, texts(b, "goal"))
    assert.same({ "Ann slew Rak'shiri!" }, live(b))
  end)

  it("are epic for a rare elite", function()
    local net, clients = crew({ "Ann", "Bob" })
    clients[1].core:rareKilled(kill(VOLCHAN))
    net:run(5)
    assert.equal("epic", rareTrophies(clients[2])[1].quality)
  end)

  it("keep the Crew's earliest kill per Rare, whichever record brings it", function()
    local net, clients = crew({ "Ann", "Bob", "Cleo" })
    local a, b, c = clients[1], clients[2], clients[3]
    b:lockdown(true)
    b.core:rareKilled(kill(RAKSHIRI))
    local bobs = net.clock
    later(net, DAY)
    a.core:rareKilled(kill(RAKSHIRI))
    net:run(5)
    assert.equal("Ann", rareTrophies(c)[1].by)
    b:lockdown(false)
    net:run(10)
    assert.equal(bobs, rareTrophies(c)[1].time)
    assert.equal("Bob", rareTrophies(c)[1].by)
    assert.same({ "Ann slew Rak'shiri!" }, texts(c, "goal"))
  end)

  it("count only Members who haven't left", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    a.core:rareKilled(kill(RAKSHIRI))
    net:run(5)
    assert.equal(1, slainNow(b))
    a.core:leaveCrew()
    net:run(10)
    assert.equal(0, slainNow(b))
  end)

  it("are quiet when first seen in a Member's record", function()
    local net, clients, _, code = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    b:logout()
    local cleo = net:add("Cleo"):login()
    cleo:join(code)
    net:run(40)
    cleo.core:rareKilled(kill(TIMBER))
    net:run(5)
    assert.same({ "Cleo slew Timber!" }, texts(a, "goal"))
    a:logout()
    b:login()
    net:run(40)
    local trophy = rareTrophies(b)[1]
    assert.equal(TIMBER, trophy.npcId)
    assert.is_true(trophy.quiet)
    assert.is_false(trophy.fresh)
    assert.same({}, texts(b, "goal"))
  end)

  it("are quiet at the silent baseline when you join", function()
    local ns = load()
    local net = ns.FakeNet.new()
    local ann = net:add("Ann"):login()
    local code = ann:join()
    net:run(40)
    ann.core:rareKilled(kill(TIMBER))
    net:run(5)
    local bob = net:add("Bob"):login()
    bob:join(code)
    net:run(40)
    assert.same({}, texts(bob, "goal"))
    assert.is_true(rareTrophies(bob)[1].quiet)
  end)

  it("keep unlisted rares up to a cap, never as trophies", function()
    local net, clients, ns = crew({ "Ann", "Bob" })
    local a = clients[1]
    for i = 1, ns.Rares.UNLISTED_CAP do
      assert.is_true(a.core:rareKilled(kill(900000 + i, { name = "Unlisted " .. i, unlisted = true })))
    end
    assert.is_false(a.core:rareKilled(kill(BJARN, { name = "Bjarn", unlisted = true })))
    -- A listed one still goes in.
    assert.is_true(a.core:rareKilled(kill(TIMBER)))
    local own = a.core.ledger:own().rares
    assert.equal("Unlisted 1", own[900001].n)
    assert.is_nil(own[BJARN])
    net:run(5)
    assert.equal(1, #rareTrophies(clients[2]))
    assert.equal(1, clients[2].core:trophies().rares.slain)
  end)

  it("ignore a malformed record field when collected", function()
    local net, clients, ns = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    local function sendRares(rares)
      a.core.ledger:changeOwn(function(record)
        record.rares = rares
        return true
      end)
      a.core.gossip:ownChanged("now")
      net:run(5)
    end
    sendRares("lots")
    assert.equal(0, slainNow(b))
    sendRares({
      [RAKSHIRI] = { t = "yesterday" },
      [TIMBER] = { t = net.clock, z = 12 },
      [BROKEN_TOOTH] = "dead",
      ["Volchan"] = { t = net.clock },
      [-5] = { t = net.clock },
    })
    assert.equal(0, slainNow(b))
    sendRares({ [RAKSHIRI] = { t = net.clock, c = a.character.guid } })
    assert.equal(1, slainNow(b))
    local tooMany = {}
    for i = 1, 300 do tooMany[i] = { t = net.clock } end
    tooMany[TIMBER] = { t = net.clock }
    sendRares(tooMany)
    assert.equal(0, slainNow(b))
    assert.truthy(ns)
  end)

  it("record nothing from a kill that isn't readable", function()
    local _, clients = crew({ "Ann" })
    local a = clients[1]
    for _, bad in ipairs({ {}, { npcId = "Rak'shiri" }, { npcId = -1 }, { npcId = 1.5 } }) do
      assert.is_false(a.core:rareKilled(bad))
    end
    assert.is_false(a.core:rareKilled(nil))
    assert.is_nil(a.core.ledger:own().rares)
  end)

  it("fill the cabinet's Rares grid in level order, greyed until slain", function()
    local net, clients, ns = crew({ "Ann", "Bob" })
    clients[1].core:rareKilled(kill(BROKEN_TOOTH))
    net:run(5)
    local trophies = clients[2].core:trophies()
    assert.equal(ns.Rares.TOTAL, trophies.rares.total)
    assert.equal(ns.Rares.TOTAL, #trophies.rares.slots)
    assert.equal(1, trophies.rares.slain)
    local tooth = slot(trophies.rares, "Broken Tooth")
    assert.is_true(tooth.slain)
    assert.equal(trophies.latest, tooth.trophy)
    local rak = slot(trophies.rares, "Rak'shiri")
    assert.is_false(rak.slain)
    assert.equal("Winterspring", rak.zone)
    assert.equal("57", rak.levels)
    assert.equal(ns.Rares.LIST[1].name, trophies.rares.slots[1].name)
  end)

  it("join the shelf with the other trophies, newest first", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    a:play({ deaths = 25 })
    net:run(5)
    later(net, DAY)
    a.core:rareKilled(kill(TIMBER))
    net:run(5)
    local trophies = b.core:trophies()
    assert.equal("rareKills", trophies.shelf[1].track)
    assert.equal(trophies.shelf[1], trophies.latest)
    assert.equal("Ann slew Timber!", trophies.latest.text)
  end)

  it("show a kill made while you were away under Crew goals", function()
    local net, clients = crew({ "Ann", "Bob" })
    clients[2]:logout()
    net:run(5)
    clients[1].core:rareKilled(kill(RAKSHIRI))
    net:run(5)
    clients[2].events = {}
    clients[2]:login()
    net:run(40)
    local summary
    for _, event in ipairs(clients[2].events) do
      if event[1] == "awaySummary" then summary = event[2] end
    end
    assert.equal("Ann slew Rak'shiri!", summary.goals[1].text)
  end)

  it("are kept outside a Crew, and make no entry there", function()
    local ns = load()
    local net = ns.FakeNet.new()
    local a = net:add("Ann"):login()
    assert.is_true(a.core:rareKilled(kill(TIMBER)))
    assert.same({}, texts(a, "goal"))
  end)
end)

local function row(client)
  for _, r in ipairs(client.core:goals()) do
    if r.track == "rares" then return r end
  end
end

-- Kills the first n Rares on the list, in one go.
local function killRares(net, client, ns, n)
  for i = 1, n do client.core:rareKilled(kill(ns.Rares.LIST[i].id)) end
  net:run(5)
end

local function stepTexts(client)
  local list = {}
  for _, text in ipairs(texts(client, "goal")) do
    if not text:find(" slew ") then list[#list + 1] = text end
  end
  return list
end

describe("The Rares slain track", function()
  it("has steps at 5, 10, 20 and every Rare", function()
    local ns = load()
    local all = ns.Rares.TOTAL
    assert.same({ 5, 10, 20, all }, ns.Goals.rungs("rares", all))
  end)

  it("shows on the Goals tab, counting Rares towards the next step", function()
    local net, clients, ns = crew({ "Ann", "Bob" })
    killRares(net, clients[1], ns, 3)
    local r = row(clients[2])
    assert.equal("Rares slain", r.title)
    assert.equal(3, r.value)
    assert.equal(5, r.goal)
  end)

  it("makes one entry for the highest step when several are crossed", function()
    local net, clients, ns = crew({ "Ann", "Bob" })
    killRares(net, clients[1], ns, 12)
    assert.same({ "The Crew has slain 10 Rares!" }, stepTexts(clients[2]))
    local cabinet = clients[2].core:trophies().cabinet
    local labels = {}
    for _, group in ipairs(cabinet) do
      if group.track == "rares" then
        for i, trophy in ipairs(group.trophies) do labels[i] = trophy.label end
      end
    end
    assert.same({ "5 Rares", "10 Rares" }, labels)
  end)

  it("words the last step as every Rare, and is then complete", function()
    local net, clients, ns = crew({ "Ann", "Bob" })
    killRares(net, clients[1], ns, ns.Rares.TOTAL)
    assert.same({ "The Crew has slain every Rare!" }, stepTexts(clients[2]))
    assert.is_true(row(clients[2]).complete)
  end)

  it("never counts unlisted rares", function()
    local net, clients = crew({ "Ann", "Bob" })
    clients[1].core:rareKilled(kill(BJARN, { name = "Bjarn", unlisted = true }))
    net:run(5)
    assert.equal(0, row(clients[2]).value)
  end)

  describe("the late baseline", function()
    local function beforeTheTrack(client)
      client.db.goals.reached.rares = nil
      client.db.goals.quiet.rares = nil
    end

    it("passes the rungs already reached quietly when the track ships", function()
      local net, clients, ns = crew({ "Ann", "Bob" })
      local bob = clients[2]
      bob:logout()
      killRares(net, clients[1], ns, 6)
      beforeTheTrack(bob)
      bob.db.feed = {}
      bob:login()
      net:run(40)
      assert.same({}, stepTexts(bob))
      killRares(net, clients[1], ns, 10)
      assert.same({ "The Crew has slain 10 Rares!" }, stepTexts(bob))
    end)
  end)
end)
