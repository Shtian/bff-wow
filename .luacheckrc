-- Core/ and Link/ are pure Lua and get no WoW globals
-- (docs/design/code-structure.md). Core/ gets LibStub for the pure libraries
-- and the bit library.
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
    "C_AddOns",
    "C_ChatInfo",
    "C_Container",
    "C_Cursor",
    "C_Item",
    "C_Map",
    "C_PartyInfo",
    "C_Timer",
    "C_XMLUtil",
    "ChatEdit_InsertLink",
    "ChatFrame_AddMessageEventFilter",
    "ChatFrame_SendTell",
    "ChatFrameUtil",
    "ChatThrottleLib",
    "ClearCursor",
    "CLOSE",
    "CreateFont",
    "CreateFrame",
    "Enum",
    "date",
    "ERR_CHAT_PLAYER_NOT_FOUND_S",
    "ERR_TOO_MANY_CHAT_CHANNELS",
    "GameTooltip",
    "GetBuildInfo",
    "GetChannelList",
    "GetChannelName",
    "GetCursorPosition",
    "GetCursorInfo",
    "GetInstanceInfo",
    "GetItemIcon",
    "GetItemInfo",
    "GetLootSlotInfo",
    "GetLootSlotLink",
    "GetMaxLevelForPlayerExpansion",
    "GetMoney",
    "GetNumLootItems",
    "GetNumGroupMembers",
    "GetProfessionInfo",
    "GetProfessions",
    "GetRealZoneText",
    "GetServerTime",
    "GetSubZoneText",
    "GetTime",
    "HBD_PINS_WORLDMAP_SHOW_WORLD",
    "HideUIPanel",
    "InCombatLockdown",
    "IsFlying",
    "IsModifiedClick",
    "IsResting",
    "IsShiftKeyDown",
    "IsMouseButtonDown",
    "IsInInstance",
    "IsInRaid",
    "IsFishingLoot",
    "ItemLocation",
    "JoinTemporaryChannel",
    "LeaveChannelByName",
    "ListChannelByName",
    "LOCALIZED_CLASS_NAMES_MALE",
    "MenuResponse",
    "MenuUtil",
    "NO",
    "NUM_BAG_SLOTS",
    "NUM_CHAT_WINDOWS",
    "NUM_TOTAL_EQUIPPED_BAG_SLOTS",
    "PixelUtil",
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
    "UnitExists",
    "UnitGUID",
    "UnitLevel",
    "UnitOnTaxi",
    "UnitName",
    "UnitXP",
    "UnitXPMax",
    "WorldMapFrame",
    "WOW_PROJECT_CAMELOT",
    "WOW_PROJECT_ID",
    "YES",
    "issecretvalue",
  },
}

-- LibStub is how Core reaches the pure libraries (LibSerialize, LibDeflate).
stds.libstub = { read_globals = { "LibStub" } }

-- WoW and LuaJIT both provide the bit library (CrewCode's hash).
stds.bit = { read_globals = { "bit" } }

files["Core/"] = { std = "lua51+libstub+bit" }
files["Link/"] = { std = "lua51" }
files["BFF.lua"] = { std = "lua51+wow" }
files["Game/"] = { std = "lua51+wow+libstub" }
files["UI/"] = { std = "lua51+wow+libstub" }
files["Dev/"] = { std = "lua51+wow" }
files["tests/"] = { std = "lua51+busted" }
