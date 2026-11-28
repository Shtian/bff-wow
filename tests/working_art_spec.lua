local load = require("tests.load")

local function sheet()
  local ns = {}
  assert(loadfile("UI/CampSheet.lua"))("BFF", ns)
  return ns.CampSheet
end

local SLOTS = { "back", "node", "held", "fleck", "find" }
local POSES = {
  "mining", "herbalism", "skinning", "alchemy", "blacksmithing", "enchanting", "engineering", "leatherworking",
  "tailoring", "cooking", "firstAid",
}

describe("The Camp's profession art", function()
  it("animates every profession but fishing", function()
    local Sheet, poses = sheet(), {}
    for pose in pairs(Sheet.working) do poses[#poses + 1] = pose end
    local named = {}
    for _, profession in ipairs(load().Professions.ALL) do named[#named + 1] = profession.work end
    table.sort(poses)
    table.sort(named)
    assert.same(named, poses)
    assert.equal(#POSES, #poses)
  end)

  it("has a figure, cloth and every slot's sprite for each frame of each animation", function()
    local Sheet = sheet()
    for _, pose in ipairs(POSES) do
      local frames = Sheet.working[pose]
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
      assert.same(Sheet.working[pose].reach, layout.working[pose], pose)
    end
  end)

  it("kneels a herbalist and a skinner on a figure a row shorter than the seated one", function()
    local Sheet = sheet()
    assert.equal(Sheet.sprites.seated[4] - 1, Sheet.sprites.crouch[4])
    assert.equal("crouch", Sheet.working.herbalism[1].body)
    assert.equal("crouch", Sheet.working.skinning[1].body)
  end)

  it("stands a smith and an enchanter as tall as the seated figure, and lifts a startled engineer a row", function()
    local Sheet = sheet()
    for _, body in ipairs({ "stand", "raise", "strike" }) do
      assert.equal(Sheet.sprites.seated[4], Sheet.sprites[body][4], body)
    end
    assert.equal(Sheet.sprites.seated[4] + 1, Sheet.sprites.jump[4])
    local bodies = {}
    for _, frame in ipairs(Sheet.working.blacksmithing) do bodies[frame.body] = true end
    assert.same({ raise = true, strike = true }, bodies)
    assert.equal("stand", Sheet.working.enchanting[1].body)
  end)
end)
