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

local function feedEntries(client)
  local texts = {}
  for _, event in ipairs(client.events) do
    if event[1] == "feedEntry" then texts[#texts + 1] = event[2].text end
  end
  return texts
end

describe("Toast settings", function()
  it("are on, with the default sound and position, until changed, and survive a reload", function()
    local _, clients = crew({ "Ann" })
    local a = clients[1]
    assert.is_true(a.core:isToastsOn())
    assert.equal("UI_BNET_TOAST", a.core:toastSound())
    assert.is_nil(a.core:toastPosition())

    a.core:setToasts(false)
    a.core:setToastSound("none")
    a.core:setToastPosition(400, 600)
    a:reload()
    assert.is_false(a.core:isToastsOn())
    assert.equal("none", a.core:toastSound())
    local x, y = a.core:toastPosition()
    assert.equal(400, x)
    assert.equal(600, y)

    a.core:setToastSound(nil)
    a.core:setToastPosition(nil)
    assert.equal("UI_BNET_TOAST", a.core:toastSound())
    assert.is_nil(a.core:toastPosition())
  end)

  it("fire changed only when toasts, the sound or the position actually change", function()
    local _, clients = crew({ "Ann" })
    local a = clients[1]
    local before = a:count("changed")
    a.core:setToasts(true)
    a.core:setToastSound("UI_BNET_TOAST")
    a.core:setToastPosition(nil)
    assert.equal(before, a:count("changed"))
    a.core:setToasts(false)
    a.core:setToastSound("READY_CHECK")
    a.core:setToastPosition(400, 600)
    a.core:setToastPosition(400, 600)
    assert.equal(before + 3, a:count("changed"))
  end)
end)

describe("Live events with toasts", function()
  it("still fire, and are seen, with chat lines off and toasts on", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    b.core:setChatLines(false)
    a:play({ level = 11 })
    net:run(3)
    assert.same({ "Ann dinged 11" }, feedEntries(b))
    assert.equal(0, b.core:unseen())
  end)
end)

describe("ToastQueue", function()
  local ToastQueue, reactionText

  before_each(function()
    local ns = {}
    assert(loadfile("UI/ToastQueue.lua"))("BFF", ns)
    ToastQueue = ns.ToastQueue
    reactionText = load().Core.reactionText
  end)

  local function texts(queue)
    local list = {}
    for _, toast in ipairs(queue:visible()) do
      list[#list + 1] = toast.entry and toast.entry.text or ("+" .. toast.more)
    end
    return list
  end

  local function entry(text)
    return { kind = "ding", text = text }
  end

  it("shows an entry with the sound, then lets it go after its time", function()
    local queue = ToastQueue.new()
    queue:push(entry("Ann dinged 11"))
    local changed, sound = queue:update(100, false)
    assert.is_true(changed)
    assert.is_true(sound)
    assert.same({ "Ann dinged 11" }, texts(queue))

    local duration = ToastQueue.DURATION
    assert.is_false((queue:update(100 + duration - 1, false)))
    assert.is_true((queue:update(100 + duration, false)))
    assert.same({}, texts(queue))
    assert.is_true(queue:isIdle())
  end)

  it("ends a burst that doesn't fit in one overflow toast", function()
    local queue = ToastQueue.new()
    for i = 1, 5 do queue:push(entry("e" .. i)) end
    queue:update(100, false)
    assert.same({ "e1", "e2", "+3" }, texts(queue))
  end)

  it("adds to the overflow toast showing, and gives it its time again", function()
    local queue = ToastQueue.new()
    for i = 1, 4 do queue:push(entry("e" .. i)) end
    queue:update(100, false)
    assert.same({ "e1", "e2", "+2" }, texts(queue))

    queue:push(entry("e5"))
    queue:update(104, false)
    assert.same({ "e1", "e2", "+3" }, texts(queue))
    queue:update(100 + ToastQueue.DURATION, false)
    assert.same({ "+3" }, texts(queue))
  end)

  it("holds new entries while the screen is full, until a slot frees", function()
    local queue = ToastQueue.new()
    for i = 1, 3 do queue:push(entry("e" .. i)) end
    queue:update(100, false)
    queue:push(entry("e4"))
    queue:update(101, false)
    assert.same({ "e1", "e2", "e3" }, texts(queue))

    queue:dismiss(queue:visible()[1])
    queue:update(102, false)
    assert.same({ "e2", "e3", "e4" }, texts(queue))
  end)

  it("shows nothing new in combat, and everything held once it ends", function()
    local queue = ToastQueue.new()
    queue:push(entry("e1"))
    local changed, sound = queue:update(100, true)
    assert.is_false(changed)
    assert.is_false(sound)
    assert.same({}, texts(queue))
    assert.is_false(queue:isIdle())

    changed, sound = queue:update(130, false)
    assert.is_true(changed)
    assert.is_true(sound)
    assert.same({ "e1" }, texts(queue))
  end)

  it("plays the sound at most once every two seconds", function()
    local queue = ToastQueue.new()
    queue:push(entry("e1"))
    assert.is_true(select(2, queue:update(100, false)))
    queue:push(entry("e2"))
    assert.is_false(select(2, queue:update(101, false)))
    queue:push(entry("e3"))
    assert.is_true(select(2, queue:update(102, false)))
  end)

  it("stops a toast's clock while hovered, and starts it again where it stopped", function()
    local queue = ToastQueue.new()
    queue:push(entry("e1"))
    queue:update(100, false)
    local toast = queue:visible()[1]
    queue:hover(toast, false, 100)
    queue:hover(toast, true, 102)
    queue:hover(toast, true, 110)
    queue:update(120, false)
    assert.same({ "e1" }, texts(queue))
    local left = ToastQueue.DURATION - 2
    assert.equal(left, queue:remaining(toast, 120))

    queue:hover(toast, false, 120)
    queue:update(120 + left - 1, false)
    assert.same({ "e1" }, texts(queue))
    queue:update(120 + left, false)
    assert.same({}, texts(queue))
  end)

  it("drops everything shown and waiting when cleared", function()
    local queue = ToastQueue.new()
    for i = 1, 3 do queue:push(entry("e" .. i)) end
    queue:update(100, true)
    queue:clear()
    queue:update(101, false)
    assert.same({}, texts(queue))
    assert.is_true(queue:isIdle())
  end)

  local function reaction(name, key)
    local phrase = "cheered your ding to " .. key
    return { reaction = "cheer", name = name, phrase = phrase, entryKey = key, text = name .. " " .. phrase }
  end

  it("merges a Reaction for the same entry into its toast, and gives it its full time again", function()
    local queue = ToastQueue.new(reactionText)
    queue:push(reaction("Bob", "30"))
    queue:update(100, false)
    queue:push(reaction("Cid", "30"))
    queue:push(entry("Ann dinged 12"))
    local changed = queue:update(104, false)
    assert.is_true(changed)
    assert.same({ "Bob and Cid cheered your ding to 30", "Ann dinged 12" }, texts(queue))
    queue:update(104 + ToastQueue.DURATION - 1, false)
    assert.same({ "Bob and Cid cheered your ding to 30", "Ann dinged 12" }, texts(queue))
    queue:update(104 + ToastQueue.DURATION, false)
    assert.same({}, texts(queue))
  end)

  it("merges Reactions waiting to show, and keeps other entries' apart", function()
    local queue = ToastQueue.new(reactionText)
    queue:push(reaction("Bob", "30"))
    queue:push(reaction("Bob", "31"))
    queue:push(reaction("Cid", "30"))
    queue:push(reaction("Cid", "30"))
    queue:update(100, false)
    assert.same({ "Bob and Cid cheered your ding to 30", "Bob cheered your ding to 31" }, texts(queue))
  end)
end)
