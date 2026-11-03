local load = require("tests.load")

-- A Core over a fresh db, outside any Crew, recording its events.
local function newCore(db)
  local deps = {
    events = {},
    db = db or {},
    now = function() return 1000 end,
    random = function() return 0.5 end,
    initialLogin = true,
    maxLevel = 60,
  }
  deps.link = { send = function() end }
  deps.listener = function(...) deps.events[#deps.events + 1] = { ... } end
  return load().Core.new(deps), deps
end

local function changes(deps)
  local found = {}
  for _, event in ipairs(deps.events) do
    if event[1] == "settingChanged" and event[2] == "panelPlace" then found[#found + 1] = { value = event[3] } end
  end
  return found
end

local SCREEN_W, SCREEN_H = 1920, 1080

describe("Panel place", function()
  it("opens at the default size, centred, until the player moves or resizes it", function()
    local core = newCore()
    assert.same({ width = 460, height = 380 }, core:panelPlace(SCREEN_W, SCREEN_H))
  end)

  it("keeps the size and position across a new Core over the same db", function()
    local core, deps = newCore()
    core:setPanelPlace(600, 500, 100, 900)
    assert.same({ width = 600, height = 500, left = 100, top = 900 }, core:panelPlace(SCREEN_W, SCREEN_H))
    assert.same({ width = 600, height = 500, left = 100, top = 900 }, newCore(deps.db):panelPlace(SCREEN_W, SCREEN_H))
  end)

  it("keeps the size between the smallest and largest panel", function()
    local core = newCore()
    core:setPanelPlace(200, 100, 10, 500)
    assert.same({ width = 460, height = 380, left = 10, top = 500 }, core:panelPlace(SCREEN_W, SCREEN_H))
    core:setPanelPlace(5000, 5000, 10, 1000)
    assert.same({ width = 900, height = 800, left = 10, top = 1000 }, core:panelPlace(SCREEN_W, SCREEN_H))
  end)

  it("keeps the panel on a screen smaller than where it was left", function()
    local core = newCore()
    core:setPanelPlace(800, 700, 1500, 1050)
    -- 1500 + 800 runs off a 1280 wide screen; 1050 is above a 720 high one.
    assert.same({ width = 800, height = 700, left = 480, top = 720 }, core:panelPlace(1280, 720))
    core:setPanelPlace(800, 700, -40, 200)
    assert.same({ width = 800, height = 700, left = 0, top = 700 }, core:panelPlace(1280, 720))
  end)

  it("shrinks a panel bigger than the screen to fit it", function()
    local core = newCore()
    core:setPanelPlace(900, 800, 0, 800)
    assert.same({ width = 800, height = 600, left = 0, top = 600 }, core:panelPlace(800, 600))
  end)

  it("saves whole pixels", function()
    local core = newCore()
    core:setPanelPlace(600.4, 500.6, 100.5, 899.2)
    assert.same({ width = 600, height = 501, left = 101, top = 899 }, core:panelPlace(SCREEN_W, SCREEN_H))
  end)

  it("resets to the default size, centred", function()
    local core = newCore()
    core:setPanelPlace(600, 500, 100, 900)
    core:resetPanelPlace()
    assert.same({ width = 460, height = 380 }, core:panelPlace(SCREEN_W, SCREEN_H))
  end)

  it("fires settingChanged only when the place actually changes", function()
    local core, deps = newCore()
    core:resetPanelPlace()
    core:setPanelPlace(600, 500, 100, 900)
    core:setPanelPlace(600, 500, 100, 900)
    core:setPanelPlace(600.2, 500, 100, 900)
    core:setPanelPlace(600, 500, 120, 900)
    core:resetPanelPlace()
    core:resetPanelPlace()
    assert.same({
      { value = { width = 600, height = 500, left = 100, top = 900 } },
      { value = { width = 600, height = 500, left = 120, top = 900 } },
      {},
    }, changes(deps))
  end)

  it("shows a reset on the Settings page, under Notifications and display", function()
    local core = newCore()
    local display = core:settings()[2]
    local reset = display.settings[#display.settings]
    assert.same({ key = "panelPlace", kind = "panelPlace", label = "Reset BFF window" },
      { key = reset.key, kind = reset.kind, label = reset.label })
    assert.is_nil(reset.value)
  end)
end)
