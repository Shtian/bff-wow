-- Snapshot: reads the Character being played and hands it to Core. It also
-- counts deaths, kept per Character in BFF_CharacterDB, so a client crash
-- loses that session's deaths (see docs/design/code-structure.md), and
-- reads where the Character stands for Core's locate(), and item info for
-- Spares.

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
}

local level = 0
local zone
local money

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
