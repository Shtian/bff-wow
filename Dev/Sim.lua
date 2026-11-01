-- Sim: /bff sim attaches a few simulated Members to your real Core through
-- FakeNet, so the panel can be tried without another Member online. Their
-- records are kept and relayed like real ones, so it only runs in a Crew
-- where no one else is known yet: start a test Crew for it. Also the dev
-- console (/bffdev, opened by /bff sim too): buttons that make each
-- simulated Member ding, die, move, react to your newest entry, offer a
-- test Hand-me-down, Claim your newest one or log out,
-- one that plays out a stretch of you being away so While you were away
-- shows (with Reactions to your entries), one that reaches the next Crew
-- deaths goal, and a live log of what
-- your Core sends, receives and fires. /bffdev toast [n] shows sample
-- toasts. Left out of releases; it lives here, not in a file of its own,
-- so the .toc (a shipped file) stays as it is.

local _, ns = ...

local Sim = {}
ns.Sim = Sim

local DAY = 24 * 60 * 60
-- How long after starting the offline Member logs out.
local LOGOUT_AFTER = 20

-- levelOffset is relative to the Character you play, so "can play" shows up.
-- The first Character is the one being played; the others were played
-- `ago` seconds earlier. main picks the Character set as Main, if any.
local MEMBERS = {
  -- Online on their Main, and can play with you.
  { name = "Simone", characters = {
    { name = "Simone", classFilename = "MAGE", levelOffset = 2, zone = "Westfall" },
    { name = "Simonette", classFilename = "PRIEST", levelOffset = -8, zone = "Darkshore", ago = 2 * DAY },
  } },
  -- On an Alt, with a Main that can play with you.
  { name = "Simbad", main = 2, characters = {
    { name = "Simbad", classFilename = "ROGUE", levelOffset = 10, zone = "Redridge Mountains" },
    { name = "Simbadsson", classFilename = "WARRIOR", levelOffset = -1, zone = "Wetlands", ago = DAY },
  } },
  -- Logs out soon after, with an Alt unseen for 40 days (hidden).
  { name = "Simba", offline = true, characters = {
    { name = "Simba", classFilename = "DRUID", levelOffset = 6, zone = "Teldrassil" },
    { name = "Simbalina", classFilename = "HUNTER", levelOffset = -15, zone = "Durotar", ago = 40 * DAY },
  } },
}

local ZONES = {
  "Elwynn Forest", "Westfall", "Duskwood", "Redridge Mountains", "Stormwind City",
  "Durotar", "The Barrens", "Ashenvale", "Stranglethorn Vale", "Ironforge",
}

-- Each zone's uiMapID as the classic-era clients number them, then as
-- retail does, so the simulated Members get world map pins. Which
-- numbering a client uses isn't known up front (Forever may have its
-- own), so mapIdFor asks C_Map and takes the one whose map has the
-- zone's name, or else looks the name up in the client's map tree.
local MAP_IDS = {
  ["Elwynn Forest"] = { 1429, 37 }, ["Westfall"] = { 1436, 52 }, ["Duskwood"] = { 1431, 47 },
  ["Redridge Mountains"] = { 1433, 49 }, ["Stormwind City"] = { 1453, 84 }, ["Durotar"] = { 1411, 1 },
  -- Retail splits the Barrens; its Northern Barrens is 10.
  ["The Barrens"] = { 1413, 10 }, ["Ashenvale"] = { 1440, 63 }, ["Stranglethorn Vale"] = { 1434, 224 },
  ["Ironforge"] = { 1455, 87 }, ["Teldrassil"] = { 1438, 57 }, ["Darkshore"] = { 1439, 62 },
  ["Wetlands"] = { 1437, 56 },
}
-- Names other than the zone's own that count as a match.
local MAP_ALIASES = { ["The Barrens"] = "Northern Barrens" }
-- zone -> resolved uiMapID. Misses aren't kept: inside an instance the
-- tree can't be read, and it can be once you're back out.
local resolved = {}

local function named(info, zone)
  return info and (info.name == zone or info.name == MAP_ALIASES[zone])
end

