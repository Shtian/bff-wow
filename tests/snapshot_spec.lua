local GLOBALS = {
  "C_Item", "C_UnitAuras", "GetItemInfo", "GetShapeshiftFormID", "InCombatLockdown",
  "IsFlying", "IsResting", "UnitClass", "UnitIsAFK", "UnitOnTaxi", "issecretvalue",
}

local previous = {}
local snapshot
local reads

local function playAs(class, formID, hasGhostWolf)
  _G.UnitClass = function() return class, class end
  _G.GetShapeshiftFormID = function()
    reads.form = reads.form + 1
    return formID
  end
  _G.C_UnitAuras = {
    GetPlayerAuraBySpellID = function()
      reads.aura = reads.aura + 1
      return hasGhostWolf and {} or nil
    end,
  }
  local ns = {}
  assert(loadfile("Game/Snapshot.lua"))("BFF", ns)
  snapshot = ns.Snapshot
end

local function fight()
  _G.InCombatLockdown = function() return true end
end

before_each(function()
  for _, name in ipairs(GLOBALS) do previous[name] = _G[name] end
  reads = { form = 0, aura = 0 }
  _G.C_Item = nil
  _G.GetItemInfo = nil
  _G.InCombatLockdown = function() return false end
  _G.IsFlying = function() return false end
  _G.IsResting = function() return false end
  _G.UnitIsAFK = function() return false end
  _G.UnitOnTaxi = function() return false end
  _G.issecretvalue = function() return false end
end)

after_each(function()
  for _, name in ipairs(GLOBALS) do _G[name] = previous[name] end
end)

describe("Snapshot doing form", function()
  it("reads a Druid's form", function()
    playAs("DRUID", 5)
    assert.equal("bear", snapshot.doing().form)
  end)

  it("keeps the last form in combat without reading it again", function()
    playAs("DRUID", 5)
    snapshot.doing()
    fight()
    local doing = snapshot.doing()
    assert.is_true(doing.combat)
    assert.equal("bear", doing.form)
    assert.same({ form = 1, aura = 0 }, reads)
  end)

  it("never reads forms or auras for classes without forms", function()
    playAs("HUNTER", 5, true)
    assert.is_nil(snapshot.doing().form)
    assert.same({ form = 0, aura = 0 }, reads)
  end)

  it("never reads the Ghost Wolf aura for a Druid", function()
    playAs("DRUID", nil, true)
    assert.is_nil(snapshot.doing().form)
    assert.equal(0, reads.aura)
  end)

  it("finds a Shaman's Ghost Wolf from its aura when the form reads none", function()
    playAs("SHAMAN", nil, true)
    assert.equal("wolf", snapshot.doing().form)
  end)
end)
