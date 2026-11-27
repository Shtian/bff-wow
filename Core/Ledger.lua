local _, ns = ...

local Ledger = {}
Ledger.__index = Ledger
ns.Ledger = Ledger

local ID_LENGTH = 8
local ID_ALPHABET = "abcdefghijklmnopqrstuvwxyz0123456789"

local CHARACTER_FIELDS = {
  "name", "lastName", "classFilename", "level", "xp", "maxXp", "zone", "deaths", "money", "professions",
}
local LOCATION_FIELDS = { "mapId", "x", "y", "instance" }

local STORED_AS = {
  professions = { store = ns.Professions.store, same = ns.Professions.same, keep = true },
  lastName = { store = function(value) return value end, same = function(a, b) return a == b end, keep = true },
}

local function stored(character, field, saved)
  local as = STORED_AS[field]
  if not as then return character[field] end
  local value = as.store(character[field])
  if value == nil and as.keep and saved then return saved[field] end
  return value
end

local function same(field, a, b)
  local as = STORED_AS[field]
  if as then return as.same(a, b) end
  return a == b
end

function Ledger.newMemberId(random)
  local chars = {}
  for i = 1, ID_LENGTH do
    local n = math.floor(random() * #ID_ALPHABET) + 1
    chars[i] = ID_ALPHABET:sub(n, n)
  end
  return table.concat(chars)
end

function Ledger.new(db, now, random, initialLogin)
  db.memberId = db.memberId or Ledger.newMemberId(random)
  db.records = db.records or {}
  db.via = db.via or {}
  db.removed = db.removed or {}
  if initialLogin or not db.heard then db.heard = {} end
  return setmetatable({ db = db, now = now }, Ledger)
end

function Ledger:memberId()
  return self.db.memberId
end

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

local function bump(self, record)
  local now = self.now()
  record.version = math.max(now, record.version + 1)
  if record.reactions then ns.Reactions.prune(record.reactions, now) end
  if self.prune then self.prune(record, now) end
end

function Ledger:pruneWith(prune)
  self.prune = prune
end

function Ledger:changeOwn(change)
  local record = ownRecord(self)
  local changed = change(record)
  if changed then bump(self, record) end
  return changed
end

function Ledger:updateOwn(character)
  if type(character) ~= "table" or type(character.guid) ~= "string" then
    error("updateOwn: character.guid must be a string", 2)
  end

  local record = ownRecord(self)
  local saved = record.characters[character.guid]
  local changed = saved == nil or self.playingGuid ~= character.guid
  local fields = {}
  for _, field in ipairs(CHARACTER_FIELDS) do
    fields[field] = stored(character, field, saved)
    if saved and not same(field, saved[field], fields[field]) then changed = true end
  end
  self.playingGuid = character.guid
  if not changed then return false end

  local before = saved
  saved = { guid = character.guid }
  for _, field in ipairs(CHARACTER_FIELDS) do saved[field] = fields[field] end
  for _, field in ipairs(LOCATION_FIELDS) do saved[field] = before and before[field] end
  saved.lastPlayed = self.now()
  record.characters[character.guid] = saved
  bump(self, record)
  return true, before
end

function Ledger:touch()
  local record = self:own()
  local saved = record and self.playingGuid and record.characters[self.playingGuid]
  if not saved then return false end
  saved.lastPlayed = self.now()
  bump(self, record)
  return true
end

local function round(value)
  return math.min(1, math.max(0, math.floor(value * 1000 + 0.5) / 1000))
end

function Ledger:locate(location)
  local record = self:own()
  local saved = record and self.playingGuid and record.characters[self.playingGuid]
  if not saved or type(location) ~= "table" then return false end

  local mapId, x, y, instance = location.mapId, location.x, location.y, location.instance
  local spot
  local hasSpot = type(mapId) == "number" and type(x) == "number" and type(y) == "number"
  if type(instance) == "string" and instance ~= "" then
    if hasSpot then
      spot = { mapId = mapId, x = round(x), y = round(y), instance = instance }
    else
      spot = { mapId = saved.mapId, x = saved.x, y = saved.y, instance = instance }
    end
  elseif hasSpot then
    spot = { mapId = mapId, x = round(x), y = round(y) }
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

function Ledger:playing()
  return self.playingGuid
end

function Ledger:displayName()
  local record = self:own()
  return record and record.displayName
end

function Ledger:writeOwn(fields)
  local record = ownRecord(self)
  local changed = false
  for _, field in ipairs({ "displayName", "left", "main", "joinedAt", "bff", "look", "generation" }) do
    local value = fields[field]
    if value ~= nil and (value or nil) ~= record[field] then
      record[field] = value or nil
      changed = true
    end
  end
  if changed then bump(self, record) end
  return changed
end

function Ledger:setPlayTimes(summary)
  local record = self:own()
  if not record or ns.PlayTimes.same(record.playTimes, summary) then return false end
  record.playTimes = summary
  bump(self, record)
  return true
end

function Ledger:addReaction(key)
  local record = ownRecord(self)
  record.reactions = record.reactions or {}
  record.reactions[#record.reactions + 1] = ns.Reactions.item(key, self.now())
  bump(self, record)
end

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

local function copied(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for k, v in pairs(value) do result[k] = copied(v) end
  return result
end

function Ledger:carryOwn(from)
  local source = from:own()
  if not source then return end
  self:changeOwn(function(record)
    for _, field in ipairs({ "displayName", "main", "look", "characters" }) do
      record[field] = copied(source[field])
    end
    record.characters = record.characters or {}
    return true
  end)
end

function Ledger:highestGeneration()
  local highest, from = 0, nil
  for id, record in pairs(self.db.records) do
    local generation = record.generation or 0
    if id ~= self.db.memberId and not record.left and generation > highest then
      highest, from = generation, id
    end
  end
  return highest, from
end

function Ledger:remove(id)
  local record = self.db.records[id]
  if not record or id == self.db.memberId then return false end
  self.db.removed[id] = { displayName = record.displayName, version = record.version }
  self.db.records[id] = nil
  self.db.heard[id] = nil
  self.db.via[id] = nil
  return true
end

function Ledger:readd(id)
  if not self.db.removed[id] then return false end
  self.db.removed[id] = nil
  return true
end

function Ledger:isRemoved(id)
  return self.db.removed[id] ~= nil
end

function Ledger:removed()
  return pairs(self.db.removed)
end

function Ledger:via(id)
  return self.db.via[id]
end

function Ledger:record(id)
  return self.db.records[id]
end

function Ledger:version(id)
  local record = self.db.records[id] or self.db.removed[id]
  return record and record.version or 0
end

function Ledger:records()
  return pairs(self.db.records)
end

function Ledger:digest(limit, after, ask)
  local own = self:own()
  local versions, count = {}, 0
  local function add(id, version)
    if count < limit and versions[id] == nil then
      versions[id] = version
      count = count + 1
    end
  end
  if own then add(own.id, own.version) end
  local asked = {}
  for id in pairs(ask or {}) do asked[#asked + 1] = id end
  table.sort(asked)
  for _, id in ipairs(asked) do add(id, self:version(id)) end

  local ids = {}
  for id, record in pairs(self.db.records) do
    if record ~= own then ids[#ids + 1] = id end
  end
  for id in pairs(self.db.removed) do ids[#ids + 1] = id end
  table.sort(ids)
  local start = 1
  if after then
    while start <= #ids and ids[start] <= after do start = start + 1 end
  end
  local last, partial = after, false
  for i = 0, #ids - 1 do
    local id = ids[(start - 1 + i) % #ids + 1]
    if versions[id] == nil then
      if count >= limit then
        partial = true
        break
      end
      add(id, self:version(id))
      last = id
    end
  end
  return versions, partial, last
end

local function isText(value) return type(value) == "string" end
local function isNumber(value) return type(value) == "number" end
local function isFraction(value) return isNumber(value) and value >= 0 and value <= 1 end
local function isCount(value) return isNumber(value) and value >= 0 and value == math.floor(value) end
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
  bff = isOptional(isText),
  playTimes = isOptional(ns.PlayTimes.valid),
  generation = isOptional(isCount),
}
local CHARACTER_SHAPE = {
  guid = isText,
  name = isText,
  lastName = isOptional(isText),
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

local function wellFormed(record)
  if not fits(record, RECORD_SHAPE) then return false end
  if record.characters == nil then return true end
  if type(record.characters) ~= "table" then return false end
  for guid, character in pairs(record.characters) do
    if not fits(character, CHARACTER_SHAPE) or character.guid ~= guid then return false end
  end
  return true
end

function Ledger:merge(record, from)
  if not wellFormed(record) or record.id == self.db.memberId then return false end
  local removed = self.db.removed[record.id]
  if removed then
    if record.version > self:version(record.id) then removed.version = record.version end
    return false
  end
  if record.version <= self:version(record.id) then return false end
  if not record.characters then record.characters = {} end
  local before = self.db.records[record.id]
  self.db.records[record.id] = record
  self.db.via[record.id] = from ~= record.id and from or nil
  return true, before
end

function Ledger:heard(id)
  if self:isRemoved(id) then return end
  self.db.heard[id] = self.now()
end

function Ledger:lastHeard(id)
  return self.db.heard[id]
end

-- WoW: on Forever the channel names a Character "First Last", while
-- UnitName's first value is the first name alone.
function Ledger:wentAway(name)
  local any = false
  local lower = name:lower()
  local first = lower:match("^(%S+)%s") or lower
  for id, record in pairs(self.db.records) do
    for _, character in pairs(record.characters) do
      local own = character.name:lower()
      if (own == lower or own == first) and self.db.heard[id] then
        self.db.heard[id] = nil
        any = true
      end
    end
  end
  return any
end
