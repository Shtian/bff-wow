local _, ns = ...

local Reactions = {}
ns.Reactions = Reactions

local DAY = 24 * 60 * 60
Reactions.KEEP_FOR = 30 * DAY
Reactions.KEEP_MAX = 50

local FOR_KIND = {
  ding = "cheer",
  maxLevel = "cheer",
  newCharacter = "cheer",
  death = "respects",
  joined = "welcome",
  newProfession = "cheer",
  professionSkill = "cheer",
  professionMaxed = "cheer",
  rareFind = "cheer",
}

local CODES = {
  ding = "d", maxLevel = "m", newCharacter = "c", death = "x", joined = "j",
  newProfession = "p", professionSkill = "s", professionMaxed = "a", rareFind = "r",
}
local KINDS = {}
for kind, code in pairs(CODES) do KINDS[code] = kind end

local NUMBERED = { ding = true, death = true, joined = true, professionSkill = true, rareFind = true }
local PROFESSION = ns.Professions.KINDS

function Reactions.forKind(kind)
  return FOR_KIND[kind]
end

function Reactions.keyOf(entry)
  local kind = entry.kind
  if not FOR_KIND[kind] or type(entry.memberId) ~= "string" then return nil end
  local n
  if kind == "ding" then
    n = entry.level
  elseif kind == "death" then
    n = entry.to
  elseif kind == "joined" then
    n = entry.joinedAt
  elseif kind == "professionSkill" then
    n = entry.milestone
  elseif kind == "rareFind" then
    n = entry.catch
  end
  if NUMBERED[kind] and type(n) ~= "number" then return nil end
  if kind ~= "joined" and type(entry.guid) ~= "string" then return nil end
  local skillLine = PROFESSION[kind] and entry.skillLine or nil
  if PROFESSION[kind] and type(skillLine) ~= "number" then return nil end
  return { memberId = entry.memberId, guid = entry.guid, kind = kind, n = n, skillLine = skillLine }
end

function Reactions.matches(entry, key)
  if entry.memberId ~= key.memberId or entry.kind ~= key.kind or entry.guid ~= key.guid
    or entry.skillLine ~= key.skillLine then
    return false
  end
  local n = key.n
  if key.kind == "ding" then
    return entry.from ~= nil and entry.level ~= nil and n > entry.from and n <= entry.level
  elseif key.kind == "death" then
    return entry.to ~= nil and entry.count ~= nil and n > entry.to - entry.count and n <= entry.to
  elseif key.kind == "joined" then
    return entry.joinedAt == n
  elseif key.kind == "professionSkill" then
    return entry.from ~= nil and entry.milestone ~= nil and n > entry.from and n <= entry.milestone
  elseif key.kind == "rareFind" then
    return entry.catch == n
  end
  return true
end

function Reactions.validKey(key)
  if type(key) ~= "table" or type(key.memberId) ~= "string" or not FOR_KIND[key.kind] then
    return nil
  end
  if key.kind == "joined" then
    if key.guid ~= nil then return nil end
  elseif type(key.guid) ~= "string" then
    return nil
  end
  if NUMBERED[key.kind] then
    if type(key.n) ~= "number" then return nil end
  elseif key.n ~= nil then
    return nil
  end
  if PROFESSION[key.kind] then
    if type(key.skillLine) ~= "number" then return nil end
  elseif key.skillLine ~= nil then
    return nil
  end
  return { memberId = key.memberId, guid = key.guid, kind = key.kind, n = key.n, skillLine = key.skillLine }
end

function Reactions.id(key)
  local id = ("%s|%s|%s|%s"):format(key.memberId, key.kind, key.guid or "", key.n or "")
  if key.skillLine then id = id .. "|" .. key.skillLine end
  return id
end

function Reactions.item(key, time)
  return { m = key.memberId, g = key.guid, k = CODES[key.kind], n = key.n, p = key.skillLine, t = time }
end

function Reactions.inRecord(record)
  local list = {}
  if type(record) ~= "table" or type(record.reactions) ~= "table" then return list end
  for _, item in ipairs(record.reactions) do
    if type(item) == "table" and type(item.t) == "number" then
      local key = Reactions.validKey({
        memberId = item.m, guid = item.g, kind = KINDS[item.k], n = item.n, skillLine = item.p,
      })
      if key then list[#list + 1] = { key = key, time = item.t } end
    end
  end
  return list
end

function Reactions.prune(list, now)
  for i = #list, 1, -1 do
    local item = list[i]
    if type(item) ~= "table" or type(item.t) ~= "number" or now - item.t > Reactions.KEEP_FOR then
      table.remove(list, i)
    end
  end
  while #list > Reactions.KEEP_MAX do table.remove(list, 1) end
end

function Reactions.names(names)
  local count = #names
  if count == 1 then return names[1] end
  if count <= 3 then
    return table.concat(names, ", ", 1, count - 1) .. " and " .. names[count]
  end
  local others = count - 3
  return ("%s and %d %s"):format(table.concat(names, ", ", 1, 3), others,
    others == 1 and "other" or "others")
end

function Reactions.text(names, phrase)
  return Reactions.names(names) .. " " .. phrase
end

function Reactions.phrase(entry, character, alt)
  local name = character and character.name or "?"
  local kind = entry.kind
  if kind == "ding" then
    return alt and ("cheered your Alt %s's ding to %d"):format(name, entry.level)
      or ("cheered your ding to %d"):format(entry.level)
  elseif kind == "maxLevel" then
    return alt and ("cheered your Alt %s reaching max level"):format(name)
      or "cheered you reaching max level"
  elseif kind == "newCharacter" then
    return "cheered your new Character " .. name
  elseif kind == "death" then
    return ("paid respects (%s died)"):format(name)
  elseif kind == "newProfession" then
    return alt and ("cheered your Alt %s picking up %s"):format(name, entry.profession)
      or ("cheered you picking up %s"):format(entry.profession)
  elseif kind == "professionSkill" then
    return alt and ("cheered your Alt %s's %d %s"):format(name, entry.milestone, entry.profession)
      or ("cheered your %d %s"):format(entry.milestone, entry.profession)
  elseif kind == "professionMaxed" then
    return alt and ("cheered your Alt %s maxing %s"):format(name, entry.profession)
      or ("cheered you maxing %s"):format(entry.profession)
  elseif kind == "rareFind" then
    return alt and ("cheered your Alt %s's %s"):format(name, entry.fish)
      or ("cheered your %s"):format(entry.fish)
  end
  return "welcomed you"
end
