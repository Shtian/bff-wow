local GLOBALS = {
  "BFF_CharacterDB", "C_EventUtils", "C_Item", "C_UnitAuras", "CreateFrame",
  "GetItemInfo", "GetMoney", "GetProfessions", "GetProfessionInfo",
  "GetRealZoneText", "GetShapeshiftFormID", "InCombatLockdown", "IsFlying",
  "IsInRaid", "IsResting", "UnitClass", "UnitExists", "UnitGUID", "UnitIsAFK",
  "UnitLevel", "UnitName", "UnitOnTaxi", "UnitXP", "UnitXPMax", "issecretvalue",
}

local previous = {}
local frames
local snapshot

local function loadSnapshot(classFilename)
  frames = {}
  _G.UnitClass = function() return classFilename, classFilename end
  local ns = {
    Rares = { watch = function() return {} end },
  }
  assert(loadfile("Game/Snapshot.lua"))("BFF", ns)
  snapshot = ns.Snapshot
end

before_each(function()
  for _, name in ipairs(GLOBALS) do previous[name] = _G[name] end
  _G.BFF_CharacterDB = {}
  _G.C_EventUtils = nil
  _G.C_Item = nil
  _G.C_UnitAuras = nil
  _G.CreateFrame = function()
    local frame = { events = {}, unitEvents = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:RegisterUnitEvent(event, unit) self.unitEvents[event] = unit end
    function frame:SetScript(name, fn) self[name] = fn end
    frames[#frames + 1] = frame
    return frame
  end
  _G.GetItemInfo = nil
  _G.GetMoney = function() return 0 end
  _G.GetProfessions = nil
  _G.GetProfessionInfo = nil
  _G.GetRealZoneText = function() return "" end
  _G.GetShapeshiftFormID = function() return nil end
  _G.InCombatLockdown = function() return false end
  _G.IsFlying = function() return false end
  _G.IsInRaid = function() return false end
  _G.IsResting = function() return false end
  _G.UnitExists = function() return false end
  _G.UnitGUID = function() return nil end
  _G.UnitIsAFK = function() return false end
  _G.UnitLevel = function() return 1 end
  _G.UnitName = function() return "Test" end
  _G.UnitOnTaxi = function() return false end
  _G.UnitXP = function() return 0 end
  _G.UnitXPMax = function() return 100 end
  _G.issecretvalue = function() return false end
  loadSnapshot("DRUID")
end)

after_each(function()
  for _, name in ipairs(GLOBALS) do _G[name] = previous[name] end
end)

local function doingFrame()
  for _, frame in ipairs(frames) do
    if frame.events.QUEST_TURNED_IN then return frame end
  end
end

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

  it("skips shapeshift and aura reads for classes without forms", function()
    loadSnapshot("MAGE")
    local formReads, auraReads = 0, 0
    _G.GetShapeshiftFormID = function()
      formReads = formReads + 1
      return 5
    end
    _G.C_UnitAuras = {
      GetPlayerAuraBySpellID = function()
        auraReads = auraReads + 1
        return {}
      end,
    }

    snapshot.start({ updateOwn = function() end, group = function() end })
    assert.is_nil(snapshot.doing().form)
    assert.equal(0, formReads)
    assert.equal(0, auraReads)
    local frame = doingFrame()
    assert.is_nil(frame.events.UPDATE_SHAPESHIFT_FORM)
    assert.is_nil(frame.unitEvents.UNIT_AURA)
  end)

  it("never queries Ghost Wolf aura for Druids", function()
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

  it("detects Ghost Wolf from its aura for Shamans out of combat even when issecretvalue exists", function()
    loadSnapshot("SHAMAN")
    _G.C_UnitAuras = { GetPlayerAuraBySpellID = function() return {} end }
    assert.equal("wolf", snapshot.doing().form)
  end)

  it("only re-reads form on form/aura/combat-end events once started", function()
    loadSnapshot("SHAMAN")
    local formReads, auraReads = 0, 0
    local hasWolf = false
    _G.GetShapeshiftFormID = function()
      formReads = formReads + 1
      return nil
    end
    _G.C_UnitAuras = {
      GetPlayerAuraBySpellID = function()
        auraReads = auraReads + 1
        return hasWolf and {} or nil
      end,
    }

    snapshot.start({ updateOwn = function() end, group = function() end })
    local frame = doingFrame()
    assert.is_true(frame.events.UPDATE_SHAPESHIFT_FORM)
    assert.is_true(frame.events.PLAYER_REGEN_ENABLED)
    assert.equal("player", frame.unitEvents.UNIT_AURA)

    assert.is_nil(snapshot.doing().form)
    assert.equal(1, formReads)
    assert.equal(1, auraReads)

    assert.is_nil(snapshot.doing().form)
    assert.is_nil(snapshot.doing().form)
    assert.equal(1, formReads)
    assert.equal(1, auraReads)

    hasWolf = true
    frame.OnEvent(frame, "UNIT_AURA", "target")
    assert.is_nil(snapshot.doing().form)
    assert.equal(1, formReads)
    assert.equal(1, auraReads)

    frame.OnEvent(frame, "UNIT_AURA", "player")
    assert.equal("wolf", snapshot.doing().form)
    assert.equal(2, formReads)
    assert.equal(2, auraReads)
  end)
end)
