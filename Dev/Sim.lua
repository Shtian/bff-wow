-- Sim: /bff sim attaches a few simulated Members to your real Core through
-- FakeNet, so the panel can be tried without another Member online. Their
-- records are kept and relayed like real ones, so it only runs in a Crew
-- where no one else is known yet: start a test Crew for it. Also the dev
-- console (/bffdev, opened by /bff sim too): buttons that make each
-- simulated Member ding, die, move or log out, one that plays out a stretch
-- of you being away so While you were away shows, and a live log of what
-- your Core sends, receives and fires. Left out of releases; it lives here, not
-- in a file of its own, so the .toc (a shipped file) stays as it is.

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

local net
local ticker
local members

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
    if client.core then client:play() else client:login() end
  end
  net.clock = now
  if spec.main then client.core:setMain(guidFor(i, spec.main)) end
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
  ns.ChannelLink.onSend = function(message) net:broadcast(you, message) end
  members = {}
  local current = members
  for i, spec in ipairs(MEMBERS) do
    local client = net:add(spec.name)
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

-- What each console button does to a simulated Member's client.
local ACTIONS = {
  ding = function(client) client:play({ level = client.character.level + 1, xp = 0 }) end,
  xp = function(client)
    local c = client.character
    client:play({ xp = math.min(c.maxXp - 1, c.xp + math.floor(c.maxXp / 4)) })
  end,
  die = function(client) client:play({ deaths = (client.character.deaths or 0) + 1 }) end,
  zone = function(client) client:play({ zone = otherZone(client.character.zone) }) end,
  max = function(client) client:play({ level = net.maxLevel, xp = 0 }) end,
  -- Switches to the Member's next Character, as logging in on an Alt would.
  alt = function(client)
    client.current = client.current % #client.characters + 1
    client.character = client.characters[client.current]
    client:play()
  end,
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
  ACTIONS[action](client)
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
  log.settled, log.upSince, log.lastData = false, nil, nil
  if core.linkUp then log:linkUp() end
  local current = members
  for i, client in ipairs(members) do
    local wasOffline = not client.core
    if wasOffline then client:login() end
    AWAY[i](client, i)
    if wasOffline then
      C_Timer.After(AWAY_LOGOUT_AFTER, function()
        if members == current and client.core then client:logout() end
      end)
    end
  end
  return true
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

local WIDTH = 640
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
  { "alt", "Alt" }, { "max", "Max" }, { "online", "Log out" },
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
  local changed = Skin.checkbox(frame, "Log every \"changed\"", function(self)
    showChanged = self:GetChecked()
  end)
  changed:SetPoint("LEFT", frame.away, "RIGHT", 12, 0)

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
SlashCmdList.BFFDEV = function()
  if ns.core then Console.toggle(ns.core) end
end
