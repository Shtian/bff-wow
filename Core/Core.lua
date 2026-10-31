-- Core: everything BFF knows and decides, in pure Lua. It never touches the
-- game; App hands it the clock, randomness, the link and saved data.
-- See docs/design/code-structure.md.

local _, ns = ...

local Core = {}
Core.__index = Core
ns.Core = Core

local required = {
  db = "table",
  now = "function",
  random = "function",
  link = "table",
  listener = "function",
  maxLevel = "number",
}

-- deps: db, now(), random(), link (with send(string)), listener(event, ...),
-- receiveOnly, initialLogin and maxLevel.
function Core.new(deps)
  for name, kind in pairs(required) do
    if type(deps[name]) ~= kind then
      error(("Core.new: %s must be a %s"):format(name, kind), 2)
    end
  end
  if type(deps.link.send) ~= "function" then
    error("Core.new: link.send must be a function", 2)
  end

  local self = setmetatable({
    db = deps.db,
    now = deps.now,
    random = deps.random,
    link = deps.link,
    listener = deps.listener,
    receiveOnly = deps.receiveOnly == true,
    initialLogin = deps.initialLogin == true,
    maxLevel = deps.maxLevel,
    ledger = ns.Ledger.new(deps.db, deps.now, deps.random, deps.initialLogin == true),
    linkUp = false,
  }, Core)
  -- Every message carries the sender's Member id.
  self.gossip = ns.Gossip.new(self.ledger, deps.now, deps.random, function(message)
    message.from = self.ledger:memberId()
    self.link.send(ns.Codec.encode(message))
  end, self.receiveOnly)
  self.gossip:setPaused(self:isPaused())
  self.online = ns.Roster.online(self.ledger, deps.now())
  return self
end

-- Gossip's link is up only while in a Crew.
local function updateLink(self)
  self.gossip:setLink(self.linkUp and self.db.crew ~= nil)
end

-- The own record's display name or left flag changed: it goes out now.
local function sendOwnNow(self)
  self.gossip:ownChanged("now")
end

-- The current state of the Character being played, from Snapshot: guid,
-- name, classFilename, level, xp, maxXp, zone and deaths.
function Core:updateOwn(character)
  local changed, before = self.ledger:updateOwn(character)
  if changed then
    self.gossip:ownChanged(ns.Gossip.urgency(before, character))
    self.listener("changed")
  end
end

-- The panel's rows, ready to render, sorted by order: "online" (default),
-- "level" or "name". Your own row comes first. Each row is a Member whose
-- Characters weren't all unseen for 30 days: memberId, displayName, own,
-- online, lastSeen, onAlt (playing a Character other than the Main),
-- mainSet (the Main was chosen, rather than the most recently played),
-- altsCanPlay, via (display name of the Member the news came through, if
-- not them) and alts, plus the shown Character: the one being played while
-- online, else the Main. A Character, shown or alt, has guid, name,
-- classFilename, level, xp, maxXp, zone, deaths, lastPlayed, main and
-- canPlay (within 3 levels of the Character you play).
function Core:rows(order)
  return ns.Roster.rows(self.ledger, self.now(), order)
end

-- Counts for the title and minimap button: online, members, canPlay (online
-- Members whose Character being played can play with you) and hidden
-- (Characters unseen for 30 days).
function Core:summary()
  return ns.Roster.summary(self.ledger, self.now())
end

-- Whether someone went online or offline since last checked.
local function onlineChanged(self)
  local online = ns.Roster.online(self.ledger, self.now())
  local differs = false
  for id in pairs(online) do
    if not self.online[id] then differs = true end
  end
  for id in pairs(self.online) do
    if not online[id] then differs = true end
  end
  self.online = online
  return differs
end

-- Fires changed if someone went online or offline since last checked.
local function checkOnline(self)
  if onlineChanged(self) then self.listener("changed") end
end

-- Called once a second. Core decides what is due.
function Core:tick()
  self.gossip:tick()
  checkOnline(self)
