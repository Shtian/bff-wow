-- Roster: builds the panel's rows from the Ledger. A row is a fresh table
-- the UI may keep or change; it never shares anything with a record.
-- See the panel decision (#7) and docs/design/code-structure.md.

local _, ns = ...

local Roster = {}
ns.Roster = Roster

-- A Member is online if heard within this long and not seen leaving the
-- channel since.
local ONLINE_FOR = 12 * 60
-- Characters unseen this long are hidden; display only.
local HIDE_AFTER = 30 * 24 * 60 * 60
Roster.HIDE_AFTER = HIDE_AFTER
-- Within this many levels of the Character you play, you can play together.
local CAN_PLAY = 3
Roster.CAN_PLAY = CAN_PLAY

local function mostRecentFirst(a, b)
  if a.lastPlayed ~= b.lastPlayed then return a.lastPlayed > b.lastPlayed end
  return a.guid < b.guid
end

-- The record's Characters seen within 30 days, most recently played first,
-- and how many were hidden.
local function visibleCharacters(record, now)
  local characters, hidden = {}, 0
  for _, character in pairs(record.characters) do
    if now - character.lastPlayed < HIDE_AFTER then
      characters[#characters + 1] = character
    else
      hidden = hidden + 1
    end
  end
  table.sort(characters, mostRecentFirst)
  return characters, hidden
end

-- The Main: the Character set as Main, or the most recently played one,
-- among the given Characters (most recently played first).
local function mainOf(record, characters)
  for _, character in ipairs(characters) do
    if character.guid == record.main then return character end
  end
  return characters[1]
end

-- The Main of a record as the panel shows it, or nil if every Character
-- is hidden.
function Roster.main(record, now)
  return mainOf(record, (visibleCharacters(record, now)))
end

-- What a Member is called in texts: their display name, else their
-- Main's name, else "Someone".
function Roster.memberName(record, now)
  if record and record.displayName then return record.displayName end
  local main = record and Roster.main(record, now)
  return main and main.name or "Someone"
end

local function canPlay(character, yourLevel)
  return yourLevel ~= nil and math.abs(character.level - yourLevel) <= CAN_PLAY
end

local function describeCharacter(character, main, yourLevel, now)
  return {
    guid = character.guid,
    name = character.name,
    classFilename = character.classFilename,
    level = character.level,
    xp = character.xp,
    maxXp = character.maxXp,
    zone = character.zone,
    deaths = character.deaths,
    money = character.money,
    mapId = character.mapId,
    x = character.x,
    y = character.y,
    instance = character.instance,
    lastPlayed = character.lastPlayed,
    sinceSeen = now - character.lastPlayed,
    playing = false,
    main = character == main,
    canPlay = canPlay(character, yourLevel),
  }
end

-- A Member's row: the Character they're playing while online, else their
-- Main, with the rest as alts. yourLevel is nil for your own row.
local function rowFor(record, characters, online, yourLevel, now)
  local main = mainOf(record, characters)
  local shown = online and characters[1] or main
  local row = describeCharacter(shown, main, yourLevel, now)
  row.playing = online
  row.memberId = record.id
  row.displayName = record.displayName
  row.online = online
  row.onAlt = shown ~= main
  row.mainSet = record.main ~= nil and record.main == main.guid
  row.lastSeen = characters[1].lastPlayed
  row.sinceSeen = now - row.lastSeen
  row.altsCanPlay = false
  row.alts = {}
  for _, character in ipairs(characters) do
    if character ~= shown then
      local alt = describeCharacter(character, main, yourLevel, now)
      row.alts[#row.alts + 1] = alt
      if alt.canPlay then row.altsCanPlay = true end
    end
  end
  return row
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

local function lower(text)
  return (text or ""):lower()
end

local function nameKey(row)
  return lower(row.displayName or row.name)
end

local function anyCanPlay(row)
  return row.canPlay or row.altsCanPlay
end

-- Each order compares two rows and returns true, false, or nil for a tie.
local ORDERS = {
  online = function(a, b)
    if a.online ~= b.online then return a.online end
    if anyCanPlay(a) ~= anyCanPlay(b) then return anyCanPlay(a) end
    if a.lastSeen ~= b.lastSeen then return a.lastSeen > b.lastSeen end
  end,
  level = function(a, b)
    if a.level ~= b.level then return a.level > b.level end
  end,
}

local function sorter(order)
  local first = ORDERS[order]
  if order ~= "name" then first = first or ORDERS.online end
  return function(a, b)
    local result = first and first(a, b)
    if result ~= nil then return result end
    if nameKey(a) ~= nameKey(b) then return nameKey(a) < nameKey(b) end
    return a.memberId < b.memberId
  end
end

-- Builds every row and the hidden count. Rows of others are unsorted.
local function buildRows(ledger, now)
  local own = ledger:own()
  local online = Roster.online(ledger, now)
  local hiddenTotal = 0
  local ownRow
  if own then
    local characters, hidden = visibleCharacters(own, now)
    hiddenTotal = hiddenTotal + hidden
    if #characters > 0 then
      ownRow = rowFor(own, characters, true, nil, now)
      ownRow.own = true
    end
  end
  local yourLevel = ownRow and ownRow.level

  local others = {}
  for _, record in ledger:records() do
    if record ~= own and not record.left then
      local characters, hidden = visibleCharacters(record, now)
      hiddenTotal = hiddenTotal + hidden
      if #characters > 0 then
        local row = rowFor(record, characters, online[record.id] == true, yourLevel, now)
        local via = ledger:via(record.id)
        local relay = via and ledger:record(via)
        row.via = relay and relay.displayName or nil
        others[#others + 1] = row
      end
    end
  end
  return ownRow, others, hiddenTotal
end

-- Your own row first, then every other Member who hasn't left, in the
-- order "online" (the default: online, can play, Last seen), "level" or
-- "name".
function Roster.rows(ledger, now, order)
  local ownRow, others = buildRows(ledger, now)
  table.sort(others, sorter(order))
  local rows = { ownRow }
  for _, row in ipairs(others) do rows[#rows + 1] = row end
  return rows
end

-- Counts for the title and minimap button: Members online, Members shown,
-- Members online whose Character being played can play with you, and
-- Characters hidden for being unseen 30 days.
function Roster.summary(ledger, now)
  local _, others, hidden = buildRows(ledger, now)
  local summary = { online = 0, members = #others, canPlay = 0, hidden = hidden }
  for _, row in ipairs(others) do
    if row.online then
      summary.online = summary.online + 1
      if row.canPlay then summary.canPlay = summary.canPlay + 1 end
    end
  end
  return summary
end
