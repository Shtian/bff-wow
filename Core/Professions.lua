local _, ns = ...

local Professions = {}
ns.Professions = Professions

-- WoW: GetProfessions() has five slots: two main professions, then first
-- aid, fishing and cooking.
local SLOTS = 5
local SECONDARY_FROM = 3
-- WoW: Forever caps professions at 300.
Professions.CAP = 300
Professions.KINDS = { newProfession = true, professionSkill = true, professionMaxed = true }
local RANKS = { { 300, "Artisan" }, { 225, "Expert" }, { 150, "Journeyman" }, { 75, "Apprentice" } }
Professions.ALL = {
  { skillLine = 171, name = "Alchemy", work = "alchemy", noun = "an Alchemist",
    icon = "Interface\\Icons\\Trade_Alchemy" },
  { skillLine = 164, name = "Blacksmithing", work = "blacksmithing", noun = "a Blacksmith",
    icon = "Interface\\Icons\\Trade_BlackSmithing" },
  { skillLine = 333, name = "Enchanting", work = "enchanting", noun = "an Enchanter",
    icon = "Interface\\Icons\\Trade_Engraving" },
  { skillLine = 202, name = "Engineering", work = "engineering", noun = "an Engineer",
    icon = "Interface\\Icons\\Trade_Engineering" },
  { skillLine = 182, name = "Herbalism", work = "herbalism", noun = "a Herbalist",
    icon = "Interface\\Icons\\Trade_Herbalism" },
  { skillLine = 165, name = "Leatherworking", work = "leatherworking", noun = "a Leatherworker",
    icon = "Interface\\Icons\\Trade_LeatherWorking" },
  { skillLine = 186, name = "Mining", work = "mining", noun = "a Miner", icon = "Interface\\Icons\\Trade_Mining" },
  { skillLine = 393, name = "Skinning", work = "skinning", noun = "a Skinner",
    icon = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01" },
  { skillLine = 197, name = "Tailoring", work = "tailoring", noun = "a Tailor",
    icon = "Interface\\Icons\\Trade_Tailoring" },
  { skillLine = 185, name = "Cooking", work = "cooking", noun = "a Cook",
    icon = "Interface\\Icons\\INV_Misc_Food_15", secondary = true },
  { skillLine = 356, name = "Fishing", noun = "an Angler", icon = "Interface\\Icons\\Trade_Fishing", secondary = true },
  { skillLine = 129, name = "First Aid", work = "firstAid", noun = "a First Aider",
    icon = "Interface\\Icons\\Spell_Holy_SealOfSacrifice", secondary = true },
}

-- WoW: skill lines 185 cooking, 356 fishing, 129 first aid.
local SECONDARY_ORDER = { [185] = 1, [356] = 2, [129] = 3 }
local OTHER_SECONDARY = 4

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
      -- WoW: Lua 5.1's ipairs stops at the first nil, and the icon can be nil.
      local values = { name, icon, skill, max, skillLine }
      for i = 1, 5 do
        if isSecret(values[i]) then return nil end
      end
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

function Professions.store(list)
  if type(list) ~= "table" then return nil end
  local stored = {}
  for i, p in ipairs(list) do
    stored[i] = { id = p.skillLine, n = p.name, i = p.icon, k = p.skill, m = p.max, s = p.secondary or nil }
  end
  if not valid(stored) then return nil end
  return stored
end

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

local WORK = {}
for _, profession in ipairs(Professions.ALL) do WORK[profession.skillLine] = profession.work end
local FISHING = 356

Professions.WORK_STATES = { crafting = true }
for _, work in pairs(WORK) do Professions.WORK_STATES[work] = true end

function Professions.workOf(skillLine)
  return WORK[skillLine]
end

-- WoW: Forever's gathering casts, one spell per rank (wowhead.com/forever).
local GATHERING_SPELLS = {
  mining = { 2575, 2576, 3564, 10248 },
  herbalism = { 2366, 2368, 3570, 11993 },
  skinning = { 8613, 8617, 8618, 10768 },
}
local GATHERED_BY = {}
for work, spells in pairs(GATHERING_SPELLS) do
  for _, spell in ipairs(spells) do GATHERED_BY[spell] = work end
end

function Professions.gatheredBy(spellId)
  return GATHERED_BY[spellId]
end

function Professions.lineNamed(professions, name)
  if type(name) ~= "string" then return nil end
  for _, profession in ipairs(professions or {}) do
    if profession.name == name then return profession.skillLine end
  end
  return nil
end

function Professions.practised(before, after)
  if not valid(before) or not valid(after) then return nil end
  local had = {}
  for _, entry in ipairs(before) do had[entry.id] = entry.k end
  local found
  for _, entry in ipairs(after) do
    if entry.id ~= FISHING and had[entry.id] and entry.k > had[entry.id] then
      if WORK[entry.id] then return WORK[entry.id] end
      found = "crafting"
    end
  end
  return found
end

Professions.MILESTONES = {}
for i = #RANKS, 1, -1 do Professions.MILESTONES[#Professions.MILESTONES + 1] = RANKS[i][1] end
local MILESTONES = Professions.MILESTONES

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

local function listedBefore(a, b)
  if a.secondary ~= b.secondary then return b.secondary end
  if a.secondary and secondaryOrder(a) ~= secondaryOrder(b) then
    return secondaryOrder(a) < secondaryOrder(b)
  end
  if a.position and b.position then return a.position < b.position end
  if a.name ~= b.name then return a.name < b.name end
  return a.skillLine < b.skillLine
end

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

function Professions.tab(rows, sortBy)
  local professions, bySkillLine = {}, {}
  for i, p in ipairs(Professions.ALL) do
    professions[i] = { skillLine = p.skillLine, name = p.name, icon = p.icon, secondary = p.secondary == true,
      had = false }
    bySkillLine[p.skillLine] = professions[i]
  end
  local members = {}
  for index, row in ipairs(rows) do
    local characters = {}
    for _, character in ipairs({ row, unpack(row.alts) }) do
      table.insert(characters, character.main and 1 or #characters + 1, character)
    end
    local member = { memberId = row.memberId, own = row.own == true, displayName = row.displayName,
      known = false, characters = characters, index = index }
    for _, character in ipairs(characters) do
      if character.professions then member.known = true end
      for _, p in ipairs(character.professions or {}) do
        local profession = bySkillLine[p.skillLine]
        if not profession then
          profession = { skillLine = p.skillLine, secondary = p.secondary == true }
          bySkillLine[p.skillLine] = profession
          professions[#professions + 1] = profession
        end
        profession.name, profession.icon, profession.had = p.name, p.icon or profession.icon, true
      end
    end
    members[#members + 1] = member
  end

  for i, profession in ipairs(professions) do profession.position = i <= #Professions.ALL and i or nil end
  table.sort(professions, function(a, b)
    if a.position and b.position then return a.position < b.position end
    if a.secondary ~= b.secondary then return b.secondary end
    if a.position or b.position then return a.position ~= nil end
    return listedBefore(a, b)
  end)
  for _, profession in ipairs(professions) do profession.position = nil end

  for _, member in ipairs(members) do
    member.cells = {}
    for i, profession in ipairs(professions) do
      local characters = {}
      for order, character in ipairs(member.characters) do
        for _, p in ipairs(character.professions or {}) do
          if p.skillLine == profession.skillLine then
            characters[#characters + 1] = { name = character.name, fullName = character.fullName,
              classFilename = character.classFilename,
              alt = not character.main, skill = p.skill, max = p.max, rank = p.rank, full = p.full, capped = p.capped,
              order = order }
          end
        end
      end
      table.sort(characters, function(a, b)
        if a.skill ~= b.skill then return a.skill > b.skill end
        return a.order < b.order
      end)
      for _, c in ipairs(characters) do c.order = nil end
      local best = characters[1]
      member.cells[i] = best and { skill = best.skill, max = best.max, rank = best.rank, full = best.full,
        capped = best.capped, characters = characters } or false
    end
    member.characters = nil
  end

  local column
  for i, profession in ipairs(professions) do
    if profession.skillLine == sortBy then column = i end
  end
  if column then
    local function skill(member) return member.cells[column] and member.cells[column].skill or -1 end
    table.sort(members, function(a, b)
      if a.own ~= b.own then return a.own end
      if skill(a) ~= skill(b) then return skill(a) > skill(b) end
      return a.index < b.index
    end)
  end
  for _, member in ipairs(members) do member.index = nil end
  local none = true
  for _, profession in ipairs(professions) do
    if profession.had then none = false end
  end
  return { professions = professions, members = members, none = none }
end
