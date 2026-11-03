-- Clears: the pure parts of dungeon and raid clears. Which boss kill clears
-- which instance (its final boss, from the dungeon table), how a Member's
-- clears are kept in their own record, and how the clears in every record
-- add up to the Crew's: per instance, the earliest clear and everyone who
-- was in a clearing party. Stateless; Goals keeps the Crew's clears as
-- trophies, tested through Core. See docs/design/trophies.md and
-- docs/adr/0005-clears-kept-in-each-members-own-record.md.

local _, ns = ...

local Clears = {}
ns.Clears = Clears

-- The dungeons and raids by name (attunements aren't cleared), and each
-- known final boss's encounter ID to its instance's name.
local INSTANCES = {}
local FINAL_BOSSES = {}
for _, dungeon in ipairs(ns.Together.DUNGEONS) do
  if dungeon.kind == "dungeon" or dungeon.kind == "raid" then
    INSTANCES[dungeon.name] = dungeon
    for _, id in ipairs(dungeon.finals or {}) do FINAL_BOSSES[id] = dungeon.name end
  end
end
Clears.FINAL_BOSSES = FINAL_BOSSES

-- The dungeon table's entry for an instance that can be cleared, or nil.
function Clears.instance(name)
  return INSTANCES[name]
end

-- Every instance of a kind ("dungeon" or "raid"), in the table's order
-- (by level).
function Clears.instances(kind)
  local list = {}
  for _, dungeon in ipairs(ns.Together.DUNGEONS) do
    if dungeon.kind == kind then list[#list + 1] = dungeon end
  end
  return list
end

-- Which instance an ENCOUNTER_END clears: { encounterId, success,
-- instanceType ("party" or "raid"), party }, with a secret value read as
-- nil, against finals (encounter ID to instance name). Returns the name,
-- or nil and why not: "unreadable", "wipe", "notInstance" or "unknown".
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

-- Adds a clear to the own record: the instance, when, and the Member ids
-- in the party. Its clears are { [name] = { t, m } }: t the first clear's
-- time, m every Member id in any of its clearing parties. Returns true if
-- the record changed (a first clear, or someone new in the party).
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

-- A record's clears of known instances, skipping anything malformed (a
-- record from the wire is only shape-checked above its clears): for name,
-- { t, m } in valid(record).
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

-- The Crew's clears over the given records: { [name] = { time (the
-- earliest), members (a set of Member ids from every clearing party) } }.
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

-- The Feed entry's text for the Crew's first clear.
function Clears.text(name)
  return ("The Crew cleared %s!"):format(name)
end

-- A medal's short name: "Deadmines" for The Deadmines.
function Clears.label(name)
  return (name:gsub("^The ", ""))
end

-- An instance's level range: "17–26", or "60".
function Clears.levels(dungeon)
  if dungeon.from == dungeon.to then return tostring(dungeon.from) end
  return ("%d–%d"):format(dungeon.from, dungeon.to)
end
