-- Ledger: what we know. For now only the own record: one per Member, all
-- their Characters inside, keyed by GUID. The version is the clock at the
-- last write, and always moves forward (docs/adr/0001).

local _, ns = ...

local Ledger = {}
Ledger.__index = Ledger
ns.Ledger = Ledger

local ID_LENGTH = 8
local ID_ALPHABET = "abcdefghijklmnopqrstuvwxyz0123456789"

-- The fields Snapshot reports for a Character.
local CHARACTER_FIELDS = { "name", "classFilename", "level", "xp", "maxXp", "zone", "deaths" }

local function newMemberId(random)
  local chars = {}
  for i = 1, ID_LENGTH do
    local n = math.floor(random() * #ID_ALPHABET) + 1
    chars[i] = ID_ALPHABET:sub(n, n)
  end
  return table.concat(chars)
end

-- db is the whole saved table; the Ledger keeps `memberId` and `records`.
function Ledger.new(db, now, random)
  db.memberId = db.memberId or newMemberId(random)
  db.records = db.records or {}
  return setmetatable({ db = db, now = now }, Ledger)
end

function Ledger:memberId()
  return self.db.memberId
end

-- The own record, or nil until the first Character is reported.
function Ledger:own()
  return self.db.records[self.db.memberId]
end

-- Records the current state of the Character being played. Returns true if
-- the record changed. Switching to a Character counts as a change even if
-- nothing else did, so it becomes the most recently played one.
function Ledger:updateOwn(character)
  if type(character) ~= "table" or type(character.guid) ~= "string" then
    error("updateOwn: character.guid must be a string", 2)
  end

  local record = self:own()
  if not record then
    record = { id = self.db.memberId, version = 0, characters = {} }
    self.db.records[record.id] = record
  end

  local saved = record.characters[character.guid]
  local changed = saved == nil or self.playingGuid ~= character.guid
  if saved then
    for _, field in ipairs(CHARACTER_FIELDS) do
      if saved[field] ~= character[field] then changed = true end
    end
  end
  self.playingGuid = character.guid
  if not changed then return false end

  saved = { guid = character.guid }
  for _, field in ipairs(CHARACTER_FIELDS) do saved[field] = character[field] end
  local now = self.now()
  saved.lastPlayed = now
  record.characters[character.guid] = saved
  record.version = math.max(now, record.version + 1)
  return true
end
