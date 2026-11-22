local GLOBALS = {
  "C_Item", "C_UnitAuras", "GetItemInfo", "GetShapeshiftFormID",
  "InCombatLockdown", "UnitIsAFK", "IsResting", "UnitOnTaxi", "IsFlying",
  "issecretvalue",
}

local previous = {}
local snapshot

before_each(function()
  for _, name in ipairs(GLOBALS) do previous[name] = _G[name] end
  _G.C_Item = nil
  _G.C_UnitAuras = nil
  _G.GetItemInfo = nil
  _G.GetShapeshiftFormID = function() return nil end
  _G.InCombatLockdown = function() return false end
  _G.UnitIsAFK = function() return false end
  _G.IsResting = function() return false end
  _G.UnitOnTaxi = function() return false end
  _G.IsFlying = function() return false end
  _G.issecretvalue = function() return false end
  local ns = {}
  assert(loadfile("Game/Snapshot.lua"))("BFF", ns)
  snapshot = ns.Snapshot
end)

after_each(function()
  for _, name in ipairs(GLOBALS) do _G[name] = previous[name] end
end)

describe("Snapshot doing form", function()
  it("keeps the last form without querying combat-restricted APIs", function()
    _G.GetShapeshiftFormID = function() return 5 end
    assert.equal("bear", snapshot.doing().form)

    local formReads, auraReads = 0, 0
    _G.GetShapeshiftFormID = function() formReads = formReads + 1 end
    _G.C_UnitAuras = {
      GetPlayerAuraBySpellID = function()
        auraReads = auraReads + 1
        return {}
      end,
    }
    _G.InCombatLockdown = function() return true end

    local doing = snapshot.doing()
    assert.is_true(doing.combat)
    assert.equal("bear", doing.form)
    assert.equal(0, formReads)
    assert.equal(0, auraReads)
  end)

  it("does not query aura data on clients with secret values", function()
    local auraReads = 0
    _G.C_UnitAuras = {
      GetPlayerAuraBySpellID = function()
        auraReads = auraReads + 1
        return {}
      end,
    }
    assert.is_nil(snapshot.doing().form)
    assert.equal(0, auraReads)
  end)

  it("still detects Ghost Wolf from its aura on clients without secret values", function()
    _G.issecretvalue = nil
    _G.C_UnitAuras = { GetPlayerAuraBySpellID = function() return {} end }
    assert.equal("wolf", snapshot.doing().form)
  end)
end)
