-- Core/ is pure Lua and gets no WoW globals (docs/design/code-structure.md),
-- only LibStub for the pure libraries.
std = "lua51"
max_line_length = false
self = false
exclude_files = { "Libs/", ".luarocks/", "lua_modules/", ".install/", ".lua/" }

-- The WoW API the game-facing files use. Add names here as they're needed.
stds.wow = {
  globals = {
    "BFF_CharacterDB",
    "BFF_DB",
    "SLASH_BFF1",
    "SlashCmdList",
  },
  read_globals = {
    "C_Timer",
    "CreateFrame",
    "GetMaxLevelForPlayerExpansion",
    "GetRealZoneText",
    "GetServerTime",
    "IsTrialAccount",
    "IsVeteranTrialAccount",
    "LOCALIZED_CLASS_NAMES_MALE",
    "RAID_CLASS_COLORS",
    "UIParent",
    "UISpecialFrames",
    "UnitClass",
    "UnitGUID",
    "UnitLevel",
    "UnitName",
    "UnitXP",
    "UnitXPMax",
  },
}

-- LibStub is how Core reaches the pure libraries (LibSerialize, LibDeflate).
stds.libstub = { read_globals = { "LibStub" } }

files["Core/"] = { std = "lua51+libstub" }
files["BFF.lua"] = { std = "lua51+wow" }
files["Game/"] = { std = "lua51+wow" }
files["UI/"] = { std = "lua51+wow" }
files["Dev/"] = { std = "lua51+wow" }
files["tests/"] = { std = "lua51+busted" }
