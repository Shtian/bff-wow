local load = require("tests.load")

local Commands = load().Commands

local function plain(line)
  return (line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local function plainLines(lines)
  local result = {}
  for i, line in ipairs(lines) do result[i] = plain(line) end
  return result
end

local function handlerNames()
  local names = {}
  for line in io.lines("BFF.lua") do
    local name = line:match("^function commands%.(%w+)%(")
    if name then names[#names + 1] = name end
  end
  table.sort(names)
  return names
end

describe("Commands", function()
  it("has an entry for every handler and a handler for every entry", function()
    local names = Commands.names()
    table.sort(names)
    assert.same(handlerNames(), names)
  end)

  it("resolves tab names, old aliases and any case", function()
    assert.equal("trophies", Commands.resolve("trophies"))
    assert.equal("trophies", Commands.resolve("goals"))
    assert.equal("playtimes", Commands.resolve("when"))
    assert.equal("playtimes", Commands.resolve("play"))
    assert.equal("dungeons", Commands.resolve("together"))
    assert.equal("roster", Commands.resolve("Roster"))
    assert.equal("whatsnew", Commands.resolve("whatsnew"))
    assert.is_nil(Commands.resolve("trophys"))
    assert.is_nil(Commands.resolve(""))
    assert.is_nil(Commands.resolve("sim", false))
    assert.equal("sim", Commands.resolve("sim", true))
  end)

  it("groups the help in a few short lines, with only tab names", function()
    local lines = plainLines(Commands.help(false))
    assert.same({
      "BFF commands",
      " /bff  open or close the panel",
      " Open a tab: /bff roster, feed, trophies, playtimes, spares,",
      "   professions, dungeons, catches, whatsnew",
      " Crew: /bff start · join <code> · code · name <name> · leave",
      " /bff spares add <item>  put up a Spare from your bags",
      " /bff settings · minimap · report · debug sync",
      " /bff help <command>  more about one",
    }, lines)
  end)

  it("colours commands gold and the rest grey", function()
    local line = Commands.help(false)[2]
    assert.truthy(line:find("|cffffd14a/bff|r", 1, true))
    assert.truthy(line:find("|cffadabb8  open or close the panel|r", 1, true))
  end)

  it("keeps every help line within a chat frame's width", function()
    for _, line in ipairs(plainLines(Commands.help(true))) do
      assert.is_true(#line:gsub("·", ".") <= Commands.WIDTH, line)
    end
  end)

  it("lists /bff sim on its own line only in a dev checkout", function()
    local function hasSim(lines)
      for _, line in ipairs(plainLines(lines)) do
        if line:find("/bff sim", 1, true) then return line end
      end
    end
    assert.is_nil(hasSim(Commands.help(false)))
    assert.truthy(hasSim(Commands.help(true)):find("^ /bff sim  "))
  end)

  it("explains every command and its forms", function()
    for _, name in ipairs(Commands.names()) do
      local lines = Commands.helpFor(name, true)
      assert.truthy(lines and #lines > 0, name)
      assert.truthy(plain(lines[1]):find("^/bff " .. name), name)
    end
    assert.same({
      "/bff spares  open the Spares tab",
      "/bff spares add <item>  put up an item from your bags as a Spare: shift-click it in after add",
    }, plainLines(Commands.helpFor("spares", false)))
    assert.equal("/bff trophies  open the Trophies tab", plain(Commands.helpFor("GOALS", false)[1]))
    assert.is_nil(Commands.helpFor("trophys", false))
    assert.is_nil(Commands.helpFor("sim", false))
  end)

  it("suggests the nearest command for a typo, a prefix or an old alias", function()
    assert.equal("trophies", Commands.suggest("trophys", false))
    assert.equal("professions", Commands.suggest("prof", false))
    assert.equal("dungeons", Commands.suggest("togeter", false))
    assert.equal("trophies", Commands.suggest("goal", false))
    assert.equal("leave", Commands.suggest("lave", false))
    assert.equal("whatsnew", Commands.suggest("whats", false))
  end)

  it("suggests nothing for nonsense, and sim only in a dev checkout", function()
    assert.is_nil(Commands.suggest("xyz", false))
    assert.is_nil(Commands.suggest("qqqqqqq", false))
    assert.is_nil(Commands.suggest("simm", false))
    assert.equal("sim", Commands.suggest("simm", true))
  end)

  it("words an unknown command without dumping the help", function()
    assert.equal("No /bff trophys. Did you mean /bff trophies? (/bff help lists them)",
      plain(Commands.unknown("trophys", false)))
    assert.equal("No /bff xyz. /bff help lists them.", plain(Commands.unknown("xyz", false)))
  end)
end)
