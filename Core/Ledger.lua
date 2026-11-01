-- Ledger: what we know. One record per Member, with the display name, the
-- left flag and all their Characters inside, keyed by GUID: the own record,
-- which only this client writes, and copies of everyone else's. The version
-- is the owner's clock at the last write and always moves forward, so a
-- higher version wins (docs/adr/0001). Also when each Member was last heard,
-- who each copy came from, and the Members removed from your own view.

local _, ns = ...

local Ledger = {}
Ledger.__index = Ledger
ns.Ledger = Ledger

local ID_LENGTH = 8
local ID_ALPHABET = "abcdefghijklmnopqrstuvwxyz0123456789"

-- The fields Snapshot reports for a Character.
local CHARACTER_FIELDS = { "name", "classFilename", "level", "xp", "maxXp", "zone", "deaths", "money" }
-- Where a Character was last seen, from locate(): written only by
-- Ledger:locate, and kept when Snapshot reports the Character.
local LOCATION_FIELDS = { "mapId", "x", "y", "instance" }

local function newMemberId(random)
  local chars = {}
  for i = 1, ID_LENGTH do
    local n = math.floor(random() * #ID_ALPHABET) + 1
    chars[i] = ID_ALPHABET:sub(n, n)
  end
  return table.concat(chars)
end

-- db is the whole saved table; the Ledger keeps `memberId`, `records`,
-- `heard`, `via` and `removed`. Last-heard times survive a reload but not
-- a logout, since nobody was heard while you were logged out.
function Ledger.new(db, now, random, initialLogin)
  db.memberId = db.memberId or newMemberId(random)
  db.records = db.records or {}
  db.via = db.via or {}
  db.removed = db.removed or {}
  if initialLogin or not db.heard then db.heard = {} end
  return setmetatable({ db = db, now = now }, Ledger)
end

function Ledger:memberId()
  return self.db.memberId
end

-- The own record, or nil until the first Character is reported.
function Ledger:own()
  return self.db.records[self.db.memberId]
end

local function ownRecord(self)
  local record = self:own()
  if not record then
    record = { id = self.db.memberId, version = 0, characters = {} }
    self.db.records[record.id] = record
  end
  return record
end

-- Every write of the own record also prunes its Reactions, and whatever
-- the pruner handed to pruneWith keeps in it, so pruning alone never sends
-- DATA.
local function bump(self, record)
  local now = self.now()
  record.version = math.max(now, record.version + 1)
  if record.reactions then ns.Reactions.prune(record.reactions, now) end
  if self.prune then self.prune(record, now) end
end

-- Hands over the pruner: prune(record, now) edits the own record on every
-- write, before it goes out. The Spares module prunes its Spares and
-- Claims this way, since only it knows which have ended.
function Ledger:pruneWith(prune)
  self.prune = prune
end

-- A write of the own record by a module that owns part of it: change(record)
-- edits it and returns true if it changed, which makes the write. Returns
-- what change did. A change returning false that edits it anyway isn't a
-- write, as when leaving the Crew clears the own Spares.
function Ledger:changeOwn(change)
  local record = ownRecord(self)
  local changed = change(record)
  if changed then bump(self, record) end
  return changed
end

-- Records the current state of the Character being played. Returns true if
-- the record changed, and the Character as it was before (nil if new).
-- Switching to a Character counts as a change even if nothing else did, so
-- it becomes the most recently played one.
function Ledger:updateOwn(character)
  if type(character) ~= "table" or type(character.guid) ~= "string" then
    error("updateOwn: character.guid must be a string", 2)
  end

  local record = ownRecord(self)
  local saved = record.characters[character.guid]
  local changed = saved == nil or self.playingGuid ~= character.guid
  if saved then
    for _, field in ipairs(CHARACTER_FIELDS) do
      if saved[field] ~= character[field] then changed = true end
    end
  end
  self.playingGuid = character.guid
  if not changed then return false end

  local before = saved
  saved = { guid = character.guid }
  for _, field in ipairs(CHARACTER_FIELDS) do saved[field] = character[field] end
  for _, field in ipairs(LOCATION_FIELDS) do saved[field] = before and before[field] end
  saved.lastPlayed = self.now()
  record.characters[character.guid] = saved
  bump(self, record)
  return true, before
end

-- Marks the Character being played as played now, for the heartbeat.
-- Returns true if there is one.
function Ledger:touch()
  local record = self:own()
  local saved = record and self.playingGuid and record.characters[self.playingGuid]
  if not saved then return false end
  saved.lastPlayed = self.now()
  bump(self, record)
  return true
end

-- Positions are kept to 0.1% of the map, so standing still isn't a change,
-- and inside 0–1, since peers drop a record with a spot off the map.
local function round(value)
  return math.min(1, math.max(0, math.floor(value * 1000 + 0.5) / 1000))
end

-- Records where the Character being played is, from locate(): mapId, x
-- and y (0–1 on that map) for the open world, which also clears the
-- instance; or instance (its name) alone, keeping the last open-world spot.
-- Nil, or anything else, keeps what was known. Returns true if the record
-- changed.
function Ledger:locate(location)
  local record = self:own()
  local saved = record and self.playingGuid and record.characters[self.playingGuid]
  if not saved or type(location) ~= "table" then return false end

  local mapId, x, y, instance = location.mapId, location.x, location.y, location.instance
  local spot
  if type(mapId) == "number" and type(x) == "number" and type(y) == "number" then
    spot = { mapId = mapId, x = round(x), y = round(y) }
  elseif type(instance) == "string" and instance ~= "" then
    spot = { mapId = saved.mapId, x = saved.x, y = saved.y, instance = instance }
  else
    return false
  end

  local changed = false
  for _, field in ipairs(LOCATION_FIELDS) do
    if saved[field] ~= spot[field] then
      saved[field] = spot[field]
      changed = true
    end
  end
  if changed then bump(self, record) end
  return changed
end

-- The GUID of the Character being played, or nil before the first report.
function Ledger:playing()
  return self.playingGuid
end

function Ledger:displayName()
  local record = self:own()
  return record and record.displayName
end

-- Writes the given displayName, left flag, Main (a Character GUID) and
-- joinedAt (when you started or joined the Crew) into the own record. A
-- field not given is kept; false clears left or Main. Returns true if the
-- record changed.
function Ledger:writeOwn(fields)
  local record = ownRecord(self)
  local changed = false
  for _, field in ipairs({ "displayName", "left", "main", "joinedAt" }) do
    local value = fields[field]
    if value ~= nil and (value or nil) ~= record[field] then
      record[field] = value or nil
      changed = true
    end
  end
  if changed then bump(self, record) end
  return changed
end

-- Writes the own Play times summary (from PlayTimes) into the own record,
-- once it exists. Returns true if the record changed.
function Ledger:setPlayTimes(summary)
  local record = self:own()
  if not record or ns.PlayTimes.same(record.playTimes, summary) then return false end
  record.playTimes = summary
  bump(self, record)
  return true
end

-- Adds a Reaction (a key from Reactions) to the own record, made now.
function Ledger:addReaction(key)
  local record = ownRecord(self)
  record.reactions = record.reactions or {}
  record.reactions[#record.reactions + 1] = ns.Reactions.item(key, self.now())
  bump(self, record)
end

-- Leaving the Crew clears the own Reactions. Not a write: the tombstone
-- carries none, and rejoining writes the record anyway.
function Ledger:clearReactions()
  local record = self:own()
  if record then record.reactions = nil end
end

-- What a Member who left publishes: no Characters.
function Ledger:tombstone()
  local record = ownRecord(self)
  return { id = record.id, version = record.version, displayName = record.displayName, left = true }
end

function Ledger:knowsOthers()
  for id in pairs(self.db.records) do
    if id ~= self.db.memberId then return true end
  end
  return false
end

-- Drops every record but the own one, who was heard, and who was removed.
function Ledger:forgetOthers()
  for id in pairs(self.db.records) do
    if id ~= self.db.memberId then self.db.records[id] = nil end
  end
  self.db.heard = {}
  self.db.via = {}
  self.db.removed = {}
end

-- Removes a Member from your own view: their record is dropped, and later
-- copies are too. Returns false for yourself or a Member not held.
function Ledger:remove(id)
  local record = self.db.records[id]
  if not record or id == self.db.memberId then return false end
  self.db.removed[id] = { displayName = record.displayName }
  self.db.records[id] = nil
  self.db.heard[id] = nil
  self.db.via[id] = nil
  return true
end

-- Takes a Member off the Remove list. Returns false if they weren't on it.
function Ledger:readd(id)
  if not self.db.removed[id] then return false end
  self.db.removed[id] = nil
  return true
end

function Ledger:isRemoved(id)
  return self.db.removed[id] ~= nil
end

-- The removed Members: for id, { displayName } in ledger:removed().
function Ledger:removed()
  return pairs(self.db.removed)
end

-- The Member id whose message brought this Member's record, if it wasn't
-- their own.
function Ledger:via(id)
  return self.db.via[id]
end

-- The record with this Member id, or nil. Not to be changed.
function Ledger:record(id)
  return self.db.records[id]
end

-- The version held for a Member id, 0 if none.
function Ledger:version(id)
  local record = self.db.records[id]
  return record and record.version or 0
end

-- Every record held, own included: for id, record in ledger:records().
function Ledger:records()
  return pairs(self.db.records)
end

-- Up to `limit` Member ids and versions: the own one first, then the most
-- recently written.
function Ledger:digest(limit)
  local own = self:own()
  local others = {}
  for _, record in pairs(self.db.records) do
    if record ~= own then others[#others + 1] = record end
  end
  table.sort(others, function(a, b)
    if a.version ~= b.version then return a.version > b.version end
    return a.id < b.id
  end)
  local versions = {}
  if own then
    versions[own.id] = own.version
    limit = limit - 1
  end
  for i = 1, math.min(limit, #others) do versions[others[i].id] = others[i].version end
  return versions
end

local function isText(value) return type(value) == "string" end
local function isNumber(value) return type(value) == "number" end
local function isFraction(value) return isNumber(value) and value >= 0 and value <= 1 end
local function isOptional(check)
  return function(value) return value == nil or check(value) end
end

local RECORD_SHAPE = {
  id = isText,
  version = isNumber,
  displayName = isOptional(isText),
  main = isOptional(isText),
  left = isOptional(function(value) return value == true end),
  joinedAt = isOptional(isNumber),
  playTimes = isOptional(ns.PlayTimes.valid),
}
local CHARACTER_SHAPE = {
  guid = isText,
  name = isText,
  classFilename = isOptional(isText),
  level = isNumber,
  xp = isOptional(isNumber),
  maxXp = isOptional(isNumber),
  zone = isOptional(isText),
  deaths = isOptional(isNumber),
  money = isOptional(function(value) return isNumber(value) and value >= 0 end),
  mapId = isOptional(function(value) return isNumber(value) and value > 0 end),
  x = isOptional(isFraction),
  y = isOptional(isFraction),
  instance = isOptional(isText),
  lastPlayed = isNumber,
}

local function fits(value, shape)
  if type(value) ~= "table" then return false end
  for field, check in pairs(shape) do
    if not check(value[field]) then return false end
  end
  return true
end

-- A record from the wire is only kept if it has the expected shape.
local function wellFormed(record)
  if not fits(record, RECORD_SHAPE) then return false end
  if record.characters == nil then return true end
  if type(record.characters) ~= "table" then return false end
  for guid, character in pairs(record.characters) do
    if not fits(character, CHARACTER_SHAPE) or character.guid ~= guid then return false end
  end
  return true
end

-- Keeps a copy of someone else's record, sent by the Member id `from`, if
-- it is newer than the one held and the Member isn't removed. Returns true
-- if it was kept, and the copy held before (nil on first sight).
function Ledger:merge(record, from)
  if not wellFormed(record) or record.id == self.db.memberId then return false end
  if self:isRemoved(record.id) then return false end
  if record.version <= self:version(record.id) then return false end
  if not record.characters then record.characters = {} end
  local before = self.db.records[record.id]
  self.db.records[record.id] = record
  self.db.via[record.id] = from ~= record.id and from or nil
  return true, before
end

-- Notes that a message from this Member was just heard.
function Ledger:heard(id)
  if self:isRemoved(id) then return end
  self.db.heard[id] = self.now()
end

-- When this Member was last heard, or nil.
function Ledger:lastHeard(id)
  return self.db.heard[id]
end

-- Forgets having heard the Members owning a Character of this name, and
-- returns whether there were any.
function Ledger:wentAway(name)
  local any = false
  local lower = name:lower()
  for id, record in pairs(self.db.records) do
    for _, character in pairs(record.characters) do
      if character.name:lower() == lower and self.db.heard[id] then
        self.db.heard[id] = nil
        any = true
      end
    end
  end
  return any
end
