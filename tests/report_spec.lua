local wow = require("tests.wow_stubs")

local function report(options)
  options = options or {}
  local game = wow()
  local env = game.env
  env.date = function(_, at) return at == 1700000000 and "2023-11-14 22:13:20" or "2026-11-11 20:31:05" end
  env.GetBuildInfo = function() return "1.16.0", "65000", "Nov 1 2026", 16001 end
  env.WOW_PROJECT_CAMELOT = 21
  env.WOW_PROJECT_ID = 21
  local ns = { VERSION = "v0.9.0" }
  game.load("Game/SyncLog.lua", ns)
  ns.syncLog = ns.SyncLog.new()
  ns.syncLog:add("20:30:00 1.000  link up (member list)")
  ns.syncLog:add("20:30:01 2.000  left the group, or it disbanded")
  ns.core = {
    crew = function()
      if options.crew == false then return nil end
      return options.crew or { code = "X", generation = 0, generationFrom = "saved", moves = 0 }
    end,
    rosterCounts = function() return { members = 2 } end,
    joinFailure = function() return options.failure end,
    ruleset = function()
      return options.ruleset or {
        key = "mode:15:Alliance", recordId = 15, faction = "Alliance", serverId = "6939",
        serverIds = { "6939", "6944" }, name = "Normal", provisional = false,
      }
    end,
  }
  ns.ChannelLink = {
    FAILURE_REASONS = {
      wrongPassword = "wrong password", tooManyChannels = "too many channels",
      stuckChannel = "the game left BFF half in the channel",
    },
    state = function() return options.link or { up = true, peers = 1, instance = "party", lockdown = true } end,
  }
  game.load("UI/Report.lua", ns)
  return ns.Report.text()
end

describe("/bff report", function()
  it("holds the versions, Crew, link, instance and lockdown state, then the sync log oldest first", function()
    assert.equal(table.concat({
      "BFF report · 2026-11-11 20:31:05",
      "BFF v0.9.0",
      "Game 1.16.0 (build 65000) · interface 16001 · WoW: Forever: yes",
      "Ruleset: mode:15:Alliance · realm name: none · record ID: 15 · faction: Alliance · name: Normal",
      "Server ID: 6939 · seen: 6939, 6944 · provisional: no",
      "Ruleset repair this session: none",
      "Crew: yes · other Members known: 2 · peers in the channel: 1",
      "Link: up",
      "Last join failure: none since the last join",
      "Channel generation: 0 (saved) · moves this session: 0",
      "In an instance: party · chat messaging lockdown: yes",
      "",
      "Sync log, oldest first (2 lines):",
      "20:30:00 1.000  link up (member list)",
      "20:30:01 2.000  left the group, or it disbanded",
    }, "\n"), report())
  end)

  it("says why the link is down", function()
    local text = report({ crew = false, link = { up = false, reason = "no Crew", peers = 0 } })
    assert.truthy(text:find("Crew: no · other Members known: 0 · peers in the channel: 0", 1, true))
    assert.truthy(text:find("Link: down (no Crew)", 1, true))
  end)

  it("gives the last join failure, which Core keeps until a join succeeds", function()
    local text = report({
      link = { up = false, reason = "wrong password", peers = 0 },
      failure = { kind = "wrongPassword", at = 1700000000 },
    })
    assert.truthy(text:find("Link: down (wrong password)", 1, true))
    assert.truthy(text:find("Last join failure: wrong password at 2023-11-14 22:13:20", 1, true))
  end)

  it("gives the channel generation, where it came from, and the moves this session", function()
    local text = report({ crew = { code = "X", generation = 3, generationFrom = "Ann's record", moves = 2 } })
    assert.truthy(text:find("Channel generation: 3 (Ann's record) · moves this session: 2", 1, true))
    assert.truthy(report({ crew = false }):find("Channel generation: none (no Crew)", 1, true))
  end)

  it("gives the Ruleset BFF thinks it's on, whether its Crew is provisional, and a repair this session", function()
    local text = report({ ruleset = {
      key = "mode:20:Horde", recordId = 20, faction = "Horde", serverId = "6939", serverIds = { "6939" },
      provisional = true, repair = "mode:15:Horde moved to mode:20:Horde (by server ID)",
    } })
    assert.truthy(text:find("Ruleset: mode:20:Horde · realm name: none · record ID: 20 · faction: Horde · name: none",
      1, true))
    assert.truthy(text:find("Server ID: 6939 · seen: 6939 · provisional: yes", 1, true))
    assert.truthy(text:find("Ruleset repair this session: mode:15:Horde moved to mode:20:Horde (by server ID)", 1, true))
  end)

  it("says none for the facts the game didn't give", function()
    local text = report({ ruleset = { key = "default", serverIds = {}, provisional = false } })
    assert.truthy(text:find("Ruleset: default · realm name: none · record ID: none · faction: none · name: none",
      1, true))
    assert.truthy(text:find("Server ID: none · seen: none · provisional: no", 1, true))
  end)

  it("gives the realm name on a game that has realms", function()
    local text = report({ ruleset = {
      key = "realm:Stormrage:Horde", realmName = "Stormrage", faction = "Horde", serverId = "1084",
      serverIds = { "1084" }, provisional = false,
    } })
    assert.truthy(text:find("Ruleset: realm:Stormrage:Horde · realm name: Stormrage · record ID: none", 1, true))
  end)
end)
