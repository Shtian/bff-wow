-- Feed: turns a record as it was and as it is now into Feed entries (ding,
-- death, new Character, max level, joined and left the Crew), and keeps the
-- account-wide log with its seen flags. A jump over skipped versions makes
-- at most one entry of each kind per Character, and the first sight of a
-- Member is a silent baseline, unless they joined the Crew after you. Also
-- knows when sync has settled after an initial login.
-- See docs/design/feed.md.

local _, ns = ...

local Feed = {}
Feed.__index = Feed
ns.Feed = Feed

local DAY = 24 * 60 * 60
-- Entries are kept this long, and at most this many.
local KEEP_FOR = 30 * DAY
local KEEP_MAX = 200
-- Settled after this long with no new DATA, or at most this long after the
-- link came up.
local QUIET_FOR = 10
local SETTLE_WITHIN = 30

-- For "a new Character: Jaina (Mage)". Core has no game strings.
local CLASS_NAMES = {
  DEATHKNIGHT = "Death Knight",
  DEMONHUNTER = "Demon Hunter",
}

local function className(classFilename)
  if not classFilename then return "?" end
  return CLASS_NAMES[classFilename] or classFilename:sub(1, 1) .. classFilename:sub(2):lower()
end

-- db is the whole saved table; Feed keeps `feed` (the log, oldest first)
-- and `feedJoins` (the joinedAt last seen per Member, so re-adding a
-- Member doesn't announce their join again). Only an initial login waits
-- for sync to settle.
function Feed.new(db, ledger, now, maxLevel, initialLogin)
  db.feed = db.feed or {}
  db.feedJoins = db.feedJoins or {}
  return setmetatable({
    db = db,
    ledger = ledger,
    now = now,
    maxLevel = maxLevel,
    settled = not initialLogin,
    -- When the link first came up in a Crew, and when DATA last changed
    -- something.
    upSince = nil,
    lastData = nil,
  }, Feed)
end

-- The Main's GUID: the Character set as Main, or the most recently played.
local function mainGuid(record)
  if record.main and record.characters[record.main] then return record.main end
  local main
  for guid, character in pairs(record.characters) do
    if not main or character.lastPlayed > main.lastPlayed
        or (character.lastPlayed == main.lastPlayed and guid < main.guid) then
      main = character
    end
  end
  return main and main.guid
end

local function memberName(record)
  if record.displayName then return record.displayName end
  local main = mainGuid(record)
  return main and record.characters[main].name or "Someone"
end

-- Who an event happened to: "Ana", "Ana's Alt Jaina", "You" or "Your Alt
-- Jaina".
local function subject(record, character, own)
  local alt = character.guid ~= mainGuid(record)
  if own then return alt and "Your Alt " .. character.name or "You" end
  local name = memberName(record)
  return alt and ("%s's Alt %s"):format(name, character.name) or name
end

local function newEntry(kind, record, own, text, character)
  return {
    kind = kind,
    time = record.version,
    memberId = record.id,
    guid = character and character.guid,
    text = text,
    own = own or nil,
    -- Your own events are never news to you.
    seen = own or nil,
  }
end

-- The entries for one Character, from how it was (nil if new) to how it is.
local function characterEntries(self, record, was, character, own, list)
  if not was then
    local owner = own and "You have" or memberName(record) .. " has"
    local entry = newEntry("newCharacter", record, own,
      ("%s a new Character: %s (%s)"):format(owner, character.name, className(character.classFilename)),
      character)
    entry.level = character.level
    list[#list + 1] = entry
    return
  end

  local level, from = character.level, was.level
  -- A level above your own max level means you're behind on a patch.
  if level > from and level <= self.maxLevel then
    local entry
    if level == self.maxLevel then
      entry = newEntry("maxLevel", record, own,
        subject(record, character, own) .. " reached max level!", character)
    else
      entry = newEntry("ding", record, own,
        ("%s dinged %d"):format(subject(record, character, own), level), character)
    end
    entry.from, entry.level = from, level
    list[#list + 1] = entry
  end

  -- A count that went down is a crash that lost a session's deaths.
  local deaths = (character.deaths or 0) - (was.deaths or 0)
  if deaths > 0 then
    local times = deaths == 1 and "" or (" %d times"):format(deaths)
    local entry = newEntry("death", record, own,
      ("%s died%s"):format(subject(record, character, own), times), character)
    entry.count = deaths
    list[#list + 1] = entry
  end
end

-- Keeps the log oldest first by time; equal times keep arrival order.
local function insert(self, entries)
  local log = self.db.feed
  for _, entry in ipairs(entries) do
    local at = #log + 1
    while at > 1 and log[at - 1].time > entry.time do at = at - 1 end
    table.insert(log, at, entry)
  end
  return entries
end

local function joinedAfterYou(self, record)
  local own = self.ledger:own()
  local yours = own and own.joinedAt
  return record.joinedAt ~= nil and yours ~= nil and record.joinedAt > yours
end

-- Someone else's record was kept: before is the copy held until now (nil
-- on first sight) and after the new one. Returns the new entries.
function Feed:recordChanged(before, after)
  local list = {}
  local joins = self.db.feedJoins
  local announced = joins[after.id]
  joins[after.id] = after.joinedAt

  if before == nil then
    if not after.left and joinedAfterYou(self, after) and after.joinedAt ~= announced then
      list[1] = newEntry("joined", after, false, memberName(after) .. " joined the Crew")
    end
  elseif after.left then
    if not before.left then
      list[1] = newEntry("left", after, false, memberName(after) .. " left the Crew")
    end
  elseif before.left then
    list[1] = newEntry("joined", after, false, memberName(after) .. " joined the Crew")
  else
    for guid, character in pairs(after.characters) do
      characterEntries(self, after, before.characters[guid], character, false, list)
    end
  end
  return insert(self, list)
end

-- The Character being played changed: was is how it was (nil if new),
-- character how it is in the own record now, and firstCharacter whether it
-- is the first one ever, which is a silent baseline. Returns the new
-- entries.
function Feed:ownChanged(was, character, firstCharacter)
  local list = {}
  if not firstCharacter then
    characterEntries(self, self.ledger:own(), was, character, true, list)
  end
  return insert(self, list)
end

-- Drops a Removed Member's entries.
function Feed:dropMember(id)
  local log = self.db.feed
  for i = #log, 1, -1 do
    if log[i].memberId == id then table.remove(log, i) end
  end
end

-- Leaving the Crew wipes the log.
function Feed:clear()
  self.db.feed = {}
  self.db.feedJoins = {}
end

function Feed:markSeen(entry)
  entry.seen = true
end

-- Marks every entry seen. Returns true if any wasn't.
function Feed:markAllSeen()
  local any = false
  for _, entry in ipairs(self.db.feed) do
    if not entry.seen then
      entry.seen = true
      any = true
    end
  end
  return any
end

-- The link came up in a Crew: settling starts, if it hasn't.
function Feed:linkUp()
  self.upSince = self.upSince or self.now()
end

-- DATA changed a record.
function Feed:dataMerged()
  self.lastData = self.now()
end

function Feed:isSettled()
  return self.settled
end

-- Called once a second: prunes the log, and settles once sync has gone
-- quiet. Returns true the moment it settles.
function Feed:tick()
  local now = self.now()
  local log = self.db.feed
  while log[1] and (#log > KEEP_MAX or now - log[1].time > KEEP_FOR) do
    table.remove(log, 1)
  end

  if self.settled or not self.upSince then return false end
  local quietSince = math.max(self.upSince, self.lastData or self.upSince)
  if now - quietSince >= QUIET_FOR or now - self.upSince >= SETTLE_WITHIN then
    self.settled = true
    return true
  end
  return false
end

-- An entry as handed out: a fresh table UI may keep.
function Feed.describe(entry)
  return {
    kind = entry.kind,
    time = entry.time,
    memberId = entry.memberId,
    guid = entry.guid,
    text = entry.text,
    from = entry.from,
    level = entry.level,
    count = entry.count,
    own = entry.own == true,
    seen = entry.seen == true,
  }
end

-- The log newest first, grouped by day (utcOffset shifts day boundaries
-- to local time): { days = { { daysAgo, time, entries } }, unseen }.
function Feed:view(utcOffset)
  local today = math.floor((self.now() + utcOffset) / DAY)
  local days, unseen = {}, 0
  local log = self.db.feed
  for i = #log, 1, -1 do
    local entry = log[i]
    local day = math.floor((entry.time + utcOffset) / DAY)
    local group = days[#days]
    if not group or group.day ~= day then
      group = { day = day, daysAgo = today - day, time = entry.time, entries = {} }
      days[#days + 1] = group
    end
    group.entries[#group.entries + 1] = Feed.describe(entry)
    if not entry.seen then unseen = unseen + 1 end
  end
  for _, group in ipairs(days) do group.day = nil end
  return { days = days, unseen = unseen }
end
