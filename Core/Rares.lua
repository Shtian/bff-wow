-- Rares: the pure parts of the Crew's Rare kills. The list of Rares (data,
-- keyed by NPC ID: a new Rare is one row), the watch that tells a kill
-- from the game's unit and loot reads (handed the API, so offline tests
-- can fake it), how a Member's Rare kills are kept in their own record,
-- and how the records add up to the Crew's: the earliest kill per Rare.
-- Goals keeps the Crew's as trophies. Stateless but for the watch's
-- memory of units seen; tested through Core. See docs/design/rares.md
-- and docs/research/rare-mobs.md.

local _, ns = ...

local Rares = {}
ns.Rares = Rares

-- The Rares: NPC ID, name (English), zone, level, and elite for a rare
-- elite. Only mobs the game classifies as rare ("rare" or "rareelite"):
-- famous elites (Mor'Ladim, Gazz'uz, and Mother Fang, Elite on Forever)
-- aren't. Levels and classifications are Wowhead Forever's, 2026-11-13.
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

-- Level order, the list's own order breaking ties; each Rare's place in
-- it, and each by NPC ID.
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

-- The Rares slain track's steps: the last is every Rare.
Rares.STEPS = { 5, 10, 20, Rares.TOTAL }

-- How many unlisted rares a record keeps: past it, a new one is dropped.
Rares.UNLISTED_CAP = 50
-- A rares field with more entries than this is ignored as a whole.
local MAX_ENTRIES = 200
-- How many units the watch remembers before it starts over.
local MEMORY = 100
-- What the dev logger shows for a value that read secret.
local SECRET = "<secret>"

-- The Rare with an NPC ID, or nil when it isn't on the list.
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

-- The NPC ID in a creature's GUID ("Creature-0-[server]-[instance]-[zone]-
-- [npc]-[spawn]"; Forever obfuscates the server and spawn parts), or nil
-- for anything else.
function Rares.npcId(guid)
  if type(guid) ~= "string" then return nil end
  local kind, id = guid:match("^(%a+)%-[^-]*%-[^-]*%-[^-]*%-[^-]*%-(%d+)%-")
  if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
  id = tonumber(id)
  return isId(id) and id or nil
end

local RARE_CLASSES = { rare = true, rareelite = true }

-- The watch: tells a Rare kill from what the game lets an addon read
-- (docs/research/rare-mobs.md, section 4), through api: unitGUID,
-- unitName, unitClassification, unitIsDead, unitIsTapDenied (the globals
-- of those names), getNumLootItems, getLootSourceInfo, zone
-- (GetRealZoneText), subzone (GetSubZoneText), mapId
-- (C_Map.GetBestMapForUnit("player")) and isSecret (issecretvalue,
-- optional). Each call returns what it found and an info for the dev
-- logger: { signal, read (each value read, "<secret>" when secret),
-- secret (the names of those that were), result (what it made of them) }.
-- A value that reads secret, or a read that errors, finds nothing: it
-- costs that kill, never an error. A kill is { npcId, signal ("loot",
-- "target" or "partyKill"), unlisted (a rare not on the list), name (an
-- unlisted one's, when read), zone, subzone, mapId }.
local Watch = {}
Watch.__index = Watch

function Rares.watch(api)
  return setmetatable({
    api = api,
    isSecret = api.isSecret or function() return false end,
    -- Units seen while readable, by GUID: { npcId, name, rare }.
    seen = {},
    count = 0,
    -- The target as last seen while readable, nil when it couldn't be.
    target = nil,
  }, Watch)
end

local function newInfo(signal)
  return { signal = signal, read = {}, secret = {} }
end

-- Reads a value for info under name: nil, true when it's secret.
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

-- Runs fn(info) guarded: an error is the info's result, and finds nothing.
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

-- Where the kill happened, each nil when unknown or secret.
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

-- A kill of the creature with this GUID, if it's on the list or was seen
-- classified rare; else nil and why not.
local function killOf(self, guid, signal, unit)
  local npcId = Rares.npcId(guid)
  if not npcId then return nil, "notCreature" end
  unit = unit or self.seen[guid]
  if BY_ID[npcId] then return { npcId = npcId, signal = signal } end
  if unit and unit.rare then return { npcId = npcId, signal = signal, unlisted = true, name = unit.name } end
  return nil, "notRare"
end

-- A unit read: its GUID, NPC ID, name and whether the game calls it
-- rare. Nil when its GUID can't be read.
local function readUnit(self, info, token)
  local guid = read(self, info, "guid", self.api.unitGUID(token))
  if type(guid) ~= "string" then return nil end
  local npcId = Rares.npcId(guid)
  if not npcId then return nil end
  local class = read(self, info, "classification", self.api.unitClassification(token))
  local name = read(self, info, "name", self.api.unitName(token))
  return guid, { npcId = npcId, name = text(name), rare = RARE_CLASSES[class] == true }
end

-- A unit was seen (PLAYER_TARGET_CHANGED for "target",
-- UPDATE_MOUSEOVER_UNIT, NAME_PLATE_UNIT_ADDED): a listed rare, or one
-- the game calls rare, is remembered by its GUID while it can be read.
-- The target is remembered apart, until the next target change, so its
-- death can be told once its GUID reads secret in combat. Returns the info.
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

-- The loot window filled (LOOT_READY): every rare among its corpses, each
-- once. Looting a corpse means your group had the tag. Returns the kills
-- (a list) and the info.
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

-- The target died (PLAYER_TARGET_DIED), or combat ended
-- (PLAYER_REGEN_ENABLED): a rare target that's dead and that nobody
-- outside the group tagged is a kill. Its GUID is read now, or, while it
-- reads secret, taken from when it was targeted. Returns the kill (or
-- nil) and the info.
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

-- PARTY_KILL: someone in the group killed something. Counts when the
-- target's GUID can be read. Returns the kill (or nil) and the info.
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

-- Adds a kill (as the watch gives it) to the own record, made at time by
-- the Character with GUID character. Its rares are { [npcId] = { t, z, s,
-- m, c, n } }: t the first kill's time, z, s and m its zone, subzone and
-- map ID, c the Character's GUID, and n an unlisted rare's name. Only the
-- first kill of each is kept; unlisted rares past UNLISTED_CAP are
-- dropped. Returns true if the record changed, else false and why not:
-- "unreadable", "had" or "full".
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

-- A record's Rare kills, skipping anything malformed (a record from the
-- wire isn't shape-checked for them): for npcId, entry in valid(record).
-- A field with more than MAX_ENTRIES is ignored; unlisted rares past
-- UNLISTED_CAP (the earliest kept) are skipped.
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

-- The Crew's Rare kills over the given records: { [npcId] = { time (the
-- earliest), memberId (whose it was; ties go to the lower Member id),
-- character (that kill's Character GUID, or nil) } }, listed Rares only.
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

-- How many listed Rares anyone in the given records has slain.
function Rares.slain(records)
  local n = 0
  for _ in pairs(Rares.collect(records)) do n = n + 1 end
  return n
end

-- The Feed entry's text for the Crew's first kill of a Rare: "Ana slew
-- Rak'shiri!", "You slew Rak'shiri!".
function Rares.text(name, who)
  return ("%s slew %s!"):format(who, name)
end