end

-- Your display name, or nil until one is set.
function Core:displayName()
  return self.ledger:displayName()
end

function Core:isReceiveOnly()
  return self.receiveOnly
end

-- The Crew: code, channel and password, leaving while a leave hasn't
-- reached the link yet, and alone while no other Member is known. Nil when
-- not in a Crew.
function Core:crew()
  local saved = self.db.crew
  if not saved then return nil end
  local channel, password = ns.CrewCode.channel(saved.code)
  return {
    code = saved.code,
    channel = channel,
    password = password,
    leaving = saved.leaving,
    alone = not self.ledger:knowsOthers(),
  }
end

local MIN_NAME, MAX_NAME = 2, 16

-- The trimmed name, or nil if it isn't 2–16 UTF-8 characters.
local function validName(name)
  if type(name) ~= "string" then return nil end
  name = name:match("^%s*(.-)%s*$")
  -- Count every byte that doesn't continue a UTF-8 character.
  local length = #name:gsub("[\128-\191]", "")
  if length < MIN_NAME or length > MAX_NAME then return nil end
  return name
end

-- Without a name, keeps the one already set.
local function nameOrCurrent(self, displayName)
  if displayName == nil then return self.ledger:displayName() end
  return validName(displayName)
end

local function enter(self, code, displayName)
  self.ledger:writeOwn({ displayName = displayName, left = false })
  sendOwnNow(self)
  self.db.crew = { code = code }
  self.listener("crewChanged")
  updateLink(self)
  return self:crew()
end

-- Starts a Crew with a new code. Returns crew(), or nil and "inCrew",
-- "receiveOnly" or "invalidName".
function Core:startCrew(displayName)
  if self.db.crew then return nil, "inCrew" end
  if self.receiveOnly then return nil, "receiveOnly" end
  local name = nameOrCurrent(self, displayName)
  if not name then return nil, "invalidName" end
  return enter(self, ns.CrewCode.generate(self.random), name)
end

-- Joins the Crew a typed code names. Joining the Crew you're in does
-- nothing, and cancels a leave that hasn't finished. Returns crew(), or nil
-- and "invalidCode", "inCrew" or "invalidName".
function Core:joinCrew(code, displayName)
  code = ns.CrewCode.normalise(code)
  if not code then return nil, "invalidCode" end
  local current = self.db.crew
  if current and current.code ~= code then return nil, "inCrew" end
  local name = nameOrCurrent(self, displayName)
  if not name then return nil, "invalidName" end
  if not current then return enter(self, code, name) end

  if current.leaving then
    current.leaving = nil
    self.ledger:writeOwn({ displayName = name, left = false })
    sendOwnNow(self)
  end
  return self:crew()
end

-- Sets your display name. Returns true, or nil and "invalidName".
function Core:setDisplayName(displayName)
  local name = validName(displayName)
  if not name then return nil, "invalidName" end
  if name ~= self.ledger:displayName() then
    self.ledger:writeOwn({ displayName = name })
    sendOwnNow(self)
  end
  return true
end

-- Set as Main: one of your own Characters by GUID, or nil for the most
-- recently played. Returns true, or nil and "unknownCharacter".
function Core:setMain(guid)
  if guid ~= nil then
    local own = self.ledger:own()
    if not (own and type(guid) == "string" and own.characters[guid]) then
      return nil, "unknownCharacter"
    end
  end
  local before = self.ledger:version(self.ledger:memberId())
  self.ledger:writeOwn({ main = guid or false })
  if self.ledger:version(self.ledger:memberId()) ~= before then
    sendOwnNow(self)
    self.listener("changed")
  end
  return true
end

-- Remove: hides a Member from your own view only, and stops relaying them.
-- Returns true, or nil and "unknownMember".
function Core:removeMember(id)
  if not self.ledger:remove(id) then return nil, "unknownMember" end
  self.gossip:forget(id)
  self.online[id] = nil
  self.listener("changed")
  return true
