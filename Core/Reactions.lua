-- Reactions: the pure parts of Reactions on Feed entries. Which Reaction
-- applies to which kind of entry, the key a Reaction points at an entry by
-- (owner, Character and what was reached, docs/adr/0002), how keys are
-- stored in the reacting Member's record, and the wording the owner sees.
-- Feed attaches Reactions to its entries. See docs/design/reactions.md.

local _, ns = ...

local Reactions = {}
ns.Reactions = Reactions

local DAY = 24 * 60 * 60
-- The reacting Member's record keeps Reactions this long, and at most
-- this many.
Reactions.KEEP_FOR = 30 * DAY
Reactions.KEEP_MAX = 50

-- The one Reaction each kind of entry has. Left has none.
local FOR_KIND = {
  ding = "cheer",
  maxLevel = "cheer",
  newCharacter = "cheer",
  death = "respects",
  joined = "welcome",
}

-- Kinds as stored in a record, kept short since records go over the wire.
local CODES = { ding = "d", maxLevel = "m", newCharacter = "c", death = "x", joined = "j" }
local KINDS = {}
for kind, code in pairs(CODES) do KINDS[code] = kind end

-- Kinds whose key has a number: the level, death total or joinedAt reached.
local NUMBERED = { ding = true, death = true, joined = true }

-- The Reaction an entry kind has ("cheer", "respects" or "welcome"), or nil.
function Reactions.forKind(kind)
  return FOR_KIND[kind]
end

-- The key a Reaction to this entry is made with: { memberId, guid, kind,
-- n }, keyed to the top of a collapsed entry's range. Nil for an entry
-- that can't be reacted to, or one saved before it had what it needs.
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
  end
  if NUMBERED[kind] and type(n) ~= "number" then return nil end
  if kind ~= "joined" and type(entry.guid) ~= "string" then return nil end
  return { memberId = entry.memberId, guid = entry.guid, kind = kind, n = n }
end

-- Whether a key falls on this entry: a collapsed ding or death matches
-- every level or death total in its range.
function Reactions.matches(entry, key)
  if entry.memberId ~= key.memberId or entry.kind ~= key.kind or entry.guid ~= key.guid then
    return false
  end
  local n = key.n
  if key.kind == "ding" then
    return entry.from ~= nil and entry.level ~= nil and n > entry.from and n <= entry.level
  elseif key.kind == "death" then
    return entry.to ~= nil and entry.count ~= nil and n > entry.to - entry.count and n <= entry.to
  elseif key.kind == "joined" then
    return entry.joinedAt == n
  end
  return true
end

-- A well-formed key from anywhere (a UI caller or the wire), or nil.
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
  return { memberId = key.memberId, guid = key.guid, kind = key.kind, n = key.n }
end

-- The same key as a string, to tell Reactions apart.
function Reactions.id(key)
  return ("%s|%s|%s|%s"):format(key.memberId, key.kind, key.guid or "", key.n or "")
end

-- A key and when it was made, as stored in a record.
function Reactions.item(key, time)
  return { m = key.memberId, g = key.guid, k = CODES[key.kind], n = key.n, t = time }
end

-- The well-formed Reactions in a record, as { key, time }. A malformed
-- item, or a list that isn't one, is skipped rather than refused.
function Reactions.inRecord(record)
  local list = {}
  if type(record) ~= "table" or type(record.reactions) ~= "table" then return list end
  for _, item in ipairs(record.reactions) do
    if type(item) == "table" and type(item.t) == "number" then
      local key = Reactions.validKey({
        memberId = item.m, guid = item.g, kind = KINDS[item.k], n = item.n,
      })
      if key then list[#list + 1] = { key = key, time = item.t } end
    end
  end
  return list
end

-- Drops the items older than KEEP_FOR, then all but the KEEP_MAX newest.
-- Items are kept in the order they were made.
function Reactions.prune(list, now)
  for i = #list, 1, -1 do
    local item = list[i]
    if type(item) ~= "table" or type(item.t) ~= "number" or now - item.t > Reactions.KEEP_FOR then
      table.remove(list, i)
    end
  end
  while #list > Reactions.KEEP_MAX do table.remove(list, 1) end
end

-- "Bob", "Bob and Cleo", "Bob, Cleo and Dan", and after three names "Bob,
-- Cleo, Dan and 2 others".
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

-- The whole line: names and what they did, "Bob and Cleo cheered your ding
-- to 30".
function Reactions.text(names, phrase)
  return Reactions.names(names) .. " " .. phrase
end

-- What a Reaction did to the owner's entry, after the names: "cheered your
-- ding to 30", "paid respects (Jaina died)". character is the entry's
-- Character in the owner's record, and alt whether it isn't their Main.
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
  end
  return "welcomed you"
end
