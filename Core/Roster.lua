-- Roster: builds the panel's rows from the Ledger. A row is a fresh table
-- the UI may keep or change; it never shares anything with a record.

local _, ns = ...

local Roster = {}
ns.Roster = Roster

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
    name = shown.name,
    classFilename = shown.classFilename,
    level = shown.level,
    xp = shown.xp,
    maxXp = shown.maxXp,
    zone = shown.zone,
    alts = alts,
  }
end

function Roster.rows(ledger)
  local rows = {}
  local own = ledger:own()
  local row = own and rowFor(own)
  if row then rows[1] = row end
  return rows
end
