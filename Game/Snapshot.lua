-- Snapshot: reads the Character being played and hands it to Core. It also
-- counts deaths, kept per Character in BFF_CharacterDB, so a client crash
-- loses that session's deaths (see docs/design/code-structure.md).

local _, ns = ...

local Snapshot = {}
ns.Snapshot = Snapshot

local EVENTS = {
  "PLAYER_ENTERING_WORLD",
  "PLAYER_LEVEL_UP",
  "PLAYER_XP_UPDATE",
  "ZONE_CHANGED_NEW_AREA",
  "PLAYER_DEAD",
}

local level = 0
local zone

local function read()
  local guid = UnitGUID("player")
  if not guid then return nil end

  -- PLAYER_LEVEL_UP fires before UnitLevel catches up, and a level never
  -- goes down, so keep the highest one seen.
  level = math.max(level, UnitLevel("player"))
  -- The zone reads empty while loading; keep the last one.
  local currentZone = GetRealZoneText()
  if currentZone and currentZone ~= "" then zone = currentZone end

  local _, classFilename = UnitClass("player")
  return {
    guid = guid,
    name = UnitName("player"),
    classFilename = classFilename,
    level = level,
    xp = UnitXP("player"),
    maxXp = UnitXPMax("player"),
    zone = zone,
    deaths = BFF_CharacterDB.deaths,
  }
end

function Snapshot.start(core)
  BFF_CharacterDB = BFF_CharacterDB or {}
  BFF_CharacterDB.deaths = BFF_CharacterDB.deaths or 0

  local function update()
    local character = read()
    if character then core:updateOwn(character) end
  end

  local frame = CreateFrame("Frame")
  for _, event in ipairs(EVENTS) do frame:RegisterEvent(event) end
  frame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LEVEL_UP" then
      level = math.max(level, (...))
    elseif event == "PLAYER_DEAD" then
      BFF_CharacterDB.deaths = BFF_CharacterDB.deaths + 1
    end
    update()
  end)
  update()
end
