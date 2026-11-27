local load = require("tests.load")

local function sheet()
  local ns = {}
  assert(loadfile("UI/CampSheet.lua"))("BFF", ns)
  return ns.CampSheet
end

local SLOTS = { "back", "node", "held", "fleck", "find" }
local POSES = { "mining", "herbalism", "skinning" }

describe("The Camp's gathering art", function()
  it("has a figure, cloth and every slot's sprite for each frame of each animation", function()
    local Sheet = sheet()
    for _, pose in ipairs(POSES) do
      local frames = Sheet.gathering[pose]
      assert.is_true(#frames > 0, pose)
      for i, frame in ipairs(frames) do
        assert.is_truthy(Sheet.sprites[frame.body], pose .. " " .. i)
        assert.is_truthy(Sheet.sprites[frame.body .. "Cloth"], pose .. " " .. i)
        for _, slot in ipairs(SLOTS) do
          if frame[slot] then assert.is_truthy(Sheet.sprites[frame[slot][1]], pose .. " " .. i .. " " .. slot) end
        end
      end
    end
  end)

  it("gets as much room in the Camp as the art reaches past the figure", function()
    local Sheet, layout = sheet(), load().Core.CAMP_LAYOUT
    for _, pose in ipairs(POSES) do
      assert.same(Sheet.gathering[pose].reach, layout.gathering[pose], pose)
    end
  end)

  it("kneels a herbalist and a skinner on a figure a row shorter than the seated one", function()
    local Sheet = sheet()
    assert.equal(Sheet.sprites.seated[4] - 1, Sheet.sprites.crouch[4])
    assert.equal("crouch", Sheet.gathering.herbalism[1].body)
    assert.equal("crouch", Sheet.gathering.skinning[1].body)
  end)
end)
