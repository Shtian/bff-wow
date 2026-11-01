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
    "BACKPACK_CONTAINER",
    "C_ChatInfo",
    "C_Container",
    "C_Cursor",
    "C_Item",
    "C_Map",
    "C_PartyInfo",
    "C_Timer",
    "ChatEdit_InsertLink",
    "ChatFrame_AddMessageEventFilter",
    "ChatFrame_SendTell",
    "ChatFrameUtil",
    "ChatThrottleLib",
    "ClearCursor",
    "CLOSE",
    "CreateFont",
    "CreateFrame",
    "date",
    "ERR_TOO_MANY_CHAT_CHANNELS",
    "GameTooltip",
    "GetChannelList",
    "GetChannelName",
    "GetCursorInfo",
    "GetInstanceInfo",
    "GetItemIcon",
    "GetItemInfo",
    "GetMaxLevelForPlayerExpansion",
    "GetMoney",
    "GetRealZoneText",
    "GetServerTime",
    "GetTime",
    "HBD_PINS_WORLDMAP_SHOW_WORLD",
    "HideUIPanel",
    "InCombatLockdown",
    "IsModifiedClick",
    "IsInInstance",
    "ItemLocation",
    "JoinTemporaryChannel",
    "LeaveChannelByName",
    "LOCALIZED_CLASS_NAMES_MALE",
    "MenuUtil",
    "NO",
    "NUM_BAG_SLOTS",
    "NUM_CHAT_WINDOWS",
    "NUM_TOTAL_EQUIPPED_BAG_SLOTS",
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
