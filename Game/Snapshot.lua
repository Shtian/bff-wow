-- Snapshot: reads the Character being played and hands it to Core. It also
-- counts deaths, kept per Character in BFF_CharacterDB, so a client crash
-- loses that session's deaths (see docs/design/code-structure.md), and
-- reads its professions (on PLAYER_ENTERING_WORLD and SKILL_LINES_CHANGED),
-- where the Character stands for Core's locate(), item info for Spares,
-- a boss kill's payload with the party for Core's encounterEnded(), a
-- fishing catch from the loot window for Core's caught(), and Rare kills
-- for Core's rareKilled(), through the watch (Rares.watch).

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
  -- On Forever UnitName's second value is the last name (retail's realm).
  local name, lastName = UnitName("player")
  if (issecretvalue and issecretvalue(lastName)) or type(lastName) ~= "string" or lastName == "" then
    lastName = nil
  end
  return {
    guid = guid,
    name = name,
    lastName = lastName,
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

-- The loot window, for Catches.read. Fishing's cast events can hide
-- their spell from addons, and there are 12 Fishing spells, so a catch
-- is told by IsFishingLoot() alone (docs/research/fishing-catches.md).
local CATCH_API = {
  isFishingLoot = IsFishingLoot,
  getNumLootItems = GetNumLootItems,
  getLootSlotLink = GetLootSlotLink,
  getLootSlotInfo = GetLootSlotInfo,
  zone = GetRealZoneText,
  subzone = GetSubZoneText,
  mapId = function() return C_Map.GetBestMapForUnit("player") end,
  isSecret = issecretvalue,
}

-- What was fished, read on LOOT_READY: the loot for Core's caught(), or
-- nil when the loot isn't from fishing (or the client has no such API).
function Snapshot.catch()
  if not (IsFishingLoot and GetNumLootItems and GetLootSlotLink and GetLootSlotInfo) then return nil end
  return ns.Catches.read(CATCH_API)
end

-- The game's reads the Rare kill watch needs (Rares.watch), each nil
-- where the client hasn't the function, which the watch's guard turns
-- into finding nothing.
local function call(name)
  return function(...)
    local fn = _G[name]
    if fn then return fn(...) end
  end
end
local RARE_API = {
  unitGUID = call("UnitGUID"),
  unitName = call("UnitName"),
  unitClassification = call("UnitClassification"),
  unitIsDead = call("UnitIsDead"),
  unitIsTapDenied = call("UnitIsTapDenied"),
  getNumLootItems = call("GetNumLootItems"),
  getLootSourceInfo = call("GetLootSourceInfo"),
  zone = call("GetRealZoneText"),
  subzone = call("GetSubZoneText"),
  mapId = function() return C_Map.GetBestMapForUnit("player") end,
  isSecret = issecretvalue,
}

-- What tells a Rare kill (docs/design/rares.md): units seen while their
-- identity can be read (the target, mouseover, nameplates), the loot
-- window (once per window, until LOOT_CLOSED), the target dying (and
-- again when combat ends, when its identity may read again) and
-- PARTY_KILL. Events this client doesn't have are skipped. Each kill goes
-- to Core; what each read made of it goes to ns.rareSink(info, results)
-- where a dev checkout sets one (the logger in Dev/Sim.lua).
local RARE_EVENTS = {
  "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED",
  "LOOT_READY", "LOOT_CLOSED", "PLAYER_TARGET_DIED", "PLAYER_REGEN_ENABLED", "PARTY_KILL",
}

local function watchRares(core)
  local watch = ns.Rares.watch(RARE_API)
  local lootRead = false
  local function report(kills, info)
    local results = {}
    for i, kill in ipairs(kills) do
      local changed, reason = core:rareKilled(kill)
      results[i] = changed and "recorded" or reason
    end
    if ns.rareSink then pcall(ns.rareSink, info, kills, results) end
  end
  local frame = CreateFrame("Frame")
  for _, event in ipairs(RARE_EVENTS) do pcall(frame.RegisterEvent, frame, event) end
  frame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_TARGET_CHANGED" then
      report({}, watch:see("target"))
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
      report({}, watch:see("mouseover"))
    elseif event == "NAME_PLATE_UNIT_ADDED" then
      local unit = ...
      if type(unit) == "string" and not (issecretvalue and issecretvalue(unit)) then report({}, watch:see(unit)) end
    elseif event == "LOOT_READY" then
      if lootRead then return end
      lootRead = true
      report(watch:loot())
    elseif event == "LOOT_CLOSED" then
      lootRead = false
    elseif event == "PLAYER_TARGET_DIED" or event == "PLAYER_REGEN_ENABLED" then
      local kill, info = watch:targetDied()
      info.event = event
      report(kill and { kill } or {}, info)
    elseif event == "PARTY_KILL" then
      local kill, info = watch:partyKill(...)
      report(kill and { kill } or {}, info)
    end
  end)
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

-- What the Character is doing right now, for Core's doing(): in combat,
-- at a vendor or the auction house (their windows, kept from their show
-- and close events), resting, and flying (a flight path, or a flying
-- mount where the client has them). A value that reads secret is false,
-- and so is one whose function the client doesn't have.
local windows = { vendor = false, auction = false }
local function flag(ask, ...)
  if not ask then return false end
  local value = ask(...)
  if issecretvalue and issecretvalue(value) then return false end
  return value and true or false
end

function Snapshot.doing()
  return {
    combat = flag(InCombatLockdown),
    vendor = windows.vendor,
    auction = windows.auction,
    resting = flag(IsResting),
    flying = flag(UnitOnTaxi, "player") or flag(IsFlying),
  }
end

local WINDOW_EVENTS = {
  MERCHANT_SHOW = { "vendor", true }, MERCHANT_CLOSED = { "vendor", false },
  AUCTION_HOUSE_SHOW = { "auction", true }, AUCTION_HOUSE_CLOSED = { "auction", false },
}

-- Keeps the windows doing() reports, and tells Core of each quest handed
-- in. Core hears what the Character is doing from App, every second.
local function watchDoing(core)
  local frame = CreateFrame("Frame")
  for event in pairs(WINDOW_EVENTS) do frame:RegisterEvent(event) end
  frame:RegisterEvent("QUEST_TURNED_IN")
  frame:SetScript("OnEvent", function(_, event)
    local window = WINDOW_EVENTS[event]
    if window then
      windows[window[1]] = window[2]
    elseif event == "QUEST_TURNED_IN" then
      core:questHandedIn()
    end
  end)
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
  watchDoing(core)
  watchRares(core)
end
