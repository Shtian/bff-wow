local _, ns = ...

local Rares = {}
ns.Rares = Rares

local function rare(id, name, zone, level, elite)
  return { id = id, name = name, zone = zone, level = level, elite = elite or nil }
end
local ELITE = true

Rares.LIST = {
  rare(259394, "Snapbeak the Quick", "Zephras Isle", 9, ELITE),
  rare(1132, "Timber", "Dun Morogh", 10),
  rare(276111, "Ghostfang", "Dun Morogh", 10),
  rare(276089, "The Condemned One", "Tirisfal Glades", 11),
  rare(5824, "Captain Flat Tusk", "Durotar", 11, ELITE),
  rare(14429, "Grimmaw", "Teldrassil", 11),
  rare(100, "Gruff Swiftbite", "Elwynn Forest", 12),
  rare(3056, "Ghost Howl", "Mulgore", 12),
  rare(599, "Marisa du'Paige", "Westfall", 18, ELITE),
  rare(5842, "Takk the Leaper", "The Barrens", 19, ELITE),
  rare(573, "Foe Reaper 4000", "Westfall", 20),
  rare(5831, "Swiftmane", "The Barrens", 21, ELITE),
  rare(10559, "Lady Vespia", "Ashenvale", 22),
  rare(521, "Lupos", "Duskwood", 23),
  rare(5828, "Humar the Pridelord", "The Barrens", 23, ELITE),
  rare(5931, "Foreman Rigger", "Stonetalon Mountains", 24, ELITE),
  rare(5797, "Aean Swiftriver", "The Barrens", 25, ELITE),
  rare(5934, "Heartrazor", "Thousand Needles", 32, ELITE),
  rare(14221, "Gravis Slipknot", "Alterac Mountains", 36),
  rare(2850, "Broken Tooth", "Badlands", 37),
  rare(2779, "Prince Nazjak", "Arathi Highlands", 41),
  rare(14445, "Lord Captain Wyrmak", "Swamp of Sorrows", 45, ELITE),
  rare(4339, "Brimgore", "Dustwallow Marsh", 45, ELITE),
  rare(8215, "Grimungous", "The Hinterlands", 50, ELITE),
  rare(10077, "Deathmaw", "Burning Steppes", 53),
  rare(10200, "Rak'shiri", "Winterspring", 57),
  rare(10202, "Azurous", "Winterspring", 59, ELITE),
  rare(6584, "King Mosh", "Un'Goro Crater", 60, ELITE),
  rare(10119, "Volchan", "Burning Steppes", 60, ELITE),
  rare(266901, "Pexmit", "Mount Hyjal", 60),
}

do
  for i, r in ipairs(Rares.LIST) do r.index = i end
  table.sort(Rares.LIST, function(a, b)
    if a.level ~= b.level then return a.level < b.level end
    return a.index < b.index
  end)
end
local BY_ID = {}
for i, r in ipairs(Rares.LIST) do
  r.index = i
  BY_ID[r.id] = r
end
Rares.TOTAL = #Rares.LIST

Rares.STEPS = { 5, 10, 20, Rares.TOTAL }

Rares.UNLISTED_CAP = 50
local MAX_ENTRIES = 200
local MEMORY = 100
local SECRET = "<secret>"

function Rares.byId(npcId)
  return BY_ID[npcId]
end

local function isId(value)
  return type(value) == "number" and value > 0 and value == math.floor(value)
end

local function text(value)
  if type(value) == "string" and value ~= "" then return value end
  return nil
end

-- WoW: a creature's GUID is "Creature-0-[server]-[instance]-[zone]-[npc]-[spawn]";
-- Forever obfuscates the server and spawn parts.
function Rares.npcId(guid)
  if type(guid) ~= "string" then return nil end
  local kind, id = guid:match("^(%a+)%-[^-]*%-[^-]*%-[^-]*%-[^-]*%-(%d+)%-")
  if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
  id = tonumber(id)
  return isId(id) and id or nil
end

local RARE_CLASSES = { rare = true, rareelite = true }

