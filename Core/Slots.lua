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

local SLOT_KEYS = {
  "crew", "channelMoves", "joinFailure",
  "memberId", "records", "via", "removed", "heard",
  "feed", "feedJoins", "goals",
  "spareItems", "nextSpare", "spareNews", "spareWinners", "catchTypesTold",
  "paused", "playTimes", "stray",
}

local function copied(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for k, v in pairs(value) do result[k] = copied(v) end
  return result
end

local function migrate(db, random)
  if db.migrated then return end
  db.migrated = 1
  if type(db.crew) ~= "table" then return end
  local slot = {}
  for _, key in ipairs(SLOT_KEYS) do slot[key] = copied(db[key]) end
  local id = slot.memberId
  if type(id) ~= "string" or db.crews[id] ~= nil then id = newSlotId(db.crews, random) end
  db.crews[id] = slot
end

function Slots.serverIdOf(guid)
  return type(guid) == "string" and guid:match("^Player%-([^%-]+)%-") or nil
end

local function tableOr(value)
  return type(value) == "table" and value or {}
end

local function ownRecord(slot)
  local record = tableOr(slot.records)[slot.memberId]
  return type(record) == "table" and type(record.characters) == "table" and record or nil
end

local function othersServerIds(slot)
  local ids = {}
  for id, record in pairs(tableOr(slot.records)) do
    if id ~= slot.memberId and type(record) == "table" then
      for guid in pairs(tableOr(record.characters)) do
        local serverId = Slots.serverIdOf(guid)
        if serverId then ids[serverId] = true end
      end
    end
  end
  return ids
end

local function crewServerIds(slot, now)
  local others = othersServerIds(slot)
  if next(others) then return others end
  local own = ownRecord(slot)
  local main = own and ns.Roster.main(own, now)
  local serverId = main and Slots.serverIdOf(main.guid)
  return serverId and { [serverId] = true } or {}
end

function Slots.belongsHere(slot, serverId)
  local others = othersServerIds(slot)
  return function(guid)
    local id = Slots.serverIdOf(guid)
    return id == nil or id == serverId or others[id] == true
  end
end

local function unclaimedIds(db)
  local ids = {}
  for _, id in ipairs(sortedKeys(db.crews)) do
    local slot = db.crews[id]
    if type(slot) == "table" and slot.ruleset == nil then ids[#ids + 1] = id end
  end
  return ids
end

local function claimable(slot, key, facts, now)
  if facts.serverId then return crewServerIds(slot, now)[facts.serverId] == true, true end
  return key == Slots.DEFAULT, false
end

local function claim(db, key, facts, now)
  local entry = db.rulesets[key]
  local active = db.crews[entry.active]
  if type(active) == "table" and active.crew ~= nil then return false end
  for _, id in ipairs(unclaimedIds(db)) do
    local slot = db.crews[id]
    local claims, provisional = claimable(slot, key, facts, now)
    if claims then
      if entry.active ~= nil then db.crews[entry.active] = nil end
      entry.active = id
      slot.ruleset = key
      slot.provisional = provisional or nil
      return true
    end
  end
  return false
end

local function activeSlot(db, key, random)
  local entry = db.rulesets[key]
  local slot = db.crews[entry.active]
  if type(slot) ~= "table" then
    entry.active, slot = Slots.newSlot(db, key, random)
  end
  return slot
end

function Slots.open(db, facts, random, now)
  layout(db)
  migrate(db, random)
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
  local claimed = claim(db, key, facts, now)
  return { key = key, entry = entry, slot = activeSlot(db, key, random), repaired = repaired, claimed = claimed }
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

function Slots.others(db, slot)
  local list = {}
  for _, id in ipairs(sortedKeys(db.crews)) do
    local other = db.crews[id]
    if type(other) == "table" and other ~= slot then list[#list + 1] = other end
  end
  return list
end

local function baseOf(key, entry)
  local faction = entry.faction
  if not faction then return key end
  local suffix = ":" .. faction
  return key:sub(-#suffix) == suffix and key:sub(1, -#suffix - 1) or key
end

local function latestName(slot)
  local own = ownRecord(slot)
  local latest
  for _, character in pairs(own and own.characters or {}) do
    if type(character.lastPlayed) == "number" and (not latest or character.lastPlayed > latest.lastPlayed) then
      latest = character
    end
  end
  return latest and latest.name
end

function Slots.elsewhere(db, key)
  local current = db.rulesets[key]
  local base = baseOf(key, current)
  local crews, offer = {}, nil
  for _, other in ipairs(sortedKeys(db.rulesets)) do
    local entry = db.rulesets[other]
    local slot = other ~= key and type(entry) == "table" and db.crews[entry.active]
    if type(slot) == "table" and slot.crew ~= nil then
      crews[#crews + 1] = { key = other, name = entry.name, faction = entry.faction, character = latestName(slot) }
      if slot.provisional and entry.faction ~= current.faction and baseOf(other, entry) == base then
        offer = offer or { key = other, name = entry.name, faction = entry.faction }
      end
    end
  end
  local unclaimed = false
  for _, id in ipairs(unclaimedIds(db)) do
    if db.crews[id].crew ~= nil then unclaimed = true end
  end
  return { crews = crews, offer = offer, unclaimed = unclaimed or nil }
end