-- The top of the map tree you stand in (the cosmic or world map).
local function rootMap()
  local id = C_Map.GetBestMapForUnit("player")
  local info = id and C_Map.GetMapInfo(id)
  while info and info.parentMapID and info.parentMapID ~= 0 do
    id = info.parentMapID
    info = C_Map.GetMapInfo(id)
  end
  return id
end

-- A zone or city map under the root with the zone's name, for clients
-- that number maps neither way.
local function searchTree(zone)
  local root = rootMap()
  if not root then return nil end
  local wanted = { [Enum.UIMapType.Zone] = true, [Enum.UIMapType.City] = true }
  for _, info in ipairs(C_Map.GetMapChildrenInfo(root, nil, true) or {}) do
    if wanted[info.mapType] and named(info, zone) then return info.mapID end
  end
  return nil
end

local function mapIdFor(zone)
  if resolved[zone] then return resolved[zone] end
  local found
  for _, id in ipairs(MAP_IDS[zone] or {}) do
    if named(C_Map.GetMapInfo(id), zone) then
      found = id
      break
    end
  end
  found = found or searchTree(zone)
  resolved[zone] = found
  return found
end

-- A made-up spot somewhere in the middle of the zone, for locate().
local function spotIn(zone)
  local mapId = mapIdFor(zone)
  if not mapId then return nil end
  return { mapId = mapId, x = 0.3 + 0.4 * math.random(), y = 0.3 + 0.4 * math.random() }
end

local net
local ticker
local members
-- Your Member id, whose entries the React button reacts to.
local yourId

-- The GUID of member i's Character j.
local function guidFor(i, j)
  return ("Player-0-Sim%d-%d"):format(i, j)
end

local function character(i, j, spec, yourLevel)
  return {
    guid = guidFor(i, j), name = spec.name, classFilename = spec.classFilename,
    level = math.max(1, yourLevel + spec.levelOffset), xp = 300 * j, maxXp = 1000 + 200 * i,
    zone = spec.zone, deaths = i + j,
  }
end

-- Plays each Character at its time, oldest first, ending on the one being
-- played now.
local function playHistory(client, i, spec, yourLevel, now)
  local order = {}
  for j = #spec.characters, 1, -1 do order[#order + 1] = j end
  table.sort(order, function(a, b)
    return (spec.characters[a].ago or 0) > (spec.characters[b].ago or 0)
  end)
  for _, j in ipairs(order) do
    net.clock = now - (spec.characters[j].ago or 0)
    client.characters[j] = character(i, j, spec.characters[j], yourLevel)
    client.current = j
    client.character = client.characters[j]
    client:move(spotIn(client.character.zone))
    if client.core then client:play() else client:login() end
  end
  net.clock = now
  if spec.main then client.core:setMain(guidFor(i, spec.main)) end
end

-- Four weeks of made-up Play times for the When tab: each Member has
-- their own evening hours (UTC) and plays most weeks, plus weekend
-- afternoons now and then.
local function playTimesHistory(i, now)
  local PlayTimes = ns.PlayTimes
  local current = PlayTimes.week(now)
  local weeks = {}
  for age = 0, PlayTimes.WEEKS - 1 do
    local week = current - age
    local slots = {}
    for day = 0, 6 do
      for hour = 0, 23 do
        local evening = day < 5 and hour >= 17 + i and hour <= 20 + i
        local weekend = day >= 5 and hour >= 12 + i and hour <= 15 + i
        if (evening and (week + day + i) % 3 ~= 0) or (weekend and (week + i) % 2 == 0) then
          slots[day * 24 + hour + 1] = 20 * 60
        end
      end
    end
    weeks[week] = slots
  end
  return { since = now - 30 * 24 * 60 * 60, weeks = weeks }
end

