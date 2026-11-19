local _, ns = ...

local Clears = {}
ns.Clears = Clears

local INSTANCES = {}
local FINAL_BOSSES = {}
for _, dungeon in ipairs(ns.Together.DUNGEONS) do
  if dungeon.kind == "dungeon" or dungeon.kind == "raid" then
    INSTANCES[dungeon.name] = dungeon
    for _, id in ipairs(dungeon.finals or {}) do FINAL_BOSSES[id] = dungeon.name end
  end
end
Clears.FINAL_BOSSES = FINAL_BOSSES

function Clears.instance(name)
  return INSTANCES[name]
end

function Clears.instances(kind)
  local list = {}
  for _, dungeon in ipairs(ns.Together.DUNGEONS) do
    if dungeon.kind == kind then list[#list + 1] = dungeon end
  end
  return list
end

function Clears.cleared(encounter, finals)
  if type(encounter) ~= "table" or type(encounter.encounterId) ~= "number"
      or type(encounter.success) ~= "boolean" or type(encounter.party) ~= "table" then
    return nil, "unreadable"
  end
  if not encounter.success then return nil, "wipe" end
  if encounter.instanceType ~= "party" and encounter.instanceType ~= "raid" then return nil, "notInstance" end
  local name = finals[encounter.encounterId]
  if not INSTANCES[name] then return nil, "unknown" end
  return name
end

function Clears.add(record, name, time, members)
  record.clears = record.clears or {}
  local clear = record.clears[name]
  if not clear then
    record.clears[name] = { t = time, m = members }
    return true
  end
  local changed = false
  local had = {}
  for _, id in ipairs(clear.m) do had[id] = true end
  for _, id in ipairs(members) do
    if not had[id] then
      clear.m[#clear.m + 1] = id
      changed = true
    end
  end
  return changed
end

local function valid(record)
  local list = {}
  if type(record.clears) ~= "table" then return pairs(list) end
  for name, clear in pairs(record.clears) do
    if INSTANCES[name] and type(clear) == "table" and type(clear.t) == "number" and type(clear.m) == "table" then
      list[name] = clear
    end
  end
  return pairs(list)
end

function Clears.collect(records)
  local crew = {}
  for _, record in ipairs(records) do
    for name, clear in valid(record) do
      local entry = crew[name]
      if not entry then
        entry = { time = clear.t, members = {} }
        crew[name] = entry
      end
      entry.time = math.min(entry.time, clear.t)
      for _, id in ipairs(clear.m) do
        if type(id) == "string" then entry.members[id] = true end
      end
    end
  end
  return crew
end

function Clears.text(name)
  return ("The Crew cleared %s!"):format(name)
end

function Clears.label(name)
  return (name:gsub("^The ", ""))
end

function Clears.levels(dungeon)
  if dungeon.from == dungeon.to then return tostring(dungeon.from) end
  return ("%d–%d"):format(dungeon.from, dungeon.to)
end
