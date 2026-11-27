local _, ns = ...

local Ruleset = {}
ns.Ruleset = Ruleset

local PREFIX = "Forever - "
local SEPARATOR = " - "

local function isText(value)
  if issecretvalue and issecretvalue(value) then return false end
  return type(value) == "string" and value ~= ""
end

function Ruleset.nameIn(richPresence)
  if not isText(richPresence) then return nil end
  local _, prefixEnd = richPresence:find(PREFIX, 1, true)
  if not prefixEnd then return nil end
  local rest = richPresence:sub(prefixEnd + 1)
  local stop = rest:find(SEPARATOR, 1, true)
  local name = stop and rest:sub(1, stop - 1) or rest
  if name == "" then return nil end
  return name
end

local function readSafely(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, value = pcall(fn, ...)
  if not ok or (issecretvalue and issecretvalue(value)) then return nil end
  return value
end

local function playerGuid()
  local guid = readSafely(UnitGUID, "player")
  return isText(guid) and guid or nil
end

local function nameFor(guid)
  if not (guid and C_BattleNet) then return nil end
  local info = readSafely(C_BattleNet.GetGameAccountInfoByGUID, guid)
  return type(info) == "table" and Ruleset.nameIn(info.richPresence) or nil
end

function Ruleset.read()
  local guid = playerGuid()
  return {
    realmName = readSafely(GetNormalizedRealmName),
    recordId = C_GameRules and readSafely(C_GameRules.GetCurrentGameModeRecordID) or nil,
    faction = readSafely(UnitFactionGroup, "player"),
    serverId = ns.Slots.serverIdOf(guid),
    name = nameFor(guid),
  }
end

function Ruleset.name()
  return nameFor(playerGuid())
end
