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
    guid = nonEmpty(raw.guid),
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

local function indexOf(list, value)
  for i, item in ipairs(type(list) == "table" and list or {}) do
    if item == value then return i end
  end
  return nil
end

local function holds(list, value)
  return indexOf(list, value) ~= nil
end

local function remove(list, value)
  local i = indexOf(list, value)
  if i then table.remove(list, i) end
  return i ~= nil
end

local function append(list, value)
  if not holds(list, value) then list[#list + 1] = value end
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

local function slotIdsOf(entry)
  local ids = {}
  for _, id in ipairs(tableOr(entry.crews)) do ids[#ids + 1] = id end
  for _, id in ipairs(tableOr(entry.left)) do ids[#ids + 1] = id end
  if entry.blank ~= nil then ids[#ids + 1] = entry.blank end
  return ids
end

local function retag(db, key)
  local entry = db.rulesets[key]
  if type(entry) ~= "table" then return end
  for _, id in ipairs(slotIdsOf(entry)) do
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
  entry.realmName = facts.realmName or entry.realmName
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

function Slots.lastPlayed(slot)
  local own = ownRecord(slot)
  local latest
  for _, character in pairs(own and own.characters or {}) do
    if type(character.lastPlayed) == "number" and (not latest or character.lastPlayed > latest) then
      latest = character.lastPlayed
    end
  end
  return latest
end

function Slots.otherNames(slot)
  local names = {}
  local removed = tableOr(slot.removed)
  for id, record in pairs(tableOr(slot.records)) do
    if id ~= slot.memberId and type(record) == "table" and not record.left and not removed[id]
      and type(record.displayName) == "string" then
      names[#names + 1] = record.displayName
    end
  end
  table.sort(names, function(a, b)
    if a:lower() ~= b:lower() then return a:lower() < b:lower() end
    return a < b
  end)
  return names
end

function Slots.ownDisplayName(slot)
  local own = ownRecord(slot)
  return own and own.displayName
end

local function migrateEntry(db, entry)
  if type(entry.crews) == "table" then return end
  local active, left = entry.active, entry.left
  entry.active, entry.crews, entry.left, entry.lastUsed = nil, {}, {}, {}
  local slot = db.crews[active]
  if hasCrew(slot) then
    entry.crews[1] = active
    local own = ownRecord(slot)
    for guid in pairs(own and own.characters or {}) do entry.lastUsed[guid] = active end
  elseif type(slot) == "table" then
    entry.blank = active
  end
  if type(db.crews[left]) == "table" then entry.left[1] = left end
end

local function shaped(db, entry)
  migrateEntry(db, entry)
  if type(entry.left) ~= "table" then entry.left = {} end
  if type(entry.lastUsed) ~= "table" then entry.lastUsed = {} end
  for _, list in ipairs({ entry.crews, entry.left }) do
    for i = #list, 1, -1 do
      if type(db.crews[list[i]]) ~= "table" then table.remove(list, i) end
    end
  end
  if entry.blank ~= nil and type(db.crews[entry.blank]) ~= "table" then entry.blank = nil end
  for guid, id in pairs(entry.lastUsed) do
    if id ~= false and not holds(entry.crews, id) then entry.lastUsed[guid] = false end
  end
  return entry
end

local function shapeAll(db)
  for _, entry in pairs(db.rulesets) do
    if type(entry) == "table" then shaped(db, entry) end
  end
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

local function dropBlank(db, entry)
  if entry.blank ~= nil then db.crews[entry.blank] = nil end
  entry.blank = nil
end

local function forget(entry, id)
  for guid, used in pairs(entry.lastUsed) do
    if used == id then entry.lastUsed[guid] = false end
  end
end

local function place(db, key, id)
  local entry = db.rulesets[key]
  dropBlank(db, entry)
  append(entry.crews, id)
  local slot = db.crews[id]
  slot.ruleset, slot.provisional = key, nil
  return slot
end

local function placeWaiting(db, key, facts, now)
  if #db.rulesets[key].crews > 0 then return false end
  for _, id in ipairs(unplacedIds(db)) do
    local places, provisional = placeable(db.crews[id], key, facts, now)
    if places then
      place(db, key, id).provisional = provisional or nil
      return true
    end
  end
  return false
end

function Slots.blank(db, key, random)
  local entry = db.rulesets[key]
  if entry.blank == nil then entry.blank = newSlot(db, key, random) end
  return entry.blank, db.crews[entry.blank]
end

local function chosen(entry, guid)
  local used = guid and entry.lastUsed[guid]
  if used then return used end
  if used == nil and #entry.crews == 1 then return entry.crews[1] end
  return nil
end

function Slots.use(db, key, id, guid)
  local entry = db.rulesets[key]
  if guid and holds(entry.crews, id) then entry.lastUsed[guid] = id end
  return db.crews[id]
end

function Slots.open(db, facts, random, now)
  if type(db.crews) ~= "table" then db.crews = {} end
  if type(db.rulesets) ~= "table" then db.rulesets = {} end
  migrate(db, random)
  shapeAll(db)
  local key = keyOf(facts)
  local repaired = repair(db, key, facts)
  local entry = shaped(db, db.rulesets[key])
  recordFacts(entry, facts)
  local placed = placeWaiting(db, key, facts, now)
  local id = chosen(entry, facts.guid)
  if id then
    Slots.use(db, key, id, facts.guid)
  else
    id = Slots.blank(db, key, random)
  end
  return { key = key, entry = entry, id = id, slot = db.crews[id], repaired = repaired, placed = placed }
end

function Slots.adopt(db, key, id, guid)
  local entry = db.rulesets[key]
  if entry.blank == id then entry.blank = nil end
  append(entry.crews, id)
  return Slots.use(db, key, id, guid)
end

function Slots.withCode(db, key, code)
  local entry = db.rulesets[key]
  for _, list in ipairs({ entry.crews, entry.left }) do
    for _, id in ipairs(list) do
      local crew = db.crews[id].crew
      if type(crew) == "table" and crew.code == code then return id, list == entry.left end
    end
  end
  return nil
end

function Slots.leave(db, key, id, random)
  local entry = db.rulesets[key]
  remove(entry.crews, id)
  remove(entry.left, id)
  table.insert(entry.left, 1, id)
  forget(entry, id)
  dropBlank(db, entry)
  return Slots.blank(db, key, random)
end

function Slots.rejoin(db, key, id, guid)
  local entry = db.rulesets[key]
  if not remove(entry.left, id) then return nil end
  dropBlank(db, entry)
  append(entry.crews, id)
  return Slots.use(db, key, id, guid)
end

function Slots.delete(db, key, id)
  local entry = db.rulesets[key]
  if not remove(entry.left, id) then return false end
  db.crews[id] = nil
  return true
end

function Slots.ids(db, key)
  local entry = db.rulesets[key]
  local crews, left = {}, {}
  for i, id in ipairs(entry.crews) do crews[i] = id end
  for i, id in ipairs(entry.left) do left[i] = id end
  return crews, left
end

function Slots.find(db, facts)
  facts = Slots.facts(facts)
  local entry = tableOr(db.rulesets)[keyOf(facts)]
  if type(entry) ~= "table" then return nil end
  local id = chosen(entry, facts.guid) or entry.blank
  return tableOr(db.crews)[id]
end

function Slots.outside(db, key)
  local list = {}
  for _, id in ipairs(sortedKeys(db.crews)) do
    local slot = db.crews[id]
    if type(slot) == "table" and slot.ruleset ~= key then list[#list + 1] = slot end
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
    for _, id in ipairs(other ~= key and type(entry) == "table" and tableOr(entry.crews) or {}) do
      local slot = db.crews[id]
      if hasCrew(slot) then list[#list + 1] = { key = other, entry = entry, id = id, slot = slot } end
    end
  end
  return list
end

local function firstPerRuleset(list)
  local seen, firsts = {}, {}
  for _, other in ipairs(list) do
    if not seen[other.key] then
      seen[other.key] = true
      firsts[#firsts + 1] = other
    end
  end
  return firsts
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

local function reachableServerIds(slot, now)
  local own = ownRecord(slot)
  local reachable = {}
  for serverId in pairs(crewServerIds(slot, now)) do
    for guid in pairs(own and own.characters or {}) do
      if Slots.serverIdOf(guid) == serverId then reachable[serverId] = true end
    end
  end
  return reachable
end

local function waitingCrew(db, now)
  for _, id in ipairs(unplacedIds(db)) do
    local slot = db.crews[id]
    if hasCrew(slot) then return id, slot, reachableServerIds(slot, now) end
  end
  return nil
end

local function askedAbout(db, key, now)
  local id, _, serverIds = waitingCrew(db, now)
  if not id or next(serverIds) or db.rulesets[key].declined then return nil end
  return id
end

local function crewAt(entry, slot)
  return { name = entry.name or entry.realmName, faction = entry.faction, character = latestName(slot) }
end

function Slots.elsewhere(db, key, now)
  local crews = {}
  local offer = offered(db, key)
  for _, other in ipairs(firstPerRuleset(otherCrews(db, key))) do
    crews[#crews + 1] = crewAt(other.entry, other.slot)
  end
  local id, slot, serverIds = waitingCrew(db, now)
  if id and next(serverIds) then crews[#crews + 1] = { character = latestName(slot, serverIds) } end
  return {
    crews = crews,
    ask = askedAbout(db, key, now) ~= nil or nil,
    offer = offer and crewAt(offer.entry, offer.slot) or nil,
  }
end

function Slots.placeHere(db, key, now, guid)
  local id = askedAbout(db, key, now)
  if not id then return nil end
  place(db, key, id)
  return Slots.use(db, key, id, guid), id
end

function Slots.decline(db, key, now)
  if not askedAbout(db, key, now) then return false end
  db.rulesets[key].declined = true
  return true
end

function Slots.bringHere(db, key, guid)
  local from = offered(db, key)
  if not from then return nil end
  remove(from.entry.crews, from.id)
  forget(from.entry, from.id)
  place(db, key, from.id)
  return Slots.use(db, key, from.id, guid), from.id
end
