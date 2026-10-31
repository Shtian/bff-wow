-- Core/ is pure Lua and gets no WoW globals (docs/design/code-structure.md).
std = "lua51"
max_line_length = false
self = false
exclude_files = { "Libs/", ".luarocks/", "lua_modules/", ".install/", ".lua/" }

-- The WoW API the game-facing files use. Add names here as they're needed.
stds.wow = {
  globals = {
    "BFF_DB",
  },
  read_globals = {
    "C_Timer",
    "CreateFrame",
    "GetMaxLevelForPlayerExpansion",
    "GetServerTime",
    "IsTrialAccount",
    "IsVeteranTrialAccount",
  },
}

files["BFF.lua"] = { std = "lua51+wow" }
files["Game/"] = { std = "lua51+wow" }
files["UI/"] = { std = "lua51+wow" }
files["Dev/"] = { std = "lua51+wow" }
files["tests/"] = { std = "lua51+busted" }
