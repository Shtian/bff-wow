local _, ns = ...

local Slots = {}
ns.Slots = Slots

local DEFAULT = "default"

local function nonEmpty(value)
  if type(value) == "string" and value ~= "" then return value end
  return nil
end

function Slots.facts(raw)
  if type(raw) ~= "table" then raw = {} end
  return {
    realmName = nonEmpty(raw.realmName),
    recordId = type(raw.recordId) == "number" and raw.recordId or nil,
    faction = nonEmpty(raw.faction),
    serverId = nonEmpty(raw.serverId),
    name = nonEmpty(raw.name),
  }
end

function Slots.serverIdOf(guid)
  return type(guid) == "string" and guid:match("^Player%-([^%-]+)%-") or nil
end

local function withFaction(base, faction)
  if not faction then return base end
  return base .. ":" .. faction
end

local function keyOf(facts)
  if facts.realmName then return withFaction("realm:" .. facts.realmName, facts.faction) end
  if facts.recordId then return withFaction("mode:" .. facts.recordId, facts.faction) end
  return DEFAULT
end

local function newSlotId(crews, random)
  while true do
    local id = ns.Ledger.newMemberId(random)
    if crews[id] == nil then return id end
  end
end

local function newSlot(db, key, random)
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

local function sortedKeys(map)
  local keys = {}
  for key in pairs(map) do keys[#keys + 1] = key end
  table.sort(keys)
  return keys
end

local function hasCrew(slot)
  return type(slot) == "table" and slot.crew ~= nil
end

local function tableOr(value)
  return type(value) == "table" and value or {}
end

local function otherEntry(rulesets, key, faction, matches)
  for _, other in ipairs(sortedKeys(rulesets)) do
    local entry = rulesets[other]
    if other ~= key and type(entry) == "table" and entry.faction == faction and matches(entry) then return other end
  end
  return nil
end

local function retag(db, key)
  local entry = db.rulesets[key]
  if type(entry) ~= "table" then return end
  for _, id in pairs({ entry.active, entry.left }) do
    local slot = db.crews[id]
    if type(slot) == "table" then slot.ruleset = key end
  end
end

local function swapEntries(db, from, to)
  db.rulesets[from], db.rulesets[to] = db.rulesets[to], db.rulesets[from]
  retag(db, from)
  retag(db, to)
end

local function repair(db, key, facts)
  local found = db.rulesets[key]
  if type(found) ~= "table" then found = nil end
  if found and holds(found.serverIds, facts.serverId) then return nil end
  local function byServerId(entry) return holds(entry.serverIds, facts.serverId) end
  local function byName(entry) return facts.name ~= nil and entry.name == facts.name end
  local from, by = otherEntry(db.rulesets, key, facts.faction, byServerId), "serverId"
  if not from and not found then from, by = otherEntry(db.rulesets, key, facts.faction, byName), "name" end
  if not from then
    if not found then db.rulesets[key] = {} end
    return nil
  end
  swapEntries(db, from, key)
  return { from = from, to = key, by = by, swapped = found ~= nil }
end

local function recordFacts(entry, facts)
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

local function migrate(db, random)
  if db.migrated then return end
  db.migrated = 1
  if type(db.crew) ~= "table" then return end
  local slot = {}
  for _, key in ipairs(SLOT_KEYS) do slot[key] = ns.Ledger.copied(db[key]) end
  local id = slot.memberId
  if type(id) ~= "string" or db.crews[id] ~= nil then id = newSlotId(db.crews, random) end
  db.crews[id] = slot
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

local function unplacedIds(db)
  local ids = {}
  for _, id in ipairs(sortedKeys(db.crews)) do
    local slot = db.crews[id]
    if type(slot) == "table" and slot.ruleset == nil then ids[#ids + 1] = id end
  end
  return ids
end

local function placeable(slot, key, facts, now)
  if facts.serverId then return crewServerIds(slot, now)[facts.serverId] == true, true end
  return key == DEFAULT, false
end

local function makeActive(db, key, id)
  local entry = db.rulesets[key]
  if entry.active ~= nil and entry.active ~= id then db.crews[entry.active] = nil end
  entry.active = id
  local slot = db.crews[id]
  slot.ruleset, slot.provisional = key, nil
  return slot
end

local function placeWaiting(db, key, facts, now)
  if hasCrew(db.crews[db.rulesets[key].active]) then return false end
  for _, id in ipairs(unplacedIds(db)) do
    local places, provisional = placeable(db.crews[id], key, facts, now)
    if places then
      makeActive(db, key, id).provisional = provisional or nil
      return true
    end
  end
  return false
end

local function activeSlot(db, key, random)
  local entry = db.rulesets[key]
  local slot = db.crews[entry.active]
  if type(slot) ~= "table" then
    entry.active, slot = newSlot(db, key, random)
  end
  return slot
end

function Slots.open(db, facts, random, now)
  if type(db.crews) ~= "table" then db.crews = {} end
  if type(db.rulesets) ~= "table" then db.rulesets = {} end
  migrate(db, random)
  local key = keyOf(facts)
  local repaired = repair(db, key, facts)
  local entry = db.rulesets[key]
  recordFacts(entry, facts)
  local placed = placeWaiting(db, key, facts, now)
  return { key = key, entry = entry, slot = activeSlot(db, key, random), repaired = repaired, placed = placed }
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
  entry.active, slot = newSlot(db, key, random)
  return slot
end

function Slots.rejoin(db, key)
  local entry = db.rulesets[key]
  db.crews[entry.active] = nil
  entry.active, entry.left = entry.left, nil
  return db.crews[entry.active]
end

function Slots.find(db, facts)
  local entry = tableOr(db.rulesets)[keyOf(Slots.facts(facts))]
  return type(entry) == "table" and tableOr(db.crews)[entry.active] or nil
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

local function latestName(slot, serverIds)
  local own = ownRecord(slot)
  local latest
  for guid, character in pairs(own and own.characters or {}) do
    local onServer = serverIds == nil or serverIds[Slots.serverIdOf(guid)] == true
    if onServer and type(character.lastPlayed) == "number"
      and (not latest or character.lastPlayed > latest.lastPlayed) then
      latest = character
    end
  end
  return latest and latest.name
end

local function otherCrews(db, key)
  local list = {}
  for _, other in ipairs(sortedKeys(db.rulesets)) do
    local entry = db.rulesets[other]
    local slot = other ~= key and type(entry) == "table" and db.crews[entry.active]
    if hasCrew(slot) then list[#list + 1] = { key = other, entry = entry, slot = slot } end
  end
  return list
end

local function offered(db, key)
  local current = db.rulesets[key]
  local base = baseOf(key, current)
  for _, other in ipairs(otherCrews(db, key)) do
    if other.slot.provisional and other.entry.faction ~= current.faction and baseOf(other.key, other.entry) == base then
      return other
    end
  end
  return nil
end

local function waitingCrew(db, now)
  for _, id in ipairs(unplacedIds(db)) do
    local slot = db.crews[id]
    if hasCrew(slot) then return id, slot, crewServerIds(slot, now) end
  end
  return nil
end

local function askedAbout(db, key, now)
  local id, _, serverIds = waitingCrew(db, now)
  if not id or next(serverIds) or db.rulesets[key].declined then return nil end
  return id
end

local function crewAt(entry, slot)
  return { name = entry.name, faction = entry.faction, character = latestName(slot) }
end

function Slots.elsewhere(db, key, now)
  local crews = {}
  local offer = offered(db, key)
  for _, other in ipairs(otherCrews(db, key)) do crews[#crews + 1] = crewAt(other.entry, other.slot) end
  local id, slot, serverIds = waitingCrew(db, now)
  if id and next(serverIds) then crews[#crews + 1] = { character = latestName(slot, serverIds) } end
  return {
    crews = crews,
    ask = askedAbout(db, key, now) ~= nil or nil,
    offer = offer and crewAt(offer.entry, offer.slot) or nil,
  }
end

function Slots.placeHere(db, key, now)
  local id = askedAbout(db, key, now)
  return id and makeActive(db, key, id) or nil
end

function Slots.decline(db, key, now)
  if not askedAbout(db, key, now) then return false end
  db.rulesets[key].declined = true
  return true
end

function Slots.bringHere(db, key, random)
  local from = offered(db, key)
  if not from then return nil end
  local id = from.entry.active
  from.entry.active = newSlot(db, from.key, random)
  return makeActive(db, key, id)
end
