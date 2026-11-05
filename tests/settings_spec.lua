local load = require("tests.load")

-- A character table for FakeNet, at the given level.
local function playing(name, level)
  return {
    guid = "Player-0-" .. name, name = name, classFilename = "WARRIOR",
    level = level or 10, xp = 0, maxXp = 1000, zone = "Elwynn Forest", deaths = 0,
  }
end

-- A net with the given clients logged in and in one Crew, settled.
local function crew(names)
  local ns = load()
  local net = ns.FakeNet.new()
  local clients = {}
  for i, name in ipairs(names) do
    clients[i] = net:add(name, { character = playing(name) }):login()
  end
  local code = clients[1]:join()
  for i = 2, #clients do clients[i]:join(code) end
  net:run(40)
  return net, clients
end

describe("Settings", function()
  it("spreads a new display name to other Members, and redraws your own views", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]

    local before = a:count("changed")
    assert.is_true(a.core:setDisplayName("Annie"))
    assert.equal(before + 1, a:count("changed"))
    assert.equal("Annie", a.core:rows()[1].displayName)

    net:run(5)
    assert.equal("Annie", b:rowFor(a).displayName)
  end)

  it("fires nothing when the display name stays the same", function()
    local _, clients = crew({ "Ann" })
    local a = clients[1]
    local before = a:count("changed")
    assert.is_true(a.core:setDisplayName("  " .. a.core:displayName() .. " "))
    assert.equal(before, a:count("changed"))
  end)

  it("counts what's new in the Feed, for the minimap tooltip when the popup is off", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    b.core:setChatLines(false)
    b.core:setToasts(false)
    b.core:setAwayPopup(false)
    assert.equal(0, b.core:unseen())

    a:play({ level = 11 })
    net:run(3)
    a:play({ level = 12 })
    net:run(3)
    assert.equal(2, b.core:unseen())

    b.core:openFeed()
    assert.equal(0, b.core:unseen())
  end)
end)

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

