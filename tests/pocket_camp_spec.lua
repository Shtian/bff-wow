local load = require("tests.load")

local AHI = 16967
local SMALLFISH = 6291

local function character(name, extra)
  local c = {
    guid = "Player-0-" .. name, name = name, classFilename = "WARRIOR",
    level = 10, xp = 0, maxXp = 1000, zone = "Elwynn Forest", deaths = 0,
  }
  for k, v in pairs(extra or {}) do c[k] = v end
  return c
end

-- A net with the given clients logged in and in one Crew, settled, the
-- first with the Pocket Camp on.
local function crew(names)
  local ns = load()
  local net = ns.FakeNet.new()
  local clients = {}
  for i, name in ipairs(names) do
    clients[i] = net:add(name, { character = character(name) }):login()
  end
  local code = clients[1]:join()
  for i = 2, #clients do clients[i]:join(code) end
  net:run(40)
  clients[1].core:setSetting("pocketCamp", true)
  return net, clients, ns
end

local function skip(net, seconds)
  net:step(net:now() + seconds)
  net:run(5)
end

local function actorFor(view, client)
  for _, actor in ipairs(view.actors) do
    if actor.memberId == client.memberId then return actor end
  end
  return nil
end

local function poseOf(viewer, client)
  local actor = actorFor(viewer.core:pocketCamp(), client)
  return actor and actor.pose
end

local function catch(itemId)
  return { items = { { itemId = itemId, quantity = 1 } }, zone = "Westfall", mapId = 1436 }
end

