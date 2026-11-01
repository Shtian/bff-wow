-- Core/ is pure Lua and gets no WoW globals (docs/design/code-structure.md),
-- only LibStub for the pure libraries and the bit library.
std = "lua51"
max_line_length = false
self = false
exclude_files = { "Libs/", ".luarocks/", "lua_modules/", ".install/", ".lua/" }

-- The WoW API the game-facing files use. Add names here as they're needed.
stds.wow = {
  globals = {
    "BFF_CharacterDB",
    "BFF_DB",
    "BFF_TogglePanel",
    "BINDING_HEADER_BFF",
    "BINDING_NAME_BFF_TOGGLE",
    "SLASH_BFF1",
    "SLASH_BFFDEV1",
    "SlashCmdList",
    "StaticPopupDialogs",
  },
  read_globals = {
    "Ambiguate",
    "C_ChatInfo",
    "C_Map",
    "C_PartyInfo",
    "C_Timer",
    "ChatFrame_AddMessageEventFilter",
    "ChatFrame_SendTell",
    "ChatFrameUtil",
    "ChatThrottleLib",
    "CLOSE",
    "CreateFont",
    "CreateFrame",
    "date",
    "ERR_TOO_MANY_CHAT_CHANNELS",
    "GameTooltip",
    "GetChannelList",
    "GetChannelName",
    "GetInstanceInfo",
    "GetMaxLevelForPlayerExpansion",
    "GetRealZoneText",
    "GetServerTime",
    "GetTime",
    "HBD_PINS_WORLDMAP_SHOW_WORLD",
    "HideUIPanel",
    "InCombatLockdown",
    "IsInInstance",
    "JoinTemporaryChannel",
    "LeaveChannelByName",
    "LOCALIZED_CLASS_NAMES_MALE",
    "MenuUtil",
    "NO",
    "NUM_CHAT_WINDOWS",
    "PlaySound",
    "RAID_CLASS_COLORS",
    "RemoveChatWindowChannel",
    "Settings",
    "SettingsPanel",
    "StaticPopup_Show",
    "SOUNDKIT",
    "time",
    "UIParent",
    "UISpecialFrames",
    "UnitClass",
    "UnitGUID",
    "UnitLevel",
    "UnitName",
    "UnitXP",
    "UnitXPMax",
    "WorldMapFrame",
    "YES",
    "issecretvalue",
  },
}

-- LibStub is how Core reaches the pure libraries (LibSerialize, LibDeflate).
stds.libstub = { read_globals = { "LibStub" } }

-- WoW and LuaJIT both provide the bit library (CrewCode's hash).
stds.bit = { read_globals = { "bit" } }

files["Core/"] = { std = "lua51+libstub+bit" }
files["BFF.lua"] = { std = "lua51+wow" }
files["Game/"] = { std = "lua51+wow+libstub" }
files["UI/"] = { std = "lua51+wow+libstub" }
files["Dev/"] = { std = "lua51+wow" }
files["tests/"] = { std = "lua51+busted" }
