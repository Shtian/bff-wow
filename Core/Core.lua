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

-- For the UI's wording.
Core.CAN_PLAY_LEVELS = ns.Roster.CAN_PLAY
-- A merged Reaction toast's text, from the names of who reacted and the
-- phrase in reaction news: "Bob and Cleo cheered your ding to 30".
Core.reactionText = ns.Reactions.text
Core.HIDE_AFTER_DAYS = ns.Roster.HIDE_AFTER / (24 * 60 * 60)

-- deps: db, now(), random(), link (with send(string)), listener(event, ...),
-- initialLogin, maxLevel and utcOffset (seconds local time is
-- ahead of server time, for the Feed's days; default 0).
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
    initialLogin = deps.initialLogin == true,
    maxLevel = deps.maxLevel,
    ledger = ns.Ledger.new(deps.db, deps.now, deps.random, deps.initialLogin == true),
    utcOffset = type(deps.utcOffset) == "number" and deps.utcOffset or 0,
    linkUp = false,
  }, Core)
  self.log = ns.Feed.new(deps.db, self.ledger, deps.now, deps.maxLevel, self.initialLogin)
  self.crewGoals = ns.Goals.new(deps.db, self.ledger, deps.now, deps.maxLevel)
  -- Every message carries the sender's Member id.
  self.gossip = ns.Gossip.new(self.ledger, deps.now, deps.random, function(message)
    message.from = self.ledger:memberId()
    self.link.send(ns.Codec.encode(message))
  end)
  self.gossip:setPaused(self:isPaused())
  self.playTracker = ns.PlayTimes.new(deps.db, deps.now)
  -- The own record's Play times may be out of date until the first tick.
  self.playTimesDue = true
  self.online = ns.Roster.online(self.ledger, deps.now())
  return self
end

-- Gossip's link is up only while in a Crew. Settling after login starts
-- once it is, and starts over if it goes down first.
local function updateLink(self)
  local up = self.linkUp and self.db.crew ~= nil
  if up then self.log:linkUp() else self.log:linkDown() end
  if up then self.crewGoals:linkUp() else self.crewGoals:linkDown() end
  self.gossip:setLink(up)
end

-- New Feed entries from other Members, and new Reactions to your own, each
-- make a chat line, a toast or both once settled, if either is on, and are
-- seen once they have.
local function announce(self, entries, reactions)
  if not (self.log:isSettled() and (self:isChatLinesOn() or self:isToastsOn())) then return end
  for _, entry in ipairs(entries) do
    self.log:markSeen(entry)
    self.listener("feedEntry", self.log:describe(entry))
  end
  for _, item in ipairs(reactions or {}) do
    self.log:markSeen(item.reaction)
    self.listener("reaction", self.log:news(item))
  end
end

-- A record changed: Crew goals newly reached each make a Crew-wide Feed
-- entry, announced like any other. Quiet when the Members counted changed
-- rather than their progress: those rungs are only recorded.
local function checkGoals(self, quiet)
  if not self.db.crew then return end
  local reached = self.crewGoals:check(quiet)
  if #reached > 0 then announce(self, self.log:goalsReached(reached)) end
end

-- Writes the Play times summary into the own record, if it may have
-- changed and the record exists. Returns true if the record changed.
local function writePlayTimes(self)
  if not (self.playTimesDue and self.ledger:own()) then return false end
  self.playTimesDue = false
  return self.ledger:setPlayTimes(self.playTracker:summary())
end

-- Play times changing alone rides the next send. Along with another
-- change, that change's send and changed event cover it.
local function sharePlayTimes(self, otherChange)
  if writePlayTimes(self) and not otherChange then
    self.gossip:ownChanged("later")
    self.listener("changed")
  end
end

-- The own record's display name or left flag changed: it goes out now.
local function sendOwnNow(self)
  self.gossip:ownChanged("now")
end

