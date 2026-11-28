local load = require("tests.load")

local function sheet()
  local ns = {}
  assert(loadfile("UI/CampSheet.lua"))("BFF", ns)
  return ns.CampSheet
end

describe("The Camp's sleeper art", function()
  it("breathes between two bedrolls as wide as a sleeper's slot, each with its cloth and snow", function()
    local Sheet, layout = sheet(), load().Core.CAMP_LAYOUT
    for _, frame in ipairs({ "", "2" }) do
      local skin, cloth = Sheet.sprites["asleep" .. frame], Sheet.sprites["asleepCloth" .. frame]
      assert.same({ layout.asleep, 6 }, { skin[3], skin[4] }, frame)
      assert.same({ skin[3], skin[4] }, { cloth[3], cloth[4] }, frame)
      local snow = Sheet.sprites["bedSnow" .. frame]
      assert.is_true(Sheet.winter.bedSnow + snow[3] <= layout.asleep, frame)
    end
  end)
end)
