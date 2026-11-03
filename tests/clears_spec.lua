local load = require("tests.load")

local DAY = 24 * 60 * 60

-- Made-up final bosses, since Forever's encounter IDs aren't known yet
-- (docs/research/boss-kills.md): every client of the net is handed these.
local FINALS = {
  [101] = "The Deadmines",
  [102] = "Wailing Caverns",
  [672] = "Molten Core",
}

local function playing(name, extra)
  local character = {
    guid = "Player-0-" .. name, name = name, classFilename = "WARRIOR",
    level = 20, xp = 0, maxXp = 1000, zone = "Westfall", deaths = 0,
  }
  for k, v in pairs(extra or {}) do character[k] = v end
  return character
end

-- A net with the given clients logged in and in one Crew, settled.
local function crew(names)
  local ns = load()
  local net = ns.FakeNet.new({ finalBosses = FINALS })
  local clients = {}
  for i, name in ipairs(names) do
    clients[i] = net:add(name, { character = playing(name) }):login()
  end
  local code = clients[1]:join()
  for i = 2, #clients do clients[i]:join(code) end
  net:run(40)
  return net, clients, ns, code
end

local function later(net, seconds)
  net:step(net.clock + seconds)
end

-- The party as the game reads it: each client's Character, plus strangers
-- by name.
local function party(clients, strangers)
  local list = {}
  for _, client in ipairs(clients) do
    list[#list + 1] = { guid = client.character.guid, name = client.character.name }
  end
  for _, name in ipairs(strangers or {}) do
    list[#list + 1] = { guid = "Player-0-" .. name, name = name }
  end
  return list
end

-- Every client in the party kills the final boss: each records it.
local function clear(clients, encounterId, instanceType, strangers)
  local results = {}
  for i, client in ipairs(clients) do
    results[i] = client.core:encounterEnded({
      encounterId = encounterId,
      success = true,
      instanceType = instanceType or "party",
      party = party(clients, strangers),
    })
  end
  return results
end

local function clearTrophies(client)
  local list = {}
  for _, trophy in ipairs(client.core:trophies().shelf) do
    if trophy.track == "clears" then list[#list + 1] = trophy end
  end
  return list
end

local function goalTexts(client)
  local texts = {}
  for _, day in ipairs(client.core:feed().days) do
    for _, entry in ipairs(day.entries) do
      if entry.kind == "goal" then texts[#texts + 1] = entry.text end
    end
  end
  return texts
end

local function liveTexts(client)
  local texts = {}
  for _, event in ipairs(client.events) do
    if event[1] == "feedEntry" and event[2].kind == "goal" then texts[#texts + 1] = event[2].text end
  end
  return texts
end

local function slot(grid, name)
  for _, s in ipairs(grid.slots) do
    if s.name == name then return s end
  end
end

describe("Clears", function()
  it("record a final boss killed in a party as a Crew trophy on every client", function()
    local net, clients = crew({ "Ann", "Bob", "Cleo" })
    local a, b, c = clients[1], clients[2], clients[3]
    assert.same({ "The Deadmines", "The Deadmines" }, clear({ a, b }, 101))
    net:run(10)

    for _, client in ipairs({ a, b, c }) do
      local trophies = clearTrophies(client)
      assert.equal(1, #trophies)
      local trophy = trophies[1]
      assert.equal("The Deadmines", trophy.instance)
      assert.equal("Deadmines", trophy.label)
      assert.equal("dungeon", trophy.kind)
      assert.equal("epic", trophy.quality)
      assert.equal("The Crew cleared The Deadmines!", trophy.text)
      assert.is_true(trophy.fresh)
      assert.matches("^%d+ %a%a%a$", trophy.date)
      -- One Feed entry, though two Members recorded it.
      assert.same({ "The Crew cleared The Deadmines!" }, goalTexts(client))
      assert.equal("clears", client.core:trophies().latest.track)
    end
    assert.same({ "You", "Bob" }, clearTrophies(a)[1].party)
    assert.same({ "Ann", "Bob" }, clearTrophies(c)[1].party)
    -- Cleo wasn't there, and hears it live.
    assert.same({ "The Crew cleared The Deadmines!" }, liveTexts(c))
  end)

  it("are legendary for a raid", function()
    local net, clients = crew({ "Ann", "Bob" })
    clear(clients, 672, "raid")
    net:run(10)
    local trophy = clearTrophies(clients[2])[1]
    assert.equal("raid", trophy.kind)
    assert.equal("legendary", trophy.quality)
    assert.equal("The Crew cleared Molten Core!", trophy.text)
  end)

  it("record nothing for a wipe, an unknown boss, outside an instance or from an unreadable payload", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a = clients[1]
    local base = { encounterId = 101, success = true, instanceType = "party", party = party(clients) }
    local function with(changes)
      local e = {}
      for k, v in pairs(base) do e[k] = v end
      for k, v in pairs(changes) do e[k] = v end
      return e
    end
    local cases = {
      { with({ success = false }), "wipe" },
      { with({ encounterId = 999 }), "unknown" },
      { with({ instanceType = "none" }), "notInstance" },
      -- Secret values reach Core as nil.
      { with({ encounterId = false }), "unreadable" },
      { with({ success = "yes" }), "unreadable" },
      { with({ party = "everyone" }), "unreadable" },
    }
    for _, case in ipairs(cases) do
      local name, reason = a.core:encounterEnded(case[1])
      assert.is_nil(name)
      assert.equal(case[2], reason)
    end
    local name, reason = a.core:encounterEnded(nil)
    assert.is_nil(name)
    assert.equal("unreadable", reason)
    net:run(10)
    assert.same({}, clearTrophies(clients[2]))
    assert.same({}, goalTexts(clients[2]))
  end)

  it("name only Members of the Crew in the party", function()
    local net, clients = crew({ "Ann", "Bob" })
    -- Ann pugs it with three strangers; a nameless one is skipped.
    local a = clients[1]
    local group = party({ a }, { "Zed", "Yan", "Xia" })
    group[#group + 1] = {}
    a.core:encounterEnded({ encounterId = 101, success = true, instanceType = "party", party = group })
    net:run(10)
    assert.same({ "Ann" }, clearTrophies(clients[2])[1].party)
  end)

  it("match a party member by name when the GUID can't be read", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    a.core:encounterEnded({
      encounterId = 101, success = true, instanceType = "party",
      party = { { name = "BOB" }, { guid = a.character.guid } },
    })
    net:run(10)
    assert.same({ "You", "Ann" }, clearTrophies(b)[1].party)
  end)

  it("keep the first clear as the Crew's trophy and credit every clearing party", function()
    local net, clients = crew({ "Ann", "Bob", "Cleo", "Dan" })
    local a, b, c, d = clients[1], clients[2], clients[3], clients[4]
    clear({ a, b }, 101)
    net:run(10)
    local first = clearTrophies(d)[1].time
    later(net, 2 * DAY)
    clear({ c, d }, 101)
    -- A repeat clear by the same party changes nothing.
    clear({ a, b }, 101)
    net:run(10)

    for _, client in ipairs(clients) do
      local trophies = clearTrophies(client)
      assert.equal(1, #trophies)
      assert.equal(first, trophies[1].time)
      assert.same({ "The Crew cleared The Deadmines!" }, goalTexts(client))
    end
    assert.same({ "You", "Ann", "Cleo", "Dan" }, clearTrophies(b)[1].party)
    assert.same({ "You", "Ann", "Bob", "Cleo" }, clearTrophies(d)[1].party)
  end)

  it("take the earliest clear's time, whichever record brings it first", function()
    local net, clients = crew({ "Ann", "Bob", "Cleo" })
    local a, b, c = clients[1], clients[2], clients[3]
    -- Bob clears it first, but locked down, so his record waits.
    b:lockdown(true)
    clear({ b }, 101)
    local bobs = net.clock
    later(net, DAY)
    clear({ a }, 101)
    net:run(10)
    assert.is_true(clearTrophies(c)[1].time > bobs)
    b:lockdown(false)
    net:run(10)
    assert.equal(bobs, clearTrophies(c)[1].time)
    assert.same({ "Ann", "Bob" }, clearTrophies(c)[1].party)
    assert.same({ "The Crew cleared The Deadmines!" }, goalTexts(c))
  end)

  it("are recorded quietly when first seen in a Member's record", function()
    local net, clients, ns, code = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    b:logout()
    local cleo = net:add("Cleo", { character = playing("Cleo") }):login()
    cleo:join(code)
    net:run(40)
    -- Ann knows Cleo already: news to her.
    clear({ cleo }, 102)
    net:run(10)
    assert.same({ "The Crew cleared Wailing Caverns!" }, goalTexts(a))
    a:logout()
    -- Bob first sees Cleo's record with the clear in it.
    b:login()
    net:run(40)
    local trophy = clearTrophies(b)[1]
    assert.equal("Wailing Caverns", trophy.instance)
    assert.is_true(trophy.quiet)
    assert.is_false(trophy.fresh)
    assert.same({}, goalTexts(b))
    assert.truthy(ns)
  end)

  it("join the shelf with goal rungs, newest first, and count since the tab was last opened", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    b.core:openGoals()
    b.core:leaveGoals()
    later(net, DAY)
    a:play({ deaths = 25 })
    net:run(5)
    later(net, DAY)
    clear(clients, 101)
    net:run(10)
    local trophies = b.core:trophies()
    assert.equal("clears", trophies.shelf[1].track)
    assert.equal("deaths", trophies.shelf[2].track)
    assert.equal(trophies.shelf[1], trophies.latest)
    assert.equal(1, trophies.sinceSeen)
    assert.equal(trophies.count - 1, trophies.goalsReached)
  end)

  it("fill the cabinet's dungeon and raid grids, attunements left out", function()
    local net, clients, ns = crew({ "Ann", "Bob" })
    clear(clients, 101)
    net:run(10)
    local trophies = clients[2].core:trophies()
    local dungeons, raids = 0, 0
    for _, d in ipairs(ns.Core.DUNGEONS) do
      if d.kind == "dungeon" then dungeons = dungeons + 1 elseif d.kind == "raid" then raids = raids + 1 end
    end
    assert.equal(dungeons, trophies.dungeons.total)
    assert.equal(dungeons, #trophies.dungeons.slots)
    assert.equal(1, trophies.dungeons.cleared)
    assert.equal(raids, trophies.raids.total)
    assert.equal(0, trophies.raids.cleared)
    assert.is_nil(slot(trophies.dungeons, "Onyxia attunement"))
    assert.is_nil(slot(trophies.raids, "Onyxia attunement"))

    local deadmines = slot(trophies.dungeons, "The Deadmines")
    assert.is_true(deadmines.cleared)
    assert.equal(trophies.latest, deadmines.trophy)
    local caverns = slot(trophies.dungeons, "Wailing Caverns")
    assert.is_false(caverns.cleared)
    assert.equal("Wailing Caverns", caverns.label)
    assert.equal("17–24", caverns.levels)
    assert.equal("60", slot(trophies.raids, "Molten Core").levels)
    -- Level order, as on the Together tab.
    assert.equal("Ragefire Chasm", trophies.dungeons.slots[1].name)
  end)

  it("record nothing outside a Crew", function()
    local ns = load()
    local net = ns.FakeNet.new({ finalBosses = FINALS })
    local a = net:add("Ann", { character = playing("Ann") }):login()
    local name, reason = a.core:encounterEnded({
      encounterId = 101, success = true, instanceType = "party", party = party({ a }),
    })
    assert.is_nil(name)
    assert.equal("noCrew", reason)
  end)

  it("know Forever's final bosses from the dungeon table", function()
    local ns = load()
    for id, name in pairs(ns.Core.FINAL_BOSSES) do
      assert.is_number(id)
      local found
      for _, d in ipairs(ns.Core.DUNGEONS) do
        if d.name == name then found = d end
      end
      assert.truthy(found, name)
      assert.is_true(found.kind == "dungeon" or found.kind == "raid")
    end
  end)
end)