-- The current state of the Character being played, from Snapshot: guid,
-- name, classFilename, level, xp, maxXp, zone and deaths.
function Core:updateOwn(character)
  local changed, before = self.ledger:updateOwn(character)
  -- The first report after login brings the Play times up to date.
  sharePlayTimes(self, changed)
  if changed then
    -- Your own events go into the Feed only while in a Crew.
    if self.db.crew then self.log:ownChanged(before, character.guid) end
    self.gossip:ownChanged(ns.Gossip.urgency(before, character))
    checkGoals(self)
    self.listener("changed")
  end
end

-- The panel's rows, ready to render, sorted by order: "online" (default),
-- "level" or "name". Your own row comes first. Each row is a Member whose
-- Characters weren't all unseen for 30 days: memberId, displayName, own,
-- online, lastSeen, sinceSeen (seconds since lastSeen), onAlt (playing a Character other than the Main),
-- mainSet (the Main was chosen, rather than the most recently played),
-- altsCanPlay, via (display name of the Member whose message brought their
-- record, if not their own) and alts, plus the shown Character: the one
-- being played while online, else the Main. A Character, shown or alt, has
-- guid, name, classFilename, level, xp, maxXp, zone, deaths, lastPlayed,
-- sinceSeen, playing (being played right now), main and canPlay (within
-- Core.CAN_PLAY_LEVELS of the Character you play).
function Core:rows(order)
  return ns.Roster.rows(self.ledger, self.now(), order)
end

-- Counts for the title and minimap button: online, members, canPlay (online
-- Members whose Character being played can play with you) and hidden
-- (Characters unseen for Core.HIDE_AFTER_DAYS).
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

-- Sync has settled after an initial login: While you were away goes out
-- if the popup is on and there's anything unseen, which is then seen. The
-- summary is { members, count, noticed }: a Member has memberId,
-- displayName, main and classFilename (their Main), time (latest
-- activity), characters (a row per Character with events, the Main's
-- first: name, main, from, level, deaths, new, maxLevel, and the cheer and
-- respects buttons, each nil when it doesn't apply), highlights ({ kind,
-- text } for max level, joined and left) and welcome. A button is { key,
-- reacted }, the key for react(). noticed is Your Crew noticed, newest
-- first: { text, reaction, time } per own entry with unseen Reactions.
local function awaySummary(self)
  if not self:isAwayPopupOn() then return end
  local summary = self.log:takeSummary()
  if not summary then return end
  self.listener("awaySummary", summary)
  self.listener("changed")
end

-- Called once a second. Core decides what is due.
function Core:tick()
  -- Counts the second played.
  if self.playTracker:tick() then self.playTimesDue = true end
  sharePlayTimes(self)
  self.gossip:tick()
  if self.log:tick() then awaySummary(self) end
  if self.db.crew and self.crewGoals:tick() then self.listener("changed") end
  checkOnline(self)
end

-- The Goals tab: a row per Crew goal track (Crew levels, Everyone at level
-- N, Crew deaths): { track, title, rung (the next one, nil when complete),
-- value and goal (the progress bar, value out of goal; nil when complete),
-- complete, last ({ rung, time }: the highest reached, or nil) }. For
-- Everyone at level N, value counts the Members with a Character at the
-- next rung, out of every Member. No Member is named.
function Core:goals()
  return self.crewGoals:rows()
end

-- The Feed tab: { days = { { daysAgo, time, entries } }, unseen }, newest
-- first, where unseen counts others' entries and Reactions to your own not
-- yet shown. An entry has kind ("ding", "death", "newCharacter",
-- "maxLevel", "joined", "left" or "goal": a Crew goal reached, with no
-- memberId), time, memberId, guid (for Character
-- events), text, from (the level before a ding or max level), level, count
-- (deaths), own and seen (false while it has unseen Reactions). And for
-- Reactions: reaction ("cheer", "respects" or "welcome", nil for left),
-- key (for react()), reactors ({ memberId, name, you }, in the order they
-- reacted), reacted (you have) and canReact (not yours, and it has a key).
function Core:feed()
  return self.log:view(self.utcOffset)
