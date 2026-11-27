local GLOBALS = {
  "C_BattleNet", "C_GameRules", "GetNormalizedRealmName", "UnitFactionGroup", "UnitGUID", "issecretvalue",
}

local previous = {}
local Ruleset

local function playOn(game)
  _G.GetNormalizedRealmName = game.realmName and function() return game.realmName end
  _G.C_GameRules = game.recordId and { GetCurrentGameModeRecordID = function() return game.recordId end }
  _G.UnitFactionGroup = function() return game.faction, game.faction end
  _G.UnitGUID = function() return game.guid end
  _G.C_BattleNet = game.richPresence and {
    GetGameAccountInfoByGUID = function(guid)
      if guid ~= game.guid then error("not this player") end
      return { richPresence = game.richPresence }
    end,
  }
end

before_each(function()
  for _, name in ipairs(GLOBALS) do previous[name] = _G[name] end
  _G.issecretvalue = nil
  local ns = {}
  assert(loadfile("Core/Slots.lua"))("BFF", ns)
  assert(loadfile("Game/Ruleset.lua"))("BFF", ns)
  Ruleset = ns.Ruleset
end)

after_each(function()
  for _, name in ipairs(GLOBALS) do _G[name] = previous[name] end
end)

describe("the Ruleset name in the rich presence", function()
  local cases = {
    { "World of Warcraft: Forever - Normal - Elwynn Forest", "Normal" },
    { "World of Warcraft: Forever - PvP - Durotar", "PvP" },
    { "World of Warcraft: Forever - Roleplay - Stormwind City", "Roleplay" },
    { "World of Warcraft: Forever - Roleplay PvP - Mulgore", "Roleplay PvP" },
    { "World of Warcraft: Forever - Normal - Hellfire Peninsula - The Stair of Destiny", "Normal" },
    { "World of Warcraft: Forever - Normal", "Normal" },
    { "Elwynn Forest", nil },
    { "In Menus", nil },
    { "Stormwind City - Stormrage", nil },
    { "World of Warcraft: Forever - ", nil },
    { "", nil },
  }
  for _, case in ipairs(cases) do
    it(("reads %q as %s"):format(case[1], tostring(case[2])), function()
      assert.equal(case[2], Ruleset.nameIn(case[1]))
    end)
  end

  it("is nil for anything but text", function()
    assert.is_nil(Ruleset.nameIn(nil))
    assert.is_nil(Ruleset.nameIn(15))
  end)
end)

describe("the Ruleset facts at login", function()
  it("reads the realm, record ID, faction, server ID and name", function()
    playOn({
      realmName = "", recordId = 15, faction = "Alliance", guid = "Player-6939-0A1B2C3D",
      richPresence = "World of Warcraft: Forever - Normal - Elwynn Forest",
    })
    assert.same({ realmName = "", recordId = 15, faction = "Alliance", serverId = "6939", name = "Normal" },
      Ruleset.read())
    assert.equal("Normal", Ruleset.name())
  end)

  it("leaves out what the game doesn't give", function()
    playOn({})
    assert.same({}, Ruleset.read())
    assert.is_nil(Ruleset.name())
  end)

  it("leaves out an API that errors", function()
    playOn({ faction = "Horde", guid = "Player-6856-0A1B2C3D", richPresence = "x" })
    _G.C_BattleNet.GetGameAccountInfoByGUID = function() error("Battle.net is down") end
    assert.same({ faction = "Horde", serverId = "6856" }, Ruleset.read())
  end)
end)
