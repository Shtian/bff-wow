local load = require("tests.load")

local function newDeps()
  local deps = {
    sent = {},
    events = {},
    db = {},
    now = function() return 1000 end,
    random = function() return 0.5 end,
    receiveOnly = false,
    initialLogin = true,
    maxLevel = 60,
  }
  deps.link = { send = function(message) deps.sent[#deps.sent + 1] = message end }
  deps.listener = function(...) deps.events[#deps.events + 1] = { ... } end
  return deps
end

local function countEvents(deps, name)
  local count = 0
  for _, event in ipairs(deps.events) do
    if event[1] == name then count = count + 1 end
  end
  return count
end

describe("Core", function()
  it("can be created and ticked", function()
    local ns = load()
    local deps = newDeps()
    local core = ns.Core.new(deps)

    for _ = 1, 10 do core:tick() end

    assert.same({}, deps.sent)
    assert.same({}, deps.events)
  end)

  it("refuses to start without what it needs", function()
    local ns = load()
    for _, name in ipairs({ "db", "now", "random", "link", "listener", "maxLevel" }) do
      local deps = newDeps()
      deps[name] = nil
      assert.has_error(function() ns.Core.new(deps) end)
    end

    local deps = newDeps()
    deps.link = {}
    assert.has_error(function() ns.Core.new(deps) end)
  end)

  describe("minimap button", function()
    it("is shown by default", function()
      local core = load().Core.new(newDeps())
      assert.is_true(core:isMinimapShown())
    end)

    it("stays hidden account-wide, across a new Core over the same db", function()
      local ns = load()
      local deps = newDeps()
      local core = ns.Core.new(deps)
      core:setMinimapShown(false)
      assert.is_false(core:isMinimapShown())
      assert.equal(1, countEvents(deps, "changed"))

      local again = ns.Core.new(deps)
      assert.is_false(again:isMinimapShown())
      again:setMinimapShown(true)
      assert.is_true(again:isMinimapShown())
    end)

    it("fires changed only when the setting changes", function()
      local deps = newDeps()
      local core = load().Core.new(deps)
      core:setMinimapShown(true)
      assert.equal(0, countEvents(deps, "changed"))
    end)

    it("keeps the button's position in the same saved table every time", function()
      local ns = load()
      local deps = newDeps()
      local icon = ns.Core.new(deps):minimapIcon()
      icon.minimapPos = 123
      assert.equal(123, ns.Core.new(deps):minimapIcon().minimapPos)
    end)

    it("is hidden through the same table the button reads", function()
      local core = load().Core.new(newDeps())
      core:setMinimapShown(false)
      assert.is_true(core:minimapIcon().hide)
    end)
  end)

  describe("Pause sharing", function()
    it("fires changed when it changes, so every view can redraw", function()
      local deps = newDeps()
      local core = load().Core.new(deps)
      core:setPaused(true)
      core:setPaused(true)
      core:setPaused(false)
      assert.equal(2, countEvents(deps, "changed"))
    end)
  end)
end)