end

-- The When tab, in the viewer's local time: grid (7 days from Monday, each
-- 24 hours from 00:00), max (the most a cell can hold), empty (every cell
-- 0), and the rules for the wording: weeks (how many are kept), usually
-- (weeks played to usually play) and minutes (to count as played). Without
-- memberId, the Crew: each cell counts the Members your Roster shows who
-- usually play then, out of max. With one, that
-- Member's weeks played (0–4) per hour, displayName, collectingSince (when
-- they started, while under a week ago) and noData (their BFF shares no
-- Play times); nil for a Member the Roster doesn't show.
function Core:playTimes(memberId)
  local now = self.now()
  local PlayTimes = ns.PlayTimes
  local rows = ns.Roster.rows(self.ledger, now)
  local function view(values, max)
    return {
      grid = PlayTimes.grid(values, self.utcOffset),
      max = max,
      empty = PlayTimes.isEmpty(values),
      weeks = PlayTimes.WEEKS,
      usually = PlayTimes.USUALLY,
      minutes = PlayTimes.PLAYED_MINUTES,
    }
  end

  if memberId == nil then
    local summaries = {}
    for _, row in ipairs(rows) do
      summaries[#summaries + 1] = self.ledger:record(row.memberId).playTimes
    end
    return view(PlayTimes.usuallyPlaying(summaries, now), #rows)
  end

  for _, row in ipairs(rows) do
    if row.memberId == memberId then
      local summary = self.ledger:record(memberId).playTimes
      local since = summary and summary.since
      local result = view(PlayTimes.weeksPlayed(summary, now), PlayTimes.WEEKS)
      result.memberId = memberId
      result.displayName = row.displayName
      result.own = row.own == true
      result.noData = summary == nil
      result.collectingSince = since and now - since < PlayTimes.WEEK and since or nil
      return result
    end
  end
  return nil
end

-- How many of others' Feed entries, and Reactions to your own, haven't
-- been shown yet.
function Core:unseen()
  return self.log:unseen()
end

-- Reacts to someone else's Feed entry, with a key from feed() or the
-- summary. It goes into your record and out with your next DATA, so it
-- works in combat and offline. Ignores your own entries, Removed Members,
-- entries that can't be reacted to, and those you already reacted to.
-- Returns true, or false and "reacted" when you already had.
function Core:react(key)
  local reason
  key, reason = self.log:react(key)
  if not key then return false, reason end
  self.ledger:addReaction(key)
  self.gossip:ownChanged("now")
  self.listener("changed")
  return true
end

-- The Feed tab was opened: every entry and Reaction is seen.
function Core:feedSeen()
  if self.log:markAllSeen() then self.listener("changed") end
end

-- Chat message for live events: on by default.
function Core:setChatLines(on)
  local off = not on or nil
  if off == self.db.chatLinesOff then return end
  self.db.chatLinesOff = off
  self.listener("changed")
end

function Core:isChatLinesOn()
  return not self.db.chatLinesOff
end

-- Show While you were away on login: on by default.
function Core:setAwayPopup(on)
  local off = not on or nil
  if off == self.db.awayPopupOff then return end
  self.db.awayPopupOff = off
  self.listener("changed")
end

function Core:isAwayPopupOn()
  return not self.db.awayPopupOff
end

-- Toasts for live events: on by default.
function Core:setToasts(on)
  local off = not on or nil
  if off == self.db.toastsOff then return end
  self.db.toastsOff = off
  self.listener("changed")
end

function Core:isToastsOn()
  return not self.db.toastsOff
end

-- The toast sound: the name UI plays it by, or "none". Nil goes back to
-- the default.
Core.DEFAULT_TOAST_SOUND = "UI_BNET_TOAST"

function Core:setToastSound(name)
  if name == Core.DEFAULT_TOAST_SOUND then name = nil end
  if name == self.db.toastSound then return end
  self.db.toastSound = name
  self.listener("changed")
end

function Core:toastSound()
  return self.db.toastSound or Core.DEFAULT_TOAST_SOUND
end

-- Where toasts appear: the centre of the first toast, as x and y from the
-- screen's bottom left. Nil x goes back to the default, where this returns
-- nil.
function Core:setToastPosition(x, y)
  local saved = self.db.toastPosition
  if x == (saved and saved.x) and y == (saved and saved.y) then return end
  self.db.toastPosition = x and { x = x, y = y } or nil
  self.listener("changed")
end

function Core:toastPosition()
  local position = self.db.toastPosition
  if not position then return nil end
  return position.x, position.y
end

-- Your display name, or nil until one is set.
function Core:displayName()
  return self.ledger:displayName()
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

-- Joining (not starting) makes your own joined entry, for Welcomes.
local function enter(self, code, displayName, joining)
  self.ledger:writeOwn({ displayName = displayName, left = false, joinedAt = self.now() })
  sendOwnNow(self)
  self.crewGoals:clear()
  self.db.crew = { code = code }
  if joining then self.log:ownJoined() end
  self.listener("crewChanged")
  updateLink(self)
  return self:crew()
end

-- Starts a Crew with a new code. Returns crew(), or nil and "inCrew" or
-- "invalidName".
function Core:startCrew(displayName)
  if self.db.crew then return nil, "inCrew" end
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
  if not current then return enter(self, code, name, true) end

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
    self.listener("changed")
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
  if self.ledger:writeOwn({ main = guid or false }) then
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
  self.log:dropMember(id)
  self.online[id] = nil
  checkGoals(self, true)
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
  for id, member in self.ledger:removed() do
    removed[#removed + 1] = { memberId = id, displayName = member.displayName }
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
  paused = paused and true or nil
  if paused == self.db.paused then return end
  self.db.paused = paused
  self.gossip:setPaused(self:isPaused())
  self.listener("changed")
end

function Core:isPaused()
  return self.db.paused == true
end

-- The minimap button's saved table, handed to LibDBIcon, which keeps the
-- button's position in it. Account-wide, like every setting.
function Core:minimapIcon()
  self.db.minimap = self.db.minimap or {}
  return self.db.minimap
end

-- Show minimap button: on by default. LibDBIcon reads hide from the same
-- table.
function Core:setMinimapShown(shown)
  local hide = not shown or nil
  local icon = self:minimapIcon()
  if hide == icon.hide then return end
  icon.hide = hide
  self.listener("changed")
end

function Core:isMinimapShown()
  return not self:minimapIcon().hide
end

-- Hands the tombstone to the link, then forgets the Crew. Your own record
-- stays, so rejoining resumes where you left off. The Crew is forgotten
-- before sending, so a link that reacts to the send can't finish it twice.
local function finishLeaving(self)
  self.db.crew = nil
  updateLink(self)
  self.gossip:sendNow({ type = "DATA", records = { self.ledger:tombstone() } })
  self.ledger:forgetOthers()
  self.ledger:clearReactions()
  self.log:clear()
  self.crewGoals:clear()
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
  if self.linkUp then finishLeaving(self) else self.listener("changed") end
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
    local kept, before = self.ledger:merge(record, from)
    if kept then
      changed = true
      self.log:dataMerged()
      self.crewGoals:dataMerged()
      announce(self, self.log:recordChanged(before, record))
      -- A Member first seen, leaving or back counts or stops counting.
      if before == nil or (before.left == true) ~= (record.left == true) then checkGoals(self, true) end
    end
    if type(record) == "table" and type(record.id) == "string" and type(record.version) == "number" then
      self.gossip:recordSeen(record.id, record.version)
    end
  end
  if changed then checkGoals(self) end
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
