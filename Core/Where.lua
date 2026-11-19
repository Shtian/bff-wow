local _, ns = ...

local Where = {}
Where.__index = Where
ns.Where = Where

local CHECK = 2
local MOVED = 0.002
local EVERY_MIN = 10
local EVERY_PER_MEMBER = 3

local PRECISION = 10000

local function round(value)
  return math.min(1, math.max(0, math.floor(value * PRECISION + 0.5) / PRECISION))
end

local function isSpot(location)
  return type(location) == "table" and type(location.mapId) == "number" and location.mapId > 0
    and type(location.x) == "number" and type(location.y) == "number"
end

local function onMap(value)
  return type(value) == "number" and value >= 0 and value <= 1
end

function Where.new(now, locate)
  return setmetatable({
    now = now,
    locate = locate,
    outside = nil,
    sent = nil,
    sentAt = -math.huge,
    lastWhereAt = nil,
    nextCheck = 0,
    live = {},
  }, Where)
end

function Where:read()
  if not self.locate then return nil end
  local location = self.locate()
  if isSpot(location) then
    self.outside = { mapId = location.mapId, x = location.x, y = location.y }
    return self.outside
  end
  if type(location) == "table" and type(location.instance) == "string" and self.outside then
    return { instance = location.instance, mapId = self.outside.mapId, x = self.outside.x, y = self.outside.y }
  end
  return location
end

function Where:dataSent(location)
  if isSpot(location) and not location.instance then
    self.sent, self.sentAt = location, self.now()
  end
end

local function moved(from, to)
  return not from or from.mapId ~= to.mapId
    or math.abs(from.x - to.x) > MOVED or math.abs(from.y - to.y) > MOVED
end

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

function Where:sentSince(version)
  return self.lastWhereAt ~= nil and self.lastWhereAt >= version
end

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

function Where:spot(memberId, guid, version)
  local held = self.live[memberId]
  if held and held.character == guid and held.at >= (version or 0) then return held end
  return nil
end

function Where:forget(memberId)
  self.live[memberId] = nil
end