local Watch = {}
Watch.__index = Watch

function Rares.watch(api)
  return setmetatable({
    api = api,
    isSecret = api.isSecret or function() return false end,
    seen = {},
    count = 0,
    target = nil,
  }, Watch)
end

local function newInfo(signal)
  return { signal = signal, read = {}, secret = {} }
end

local function read(self, info, name, value)
  if self.isSecret(value) then
    if info.read[name] ~= SECRET then info.secret[#info.secret + 1] = name end
    info.read[name] = SECRET
    return nil, true
  end
  local kind = type(value)
  if kind == "string" or kind == "number" or kind == "boolean" then info.read[name] = value end
  return value, false
end

local function guarded(self, signal, fn, empty)
  local info = newInfo(signal)
  local ok, found = pcall(fn, self, info)
  if not ok then
    info.result = "error"
    info.error = tostring(found)
    return empty, info
  end
  return found, info
end

local function where(self, info, kill)
  kill.zone = text((read(self, info, "zone", self.api.zone())))
  kill.subzone = text((read(self, info, "subzone", self.api.subzone())))
  local mapId = read(self, info, "mapId", self.api.mapId())
  kill.mapId = isId(mapId) and mapId or nil
  return kill
end

local function remember(self, guid, unit)
  if not self.seen[guid] then
    self.count = self.count + 1
    if self.count > MEMORY then
      self.seen, self.count = {}, 1
    end
  end
  self.seen[guid] = unit
end

local function killOf(self, guid, signal, unit)
  local npcId = Rares.npcId(guid)
  if not npcId then return nil, "notCreature" end
  unit = unit or self.seen[guid]
  if BY_ID[npcId] then return { npcId = npcId, signal = signal } end
  if unit and unit.rare then return { npcId = npcId, signal = signal, unlisted = true, name = unit.name } end
  return nil, "notRare"
end

local function readUnit(self, info, token)
  local guid = read(self, info, "guid", self.api.unitGUID(token))
  if type(guid) ~= "string" then return nil end
  local npcId = Rares.npcId(guid)
  if not npcId then return nil end
  local class = read(self, info, "classification", self.api.unitClassification(token))
  local name = read(self, info, "name", self.api.unitName(token))
  return guid, { npcId = npcId, name = text(name), rare = RARE_CLASSES[class] == true }
end

function Watch:see(token)
  local _, info = guarded(self, "seen", function(_, i)
    i.unit = token
    local guid, unit = readUnit(self, i, token)
    if token == "target" then self.target = nil end
    if not guid then
      i.result = #i.secret > 0 and "secret" or "notCreature"
      return
    end
    if not (BY_ID[unit.npcId] or unit.rare) then
      i.result = "notRare"
      return
    end
    remember(self, guid, unit)
    if token == "target" then self.target = { guid = guid, unit = unit } end
    i.result = BY_ID[unit.npcId] and ("listed " .. BY_ID[unit.npcId].name) or "unlisted rare"
  end)
  return info
end

-- WoW: looting a corpse means your group had the tag.
function Watch:loot()
  return guarded(self, "loot", function(_, info)
    local kills, found = {}, {}
    local count = read(self, info, "count", self.api.getNumLootItems())
    if type(count) ~= "number" then
      info.result = "unreadable"
      return kills
    end
    local reason
    for slot = 1, count do
      local sources = { self.api.getLootSourceInfo(slot) }
      for i = 1, #sources, 2 do
        local guid = read(self, info, "source", sources[i])
        if type(guid) == "string" then
          info.read["source" .. slot .. "." .. (i + 1) / 2] = guid
          local kill, why = killOf(self, guid, "loot")
          if kill and not found[kill.npcId] then
            found[kill.npcId] = true
            kills[#kills + 1] = where(self, info, kill)
          end
          reason = reason or why
        end
      end
    end
    if #kills > 0 then
      info.result = "found"
    else
      info.result = #info.secret > 0 and "secret" or reason or "empty"
    end
    return kills
  end, {})
end

-- WoW: a target's GUID can read secret in combat, so it's taken from
-- when it was targeted.
function Watch:targetDied()
  return guarded(self, "target", function(_, info)
    local guid, unit = readUnit(self, info, "target")
    if not guid and self.target then
      guid, unit = self.target.guid, self.target.unit
      info.read.remembered = guid
    end
    if not guid then
      info.result = "unknown"
      return nil
    end
    local dead = read(self, info, "dead", self.api.unitIsDead("target"))
    local tapDenied = read(self, info, "tapDenied", self.api.unitIsTapDenied("target"))
    if dead == nil or tapDenied == nil then
      info.result = "secret"
      return nil
    end
    if not dead then
      info.result = "alive"
      return nil
    end
    if tapDenied then
      info.result = "tapDenied"
      return nil
    end
    local kill, why = killOf(self, guid, "target", unit)
    info.result = kill and "found" or why
    return kill and where(self, info, kill)
  end)
end

function Watch:partyKill(attackerGUID, targetGUID)
  return guarded(self, "partyKill", function(_, info)
    read(self, info, "attackerGUID", attackerGUID)
    local guid = read(self, info, "targetGUID", targetGUID)
    if type(guid) ~= "string" then
      info.result = #info.secret > 0 and "secret" or "unreadable"
      return nil
    end
    local kill, why = killOf(self, guid, "partyKill")
    info.result = kill and "found" or why
    return kill and where(self, info, kill)
  end)
end

local function unlistedCount(rares)
  local n = 0
  for id in pairs(rares) do
    if not BY_ID[id] then n = n + 1 end
  end
  return n
end

function Rares.add(record, kill, time, character)
  if type(kill) ~= "table" or not isId(kill.npcId) then return false, "unreadable" end
  record.rares = record.rares or {}
  if record.rares[kill.npcId] then return false, "had" end
  local listed = BY_ID[kill.npcId] ~= nil
  if not listed and unlistedCount(record.rares) >= Rares.UNLISTED_CAP then return false, "full" end
  record.rares[kill.npcId] = {
    t = time, z = text(kill.zone), s = text(kill.subzone), m = isId(kill.mapId) and kill.mapId or nil,
    c = text(character), n = not listed and text(kill.name) or nil,
  }
  return true
end

local function optional(check)
  return function(value) return value == nil or check(value) end
end
local isText = optional(function(value) return type(value) == "string" end)
local isMap = optional(isId)

local function validEntry(entry)
  return type(entry) == "table" and type(entry.t) == "number"
    and isText(entry.z) and isText(entry.s) and isMap(entry.m) and isText(entry.c) and isText(entry.n)
end

local function valid(record)
  local list = {}
  local rares = record.rares
  if type(rares) ~= "table" then return pairs(list) end
  local n = 0
  for _ in pairs(rares) do n = n + 1 end
  if n > MAX_ENTRIES then return pairs(list) end
  local unlisted = {}
  for id, entry in pairs(rares) do
    if isId(id) and validEntry(entry) then
      list[id] = entry
      if not BY_ID[id] then unlisted[#unlisted + 1] = { id = id, t = entry.t } end
    end
  end
  table.sort(unlisted, function(a, b)
    if a.t ~= b.t then return a.t < b.t end
    return a.id < b.id
  end)
  for i = Rares.UNLISTED_CAP + 1, #unlisted do list[unlisted[i].id] = nil end
  return pairs(list)
end

function Rares.collect(records)
  local crew = {}
  for _, record in ipairs(records) do
    for id, entry in valid(record) do
      if BY_ID[id] then
        local had = crew[id]
        if not had or entry.t < had.time or (entry.t == had.time and tostring(record.id) < tostring(had.memberId)) then
          crew[id] = { time = entry.t, memberId = record.id, character = entry.c }
        end
      end
    end
  end
  return crew
end

function Rares.slain(records)
  local n = 0
  for _ in pairs(Rares.collect(records)) do n = n + 1 end
  return n
end

function Rares.text(name, who)
  return ("%s slew %s!"):format(who, name)
end
