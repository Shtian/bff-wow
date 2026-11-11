-- Where: other Members' live spots on the world map, between their DATA.
-- A record's spot only changes when its DATA goes out (a zone change, a
-- ding, the 5-minute heartbeat), so a pin could lag a Member by minutes.
-- While you move in the open world with others online, a small WHERE goes
-- out instead: { character (GUID), mapId, x, y, at (your clock) }, one
-- chunk, never DATA, and never a change to your record, so DIGESTs don't
-- start asking for it. Received WHEREs are held in memory only, and give
-- way to a record written since. Older BFFs ignore the unknown type.
-- Also keeps the last open-world spot read, so a record entering an
-- instance keeps the spot you went in from rather than the last one sent.

local _, ns = ...

local Where = {}
Where.__index = Where
ns.Where = Where

-- Seconds between reads of where you stand.
local CHECK = 2
-- A move smaller than this on either axis isn't one.
local MOVED = 0.002
-- The least time between WHEREs, and how much it grows per other Member
-- online, so a big Crew stays at about 20 whispers a minute.
local EVERY_MIN = 10
local EVERY_PER_MEMBER = 3

-- A WHERE keeps positions to 0.01% of the map, as OpenMap does (records
-- keep 0.1%, so standing still isn't a change).
local function round(value)
  return math.min(1, math.max(0, math.floor(value * 10000 + 0.5) / 10000))
end

local function isSpot(location)
  return type(location) == "table" and type(location.mapId) == "number" and location.mapId > 0
    and type(location.x) == "number" and type(location.y) == "number"
end

local function onMap(value)
  return type(value) == "number" and value >= 0 and value <= 1
end

-- now() is Core's clock; locate() is the optional deps.locate.
function Where.new(now, locate)
  return setmetatable({
    now = now,
    locate = locate,
    -- The last open-world spot read: { mapId, x, y }.
    outside = nil,
    -- The last spot that went out (in DATA or a WHERE), and when.
    sent = nil,
    sentAt = -math.huge,
    -- When the last WHERE (not DATA) went out.
    lastWhereAt = nil,
    nextCheck = 0,
    -- memberId -> { character, mapId, x, y, at }.
    live = {},
  }, Where)
end

-- Reads where you stand, as locate() says (nil when it can't be read).
-- Inside an instance the last open-world spot read comes with it.
function Where:read()
  if not self.locate then return nil end
  local location = self.locate()
  if isSpot(location) then
    -- Raw: the Ledger rounds what goes in the record.
    self.outside = { mapId = location.mapId, x = location.x, y = location.y }
    return self.outside
  end
  if type(location) == "table" and type(location.instance) == "string" and self.outside then
    return { instance = location.instance, mapId = self.outside.mapId, x = self.outside.x, y = self.outside.y }
  end
  return location
end

-- Own DATA went out carrying this location (from read()).
function Where:dataSent(location)
  if isSpot(location) and not location.instance then
    self.sent, self.sentAt = location, self.now()
  end
end

local function moved(from, to)
  return not from or from.mapId ~= to.mapId
    or math.abs(from.x - to.x) > MOVED or math.abs(from.y - to.y) > MOVED
end

-- Called once a second. talking says Gossip may talk, others how many other
-- Members are online, guid the Character being played and version the own
-- record's (which can run a few seconds ahead of the clock). Returns a
-- WHERE to send to everyone, or nil. Its at is never older than the
-- record, so it wins over the record's spot.
function Where:tick(talking, others, guid, version)
  local now = self.now()
  if now < self.nextCheck then return nil end
  self.nextCheck = now + CHECK
  local here = self:read()
  if not (talking and others > 0 and type(guid) == "string" and isSpot(here)) or here.instance then return nil end
  if not moved(self.sent, here) then return nil end
  if now - self.sentAt < math.max(EVERY_MIN, EVERY_PER_MEMBER * others) then return nil end
  local at = math.max(now, version or 0)
  self.sent, self.sentAt, self.lastWhereAt = here, now, at
  return { type = "WHERE", character = guid, mapId = here.mapId, x = round(here.x), y = round(here.y), at = at }
end

-- Whether a WHERE went out after the own record's version: DATA must then
-- carry a newer version, or peers would keep showing that WHERE's spot.
function Where:sentSince(version)
  return self.lastWhereAt ~= nil and self.lastWhereAt >= version
end

-- A WHERE from the Member with this id. Returns true if it was kept.
function Where:heard(from, message)
  if type(message.character) ~= "string" or type(message.mapId) ~= "number" or message.mapId <= 0
      or not onMap(message.x) or not onMap(message.y) or type(message.at) ~= "number" then
    return false
  end
  local held = self.live[from]
  if held and held.at > message.at then return false end
  self.live[from] = { character = message.character, mapId = message.mapId, x = message.x, y = message.y,
    at = message.at }
  return true
end

-- The live spot for a Member's Character, if one was heard since the
-- record's version (when the record's own spot was last read), else nil.
function Where:spot(memberId, guid, version)
  local held = self.live[memberId]
  if held and held.character == guid and held.at >= (version or 0) then return held end
  return nil
end

-- A removed Member's spot goes.
function Where:forget(memberId)
  self.live[memberId] = nil
end
