local _, ns = ...

local Slots = {}
ns.Slots = Slots

Slots.DEFAULT = "default"

local function text(value)
  if type(value) == "string" and value ~= "" then return value end
  return nil
end

function Slots.facts(raw)
  if type(raw) ~= "table" then raw = {} end
  return {
    realmName = text(raw.realmName),
    recordId = type(raw.recordId) == "number" and raw.recordId or nil,
    faction = text(raw.faction),
    serverId = text(raw.serverId),
    name = text(raw.name),
  }
end

local function withFaction(base, faction)
  if not faction then return base end
  return base .. ":" .. faction
end

function Slots.key(facts)
  if facts.realmName then return withFaction("realm:" .. facts.realmName, facts.faction) end
  if facts.recordId then return withFaction("mode:" .. facts.recordId, facts.faction) end
  return Slots.DEFAULT
end

local function newSlotId(crews, random)
  while true do
    local id = ns.Ledger.newMemberId(random)
    if crews[id] == nil then return id end
  end
end

local function layout(db)
  if type(db.crews) ~= "table" then db.crews = {} end
  if type(db.rulesets) ~= "table" then db.rulesets = {} end
end

function Slots.newSlot(db, key, random)
  layout(db)
  local id = newSlotId(db.crews, random)
  db.crews[id] = { ruleset = key, memberId = id }
  return id, db.crews[id]
end

local function holds(list, value)
  for _, item in ipairs(type(list) == "table" and list or {}) do
    if item == value then return true end
  end
  return false
end

local function sortedKeys(rulesets)
  local keys = {}
  for key in pairs(rulesets) do keys[#keys + 1] = key end
  table.sort(keys)
  return keys
end

local function findMoved(rulesets, facts)
  local keys = sortedKeys(rulesets)
  local function first(matches)
    for _, key in ipairs(keys) do
      local entry = rulesets[key]
      if type(entry) == "table" and entry.faction == facts.faction and matches(entry) then return key end
    end
    return nil
  end
  local byServer = facts.serverId and first(function(entry) return holds(entry.serverIds, facts.serverId) end)
  if byServer then return byServer, "serverId" end
  local byName = facts.name and first(function(entry) return entry.name == facts.name end)
  if byName then return byName, "name" end
  return nil
end

local function moveEntry(db, from, to)
  local entry = db.rulesets[from]
  db.rulesets[from] = nil
  db.rulesets[to] = entry
  for _, id in ipairs({ entry.active, entry.left }) do
    local slot = db.crews[id]
    if type(slot) == "table" then slot.ruleset = to end
  end
end

local function note(entry, facts)
  entry.recordId = facts.recordId or entry.recordId
  entry.name = facts.name or entry.name
  entry.faction = facts.faction
  if type(entry.serverIds) ~= "table" then entry.serverIds = {} end
  if facts.serverId and not holds(entry.serverIds, facts.serverId) then
    entry.serverIds[#entry.serverIds + 1] = facts.serverId
  end
end

local function activeSlot(db, key, random)
  local entry = db.rulesets[key]
  local slot = db.crews[entry.active]
  if type(slot) ~= "table" then
    entry.active, slot = Slots.newSlot(db, key, random)
  end
  return slot
end

function Slots.open(db, facts, random)
  layout(db)
  local key = Slots.key(facts)
  local repaired
  if type(db.rulesets[key]) ~= "table" then
    local from, by = findMoved(db.rulesets, facts)
    if from then
      moveEntry(db, from, key)
      repaired = { from = from, to = key, by = by }
    else
      db.rulesets[key] = {}
    end
  end
  local entry = db.rulesets[key]
  note(entry, facts)
  return { key = key, entry = entry, slot = activeSlot(db, key, random), repaired = repaired }
end

function Slots.left(db, key)
  local slot = db.crews[db.rulesets[key].left]
  return type(slot) == "table" and slot or nil
end

function Slots.dropLeft(db, key)
  local entry = db.rulesets[key]
  if entry.left ~= nil then db.crews[entry.left] = nil end
  entry.left = nil
end

function Slots.leave(db, key, random)
  Slots.dropLeft(db, key)
  local entry = db.rulesets[key]
  local slot
  entry.left = entry.active
  entry.active, slot = Slots.newSlot(db, key, random)
  return slot
end

function Slots.rejoin(db, key)
  local entry = db.rulesets[key]
  db.crews[entry.active] = nil
  entry.active, entry.left = entry.left, nil
  return db.crews[entry.active]
end

function Slots.find(db, facts)
  local rulesets = type(db.rulesets) == "table" and db.rulesets or {}
  local entry = rulesets[Slots.key(Slots.facts(facts))]
  local crews = type(db.crews) == "table" and db.crews or {}
  return type(entry) == "table" and crews[entry.active] or nil
end