local function fired(deps, name)
  local found = {}
  for _, event in ipairs(deps.events) do
    if event[1] == name then found[#found + 1] = event end
  end
  return found
end

-- Every setting in Core's list: its default and another value to set.
local SETTINGS = {
  { key = "chatLines", default = true, other = false },
  { key = "awayPopup", default = true, other = false },
  { key = "toasts", default = true, other = false },
  { key = "minimap", default = true, other = false },
  { key = "camp", default = true, other = false },
  { key = "toastSound", default = "UI_BNET_TOAST", other = "none" },
  { key = "toastPosition", default = nil, other = { x = 400, y = 600 } },
  { key = "panelPlace", default = nil, other = { width = 600, height = 500, left = 100, top = 900 } },
  { key = "paused", default = false, other = true },
  { key = "togetherOffline", default = true, other = false },
  { key = "togetherAlts", default = false, other = true },
  { key = "togetherNear", default = false, other = true },
  { key = "togetherAttunements", default = true, other = false },
  { key = "togetherRaids", default = false, other = true },
}

describe("Settings list", function()
  it("covers exactly the settings in the list, in order", function()
    local core = newCore()
    local keys = {}
    for _, section in ipairs(core:settings()) do
      for _, setting in ipairs(section.settings) do keys[#keys + 1] = setting.key end
    end
    assert.same({ "paused", "chatLines", "awayPopup", "minimap", "camp", "panelPlace", "toasts", "toastSound",
      "toastPosition" }, keys)
  end)

  it("gives the Settings page sections with finished labels and current values", function()
    local core = newCore()
    core:setSetting("chatLines", false)
    local sections = core:settings()
    assert.same({ "Sharing", "Notifications and display", "Toasts" },
      { sections[1].title, sections[2].title, sections[3].title })
    local chat = sections[2].settings[1]
    assert.same({ key = "chatLines", kind = "toggle", label = "Chat message for live events", value = false }, chat)
    assert.equal("Appear offline: send nothing, so your Crew sees you as offline", sections[1].settings[1].label)
    assert.equal("sound", sections[3].settings[2].kind)
    assert.equal("position", sections[3].settings[3].kind)
  end)

  it("refuses a key that isn't in the list", function()
    local core = newCore()
    assert.has_error(function() core:setting("nope") end)
    assert.has_error(function() core:setSetting("nope", true) end)
  end)

  for _, case in ipairs(SETTINGS) do
    describe(case.key, function()
      it("starts at its default", function()
        assert.same(case.default, (newCore():setting(case.key)))
      end)

      it("keeps a set value across a new Core over the same db", function()
        local core, deps = newCore()
        core:setSetting(case.key, case.other)
        assert.same(case.other, core:setting(case.key))
        assert.same(case.other, (newCore(deps.db):setting(case.key)))
      end)

      it("fires settingChanged once on a real change, nothing on a no-op, and never changed", function()
        local core, deps = newCore()
        core:setSetting(case.key, case.default)
        assert.same({}, deps.events)
        core:setSetting(case.key, case.other)
        core:setSetting(case.key, case.other)
        local events = fired(deps, "settingChanged")
        assert.equal(1, #events)
        assert.equal(case.key, events[1][2])
        assert.same(case.other, events[1][3])
        core:setSetting(case.key, case.default)
        assert.equal(2, #fired(deps, "settingChanged"))
        assert.equal(0, #fired(deps, "changed"))
      end)
    end)
  end

  it("loads a db saved before the list with every value unchanged", function()
    local db = {
      chatLinesOff = true,
      awayPopupOff = true,
      toastsOff = true,
      toastSound = "READY_CHECK",
      toastPosition = { x = 12, y = 34 },
      paused = true,
      minimap = { hide = true, minimapPos = 200 },
    }
    local core = newCore(db)
    assert.is_false(core:setting("chatLines"))
    assert.is_false(core:setting("awayPopup"))
    assert.is_false(core:setting("toasts"))
    assert.is_false(core:setting("minimap"))
    assert.equal("READY_CHECK", core:setting("toastSound"))
    assert.same({ x = 12, y = 34 }, core:setting("toastPosition"))
    assert.is_true(core:setting("paused"))
    assert.equal(200, core:minimapIcon().minimapPos)
  end)

  it("has named methods that agree with the generic ones", function()
    local core = newCore()
    local function agree()
      assert.equal(core:setting("chatLines"), core:isChatLinesOn())
      assert.equal(core:setting("awayPopup"), core:isAwayPopupOn())
      assert.equal(core:setting("toasts"), core:isToastsOn())
      assert.equal(core:setting("minimap"), core:isMinimapShown())
      assert.equal(core:setting("toastSound"), core:toastSound())
      assert.equal(core:setting("paused"), core:isPaused())
      local position = core:setting("toastPosition")
      local x, y = core:toastPosition()
      assert.equal(position and position.x, x)
      assert.equal(position and position.y, y)
    end
    agree()
    core:setChatLines(false)
    core:setAwayPopup(false)
    core:setToasts(false)
    core:setMinimapShown(false)
    core:setToastSound("none")
    core:setToastPosition(1, 2)
    core:setPaused(true)
    agree()
    for _, case in ipairs(SETTINGS) do core:setSetting(case.key, case.default) end
    agree()
    core:setToastSound(nil)
    assert.equal("UI_BNET_TOAST", core:toastSound())
  end)

  it("pauses sharing whichever interface changes Pause", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]

    a.core:setSetting("paused", true)
    a:play({ level = 11 })
    net:run(13 * 60)
    assert.equal(10, b:rowFor(a).level)
    a.core:setPaused(false)
    net:run(5)
    assert.equal(11, b:rowFor(a).level)

    a.core:setPaused(true)
    a:play({ level = 12 })
    net:run(13 * 60)
    assert.equal(11, b:rowFor(a).level)
    a.core:setSetting("paused", false)
    net:run(5)
    assert.equal(12, b:rowFor(a).level)
  end)

  -- Bob's events of this kind since mark, as { text, outlets }.
  local function liveEvents(client, name, mark)
    local found = {}
    for i = mark + 1, #client.events do
      local event = client.events[i]
      if event[1] == name then found[#found + 1] = { text = event[2].text, outlets = event[3] } end
    end
    return found
  end

  for _, chat in ipairs({ true, false }) do
    for _, toast in ipairs({ true, false }) do
      local announced = chat or toast
      it(("sends Live events to chat %s and toast %s, %s"):format(tostring(chat), tostring(toast),
        announced and "marking them seen" or "leaving them unseen"), function()
        local net, clients = crew({ "Ann", "Bob" })
        local a, b = clients[1], clients[2]
        b.core:setSetting("chatLines", chat)
        b.core:setSetting("toasts", toast)

        local mark = #b.events
        a:play({ level = 11 })
        net:run(3)
        local outlets = { chat = chat, toast = toast }
        if announced then
          assert.same({ { text = "Ann dinged 11", outlets = outlets } }, liveEvents(b, "feedEntry", mark))
          assert.equal(0, b.core:unseen())
        else
          assert.same({}, liveEvents(b, "feedEntry", mark))
          assert.equal(1, b.core:unseen())
        end

        -- A Reaction to Bob's own entry.
        b:play({ level = 11 })
        net:run(3)
        b.core:openFeed()
        mark = #b.events
        local key
        for _, day in ipairs(a.core:feed().days) do
          for _, entry in ipairs(day.entries) do
            if entry.text == "Bob dinged 11" then key = entry.key end
          end
        end
        assert.is_true(a.core:react(key))
        net:run(5)
        if announced then
          assert.same({ { text = "Ann cheered your ding to 11", outlets = outlets } },
            liveEvents(b, "reaction", mark))
          assert.equal(0, b.core:unseen())
        else
          assert.same({}, liveEvents(b, "reaction", mark))
          assert.equal(1, b.core:unseen())
        end
      end)
    end
  end
end)
