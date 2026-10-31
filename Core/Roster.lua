-- Roster: builds the panel's rows from the Ledger. A row is a fresh table
-- the UI may keep or change; it never shares anything with a record.

local _, ns = ...

local Roster = {}
ns.Roster = Roster

-- A Member is online if heard within this long and not seen leaving the
-- channel since.
local ONLINE_FOR = 12 * 60

local function mostRecentFirst(a, b)
  if a.lastPlayed ~= b.lastPlayed then return a.lastPlayed > b.lastPlayed end
  return a.guid < b.guid
end

local function rowFor(record)
  local characters = {}
  for _, character in pairs(record.characters) do
    characters[#characters + 1] = character
  end
  if #characters == 0 then return nil end
  table.sort(characters, mostRecentFirst)

  -- No Main override yet, so the Main is the most recently played
  -- Character and every other one is an Alt.
  local shown = characters[1]
  local alts = {}
  for i = 2, #characters do
    local alt = characters[i]
    alts[#alts + 1] = { name = alt.name, classFilename = alt.classFilename, level = alt.level }
  end
  return {
    memberId = record.id,
    displayName = record.displayName,
    name = shown.name,
    classFilename = shown.classFilename,
    level = shown.level,
    xp = shown.xp,
    maxXp = shown.maxXp,
    zone = shown.zone,
    alts = alts,
  }
end

-- The ids of other Members online now, as a set.
function Roster.online(ledger, now)
  local online = {}
  for id, record in ledger:records() do
    local heard = ledger:lastHeard(id)
    if heard and now - heard < ONLINE_FOR and not record.left then online[id] = true end
  end
  return online
end

local function byName(a, b)
  if a.name ~= b.name then return a.name < b.name end
  return a.memberId < b.memberId
end

-- Your own row first, then every other Member who hasn't left, by name.
function Roster.rows(ledger, now)
  local own = ledger:own()
  local online = Roster.online(ledger, now)
  local others = {}
  for _, record in ledger:records() do
    local row = record ~= own and not record.left and rowFor(record)
    if row then
      row.online = online[record.id] == true
      others[#others + 1] = row
    end
  end
  table.sort(others, byName)

  local rows = {}
  local row = own and rowFor(own)
  if row then
    row.own = true
    row.online = true
    rows[1] = row
  end
  for _, other in ipairs(others) do rows[#rows + 1] = other end
  return rows
end
