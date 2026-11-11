local wow = require("tests.wow_stubs")

-- /bff report's text, with a Crew of two others known and the link up to
-- one of them, in a dungeon during lockdown.
local function report(options)
  options = options or {}
  local game = wow()
  local env = game.env
  env.date = function() return "2026-11-11 20:31:05" end
  env.GetBuildInfo = function() return "1.16.0", "65000", "Nov 1 2026", 16001 end
  env.WOW_PROJECT_CAMELOT = 21
  env.WOW_PROJECT_ID = 21
  local ns = { VERSION = "v0.9.0" }
  game.load("Game/SyncLog.lua", ns)
  ns.syncLog = ns.SyncLog.new()
  ns.syncLog:add("20:30:00 1.000  link up (member list)")
  ns.syncLog:add("20:30:01 2.000  left the group, or it disbanded")
  ns.core = {
    crew = function() return options.crew ~= false and { code = "X" } or nil end,
    summary = function() return { members = 2 } end,
  }
  ns.ChannelLink = { state = function() return options.link or { up = true, peers = 1, instance = "party", lockdown = true } end }
  game.load("UI/Report.lua", ns)
  return ns.Report.text()
end

describe("/bff report", function()
  it("holds the versions, Crew, link, instance and lockdown state, then the sync log oldest first", function()
    assert.equal(table.concat({
      "BFF report · 2026-11-11 20:31:05",
      "BFF v0.9.0",
      "Game 1.16.0 (build 65000) · interface 16001 · WoW: Forever: yes",
      "Crew: yes · other Members known: 2 · peers in the channel: 1",
      "Link: up",
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
end)