-- Starts the simulated Members. Returns true, or nil and "running" or
-- "notAlone".
function Sim.start(core)
  if net then return nil, "running" end
  local crew = core:crew()
  if not crew or crew.leaving or not crew.alone then return nil, "notAlone" end

  local now = GetServerTime()
  local own = core:rows()[1]
  local yourLevel = own and own.level or 10
  net = ns.FakeNet.new({ clock = now, maxLevel = GetMaxLevelForPlayerExpansion() })
  local you = net:attach(core)
  yourId = core.ledger:memberId()
  ns.ChannelLink.onSend = function(message) net:broadcast(you, message) end
  members = {}
  local current = members
  for i, spec in ipairs(MEMBERS) do
    local client = net:add(spec.name, { db = { playTimes = playTimesHistory(i, now) } })
    client.characters = {}
    playHistory(client, i, spec, yourLevel, now)
    client:join(crew.code)
    members[i] = client
    if spec.offline then
      C_Timer.After(LOGOUT_AFTER, function()
        if members == current and client.core then client:logout() end
      end)
    end
  end
  ticker = C_Timer.NewTicker(1, function() net:step(GetServerTime()) end)
  ns.Console.open(core)
  return true
end

-- One online simulated Member dings. Returns their Character's name, or nil.
function Sim.ding()
  if not net then return nil end
  local online = {}
  for _, client in ipairs(members) do
    if client.core then online[#online + 1] = client end
  end
  if #online == 0 then return nil end
  local client = online[math.random(#online)]
  client:play({ level = client.character.level + 1, xp = 0 })
  return client.character.name
end

function Sim.isRunning()
  return net ~= nil
end

-- What the console shows per simulated Member: name, online, and the
-- Character being played.
function Sim.members()
  local list = {}
  for i, client in ipairs(members or {}) do
    list[i] = { name = client.name, online = client.core ~= nil, character = client.character }
  end
  return list
end

local function otherZone(current)
  local zone
  repeat zone = ZONES[math.random(#ZONES)] until zone ~= current
  return zone
end

-- Reacts to your newest Feed entry the client can still react to.
local function reactToYou(client, you)
  for _, day in ipairs(client.core:feed().days) do
    for _, entry in ipairs(day.entries) do
      if entry.memberId == you and entry.canReact and not entry.reacted then
        return client.core:react(entry.key)
      end
    end
  end
  return false
end

-- Test Hand-me-downs, as links the way the game hands them out: one
-- plain, one with an enchant, one with a scaling random suffix.
local TEST_ITEMS = {
  { link = "|cff1eff00|Hitem:5191::::::::18:::::::|h[Cruel Barb]|h|r", level = 19 },
  { link = "|cff1eff00|Hitem:2042:1897:::::::20:::::::|h[Staff of Westfall]|h|r", level = 18 },
  { link = "|cff1eff00|Hitem:15210::::::-19:1238425:30:::::::|h[Raider Shortsword of the Monkey]|h|r", level = 15 },
}

-- Offers a test Hand-me-down to the Crew.
local function offer(client, i)
  local item = TEST_ITEMS[(i - 1) % #TEST_ITEMS + 1]
  return client.core:postHandMeDown(item.link, item.level)
end

-- Claims your newest Hand-me-down the client hasn't claimed yet.
local function claimYours(client, you)
  for _, row in ipairs(client.core:handMeDowns().crew) do
    if row.ownerId == you and row.canClaim then
      return client.core:claimHandMeDown(row.ownerId, row.id)
    end
  end
  return false
end

-- What each console button does to a simulated Member's client.
local ACTIONS = {
  ding = function(client) client:play({ level = client.character.level + 1, xp = 0 }) end,
  xp = function(client)
    local c = client.character
    client:play({ xp = math.min(c.maxXp - 1, c.xp + math.floor(c.maxXp / 4)) })
  end,
  die = function(client) client:play({ deaths = (client.character.deaths or 0) + 1 }) end,
  zone = function(client)
    local zone = otherZone(client.character.zone)
    client:move(spotIn(zone))
    client:play({ zone = zone })
  end,
  max = function(client) client:play({ level = net.maxLevel, xp = 0 }) end,
  -- Switches to the Member's next Character, as logging in on an Alt would.
  alt = function(client)
    client.current = client.current % #client.characters + 1
    client.character = client.characters[client.current]
    client:move(spotIn(client.character.zone))
    client:play()
  end,
  react = function(client) reactToYou(client, yourId) end,
  offer = function(client, i) offer(client, i) end,
  claim = function(client) claimYours(client, yourId) end,
  online = function(client)
    if client.core then client:logout() else client:login() end
  end,
}

-- Makes simulated Member i do action (a key of ACTIONS). Online-only
-- actions do nothing while they're logged out. Returns true if it did
-- something.
function Sim.act(i, action)
  local client = members and members[i]
  if not client or not ACTIONS[action] then return false end
  if action ~= "online" and not client.core then return false end
  ACTIONS[action](client, i)
  return true
end

-- How long after Sim.away an offline Member who played logs out again.
local AWAY_LOGOUT_AFTER = 5

local function levelUp(client, levels)
  return { level = math.min(net.maxLevel, client.character.level + levels), xp = 0 }
end

local function playCharacter(client, j)
  client.current = j
  client.character = client.characters[j]
  client:play()
end

-- What each simulated Member gets up to while you're away, by index.
local AWAY = {
  -- Rolls a new Character and plays it a little, then dings and dies on
  -- the one they were on.
  function(client, i)
    local was = client.current
    local j
    for k, c in ipairs(client.characters) do
      if c.name == "Simonetta" then j = k end
    end
    if not j then
      j = #client.characters + 1
      client.characters[j] = {
        guid = guidFor(i, j), name = "Simonetta", classFilename = "WARLOCK",
        level = 1, xp = 0, maxXp = 400, zone = "Elwynn Forest", deaths = 0,
      }
    end
    playCharacter(client, j)
    client:play(levelUp(client, 4))
    playCharacter(client, was)
    client:play(levelUp(client, 3))
    client:play({ deaths = (client.character.deaths or 0) + 2 })
  end,
  -- Dings and dies on the one they're on, then dings on the other.
  function(client)
    client:play(levelUp(client, 2))
    client:play({ deaths = (client.character.deaths or 0) + 1 })
    playCharacter(client, client.current % #client.characters + 1)
    client:play(levelUp(client, 1))
  end,
  -- Reaches max level.
  function(client)
    client:play({ level = net.maxLevel, xp = 0 })
  end,
}

-- Plays out a stretch of you being away: core goes back to how it is
-- right after logging in, so what happens next isn't announced, then each
-- simulated Member plays (logging in first if offline, and out again
-- after). Once sync settles, Core sends While you were away as on a real
-- login. Returns true, or nil and "notRunning".
function Sim.away(core)
  if not net then return nil, "notRunning" end
  local log = core.log
  log.settle:restart()
  if core.linkUp then log:linkUp() end
  local current = members
  for i, client in ipairs(members) do
    local wasOffline = not client.core
    if wasOffline then client:login() end
    AWAY[i](client, i)
    reactToYou(client, core.ledger:memberId())
    if wasOffline then
      C_Timer.After(AWAY_LOGOUT_AFTER, function()
        if members == current and client.core then client:logout() end
      end)
    end
  end
  return true
end

-- The first simulated Member online dies as many times as the Crew needs
-- to reach its next Crew deaths goal, so the goal's Feed entry and toast
-- show. Returns the rung, or nil and "notRunning" or "nobodyOnline".
function Sim.goal(core)
  if not net then return nil, "notRunning" end
  local client
  for _, member in ipairs(members) do
    if member.core then client = client or member end
  end
  if not client then return nil, "nobodyOnline" end
  for _, goal in ipairs(core:goals()) do
    if goal.track == "deaths" then
      client:play({ deaths = (client.character.deaths or 0) + goal.goal - goal.value })
      return goal.rung
    end
  end
end

-- Logs the simulated Members out; you see them go offline.
function Sim.stop()
  if not net then return end
  for _, client in ipairs(members) do
    if client.core then client:logout() end
  end
  net:step(GetServerTime())
  ticker:Cancel()
  ns.ChannelLink.onSend = nil
  net, ticker, members = nil, nil, nil
end

-- Console: the dev window. Watching starts the first time it opens, by
-- wrapping the real Core's link, listener and incoming calls, and goes on
-- until a /reload.

local Console = {}
ns.Console = Console

local Skin = ns.Skin

local WIDTH = 760
local HEIGHT = 480
local INSET = 12
local ROW_HEIGHT = 28
local BUTTON_WIDTH = 50
local MAX_LINES = 1000

local SENT = "ffd14a"
local RECEIVED = "70e370"
local EVENT = "8fb6ff"
local LINK = "c0a0ff"
local DIM = "8c8a99"

-- The console buttons on each simulated Member's row, left to right.
local BUTTONS = {
  { "ding", "Ding" }, { "xp", "XP" }, { "die", "Die" }, { "zone", "Zone" },
  { "alt", "Alt" }, { "max", "Max" }, { "react", "React" }, { "offer", "Offer" },
  { "claim", "Claim" }, { "online", "Log out" },
}

local frame
local watched
local showChanged = false

local function color(hex, text)
  return "|cff" .. hex .. text .. "|r"
end

local function log(text)
  if not frame then return end
  frame.log:AddMessage(color(DIM, date("%H:%M:%S")) .. "  " .. text)
end

-- A Member id as a name: you, a simulated Member, or whoever the panel
-- shows for it.
local function nameOf(id)
  if id == watched.ledger:memberId() then return "you" end
  for _, client in ipairs(members or {}) do
    if client.memberId == id then return client.name end
  end
  for _, row in ipairs(watched:rows()) do
    if row.memberId == id then return row.displayName or row.name end
  end
  return id
end

-- A record in one line: who, and the Character they played last.
local function describeRecord(record)
  local latest
  for _, c in pairs(record.characters or {}) do
    if not latest or (c.lastPlayed or 0) > (latest.lastPlayed or 0) then latest = c end
  end
  local who = record.displayName or nameOf(record.id)
  if not latest then return who end
  return ("%s: %s L%s %s, %s deaths"):format(who, latest.name, latest.level, latest.zone or "?", latest.deaths or 0)
end

-- A wire message in one line, and the Member id that sent it.
local function describe(message)
  local decoded, reason = ns.Codec.decode(message)
  if type(decoded) ~= "table" then return color(DIM, "undecodable (" .. tostring(reason) .. ")") end
  if decoded.type == "DIGEST" then
    local n = 0
    for _ in pairs(decoded.versions or {}) do n = n + 1 end
    return ("DIGEST %d version%s"):format(n, n == 1 and "" or "s"), decoded.from
  elseif decoded.type == "DATA" then
    local parts = {}
    for _, record in ipairs(decoded.records or {}) do parts[#parts + 1] = describeRecord(record) end
    return "DATA " .. table.concat(parts, "; "), decoded.from
  end
  return tostring(decoded.type), decoded.from
end

local function onEvent(event, arg)
  if event == "changed" then
    if showChanged then log(color(DIM, "changed")) end
  elseif event == "feedEntry" then
    log(color(EVENT, "feed  ") .. arg.text)
  elseif event == "reaction" then
    log(color(EVENT, "reaction  ") .. arg.text)
  elseif event == "handMeDown" then
    log(color(EVENT, "hand-me-down  ") .. arg.text)
  elseif event == "awaySummary" then
    log(color(EVENT, "away summary  ") .. tostring(arg.count) .. " entries from " .. #arg.members .. " Members")
  else
    log(color(EVENT, event) .. (arg ~= nil and "  " .. tostring(arg) or ""))
  end
end

-- Wraps the Core's ports on the instance, so every message and event also
-- reaches the log. Your own messages echoed back by the channel are left
-- out: they show once, as sent.
local function watch(core)
  if watched then return end
  watched = core

  local link = core.link
  core.link = {
    send = function(message)
      log(color(SENT, "-> sent  ") .. (describe(message)))
      return link.send(message)
    end,
  }

  local listener = core.listener
  core.listener = function(event, ...)
    onEvent(event, ...)
    return listener(event, ...)
  end

  local received, up, down, gone = core.received, core.up, core.down, core.gone
  function core.received(self, message)
    local text, from = describe(message)
    if from ~= self.ledger:memberId() then
      log(color(RECEIVED, "<- " .. (from and nameOf(from) or "?") .. "  ") .. text)
    end
    return received(self, message)
  end
  function core.up(self)
    log(color(LINK, "link up"))
    return up(self)
  end
  function core.down(self)
    log(color(LINK, "link down"))
    return down(self)
  end
  function core.gone(self, name)
    log(color(LINK, "gone  ") .. tostring(name))
    return gone(self, name)
  end
end

local function refreshMembers()
  local list = Sim.members()
  local running = Sim.isRunning()
  frame.headerRight:SetText(running and "sim running" or "sim off")
  frame.start:SetEnabled(not running)
  frame.start:SetAlpha(running and 0.4 or 1)
  frame.stop:SetEnabled(running)
  frame.stop:SetAlpha(running and 1 or 0.4)
  frame.away:SetEnabled(running)
  frame.away:SetAlpha(running and 1 or 0.4)
  frame.empty:SetShown(not running)
  for i, row in ipairs(frame.rows) do
    local member = list[i]
    row:SetShown(member ~= nil)
    if member then
      local c = member.character
      local state = member.online and color("70e370", "online") or color(DIM, "offline")
      row.label:SetText(("%s  %s\n%s L%d %s, %d xp, %d deaths"):format(
        member.name, state, c.name, c.level, c.zone, c.xp, c.deaths or 0))
      for _, button in ipairs(row.buttons) do
        if button.action == "online" then
          button:SetText(member.online and "Log out" or "Log in")
        else
          button:SetEnabled(member.online)
          button:SetAlpha(member.online and 1 or 0.4)
        end
      end
    end
  end
end

local function memberRow(i)
  local row = CreateFrame("Frame", nil, frame)
  row:SetHeight(ROW_HEIGHT)
  row:SetPoint("TOPLEFT", INSET, -(Skin.HEADER_HEIGHT + 44 + (i - 1) * (ROW_HEIGHT + 4)))
  row:SetPoint("RIGHT", -INSET, 0)
  row.buttons = {}
  local anchor
  for b = #BUTTONS, 1, -1 do
    local action, text = BUTTONS[b][1], BUTTONS[b][2]
    local button = Skin.button(row, text, function()
      if Sim.act(i, action) then
        local member = Sim.members()[i]
        log(color(DIM, ("sim  %s: %s"):format(member.name, action)))
      end
      refreshMembers()
    end)
    button:SetSize(action == "online" and 64 or BUTTON_WIDTH, 22)
    if anchor then button:SetPoint("RIGHT", anchor, "LEFT", -4, 0) else button:SetPoint("RIGHT", 0, 0) end
    button.action = action
    anchor = button
    row.buttons[#row.buttons + 1] = button
  end
  -- Cut short with "..." rather than run under the buttons.
  row.label = Skin.label(row, "small", Skin.TEXT)
  row.label:SetPoint("TOPLEFT", 0, 0)
  row.label:SetPoint("BOTTOMLEFT", 0, 0)
  row.label:SetPoint("RIGHT", anchor, "LEFT", -8, 0)
  return row
end

local function create()
  frame = Skin.window("BFFDevConsole", WIDTH, "BFF dev console")
  frame:SetHeight(HEIGHT)
  frame:SetPoint("CENTER", 200, 0)

  local top = -(Skin.HEADER_HEIGHT + 10)
  frame.start = Skin.button(frame, "Start sim", function()
    local ok, reason = Sim.start(watched)
    if not ok then
      log(color(DIM, reason == "notAlone"
        and "the sim needs a Crew no one else is in yet: /bff leave, then /bff start"
        or "the sim is already running"))
    end
    refreshMembers()
  end, true)
  frame.start:SetPoint("TOPLEFT", INSET, top)
  frame.stop = Skin.button(frame, "Stop sim", function()
    Sim.stop()
    refreshMembers()
  end)
  frame.stop:SetPoint("LEFT", frame.start, "RIGHT", 6, 0)
  local clear = Skin.button(frame, "Clear log", function() frame.log:Clear() end)
  clear:SetPoint("LEFT", frame.stop, "RIGHT", 6, 0)
  frame.away = Skin.button(frame, "Away", function()
    if not Sim.away(watched) then return end
    log(color(DIM, watched:isAwayPopupOn()
      and "sim  you were away: the popup shows once sync settles (about 10 s)"
      or "sim  you were away, but the popup is off in Settings"))
  end)
  frame.away:SetPoint("LEFT", clear, "RIGHT", 6, 0)
  frame.goal = Skin.button(frame, "Goal", function()
    local rung, reason = Sim.goal(watched)
    if rung then
      log(color(DIM, ("sim  the Crew dies its way to %d deaths"):format(rung)))
    elseif reason == "nobodyOnline" then
      log(color(DIM, "sim  log a simulated Member in first"))
    end
  end)
  frame.goal:SetPoint("LEFT", frame.away, "RIGHT", 6, 0)
  local changed = Skin.checkbox(frame, "Log every \"changed\"", function(self)
    showChanged = self:GetChecked()
  end)
  changed:SetPoint("LEFT", frame.goal, "RIGHT", 12, 0)

  frame.empty = Skin.label(frame, "small", Skin.MUTED)
  frame.empty:SetPoint("TOPLEFT", INSET, top - 38)
  frame.empty:SetText("The sim is off. The log still shows real traffic on your Crew's channel.")

  frame.rows = {}
  for i = 1, #MEMBERS do frame.rows[i] = memberRow(i) end

  local logTop = Skin.HEADER_HEIGHT + 44 + #MEMBERS * (ROW_HEIGHT + 4) + 8
  local plate = CreateFrame("Frame", nil, frame)
  plate:SetPoint("TOPLEFT", INSET, -logTop)
  plate:SetPoint("BOTTOMRIGHT", -INSET, INSET)
  Skin.fill(plate, { 0, 0, 0, 0.35 })
  Skin.border(plate, Skin.BORDER)

  local messages = CreateFrame("ScrollingMessageFrame", nil, plate)
  messages:SetPoint("TOPLEFT", 6, -6)
  messages:SetPoint("BOTTOMRIGHT", -6, 6)
  messages:SetFontObject(Skin.fonts.small)
  messages:SetJustifyH("LEFT")
  messages:SetFading(false)
  messages:SetMaxLines(MAX_LINES)
  messages:EnableMouseWheel(true)
  messages:SetScript("OnMouseWheel", function(self, delta)
    if delta > 0 then self:ScrollUp() else self:ScrollDown() end
  end)
  frame.log = messages

  -- The simulated Members' rows follow their state, whoever changed it.
  local elapsedSince = 0
  frame:SetScript("OnUpdate", function(_, elapsed)
    elapsedSince = elapsedSince + elapsed
    if elapsedSince >= 0.5 then
      elapsedSince = 0
      refreshMembers()
    end
  end)
end

-- Opens the console, and starts watching core the first time.
function Console.open(core)
  if not frame then create() end
  watch(core)
  refreshMembers()
  frame:Show()
end

function Console.toggle(core)
  if frame and frame:IsShown() then frame:Hide() else Console.open(core) end
end

SLASH_BFFDEV1 = "/bffdev"
-- Sample toasts, one of each kind, for /bffdev toast.
local SAMPLE_TOASTS = {
  { kind = "ding", text = "Simone dinged 24" },
  { kind = "death", text = "Simbad died 2 times" },
  { kind = "maxLevel", text = "Simba reached max level!" },
  { kind = "newCharacter", text = "Simone has a new Character: Simonette (Priest)" },
  { kind = "joined", text = "Simbad joined the Crew" },
  { kind = "left", text = "Simba left the Crew" },
  { kind = "goal", text = "The Crew reached 300 Crew levels!" },
  { kind = "claimed", text = "Simone claimed [Cruel Barb] for Simonette", opens = "handMeDowns" },
  { kind = "given", text = "Simbad sent you [Staff of Westfall]. Check Simonette's mailbox.", opens = "handMeDowns" },
  { kind = "gave", text = "Simbad gave Simone [Staff of Westfall]" },
}

-- /bffdev toggles the console; /bffdev toast [n] shows n sample toasts
-- (default 1), straight to the toasts and not through Core.
SlashCmdList.BFFDEV = function(input)
  if not ns.core then return end
  local command, count = (input or ""):match("^%s*(%S*)%s*(%d*)")
  if command == "toast" then
    for i = 1, tonumber(count) or 1 do
      ns.Toasts.show(SAMPLE_TOASTS[(i - 1) % #SAMPLE_TOASTS + 1])
    end
    return
  end
  Console.toggle(ns.core)
end
