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
end)
