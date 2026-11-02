-- Professions: the pure parts of a Character's Professions. Reading them
-- from the game (handed the API, so offline tests can fake it), how a list
-- is stored in a record (short field names) and checked off the wire, the
-- rank from the max skill, and the Professions tab: who has each profession.
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
-- The twelve professions, by skill line, in the tabs' order: main ones by
-- name, then cooking, fishing and first aid. The name and icon are for a
-- profession nobody has; one somebody has shows as their client words it.
-- noun names whoever has it, for Every profession in the Crew's Feed entry.
Professions.ALL = {
  { skillLine = 171, name = "Alchemy", noun = "an Alchemist", icon = "Interface\\Icons\\Trade_Alchemy" },
  { skillLine = 164, name = "Blacksmithing", noun = "a Blacksmith", icon = "Interface\\Icons\\Trade_BlackSmithing" },
  { skillLine = 333, name = "Enchanting", noun = "an Enchanter", icon = "Interface\\Icons\\Trade_Engraving" },
  { skillLine = 202, name = "Engineering", noun = "an Engineer", icon = "Interface\\Icons\\Trade_Engineering" },
  { skillLine = 182, name = "Herbalism", noun = "a Herbalist", icon = "Interface\\Icons\\Trade_Herbalism" },
  { skillLine = 165, name = "Leatherworking", noun = "a Leatherworker",
    icon = "Interface\\Icons\\Trade_LeatherWorking" },
  { skillLine = 186, name = "Mining", noun = "a Miner", icon = "Interface\\Icons\\Trade_Mining" },
  { skillLine = 393, name = "Skinning", noun = "a Skinner", icon = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01" },
  { skillLine = 197, name = "Tailoring", noun = "a Tailor", icon = "Interface\\Icons\\Trade_Tailoring" },
  { skillLine = 185, name = "Cooking", noun = "a Cook", icon = "Interface\\Icons\\INV_Misc_Food_15", secondary = true },
  { skillLine = 356, name = "Fishing", noun = "an Angler", icon = "Interface\\Icons\\Trade_Fishing", secondary = true },
  { skillLine = 129, name = "First Aid", noun = "a First Aider", icon = "Interface\\Icons\\Spell_Holy_SealOfSacrifice",
    secondary = true },
}

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

-- The skills that are Feed news, lowest first: each rank's cap, the last
-- (Professions.CAP) being maxed.
Professions.MILESTONES = {}
for i = #RANKS, 1, -1 do Professions.MILESTONES[#Professions.MILESTONES + 1] = RANKS[i][1] end
local MILESTONES = Professions.MILESTONES

-- What's news between a Character's stored list as it was and as it is:
-- a list of { kind, skillLine, name, icon, from, milestone }, in after's
-- order. kind is "newProfession" for one it didn't have, "professionMaxed"
-- for reaching 300, or "professionSkill" for reaching 75, 150 or 225 (the
-- highest crossed, with from the skill before). Base skill only. Empty
-- when either list is unknown or malformed (a first share is a silent
-- baseline), and for drops and unlearning.
function Professions.news(before, after)
  local list = {}
  if not valid(before) or not valid(after) then return list end
  local had = {}
  for _, entry in ipairs(before) do had[entry.id] = entry end
  for _, entry in ipairs(after) do
    local was = had[entry.id]
    local item = { skillLine = entry.id, name = entry.n, icon = entry.i }
    if not was then
      item.kind = "newProfession"
      list[#list + 1] = item
    else
      local reached
      for _, milestone in ipairs(MILESTONES) do
        if was.k < milestone and entry.k >= milestone then reached = milestone end
      end
      if reached then
        item.kind = reached == Professions.CAP and "professionMaxed" or "professionSkill"
        item.from, item.milestone = was.k, reached
        list[#list + 1] = item
      end
    end
  end
  return list
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
function Professions.tab(rows)
  local professions, bySkillLine = {}, {}
  for i, p in ipairs(Professions.ALL) do
    professions[i] = { skillLine = p.skillLine, name = p.name, icon = p.icon, secondary = p.secondary == true,
      holders = {} }
    bySkillLine[p.skillLine] = professions[i]
  end
  local unshared, shown = {}, 0
  local function add(row, character)
    shown = shown + 1
    if not character.professions then
      unshared[#unshared + 1] = { memberId = row.memberId, own = row.own == true, displayName = row.displayName,
        name = character.name, classFilename = character.classFilename }
      return
    end
    for _, p in ipairs(character.professions) do
      local profession = bySkillLine[p.skillLine]
      if not profession then
        -- One outside the twelve: listed too, after its kind.
        profession = { skillLine = p.skillLine, secondary = p.secondary, holders = {} }
        bySkillLine[p.skillLine] = profession
        professions[#professions + 1] = profession
      end
      -- As the holder's client words it.
      profession.name, profession.icon = p.name, p.icon or profession.icon
      local holders = profession.holders
      holders[#holders + 1] = {
        memberId = row.memberId, own = row.own == true, displayName = row.displayName,
        name = character.name, classFilename = character.classFilename, alt = not character.main,
        skill = p.skill, max = p.max, rank = p.rank, full = p.full, capped = p.capped, shown = shown,
      }
    end
  end
  for _, row in ipairs(rows) do
    local characters = { row }
    for _, alt in ipairs(row.alts) do characters[#characters + 1] = alt end
    for _, character in ipairs(characters) do
      if character.main then add(row, character) end
    end
    for _, character in ipairs(characters) do
      if not character.main then add(row, character) end
    end
  end

  -- The twelve keep their order; any other goes after its kind, by name.
  for i, profession in ipairs(professions) do profession.position = i <= #Professions.ALL and i or nil end
  table.sort(professions, function(a, b)
    if a.position and b.position then return a.position < b.position end
    if a.secondary ~= b.secondary then return b.secondary end
    if a.position or b.position then return a.position ~= nil end
    return listedBefore(a, b)
  end)
  for _, profession in ipairs(professions) do
    profession.position = nil
    -- Best first; as the Roster shows them otherwise.
    table.sort(profession.holders, function(a, b)
      if a.skill ~= b.skill then return a.skill > b.skill end
      return a.shown < b.shown
    end)
    for _, holder in ipairs(profession.holders) do holder.shown = nil end
  end
  return { professions = professions, unshared = unshared }
end