-- The animations the client's Core fired, as "kind" or "kind:Name".
local function animations(client, clients)
  local names = {}
  for _, other in ipairs(clients) do names[other.memberId] = other.name end
  local list = {}
  for _, event in ipairs(client.events) do
    if event[1] == "pocketCampAnimation" then
      local animation = event[2]
      list[#list + 1] = animation.memberId and (animation.kind .. ":" .. names[animation.memberId]) or animation.kind
    end
  end
  return list
end

-- Steps until the viewer shows the client fishing; fails after `within` s.
local function untilFishing(net, viewer, client, within)
  for _ = 1, within do
    if poseOf(viewer, client) == "fishing" then return end
    net:step()
  end
  error(client.name .. " never fished")
end

describe("The Pocket Camp", function()
  it("is off by default, and nil while it or the Camp is off, or outside a Crew", function()
    local ns = load()
    local net = ns.FakeNet.new()
    local a = net:add("Ann"):login()
    a.core:setSetting("pocketCamp", true)
    assert.is_nil(a.core:pocketCamp())
    a.core:setSetting("pocketCamp", false)
    a:join()
    net:run(5)
    assert.is_false(a.core:setting("pocketCamp"))
    assert.is_nil(a.core:pocketCamp())
    a.core:setSetting("pocketCamp", true)
    assert.is_table(a.core:pocketCamp())
    a.core:setSetting("camp", false)
    assert.is_nil(a.core:pocketCamp())
  end)

  it("shows the fire and exactly the online Members, you first: no sleepers, graves or tent", function()
    local net, clients, ns = crew({ "Ann", "Bob", "Cid" })
    local a, b, c = clients[1], clients[2], clients[3]
    b:play({ deaths = 1 })
    net:run(15)
    c:logout()
    net:run(2)
    local view = a.core:pocketCamp()
    assert.equal(ns.Core.CAMP_LAYOUT.pocketColumns, view.columns)
    assert.equal(ns.Core.CAMP_LAYOUT.pocketRows, view.rows)
    assert.equal(2, #view.actors)
    assert.same({ "You", true, "seated" }, { view.actors[1].label, view.actors[1].you, view.actors[1].pose })
    assert.same({ "Bob", "seated", "WARRIOR" },
      { actorFor(view, b).label, actorFor(view, b).pose, actorFor(view, b).classFilename })
    assert.is_nil(actorFor(view, c))
    assert.is_nil(view.graves)
    assert.is_nil(view.tent)
    assert.is_nil(view.more)
    -- The Camp itself is unchanged.
    assert.equal("asleep", actorFor(a.core:camp(300), c).pose)
  end)

  it("counts the online Members that don't fit as +N, and keeps everyone inside it and off the fire", function()
    local names = { "Ann", "Bob", "Cid", "Dee", "Eve", "Fay", "Gus", "Hal", "Ivy" }
    local _, clients, ns = crew(names)
    local layout = ns.Core.CAMP_LAYOUT
    local view = clients[1].core:pocketCamp()
    local shown = #view.actors
    assert.is_true(shown < #names)
    assert.equal(#names - shown, view.more)
    assert.equal(("+%d"):format(#names - shown), view.moreText)
    local half = layout.pocketColumns / 2
    for i, actor in ipairs(view.actors) do
      assert.is_true(actor.x >= -half and actor.x + actor.width <= half)
      assert.is_true(actor.x + actor.width <= -layout.fire or actor.x >= layout.fire)
      for j = i + 1, #view.actors do
        local other = view.actors[j]
        assert.is_true(actor.x + actor.width <= other.x or other.x + other.width <= actor.x)
      end
    end
  end)

  it("shows a Member whose Character is in an instance adventuring, and names the instance", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    assert.same({ "seated", "by the fire" }, { poseOf(a, b), actorFor(a.core:pocketCamp(), b).status })
    b:move({ instance = "The Deadmines" })
    b:play({ zone = "The Deadmines" })
    net:run(15)
    local bob = actorFor(a.core:pocketCamp(), b)
    assert.same({ "adventuring", "The Deadmines", "in The Deadmines" }, { bob.pose, bob.instance, bob.status })

    b:move({ mapId = 1436, x = 0.5, y = 0.5 })
    b:play({ zone = "Westfall" })
    net:run(15)
    bob = actorFor(a.core:pocketCamp(), b)
    assert.same({ "seated", nil }, { bob.pose, bob.instance })
  end)

  it("marks a max level of the last day with a spark", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    b:play({ level = 60 })
    net:run(15)
    assert.is_true(actorFor(a.core:pocketCamp(), b).spark)
    skip(net, 24 * 60 * 60)
    b:play({ xp = 5 })
    net:run(70)
    assert.is_nil(actorFor(a.core:pocketCamp(), b).spark)
  end)

  it("comes with how it's shown: opacity, lock, hiding in combat, position, scale and a worded tooltip", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    local view = a.core:pocketCamp()
    assert.same({ 0.6, false, false, nil, 1 },
      { view.opacity, view.locked, view.hideInCombat, view.position, view.scale })
    assert.same({ title = "Pocket Camp", lines = { "You: by the fire", "Bob: by the fire" },
      hint = "Click to open BFF. Drag to move." }, view.tooltip)

    a.core:setSetting("pocketCampOpacity", 0)
    a.core:setSetting("pocketCampLocked", true)
    a.core:setSetting("pocketCampCombat", true)
    a.core:setPocketCampPosition(120.4, 300)
    a.core:setPocketCampScale(1.5)
    b:move({ instance = "The Deadmines" })
    b:play({ zone = "The Deadmines" })
    net:run(15)
    view = a.core:pocketCamp()
    assert.same({ 0, true, true }, { view.opacity, view.locked, view.hideInCombat })
    assert.same({ x = 120.4, y = 300 }, view.position)
    assert.equal(1.5, view.scale)
    assert.same({ "You: by the fire", "Bob: in The Deadmines" }, view.tooltip.lines)
    assert.equal("Click to open BFF.", view.tooltip.hint)
  end)

  it("keeps its scale within its limits, in whole percents, and goes back to 1 on nil", function()
    local _, clients = crew({ "Ann", "Bob" })
    local core = clients[1].core
    core:setPocketCampScale(1.234)
    assert.equal(1.23, core:pocketCamp().scale)
    core:setPocketCampScale(9)
    assert.equal(3, core:pocketCamp().scale)
    core:setPocketCampScale(0.1)
    assert.equal(0.5, core:pocketCamp().scale)
    core:setPocketCampScale(nil)
    assert.equal(1, core:pocketCamp().scale)
  end)

  it("gives each actor its Roster row, for the tooltip over its figure", function()
    local _, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    local view = a.core:pocketCamp()
    local row = actorFor(view, b).row
    assert.same({ b.memberId, "Bob", "Bob", 10, "Elwynn Forest", true },
      { row.memberId, row.displayName, row.fullName, row.level, row.zone, row.playing })
    assert.is_true(actorFor(view, a).row.own)
  end)

  it("changes no record and sends nothing when read", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a = clients[1]
    a.events = {}
    local mark = #net.wire
    a.core:pocketCamp()
    net:step()
    assert.equal(mark, #net.wire)
    assert.same({}, a.events)
  end)

  describe("fishing", function()
    it("lasts 60 s from when a Member's catch count is seen to grow, then goes back", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      b.core:caught(catch(SMALLFISH))
      untilFishing(net, a, b, 70)
      assert.equal("fishing", actorFor(a.core:pocketCamp(), b).status)
      assert.same({ "You: by the fire", "Bob: fishing" }, a.core:pocketCamp().tooltip.lines)
      net:run(59)
      assert.equal("fishing", poseOf(a, b))
      local before = a:count("changed")
      net:run(1)
      assert.equal("seated", poseOf(a, b))
      -- The Pocket Camp is told to redraw when the spell ends.
      assert.equal(before + 1, a:count("changed"))
    end)

    it("starts over on another increase, and replaces adventuring while it lasts", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      b:move({ instance = "The Deadmines" })
      b:play({ zone = "The Deadmines" })
      net:run(15)
      b.core:caught(catch(SMALLFISH))
      untilFishing(net, a, b, 70)
      net:run(30)
      -- Two catches in one update: one spell, restarted.
      b.core:caught(catch(SMALLFISH))
      b.core:caught(catch(SMALLFISH))
      b:play({ level = 11 })
      net:run(3)
      net:run(55)
      assert.equal("fishing", poseOf(a, b))
      net:run(10)
      assert.equal("adventuring", poseOf(a, b))
    end)

    it("shows you fishing for 60 s after your own catch", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a = clients[1]
      a.core:caught(catch(SMALLFISH))
      assert.equal("fishing", poseOf(a, a))
      net:run(59)
      assert.equal("fishing", poseOf(a, a))
      net:run(1)
      assert.equal("seated", poseOf(a, a))
    end)

    it("is silent on the first sight of a Member, at login and after a reload", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      -- First sight: Cid joins already holding catches.
      local c = net:add("Cid", { character = character("Cid") }):login()
      c.core:caught(catch(SMALLFISH))
      c:join(a.core:crew().code)
      net:run(40)
      assert.equal("seated", poseOf(a, c))

      -- Login: Bob fished while Ann was away.
      a:logout()
      net:run(5)
      b.core:caught(catch(SMALLFISH))
      net:run(70)
      a:login()
      net:run(40)
      assert.equal("seated", poseOf(a, b))

      -- Reload: a spell under way isn't kept.
      b.core:caught(catch(SMALLFISH))
      untilFishing(net, a, b, 70)
      a:reload()
      net:run(5)
      assert.equal("seated", poseOf(a, b))
    end)

    it("never shows an offline Member, and makes nothing of other record changes", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      b:play({ level = 11 })
      net:run(15)
      assert.equal("seated", poseOf(a, b))
      b.core:caught(catch(SMALLFISH))
      untilFishing(net, a, b, 70)
      b:logout()
      net:run(2)
      assert.is_nil(actorFor(a.core:pocketCamp(), b))
    end)
  end)

  describe("animations", function()
    it("play once for a ding, max level, death and rare find, whatever the chat and toast settings", function()
      local net, clients = crew({ "Ann", "Bob", "Cid" })
      local a, b, c = clients[1], clients[2], clients[3]
      a.core:setChatLines(false)
      a.core:setToasts(false)
      a.events = {}
      b:play({ level = 11 })
      net:run(5)
      c:play({ deaths = 2 })
      net:run(5)
      b.core:caught(catch(AHI))
      net:run(5)
      c:play({ level = 60 })
      net:run(5)
      -- Cid's max level also takes the Crew to 50 Crew levels.
      assert.same({ "ding:Bob", "death:Cid", "rareFind:Bob", "maxLevel:Cid", "goal" }, animations(a, clients))
      assert.equal(0, a:count("feedEntry"))
      -- The entries stay unseen, for While you were away.
      assert.equal(5, a.core:unseen())
    end)

    it("flare the fire for a Crew goal, and animate your own news", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a = clients[1]
      a.events = {}
      a:play({ level = 40 })
      net:run(5)
      assert.same({ "ding:Ann", "goal" }, animations(a, clients))
    end)

    it("play nothing for other kinds", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      a.events = {}
      b:play(character("Bobalt", { classFilename = "PRIEST" }))
      net:run(15)
      b.core:caught(catch(SMALLFISH))
      net:run(70)
      assert.is_true(a:count("feedEntry") > 0)
      assert.same({}, animations(a, clients))
    end)

    it("play nothing while the Pocket Camp is off", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      a.core:setSetting("pocketCamp", false)
      a.events = {}
      b:play({ level = 11 })
      net:run(5)
      assert.equal(1, a:count("feedEntry"))
      assert.same({}, animations(a, clients))
    end)

    it("play nothing for a sleeper's news or a Member counted in +N", function()
      local names = { "Ann", "Bob", "Cid", "Dee", "Eve", "Fay", "Gus", "Hal", "Ivy" }
      local net, clients = crew(names)
      local a = clients[1]
      -- Ivy can't play with Ann, so the Roster lists her last: she's in +N.
      local hidden = clients[9]
      hidden:play({ level = 30 })
      net:run(5)
      assert.is_nil(actorFor(a.core:pocketCamp(), hidden))
      a.events = {}
      hidden:play({ level = 31 })
      net:run(5)
      assert.equal(1, a:count("feedEntry"))
      assert.same({}, animations(a, clients))

      -- Bob dings and logs out while Ann can't hear; the news comes later.
      local b = clients[2]
      a:lockdown(true)
      b:play({ level = 11 })
      net:run(5)
      b:logout()
      skip(net, 13 * 60)
      a:lockdown(false)
      net:run(15)
      assert.equal(2, a:count("feedEntry"))
      assert.same({}, animations(a, clients))
    end)

    it("play nothing for what's caught up at login", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      a:logout()
      net:run(5)
      b:play({ level = 11 })
      net:run(15)
      a.events = {}
      a:login()
      net:run(40)
      assert.equal(1, a:count("awaySummary"))
      assert.same({}, animations(a, clients))
    end)
  end)
end)

describe("Tips", function()
  local TEXT = "Keep your Crew on screen. The Pocket Camp shows the fire and who's by it while you play. "
    .. "You can turn it on or off any time in Settings."

  local function inCrew()
    local ns = load()
    local net = ns.FakeNet.new()
    local a = net:add("Ann"):login()
    a:join()
    net:run(5)
    return a, net
  end

  it("offers the Pocket Camp once, worded, with its two buttons", function()
    local a = inCrew()
    assert.same({ key = "pocketCamp", title = "New: the Pocket Camp", text = TEXT, accept = "Turn on",
      dismiss = "No thanks" }, a.core:tip())
  end)

  it("offers it in a window once on the account, the first time there is one", function()
    local net = load().FakeNet.new()
    local a = net:add("Ann"):login()
    net:run(5)
    -- Outside a Crew there's no Tip to offer yet.
    assert.equal(0, a:count("tip"))
    a:join()
    net:run(5)
    assert.equal(1, a:count("tip"))
    local offered
    for _, event in ipairs(a.events) do
      if event[1] == "tip" then offered = event[2] end
    end
    assert.same(a.core:tip(), offered)
    -- Left unanswered, it stays in the panel but isn't offered again.
    a:reload()
    net:run(5)
    a:logout()
    a:login()
    net:run(5)
    assert.equal(1, a:count("tip"))
    assert.equal("pocketCamp", a.core:tip().key)
  end)

  it("offers nothing once the Pocket Camp is already on", function()
    local net = load().FakeNet.new()
    local a = net:add("Ann"):login()
    a.core:setSetting("pocketCamp", true)
    a:join()
    net:run(5)
    assert.equal(0, a:count("tip"))
  end)

  it("shows no Tip outside a Crew", function()
    local a = load().FakeNet.new():add("Ann"):login()
    assert.is_nil(a.core:tip())
  end)

  it("Turn on enables the Pocket Camp, and the Tip never shows again on the account", function()
    local a = inCrew()
    a.events = {}
    assert.is_true(a.core:acceptTip("pocketCamp"))
    assert.is_true(a.core:setting("pocketCamp"))
    assert.is_table(a.core:pocketCamp())
    assert.same({ "settingChanged", "pocketCamp", true }, a.events[1])
    assert.equal(1, a:count("changed"))
    assert.is_nil(a.core:tip())
    -- Off again later, on another Character, after a reload: still answered.
    a.core:setSetting("pocketCamp", false)
    a:reload()
    assert.is_nil(a.core:tip())
    a:logout()
    a.character = { guid = "Player-0-Annalt", name = "Annalt", classFilename = "MAGE",
      level = 3, xp = 0, maxXp = 1000, zone = "Elwynn Forest", deaths = 0 }
    a:login()
    assert.is_nil(a.core:tip())
  end)

  it("No thanks only answers it", function()
    local a = inCrew()
    a.events = {}
    assert.is_true(a.core:dismissTip("pocketCamp"))
    assert.is_false(a.core:setting("pocketCamp"))
    assert.is_nil(a.core:pocketCamp())
    assert.equal(1, a:count("changed"))
    assert.equal(0, a:count("settingChanged"))
    assert.is_nil(a.core:tip())
    a:reload()
    assert.is_nil(a.core:tip())
  end)

  it("never shows once the Pocket Camp was turned on in Settings", function()
    local a = inCrew()
    a.core:setSetting("pocketCamp", true)
    assert.is_nil(a.core:tip())
    a.core:setSetting("pocketCamp", false)
    assert.is_nil(a.core:tip())
  end)

  it("waits while the Camp is off, since the Pocket Camp can't show then", function()
    local a = inCrew()
    a.core:setSetting("camp", false)
    assert.is_nil(a.core:tip())
    a.core:setSetting("camp", true)
    assert.equal("pocketCamp", a.core:tip().key)
  end)

  it("refuses a Tip it doesn't have", function()
    local a = inCrew()
    assert.is_false(a.core:acceptTip("nope"))
    assert.is_false(a.core:dismissTip("nope"))
    assert.equal("pocketCamp", a.core:tip().key)
  end)
end)
