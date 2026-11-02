-- Professions: the pure parts of a Character's Professions. Reading them
-- from the game (handed the API, so offline tests can fake it), how a list
-- is stored in a record (short field names) and checked off the wire, the
-- rank from the max skill, and the Professions tab's grid.
-- See docs/design/professions.md.

local _, ns = ...

local Professions = {}
ns.Professions = Professions

-- GetProfessions() has five slots: two main professions, then first aid,
-- fishing and cooking.
local SLOTS = 5
local SECONDARY_FROM = 3
-- Forever caps professions at 300 (#97).
Professions.CAP = 300
local RANKS = { { 300, "Artisan" }, { 225, "Expert" }, { 150, "Journeyman" }, { 75, "Apprentice" } }
-- The secondary columns' order, by skill line ID: cooking, fishing, first
-- aid. Any other secondary goes after them, by name.
local SECONDARY_ORDER = { [185] = 1, [356] = 2, [129] = 3 }
local OTHER_SECONDARY = 4

-- The rank a max skill stands for: 75 Apprentice up to 300 Artisan. Nil
-- below 75.
function Professions.rank(max)
  for _, rank in ipairs(RANKS) do
    if max >= rank[1] then return rank[2] end
  end
  return nil
end

local function isCount(value)
  return type(value) == "number" and value >= 0 and value == math.floor(value)
end

local function readAll(api)
  local isSecret = api.isSecret or function() return false end
  local slots = { api.getProfessions() }
  local list = {}
  for slot = 1, SLOTS do
    local index = slots[slot]
    if index ~= nil then
      if isSecret(index) then return nil end
      local name, icon, skill, max, _, _, skillLine = api.getProfessionInfo(index)
      for _, value in ipairs({ name, icon, skill, max, skillLine }) do
        if isSecret(value) then return nil end
      end
      -- Anything a record couldn't store keeps the last list instead.
      if type(name) ~= "string" or name == "" or not isCount(skill) or not isCount(max) or max == 0
        or not isCount(skillLine) or skillLine == 0 then
        return nil
      end
      list[#list + 1] = {
        skillLine = skillLine,
        name = name,
        icon = type(icon) == "number" and icon or nil,
        skill = skill,
        max = max,
        secondary = slot >= SECONDARY_FROM or nil,
      }
    end
  end
  return list
end

-- The Character's professions as the game has them, through api:
-- getProfessions (GetProfessions), getProfessionInfo (GetProfessionInfo)
-- and isSecret (issecretvalue, optional). A list of up to 5 { skillLine,
-- name, icon, skill (the base skill, without gear and racial bonuses), max,
-- secondary }, in the game's order; empty for none. A value that reads
-- secret, or a read that errors, keeps `last`.
function Professions.read(api, last)
  local ok, list = pcall(readAll, api)
  if ok and list then return list end
  return last
end

local function validEntry(entry)
  return type(entry) == "table"
    and isCount(entry.id) and entry.id > 0
    and type(entry.n) == "string" and entry.n ~= ""
    and (entry.i == nil or type(entry.i) == "number")
    and isCount(entry.k)
    and isCount(entry.m) and entry.m > 0
    and (entry.s == nil or entry.s == true)
end

-- Whether a list from a record has the expected shape: up to 5 entries of
-- { id (skill line), n (name), i (icon file ID, optional), k (skill), m
-- (max skill), s (true if secondary) }.
local function valid(stored)
  if type(stored) ~= "table" then return false end
  local count = 0
  for _ in pairs(stored) do count = count + 1 end
  if count > SLOTS or count ~= #stored then return false end
  for _, entry in ipairs(stored) do
    if not validEntry(entry) then return false end
  end
  return true
end

-- A list from read() as the record stores it, or nil for none known.
function Professions.store(list)
  if type(list) ~= "table" then return nil end
  local stored = {}
  for i, p in ipairs(list) do
    stored[i] = { id = p.skillLine, n = p.name, i = p.icon, k = p.skill, m = p.max, s = p.secondary or nil }
  end
  if not valid(stored) then return nil end
  return stored
end

-- Whether two stored lists are the same.
function Professions.same(a, b)
  if a == nil or b == nil then return a == b end
  if #a ~= #b then return false end
  for i, entry in ipairs(a) do
    local other = b[i]
    for _, field in ipairs({ "id", "n", "i", "k", "m", "s" }) do
      if entry[field] ~= other[field] then return false end
    end
  end
  return true
end

local function secondaryOrder(p)
  return SECONDARY_ORDER[p.skillLine] or OTHER_SECONDARY
end

-- Main professions first, then cooking, fishing and first aid; the game's
-- order, or by name, otherwise.
local function listedBefore(a, b)
  if a.secondary ~= b.secondary then return b.secondary end
  if a.secondary and secondaryOrder(a) ~= secondaryOrder(b) then
    return secondaryOrder(a) < secondaryOrder(b)
  end
  if a.position and b.position then return a.position < b.position end
  if a.name ~= b.name then return a.name < b.name end
  return a.skillLine < b.skillLine
end

-- A stored list as rows show it, or nil when unknown or malformed: a fresh
-- list of { skillLine, name, icon, skill, max, secondary, rank, full (skill
-- at the max skill), capped (skill at 300) }, main professions first.
function Professions.describe(stored)
  if not valid(stored) then return nil end
  local list = {}
  for i, entry in ipairs(stored) do
    list[i] = {
      skillLine = entry.id,
      name = entry.n,
      icon = entry.i,
      skill = entry.k,
      max = entry.m,
      secondary = entry.s == true,
      rank = Professions.rank(entry.m),
      full = entry.k >= entry.m,
      capped = entry.k >= Professions.CAP,
      position = i,
    }
  end
  table.sort(list, listedBefore)
  for _, p in ipairs(list) do p.position = nil end
  return list
end

-- The Professions tab from the Roster's rows (own first, then in the
-- Roster's order). See Core:professions().
function Professions.grid(rows)
  local columns, bySkillLine = {}, {}
  local gridRows = {}
  local function addCharacter(row, character, first)
    local gridRow = {
      memberId = row.memberId,
      own = row.own == true,
      displayName = row.displayName,
      name = character.name,
      classFilename = character.classFilename,
      level = character.level,
      main = character.main,
      alt = not character.main,
      first = first or nil,
      known = character.professions ~= nil,
      professions = character.professions,
    }
    for _, p in ipairs(character.professions or {}) do
      if not bySkillLine[p.skillLine] then
        local column = { skillLine = p.skillLine, name = p.name, icon = p.icon, secondary = p.secondary }
        bySkillLine[p.skillLine] = column
        columns[#columns + 1] = column
      end
    end
    gridRows[#gridRows + 1] = gridRow
  end
  for _, row in ipairs(rows) do
    local characters = { row }
    for _, alt in ipairs(row.alts) do characters[#characters + 1] = alt end
    for i, character in ipairs(characters) do
      if character.main then
        table.remove(characters, i)
        table.insert(characters, 1, character)
        break
      end
    end
    for i, character in ipairs(characters) do addCharacter(row, character, i == 1) end
  end

  table.sort(columns, listedBefore)
  for _, gridRow in ipairs(gridRows) do
    gridRow.cells = {}
    if gridRow.known then
      local learned = {}
      for _, p in ipairs(gridRow.professions) do learned[p.skillLine] = p end
      for i, column in ipairs(columns) do gridRow.cells[i] = learned[column.skillLine] or false end
    end
    gridRow.professions = nil
  end
  return { columns = columns, rows = gridRows }
end
