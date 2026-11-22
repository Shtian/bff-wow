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
local PROFESSION_EVENTS = { PLAYER_ENTERING_WORLD = true, SKILL_LINES_CHANGED = true }

local level = 0
local zone
local money
local professions

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

  -- WoW: PLAYER_LEVEL_UP fires before UnitLevel catches up.
  level = math.max(level, UnitLevel("player"))
  -- WoW: GetRealZoneText reads empty while loading.
  local currentZone = GetRealZoneText()
  if currentZone and currentZone ~= "" then zone = currentZone end
  local currentMoney = GetMoney()
  if type(currentMoney) == "number" and not (issecretvalue and issecretvalue(currentMoney)) then
    money = currentMoney
  end

  local _, classFilename = UnitClass("player")
  -- WoW: on Forever UnitName's second value is the last name (retail's realm).
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

function Snapshot.locate()
  local ok, location = pcall(locate)
  return ok and location or nil
end

local function readable(value)
  if issecretvalue and issecretvalue(value) then return nil end
  return value
end

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

function Snapshot.party()
  local party = {}
  for _, unit in ipairs(groupUnits()) do
    if UnitExists(unit) then
      local name, lastName = UnitName(unit)
      name, lastName = readable(name), readable(lastName)
      if lastName == "" then lastName = nil end
      party[#party + 1] = { guid = readable(UnitGUID(unit)), name = name, lastName = lastName }
    end
  end
  return party
end

local function encounter(encounterID, success)
  local _, instanceType = GetInstanceInfo()
  success = readable(success)
  -- WoW: the wiki has ENCOUNTER_END's success as 1 or 0; a boolean is taken too.
  if success == 1 then success = true elseif success == 0 then success = false end
  if type(success) ~= "boolean" then success = nil end
  return {
    encounterId = readable(encounterID),
    success = success,
    instanceType = readable(instanceType),
    party = Snapshot.party(),
  }
end

function Snapshot.encounter(encounterID, _, _, _, success)
  local ok, result = pcall(encounter, encounterID, success)
  return ok and result or nil
end

-- WoW: Fishing's cast events can hide their spell from addons, and there
-- are 12 Fishing spells, so IsFishingLoot() alone tells a catch.
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

function Snapshot.catch()
  if not (IsFishingLoot and GetNumLootItems and GetLootSlotLink and GetLootSlotInfo) then return nil end
  return ns.Catches.read(CATCH_API)
end

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

local getItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo

-- WoW: asking starts loading an uncached item, and GET_ITEM_INFO_RECEIVED
-- says when it has.
function Snapshot.itemLink(itemString)
  local _, link = getItemInfo(itemString)
  return link
end

function Snapshot.requiredLevel(link)
  return (select(5, getItemInfo(link)))
end

local windows = { vendor = false, auction = false }
local function flag(ask, ...)
  if not ask then return false end
  local value = ask(...)
  if issecretvalue and issecretvalue(value) then return false end
  return value and true or false
end

-- WoW: GetShapeshiftFormID: cat 1, travel 3, aquatic 4, bear 5, dire bear 8,
-- Ghost Wolf 16, moonkin 31 and 35.
local FORM_IDS = { [1] = "cat", [3] = "travel", [4] = "seal", [5] = "bear", [8] = "bear", [16] = "wolf",
  [31] = "moonkin", [35] = "moonkin" }
-- WoW: Ghost Wolf can read as no form while its aura (this spell) shows.
local GHOST_WOLF = 2645
-- WoW: under Midnight's restrictions the form reads secret in combat.
local lastForm = nil

local function askSafely(ask, ...)
  if not ask then return nil end
  local ok, value = pcall(ask, ...)
  if not ok or (issecretvalue and issecretvalue(value)) then return nil, true end
  return value
end

local function form(inCombat)
  if inCombat then return lastForm end
  local id, secret = askSafely(GetShapeshiftFormID)
  if secret then return lastForm end
  local found = FORM_IDS[id]
  if not found and C_UnitAuras and not issecretvalue then
    local aura, auraSecret = askSafely(C_UnitAuras.GetPlayerAuraBySpellID, GHOST_WOLF)
    if auraSecret then return lastForm end
    if aura then found = "wolf" end
  end
  lastForm = found
  return found
end

function Snapshot.doing()
  local inCombat = flag(InCombatLockdown)
  return {
    combat = inCombat,
    vendor = windows.vendor,
    auction = windows.auction,
    afk = flag(UnitIsAFK, "player"),
    resting = flag(IsResting),
    flying = flag(UnitOnTaxi, "player") or flag(IsFlying),
    form = form(inCombat),
  }
end

-- WoW: C_DateAndTime.IsDayTime and DIEL_CYCLE_CHANGED are Forever's, behind its minimap's sun and moon.
function Snapshot.daylight()
  if C_DateAndTime and C_DateAndTime.IsDayTime then return C_DateAndTime.IsDayTime() end
  return nil, GetGameTime()
end

local function watchDaylight(core)
  local event = "DIEL_CYCLE_CHANGED"
  if not (C_EventUtils and C_EventUtils.IsEventValid and C_EventUtils.IsEventValid(event)) then return end
  local frame = CreateFrame("Frame")
  frame:RegisterEvent(event)
  frame:SetScript("OnEvent", function() core:daylightChanged() end)
end

local WINDOW_EVENTS = {
  MERCHANT_SHOW = { "vendor", true }, MERCHANT_CLOSED = { "vendor", false },
  AUCTION_HOUSE_SHOW = { "auction", true }, AUCTION_HOUSE_CLOSED = { "auction", false },
}

local function watchGroup(core)
  local function tell()
    local ok, party = pcall(Snapshot.party)
    if ok then core:group(party) end
  end
  local frame = CreateFrame("Frame")
  frame:RegisterEvent("GROUP_ROSTER_UPDATE")
  frame:SetScript("OnEvent", tell)
  tell()
end

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
      local _, instanceType = GetInstanceInfo()
      if ns.Deaths.counts(instanceType) then BFF_CharacterDB.deaths = BFF_CharacterDB.deaths + 1 end
    end
    if PROFESSION_EVENTS[event] then readProfessions() end
    update()
  end)
  update()
  watchDoing(core)
  watchRares(core)
  watchGroup(core)
  watchDaylight(core)
end
