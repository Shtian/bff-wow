-- Snapshot: reads the Character being played and hands it to Core. It also
-- counts deaths, kept per Character in BFF_CharacterDB, so a client crash
-- loses that session's deaths (see docs/design/code-structure.md), and
-- reads its professions (on PLAYER_ENTERING_WORLD and SKILL_LINES_CHANGED),
-- where the Character stands for Core's locate(), item info for Spares,
-- and a boss kill's payload with the party for Core's encounterEnded().

local _, ns = ...

local Snapshot = {}
ns.Snapshot = Snapshot

local EVENTS = {
  "PLAYER_ENTERING_WORLD",
  "PLAYER_LEVEL_UP",
  "PLAYER_XP_UPDATE",
  "ZONE_CHANGED_NEW_AREA",
  "PLAYER_DEAD",
  "PLAYER_MONEY",
  "SKILL_LINES_CHANGED",
}
-- Professions are read again only on these.
local PROFESSION_EVENTS = { PLAYER_ENTERING_WORLD = true, SKILL_LINES_CHANGED = true }

local level = 0
local zone
local money
local professions

-- The professions, read through Professions.read, which keeps the last
-- good list when a value reads secret or the read errors: that costs the
-- professions, never the send.
local PROFESSION_API = {
  getProfessions = GetProfessions,
  getProfessionInfo = GetProfessionInfo,
  isSecret = issecretvalue,
}
local function readProfessions()
  if not (GetProfessions and GetProfessionInfo) then return end
  professions = ns.Professions.read(PROFESSION_API, professions)
end

local function read()
  local guid = UnitGUID("player")
  if not guid then return nil end

  -- PLAYER_LEVEL_UP fires before UnitLevel catches up, and a level never
  -- goes down, so keep the highest one seen.
  level = math.max(level, UnitLevel("player"))
  -- The zone reads empty while loading; keep the last one.
  local currentZone = GetRealZoneText()
  if currentZone and currentZone ~= "" then zone = currentZone end
  -- Money (copper) isn't a combat API, but should it ever read secret,
  -- keep the last one rather than compare a secret.
  local currentMoney = GetMoney()
  if type(currentMoney) == "number" and not (issecretvalue and issecretvalue(currentMoney)) then
    money = currentMoney
  end

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
    money = money,
    professions = professions,
  }
end

-- Where the Character stands: mapId, x and y (0–1) on the best map for
-- the player, or instance (its name) inside an instance, where the
-- position can't be read. Nil while neither is (loading screens, unmapped
-- areas); Core keeps the last known spot and rounds it.
local function locate()
  if IsInInstance() then
    local name = GetInstanceInfo()
    if type(name) == "string" and name ~= "" then return { instance = name } end
    return nil
  end
  local mapId = C_Map.GetBestMapForUnit("player")
  if not mapId then return nil end
  local position = C_Map.GetPlayerMapPosition(mapId, "player")
  if not position then return nil end
  local x, y = position:GetXY()
  if type(x) ~= "number" or type(y) ~= "number" then return nil end
  if issecretvalue and (issecretvalue(x) or issecretvalue(y)) then return nil end
  return { mapId = mapId, x = x, y = y }
end

-- Core calls this just before own DATA goes out. A map API that errors
-- (a restriction we don't know of) only costs the spot, never the send.
function Snapshot.locate()
  local ok, location = pcall(locate)
  return ok and location or nil
end

-- A value as Core may see it: nil when secret, so Core never compares one.
local function readable(value)
  if issecretvalue and issecretvalue(value) then return nil end
  return value
end

-- The group's units, you included.
local function groupUnits()
  local units = {}
  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
  else
    units[1] = "player"
    for i = 1, 4 do units[#units + 1] = "party" .. i end
  end
  return units
end

-- Who is in the group: { guid, name } per member, either nil when secret.
-- The name is UnitName's, without the realm.
function Snapshot.party()
  local party = {}
  for _, unit in ipairs(groupUnits()) do
    if UnitExists(unit) then
      party[#party + 1] = { guid = readable(UnitGUID(unit)), name = readable((UnitName(unit))) }
    end
  end
  return party
end

local function encounter(encounterID, success)
  local _, instanceType = GetInstanceInfo()
  success = readable(success)
  -- The wiki has success as 1 or 0; take a boolean too.
  if success == 1 then success = true elseif success == 0 then success = false end
  if type(success) ~= "boolean" then success = nil end
  return {
    encounterId = readable(encounterID),
    success = success,
    instanceType = readable(instanceType),
    party = Snapshot.party(),
  }
end

-- ENCOUNTER_END's payload (encounterID, encounterName, difficultyID,
-- groupSize, success) as Core's encounterEnded() takes it, with the
-- instance type and the party. A value that reads secret is nil, and a
-- read that errors (a restriction we don't know of) is nil altogether, so
-- Core records nothing.
function Snapshot.encounter(encounterID, _, _, _, success)
  local ok, result = pcall(encounter, encounterID, success)
  return ok and result or nil
end

-- Item info, through C_Item where the client has it.
local getItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo

-- The game's link for an item string, or nil until it's cached. Asking
-- also starts loading it, and GET_ITEM_INFO_RECEIVED says when it has.
function Snapshot.itemLink(itemString)
  local _, link = getItemInfo(itemString)
  return link
end

-- The level an item (link or item string) needs, or nil until it's cached.
function Snapshot.requiredLevel(link)
  return (select(5, getItemInfo(link)))
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
  readProfessions()
  frame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LEVEL_UP" then
      level = math.max(level, (...))
    elseif event == "PLAYER_DEAD" then
      BFF_CharacterDB.deaths = BFF_CharacterDB.deaths + 1
    end
    if PROFESSION_EVENTS[event] then readProfessions() end
    update()
  end)
  update()
end
