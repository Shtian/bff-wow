local load = require("tests.load")

local NORMAL = { realmName = "", recordId = 15, faction = "Alliance", serverId = "6939", name = "Normal" }
local PVP = { realmName = "", recordId = 14, faction = "Alliance", serverId = "6856", name = "PvP" }

local function with(facts, changes)
  local result = {}
  for k, v in pairs(facts) do result[k] = v end
  for k, v in pairs(changes or {}) do result[k] = v end
  return result
end

local function on(client, facts)
  if client.core then client:logout() end
  client.ruleset = facts
  return client:login()
end

local function feedKinds(client)
  local kinds = {}
  for _, day in ipairs(client.core:feed().days) do
    for _, entry in ipairs(day.entries) do kinds[#kinds + 1] = entry.kind end
  end
  return kinds
end

local function memberIds(client)
  local ids = {}
  for _, row in ipairs(client.core:rows()) do ids[#ids + 1] = row.memberId end
  table.sort(ids)
  return ids
end

describe("A Crew per Ruleset and faction", function()
  local ns, net

  before_each(function()
    ns = load()
    net = ns.FakeNet.new({ channels = true })
  end)

  local function startedOn(facts)
    local ann = net:add("Ann", { ruleset = facts }):login()
    local code = ann:join()
    return ann, code
  end

  describe("its key", function()
    it("keeps one Crew when the game gives no facts", function()
      local ann, code = startedOn(nil)
      on(ann, {})
      assert.equal(code, ann.core:crew().code)
      on(ann, { faction = "Horde" })
      assert.equal(code, ann.core:crew().code)
    end)

    it("takes the realm name over the record ID", function()
      local ann, code = startedOn({ realmName = "Stormrage", recordId = 15, faction = "Alliance" })
      on(ann, { realmName = "Stormrage", recordId = 99, faction = "Alliance" })
      assert.equal(code, ann.core:crew().code)
      on(ann, { realmName = "Silvermoon", recordId = 15, faction = "Alliance" })
      assert.is_nil(ann.core:crew())
    end)

    it("takes the record ID when the realm name is empty", function()
      local ann, code = startedOn({ realmName = "", recordId = 15, faction = "Alliance" })
      on(ann, { realmName = "", recordId = 16, faction = "Alliance" })
      assert.is_nil(ann.core:crew())
      on(ann, { realmName = "", recordId = 15, faction = "Alliance" })
      assert.equal(code, ann.core:crew().code)
    end)

    it("splits by faction, even on one server with one ruleset name", function()
      local ann, code = startedOn(NORMAL)
      on(ann, with(NORMAL, { faction = "Horde" }))
      assert.is_nil(ann.core:crew())
      on(ann, NORMAL)
      assert.equal(code, ann.core:crew().code)
    end)

    it("names the key, the facts it was built from and the server IDs seen", function()
      local ann = startedOn(NORMAL)
      assert.same({
        key = "mode:15:Alliance", recordId = 15, faction = "Alliance", serverId = "6939", serverIds = { "6939" },
        name = "Normal", provisional = false,
      }, ann.core:ruleset())
      on(ann, { realmName = "Stormrage", faction = "Horde", serverId = "1084" })
      assert.same({
        key = "realm:Stormrage:Horde", realmName = "Stormrage", faction = "Horde", serverId = "1084",
        serverIds = { "1084" }, provisional = false,
      }, ann.core:ruleset())
      on(ann, nil)
      assert.same({ key = "default", serverIds = {}, provisional = false }, ann.core:ruleset())
    end)
  end)

  describe("its repair", function()
    it("keeps the Crew when the record ID changes and the server ID is known", function()
      local ann, code = startedOn(NORMAL)
      local id = ann.memberId
      on(ann, with(NORMAL, { recordId = 20, name = "Normaal" }))
      assert.equal(code, ann.core:crew().code)
      assert.equal(id, ann.core:rows()[1].memberId)
      assert.equal("mode:15:Alliance moved to mode:20:Alliance (by server ID)", ann.core:ruleset().repair)
    end)

    it("keeps the Crew when the server ID is new and the name is known", function()
      local ann, code = startedOn(NORMAL)
      on(ann, with(NORMAL, { recordId = 20, serverId = "7001" }))
      assert.equal(code, ann.core:crew().code)
      assert.same({ "6939", "7001" }, ann.core:ruleset().serverIds)
      assert.equal("mode:15:Alliance moved to mode:20:Alliance (by name)", ann.core:ruleset().repair)
    end)

    it("moves the Crew only once", function()
      local ann, code = startedOn(NORMAL)
      on(ann, with(NORMAL, { recordId = 20 }))
      on(ann, with(NORMAL, { recordId = 20 }))
      assert.equal(code, ann.core:crew().code)
      assert.is_nil(ann.core:ruleset().repair)
    end)

    it("makes a new entry and leaves the old one alone when nothing matches", function()
      local ann, code = startedOn(NORMAL)
      on(ann, { realmName = "", recordId = 20, faction = "Alliance", serverId = "7001" })
      assert.is_nil(ann.core:crew())
      assert.is_nil(ann.core:ruleset().repair)
      on(ann, NORMAL)
      assert.equal(code, ann.core:crew().code)
    end)

    it("never takes the other faction's Crew", function()
      local ann = startedOn(NORMAL)
      on(ann, with(NORMAL, { recordId = 20, faction = "Horde" }))
      assert.is_nil(ann.core:crew())
      assert.is_nil(ann.core:ruleset().repair)
    end)

    it("swaps two Crews when the record IDs swap, going by the server ID", function()
      local ann, normalCode = startedOn(NORMAL)
      on(ann, PVP)
      local pvpCode = ann:join()
      on(ann, with(NORMAL, { recordId = 14 }))
      assert.equal(normalCode, ann.core:crew().code)
      assert.same({ "6939" }, ann.core:ruleset().serverIds)
      assert.equal("mode:15:Alliance and mode:14:Alliance swapped (by server ID)", ann.core:ruleset().repair)
      on(ann, with(PVP, { recordId = 15 }))
      assert.equal(pvpCode, ann.core:crew().code)
      assert.same({ "6856" }, ann.core:ruleset().serverIds)
      assert.is_nil(ann.core:ruleset().repair)
    end)

    it("keeps the Crew it found when a new server ID is nowhere else", function()
      local ann, code = startedOn(NORMAL)
      on(ann, with(NORMAL, { serverId = "7001" }))
      assert.equal(code, ann.core:crew().code)
      assert.same({ "6939", "7001" }, ann.core:ruleset().serverIds)
      assert.is_nil(ann.core:ruleset().repair)
    end)

    it("writes the move to the sync log once tracing starts", function()
      startedOn(NORMAL)
      local ann = net.clients[1]
      on(ann, with(NORMAL, { recordId = 20 }))
      local lines = {}
      ann.core:setTrace(function(line) lines[#lines + 1] = line end)
      assert.same({ "ruleset mode:15:Alliance moved to mode:20:Alliance (by server ID)" }, lines)
      ann.core:setTrace(function(line) lines[#lines + 1] = line end)
      assert.equal(1, #lines)
    end)
  end)

  describe("two Rulesets", function()
    local ann, bob, cid, pvpCode, normalCode

    before_each(function()
      ann = net:add("Ann", { ruleset = PVP }):login()
      bob = net:add("Bob", { ruleset = PVP }):login()
      cid = net:add("Cid", { ruleset = NORMAL }):login()
      pvpCode = ann:join()
      bob:join(pvpCode)
      net:run(20)
      on(ann, NORMAL)
      normalCode = ann:join()
      cid:join(normalCode)
      net:run(20)
    end)

    it("give two Crews with their own Member ids and rosters", function()
      local normalId = ann.memberId
      local normalIds = memberIds(ann)
      on(ann, PVP)
      net:run(20)
      assert.equal(pvpCode, ann.core:crew().code)
      assert.not_equal(normalId, ann.memberId)
      local pvpIds = { ann.memberId, bob.memberId }
      table.sort(pvpIds)
      assert.same(pvpIds, memberIds(ann))
      assert.same(pvpIds, memberIds(bob))
      local both = { normalId, cid.memberId }
      table.sort(both)
      assert.same(both, normalIds)
    end)

    it("keep their Feeds apart", function()
      bob:play({ level = 11 })
      net:run(5)
      on(ann, PVP)
      net:run(20)
      local pvp = feedKinds(ann)
      on(ann, NORMAL)
      net:run(20)
      local found = false
      for _, kind in ipairs(pvp) do if kind == "ding" then found = true end end
      assert.is_true(found)
      for _, kind in ipairs(feedKinds(ann)) do assert.not_equal("ding", kind) end
    end)

    it("share settings", function()
      ann.core:setSetting("chatLines", false)
      ann.core:setPanelPlace(500, 480, 10, 600)
      on(ann, PVP)
      assert.is_false(ann.core:setting("chatLines"))
      assert.same({ width = 500, height = 480, left = 10, top = 600 }, ann.core:setting("panelPlace"))
    end)

    it("keep Appear offline to the Crew it was set in", function()
      ann.core:setPaused(true)
      on(ann, PVP)
      assert.is_false(ann.core:isPaused())
      on(ann, NORMAL)
      assert.is_true(ann.core:isPaused())
    end)
  end)

  describe("its name", function()
    local UNNAMED = { realmName = "", recordId = 15, faction = "Alliance", serverId = "6939" }

    it("is saved when Battle.net info arrives after login, so a later repair can find it", function()
      local ann, code = startedOn(UNNAMED)
      ann.core:rulesetNamed("Normal")
      assert.equal("Normal", ann.core:ruleset().name)
      on(ann, { realmName = "", recordId = 20, faction = "Alliance", serverId = "7001", name = "Normal" })
      assert.equal(code, ann.core:crew().code)
      assert.equal("mode:15:Alliance moved to mode:20:Alliance (by name)", ann.core:ruleset().repair)
    end)

    it("keeps the saved name when Battle.net gives none", function()
      local ann = startedOn(NORMAL)
      ann.core:rulesetNamed(nil)
      ann.core:rulesetNamed("")
      assert.equal("Normal", ann.core:ruleset().name)
    end)

    it("writes a new name to the sync log, and not the same one again", function()
      local ann = startedOn(UNNAMED)
      local lines = {}
      ann.core:setTrace(function(line) lines[#lines + 1] = line end)
      ann.core:rulesetNamed("Normal")
      ann.core:rulesetNamed("Normal")
      assert.same({ "ruleset mode:15:Alliance named Normal" }, lines)
    end)
  end)

  it("remembers What's new across Rulesets", function()
    local changelog = "## 2.3.0\n<sub>2026-11-10</sub>\n\n- *(minor)* Something new.\n\n"
      .. "## 2.2.0\n<sub>2026-11-01</sub>\n\n- *(patch)* A fix.\n\n"
    local ann = net:add("Ann", { ruleset = NORMAL, version = "v2.3.0", changelog = changelog,
      db = { changesSeen = "2.2.0" } }):login()
    assert.is_true(ann.core:hasNewChanges())
    ann.core:openWhatsNew()
    ann.core:leaveWhatsNew()
    on(ann, PVP)
    assert.is_false(ann.core:hasNewChanges())
  end)
end)