end

-- Re-adds a removed Member: a DIGEST without them goes out, and whoever
-- holds them replies with DATA. Returns true, or nil and "unknownMember".
function Core:readdMember(id)
  if not self.ledger:readd(id) then return nil, "unknownMember" end
  self.gossip:askAround()
  self.listener("changed")
  return true
end

-- The removed Members, by display name: memberId and displayName.
function Core:removed()
  local removed = {}
  for id, displayName in self.ledger:removed() do
    removed[#removed + 1] = { memberId = id, displayName = type(displayName) == "string" and displayName or nil }
  end
  table.sort(removed, function(a, b)
    local x, y = (a.displayName or ""):lower(), (b.displayName or ""):lower()
    if x ~= y then return x < y end
    return a.memberId < b.memberId
  end)
  return removed
end

-- Pause sharing: send nothing, still receive, and appear offline. Kept
-- across reloads and logouts.
function Core:setPaused(paused)
  self.db.paused = paused and true or nil
  self.gossip:setPaused(self:isPaused())
end

function Core:isPaused()
  return self.db.paused == true
end

-- Hands the tombstone to the link, then forgets the Crew. Your own record
-- stays, so rejoining resumes where you left off. The Crew is forgotten
-- before sending, so a link that reacts to the send can't finish it twice.
local function finishLeaving(self)
  self.db.crew = nil
  updateLink(self)
  self.gossip:sendNow({ type = "DATA", records = { self.ledger:tombstone() } })
  self.ledger:forgetOthers()
  self.online = {}
  self.listener("crewChanged")
  self.listener("notice", "leftCrew")
end

-- Leaves the Crew: marks your record left, and finishes once the link is
-- up, even after a logout. Returns true, or nil and "noCrew".
function Core:leaveCrew()
  local crew = self.db.crew
  if not crew then return nil, "noCrew" end
  if crew.leaving then return true end
  crew.leaving = true
  self.ledger:writeOwn({ left = true })
  if self.linkUp then finishLeaving(self) end
  return true
end

-- The incoming half of the link port. Every up() sends a fresh DIGEST, plus
-- own DATA if the own record changed while the link was down.
function Core:up()
  self.linkUp = true
  if self.db.crew and self.db.crew.leaving then
    finishLeaving(self)
  else
    updateLink(self)
  end
end

function Core:down()
  self.linkUp = false
  updateLink(self)
end

-- A Character of this name left the channel, i.e. logged out: its Member
-- shows offline right away.
function Core:gone(name)
  if type(name) == "string" and self.ledger:wentAway(name) then checkOnline(self) end
end

local function dataReceived(self, records, from)
  local changed = false
  for _, record in ipairs(records) do
    if self.ledger:merge(record, from) then changed = true end
    if type(record) == "table" and type(record.id) == "string" and type(record.version) == "number" then
      self.gossip:recordSeen(record.id, record.version)
    end
  end
  return changed
end

-- A message from the link. Your own, echoed back by the channel, and
-- anything arriving outside a Crew are dropped.
function Core:received(message)
  if type(message) ~= "string" or not self.db.crew then return end
  local decoded, reason = ns.Codec.decode(message)
  if reason == "newer" then
    if not self.toldOutOfDate then
      self.toldOutOfDate = true
      self.listener("notice", "outOfDate")
    end
    return
  end
  if type(decoded) ~= "table" or type(decoded.from) ~= "string"
      or decoded.from == self.ledger:memberId() then
    return
  end

  self.ledger:heard(decoded.from)
  local changed = false
  if decoded.type == "DIGEST" and type(decoded.versions) == "table" then
    self.gossip:digestReceived(decoded.versions)
  elseif decoded.type == "DATA" and type(decoded.records) == "table" then
    changed = dataReceived(self, decoded.records, decoded.from)
  end
  if onlineChanged(self) or changed then self.listener("changed") end
end
