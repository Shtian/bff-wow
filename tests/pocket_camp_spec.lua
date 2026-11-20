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

local function untilFishing(net, viewer, client, within)
  for _ = 1, within do
    if poseOf(viewer, client) == "fishing" then return end
    net:step()
  end
  error(client.name .. " never fished")
end

describe("The Pocket Camp", function()
  it("is on by default, and nil while it or the Camp is off, or outside a Crew", function()
    local ns = load()
    local net = ns.FakeNet.new()
    local a = net:add("Ann"):login()
    assert.is_true(a.core:setting("pocketCamp"))
    assert.is_nil(a.core:pocketCamp())
    a:join()
    net:run(5)
    assert.is_table(a.core:pocketCamp())
    a.core:setSetting("pocketCamp", false)
    assert.is_nil(a.core:pocketCamp())
    a.core:setSetting("pocketCamp", true)
    assert.is_table(a.core:pocketCamp())
    a.core:setSetting("camp", false)
    assert.is_nil(a.core:pocketCamp())
  end)

  it("reads as on whatever an opt-in save held, Turn on or No thanks", function()
    local ns = load()
    local net = ns.FakeNet.new()
    local on = net:add("Ann", { db = { pocketCamp = true, tipsAnswered = { pocketCamp = true } } }):login()
    local declined = net:add("Bob", { db = { tipsAnswered = { pocketCamp = true }, tipsOffered = { pocketCamp = true } } }):login()
    assert.is_true(on.core:setting("pocketCamp"))
    assert.is_true(declined.core:setting("pocketCamp"))
  end)

  it("shows the fire and exactly the online Members, you first: no older sleepers, graves or tent", function()
    local net, clients, ns = crew({ "Ann", "Bob", "Cid" })
    local a, b, c = clients[1], clients[2], clients[3]
    b:play({ deaths = 1 })
    net:run(15)
    c:logout()
    net:run(2)
    skip(net, 10 * 60)
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

  it("comes with how it's shown: opacity, lock, what it does in combat, position, scale and a worded tooltip", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    local view = a.core:pocketCamp()
    assert.same({ 0.6, false, "stay", 0.25, nil, 1 },
      { view.opacity, view.locked, view.inCombat, view.combatFade, view.position, view.scale })
    assert.is_nil(view.hideInCombat)
    assert.same({ title = "Pocket Camp", lines = { "You: by the fire", "Bob: by the fire" },
      hint = "Click to open BFF. Drag to move." }, view.tooltip)

    a.core:setSetting("pocketCampOpacity", 0)
    a.core:setSetting("pocketCampLocked", true)
    a.core:setSetting("pocketCampCombat", "fade")
    a.core:setSetting("pocketCampCombatFade", 40)
    a.core:setPocketCampPosition(120.4, 300)
    a.core:setPocketCampScale(1.5)
    b:move({ instance = "The Deadmines" })
    b:play({ zone = "The Deadmines" })
    net:run(15)
    view = a.core:pocketCamp()
    assert.same({ 0, true, "fade", 0.4 }, { view.opacity, view.locked, view.inCombat, view.combatFade })
    assert.same({ x = 120.4, y = 300 }, view.position)
    assert.equal(1.5, view.scale)
    assert.same({ "You: by the fire", "Bob: in The Deadmines" }, view.tooltip.lines)
    assert.equal("Click to open BFF.", view.tooltip.hint)
  end)

  it("reads an old saved Hide in combat as Hide, and nothing saved as Stay", function()
    local function inCombat(saved)
      local ns = load()
      local net = ns.FakeNet.new()
      local a = net:add("Ann", { db = saved }):login()
      a:join()
      net:run(5)
      return a.core:pocketCamp().inCombat
    end
    assert.equal("stay", inCombat({}))
    assert.equal("hide", inCombat({ pocketCampCombatHide = true }))
    assert.equal("stay", inCombat({ pocketCampCombatHide = false }))
  end)

  it("sends nothing more for what it does in combat", function()
    local function sentBy(choice)
      local net, clients = crew({ "Ann", "Bob" })
      local a = clients[1]
      local mark = #net.wire
      a.core:setSetting("pocketCampCombat", choice)
      a.core:setSetting("pocketCampCombatFade", 40)
      a.core:pocketCamp()
      net:run(6 * 60)
      local types = {}
      for _, message in ipairs(net:sent(mark, "Ann")) do types[#types + 1] = message.type end
      return types
    end
    assert.same(sentBy("stay"), sentBy("fade"))
    assert.same(sentBy("stay"), sentBy("hide"))
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

  it("grows a step at a time to fit who's online, up to its max width, and counts the rest", function()
    local names = { "Ann", "Bob", "Cid", "Dee", "Eve", "Fay", "Gus", "Hal", "Ivy" }
    local _, clients, ns = crew(names)
    local core = clients[1].core
    local layout = ns.Core.CAMP_LAYOUT
    local view = core:pocketCamp()
    assert.same({ layout.pocketColumns, layout.pocketColumns, 6, 3 },
      { view.columns, view.maxColumns, #view.actors, view.more })
    core:setPocketCampColumns(layout.pocketMaxColumns)
    view = core:pocketCamp()
    assert.same({ layout.pocketColumns + 2 * layout.pocketStep, layout.pocketMaxColumns, 9 },
      { view.columns, view.maxColumns, #view.actors })
    assert.is_nil(view.more)
    local half = view.columns / 2
    for _, actor in ipairs(view.actors) do
      assert.is_true(actor.x >= -half and actor.x + actor.width <= half)
    end
    core:setPocketCampColumns(layout.pocketColumns + layout.pocketStep)
    view = core:pocketCamp()
    assert.same({ layout.pocketColumns + layout.pocketStep, 8, 1, "+1" },
      { view.columns, #view.actors, view.more, view.moreText })
  end)

  it("stays its usual width with few online, whatever its max", function()
    local _, clients, ns = crew({ "Ann", "Bob" })
    local core = clients[1].core
    core:setPocketCampColumns(ns.Core.CAMP_LAYOUT.pocketMaxColumns)
    assert.equal(ns.Core.CAMP_LAYOUT.pocketColumns, core:pocketCamp().columns)
  end)

  it("keeps its max width to the layout's steps and limits, and goes back to the usual on nil", function()
    local _, clients, ns = crew({ "Ann", "Bob" })
    local core = clients[1].core
    local layout = ns.Core.CAMP_LAYOUT
    core:setPocketCampColumns(layout.pocketColumns + layout.pocketStep + 3)
    assert.equal(layout.pocketColumns + layout.pocketStep, core:pocketCamp().maxColumns)
    core:setPocketCampColumns(layout.pocketColumns + layout.pocketStep * 1.6)
    assert.equal(layout.pocketColumns + 2 * layout.pocketStep, core:pocketCamp().maxColumns)
    core:setPocketCampColumns(9999)
    assert.equal(layout.pocketMaxColumns, core:pocketCamp().maxColumns)
    core:setPocketCampColumns(1)
    assert.equal(layout.pocketColumns, core:pocketCamp().maxColumns)
    core:setPocketCampColumns(layout.pocketMaxColumns)
    core:setPocketCampColumns(nil)
    assert.equal(layout.pocketColumns, core:pocketCamp().maxColumns)
  end)

  it("counts the seats at each width from the layout: three a side at the usual width, one more a side per step", function()
    local _, _, ns = crew({ "Ann" })
    local layout = ns.Core.CAMP_LAYOUT
    assert.equal(6, ns.Core.pocketCampSeats(layout.pocketColumns))
    assert.equal(8, ns.Core.pocketCampSeats(layout.pocketColumns + layout.pocketStep))
    assert.equal(18, ns.Core.pocketCampSeats(layout.pocketMaxColumns))
    assert.equal(layout.pocketColumns + layout.pocketStep, ns.Core.pocketCampWidth(layout.pocketColumns + 20))
    assert.equal(layout.pocketMaxColumns, ns.Core.pocketCampWidth(1000))
  end)

  it("marks a Member on an Alt, in the actor and the tooltip, and not one on their Main", function()
    local net, clients = crew({ "Ann", "Bob", "Cy" })
    local a, b, c = clients[1], clients[2], clients[3]
    b.character = character("Bobalt", { level = 4 })
    b:play()
    net:run(5)
    assert.is_true(b.core:setMain("Player-0-Bob"))
    net:run(15)

    local view = a.core:pocketCamp()
    assert.is_true(actorFor(view, b).onAlt)
    assert.is_nil(actorFor(view, a).onAlt)
    assert.is_nil(actorFor(view, c).onAlt)
    assert.same({ "You: by the fire", "Bob (on alt): by the fire", "Cy: by the fire" }, view.tooltip.lines)

    view = b.core:pocketCamp()
    assert.is_true(actorFor(view, b).onAlt)
    assert.equal("You (on alt): by the fire", view.tooltip.lines[1])

    b.character = character("Bob")
    b:play()
    net:run(70)
    assert.is_nil(actorFor(a.core:pocketCamp(), b).onAlt)
    assert.equal("Bob: by the fire", a.core:pocketCamp().tooltip.lines[2])
  end)

  it("shows nobody on an Alt with its setting off, and again with it on", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    b.character = character("Bobalt", { level = 4 })
    b:play()
    net:run(5)
    assert.is_true(b.core:setMain("Player-0-Bob"))
    net:run(15)

    a.core:setSetting("pocketCampAlts", false)
    local view = a.core:pocketCamp()
    assert.is_nil(actorFor(view, b).onAlt)
    assert.same({ "You: by the fire", "Bob: by the fire" }, view.tooltip.lines)
    assert.is_true(actorFor(view, b).row.onAlt)

    a.core:setSetting("pocketCampAlts", true)
    assert.is_true(actorFor(a.core:pocketCamp(), b).onAlt)
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

  describe("menu", function()
    it("comes on another Member's figure, titled and aimed at the full Character name", function()
      local ns = load()
      local net = ns.FakeNet.new()
      local a = net:add("Ann", { character = character("Ann") }):login()
      local b = net:add("Bob", { character = character("Bob", { lastName = "Stone" }) }):login()
      b:join(a:join())
      net:run(40)
      local menu = actorFor(a.core:pocketCamp(), b).menu
      assert.equal("Bob Stone", menu.fullName)
    end)

    it("is never on your own figure", function()
      local _, clients = crew({ "Ann", "Bob" })
      local a = clients[1]
      assert.is_nil(actorFor(a.core:pocketCamp(), a).menu)
    end)

    it("is never on a bedroll", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      b:logout()
      skip(net, 10)
      local actor = actorFor(a.core:pocketCamp(), b)
      assert.equal("asleep", actor.pose)
      assert.is_nil(actor.menu)
    end)

    it("has no map without a known spot", function()
      local _, clients = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      assert.is_nil(actorFor(a.core:pocketCamp(), b).menu.mapId)
    end)

    it("has the map of the Member's pin: the record's spot, then the live one", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      b:move({ mapId = 1429, x = 0.4, y = 0.6 })
      skip(net, 6 * 60)
      assert.equal(1429, actorFor(a.core:pocketCamp(), b).menu.mapId)
      b:move({ mapId = 1436, x = 0.3, y = 0.4 })
      net:run(15)
      assert.equal(1436, actorFor(a.core:pocketCamp(), b).menu.mapId)
    end)

    it("keeps the map of the last spot outside while the Member is in an instance", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      b:move({ mapId = 1436, x = 0.42, y = 0.71 })
      net:run(4)
      b:move({ instance = "The Deadmines" })
      b:play({ zone = "The Deadmines" })
      net:run(12)
      assert.equal(1436, actorFor(a.core:pocketCamp(), b).menu.mapId)
    end)

    it("has the map whatever the map pins setting", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      b:move({ mapId = 1429, x = 0.4, y = 0.6 })
      skip(net, 6 * 60)
      a.core:setSetting("mapPins", false)
      assert.equal(1429, actorFor(a.core:pocketCamp(), b).menu.mapId)
    end)
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
      local c = net:add("Cid", { character = character("Cid") }):login()
      c.core:caught(catch(SMALLFISH))
      c:join(a.core:crew().code)
      net:run(40)
      assert.equal("seated", poseOf(a, c))

      a:logout()
      net:run(5)
      b.core:caught(catch(SMALLFISH))
      net:run(70)
      a:login()
      net:run(40)
      assert.equal("seated", poseOf(a, b))

      b.core:caught(catch(SMALLFISH))
      untilFishing(net, a, b, 70)
      a:reload()
      net:run(5)
      assert.equal("seated", poseOf(a, b))
    end)

    it("never shows an offline Member fishing, and makes nothing of other record changes", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      b:play({ level = 11 })
      net:run(15)
      assert.equal("seated", poseOf(a, b))
      b.core:caught(catch(SMALLFISH))
      untilFishing(net, a, b, 70)
      b:logout()
      net:run(2)
      assert.equal("asleep", poseOf(a, b))
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
      assert.same({ "ding:Bob", "death:Cid", "rareFind:Bob", "maxLevel:Cid", "goal" }, animations(a, clients))
      assert.equal(0, a:count("feedEntry"))
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
      local hidden = clients[9]
      hidden:play({ level = 30 })
      net:run(5)
      assert.is_nil(actorFor(a.core:pocketCamp(), hidden))
      a.events = {}
      hidden:play({ level = 31 })
      net:run(5)
      assert.equal(1, a:count("feedEntry"))
      assert.same({}, animations(a, clients))

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

describe("Arrivals and bedrolls", function()
  local function arrivals(client, clients)
    local list = {}
    for _, name in ipairs(animations(client, clients)) do
      if name:find("^arrive") then list[#list + 1] = name end
    end
    return list
  end

  local function settledCrew(names)
    local net, clients, ns = crew(names)
    skip(net, 2 * 60)
    return net, clients, ns
  end

  it("walks in a Member who comes online, once", function()
    local net, clients = settledCrew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    b:logout()
    net:run(5)
    a.events = {}
    b:login()
    net:run(40)
    assert.same({ "arrive:Bob" }, arrivals(a, clients))
    assert.equal("seated", poseOf(a, b))
    assert.same({}, arrivals(b, clients))
  end)

  it("walks in nobody on first sight, at login catch-up or after a reload", function()
    local net, clients = settledCrew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    a.events = {}
    local c = net:add("Cid", { character = character("Cid") }):login()
    c:join(a.core:crew().code)
    clients[3] = c
    net:run(40)
    assert.is_table(actorFor(a.core:pocketCamp(), c))
    assert.same({}, arrivals(a, clients))

    a:logout()
    net:run(5)
    a:login()
    net:run(3 * 60)
    assert.same({}, arrivals(a, clients))

    a:reload()
    net:run(3 * 60)
    assert.same({}, arrivals(a, clients))

    b:logout()
    net:run(5)
    a:logout()
    net:run(5)
    a:login()
    b:login()
    net:run(5)
    assert.same({}, arrivals(a, clients))
  end)

  it("walks in nobody, and makes no bedroll, when it's your link that was down", function()
    local net, clients = settledCrew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    a.events = {}
    a:lockdown(true)
    net:run(13 * 60)
    assert.is_nil(actorFor(a.core:pocketCamp(), b))
    a:lockdown(false)
    net:run(3 * 60)
    assert.equal("seated", poseOf(a, b))
    assert.same({}, arrivals(a, clients))
  end)

  it("still walks in a Member who comes online right after a fight's short lockdown", function()
    local net, clients = settledCrew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    b:logout()
    net:run(5)
    a:lockdown(true)
    net:run(30)
    a:lockdown(false)
    a.events = {}
    b:login()
    net:run(40)
    assert.same({ "arrive:Bob" }, arrivals(a, clients))
  end)

  it("walks in nobody while the Pocket Camp is off", function()
    local net, clients = settledCrew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    a.core:setSetting("pocketCamp", false)
    b:logout()
    net:run(5)
    a.events = {}
    b:login()
    net:run(40)
    assert.same({}, arrivals(a, clients))
  end)

  it("keeps a Member who went offline asleep in a bedroll for 10 minutes, then lets them go", function()
    local net, clients = settledCrew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    b:logout()
    net:run(2)
    local actor = actorFor(a.core:pocketCamp(), b)
    assert.same({ "asleep", "asleep" }, { actor.pose, actor.status })
    assert.equal(b.memberId, actor.row.memberId)
    skip(net, 4 * 60)
    actor = actorFor(a.core:pocketCamp(), b)
    assert.equal("asleep · 4m", actor.status)
    assert.same({ "You: by the fire", "Bob: asleep · 4m" }, a.core:pocketCamp().tooltip.lines)
    a.events = {}
    skip(net, 6 * 60)
    assert.is_nil(actorFor(a.core:pocketCamp(), b))
    assert.is_true(a:count("changed") > 0)
  end)

  it("swaps the bedroll for the figure when the Member comes back within the 10 minutes, and walks them in", function()
    local net, clients = settledCrew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    b:logout()
    net:run(5)
    assert.equal("asleep", poseOf(a, b))
    a.events = {}
    b:login()
    net:run(40)
    assert.equal("seated", poseOf(a, b))
    assert.same({ "arrive:Bob" }, arrivals(a, clients))
    skip(net, 11 * 60)
    assert.equal("seated", poseOf(a, b))
  end)

  it("forgets bedrolls on a reload", function()
    local net, clients = settledCrew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    b:logout()
    net:run(2)
    assert.equal("asleep", poseOf(a, b))
    a:reload()
    net:run(5)
    assert.is_nil(actorFor(a.core:pocketCamp(), b))
  end)

  it("gives no bedroll to a Member who's removed or who left the Crew", function()
    local net, clients = settledCrew({ "Ann", "Bob", "Cid" })
    local a, b, c = clients[1], clients[2], clients[3]
    b:logout()
    net:run(2)
    assert.equal("asleep", poseOf(a, b))
    a.core:removeMember(b.memberId)
    assert.is_nil(actorFor(a.core:pocketCamp(), b))
    c.core:leaveCrew()
    net:run(20)
    assert.is_nil(actorFor(a.core:pocketCamp(), c))
  end)

  it("seats online Members before bedrolls, and never counts or widens for a bedroll", function()
    local names = { "Ann", "Bob", "Cid", "Dee", "Eve", "Fay", "Gus", "Hal", "Ivy" }
    local net, clients, ns = crew(names)
    local a = clients[1]
    a.core:setPocketCampColumns(ns.Core.CAMP_LAYOUT.pocketMaxColumns)
    for i = 6, #names do clients[i]:logout() end
    net:run(2)
    local view = a.core:pocketCamp()
    assert.equal(ns.Core.CAMP_LAYOUT.pocketColumns, view.columns)
    assert.is_nil(view.more)
    local online, asleep = 0, 0
    for i, actor in ipairs(view.actors) do
      if actor.pose == "asleep" then
        asleep = asleep + 1
      else
        online = online + 1
        assert.equal(i, online)
      end
    end
    assert.equal(5, online)
    assert.is_true(asleep < 4)

    a.core:setPocketCampColumns(nil)
    for i = 6, #names do clients[i]:login() end
    net:run(40)
    clients[2]:logout()
    net:run(2)
    view = a.core:pocketCamp()
    assert.equal(ns.Core.CAMP_LAYOUT.pocketColumns, view.columns)
    assert.is_nil(actorFor(view, clients[2]))
    assert.equal(8 - #view.actors, view.more)
  end)

  it("sends nothing it wouldn't send without the Pocket Camp", function()
    local function sentBy(on)
      local net, clients = settledCrew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      a.core:setSetting("pocketCamp", on)
      local mark = #net.wire
      b:logout()
      net:run(5)
      a.core:pocketCamp()
      b:login()
      net:run(40)
      skip(net, 11 * 60)
      local types = {}
      for _, message in ipairs(net:sent(mark, "Ann")) do types[#types + 1] = message.type end
      return types
    end
    assert.same(sentBy(false), sentBy(true))
  end)
end)

describe("Playing together", function()
  local function order(view)
    local labels = {}
    for i, actor in ipairs(view.actors) do labels[i] = actor.label end
    return labels
  end

  local function unit(client)
    return { guid = client.character.guid, name = client.character.name }
  end

  local function inside(net, clients, instance)
    for _, client in ipairs(clients) do
      client:move({ instance = instance })
      client:play({ zone = instance })
    end
    net:run(15)
  end

  local function under(view, doorway)
    local labels = {}
    for _, actor in ipairs(view.actors) do
      if actor.doorway == doorway then labels[#labels + 1] = actor.label end
    end
    table.sort(labels)
    return labels
  end

  it("seats your group right after you, whatever the Roster's order, and marks them", function()
    local _, clients = crew({ "Ann", "Bob", "Cid", "Dee" })
    local a, b, c, d = clients[1], clients[2], clients[3], clients[4]
    assert.same({ "You", "Bob", "Cid", "Dee" }, order(a.core:pocketCamp()))
    a.core:group({ unit(a), unit(d), unit(c) })
    local view = a.core:pocketCamp()
    assert.same({ "You", "Cid", "Dee", "Bob" }, order(view))
    assert.same({ true, true }, { actorFor(view, c).group, actorFor(view, d).group })
    assert.is_nil(actorFor(view, b).group)
    assert.is_nil(view.actors[1].group)
  end)

  it("matches a Character by first and last name when the GUID can't be read", function()
    local net, clients = crew({ "Ann", "Bob", "Cid" })
    local a, b, c = clients[1], clients[2], clients[3]
    c:play({ lastName = "Stormgaard" })
    b:play({ lastName = "Ashby" })
    net:run(70)
    a.core:group({ { name = "Cid", lastName = "Stormgaard" }, { name = "Bob", lastName = "Other" } })
    local view = a.core:pocketCamp()
    assert.same({ "You", "Cid", "Bob" }, order(view))
    assert.is_true(actorFor(view, c).group)
    assert.is_nil(actorFor(view, b).group)
    a.core:group({ { name = "cid", lastName = "STORMGAARD" }, { name = "Bob" } })
    view = a.core:pocketCamp()
    assert.is_true(actorFor(view, c).group)
    assert.is_nil(actorFor(view, b).group)
    a.core:group({ { name = "Ann", lastName = "Lee" } })
    assert.is_nil(actorFor(a.core:pocketCamp(), b).group)
  end)

  it("seats your group before a Member who only shares your instance", function()
    local net, clients = crew({ "Ann", "Bob", "Cid" })
    local a, b, c = clients[1], clients[2], clients[3]
    inside(net, { a, b }, "The Deadmines")
    a.core:group({ unit(a), unit(c) })
    assert.same({ "You", "Cid", "Bob" }, order(a.core:pocketCamp()))
  end)

  it("orders you, your group, each set sharing an instance, then the rest, whatever the Roster's order", function()
    local net, clients = crew({ "Ann", "Bea", "Cal", "Dot", "Eli", "Fin", "Gus", "Hal" })
    local a, cal, eli, fin, gus, hal = clients[1], clients[3], clients[5], clients[6], clients[7], clients[8]
    a.core:setSetting("pocketCampColumns", 304)
    inside(net, { a, fin, hal }, "The Deadmines")
    inside(net, { cal, eli }, "Ragefire Chasm")
    a.core:group({ unit(a), unit(gus), unit(hal) })
    assert.same({ "You", "Hal", "Gus", "Fin", "Cal", "Eli", "Bea", "Dot" }, order(a.core:pocketCamp()))
  end)

  it("puts Members in the same instance in one shared doorway, and others in one each", function()
    local net, clients, ns = crew({ "Ann", "Bob", "Cid", "Dee", "Eve" })
    local a, b, c, d, e = clients[1], clients[2], clients[3], clients[4], clients[5]
    inside(net, { b, e }, "The Deadmines")
    inside(net, { d }, "Ragefire Chasm")
    local view = a.core:pocketCamp()
    local labels = order(view)
    local at = {}
    for i, label in ipairs(labels) do at[label] = i end
    assert.equal(1, math.abs(at.Bob - at.Eve))
    assert.equal(2, #view.doorways)
    local bob, eve, dee = actorFor(view, b), actorFor(view, e), actorFor(view, d)
    assert.equal(bob.doorway, eve.doorway)
    assert.are_not.equal(bob.doorway, dee.doorway)
    assert.is_nil(actorFor(view, c).doorway)
    local layout = ns.Core.CAMP_LAYOUT
    local shared = view.doorways[bob.doorway]
    local first, last = bob, eve
    if eve.x < bob.x then first, last = eve, bob end
    assert.equal(first.x + first.width + layout.doorwayGap, last.x)
    assert.same({ first.x - layout.doorway, last.x + last.width - first.x + 2 * layout.doorway, "The Deadmines" },
      { shared.x, shared.width, shared.instance })
    local own = view.doorways[dee.doorway]
    assert.same({ dee.x - layout.doorway, dee.width + 2 * layout.doorway, "Ragefire Chasm" },
      { own.x, own.width, own.instance })
  end)

  it("takes you and your group into the doorway, and marks a raid's", function()
    local net, clients = crew({ "Ann", "Bob", "Cid" })
    local a, c = clients[1], clients[3]
    inside(net, { a, c }, "Molten Core")
    a.core:group({ unit(a), unit(c) })
    local view = a.core:pocketCamp()
    assert.same({ "You", "Cid", "Bob" }, order(view))
    assert.equal(1, #view.doorways)
    assert.same({ "Cid", "You" }, under(view, 1))
    assert.is_true(view.doorways[1].raid)
  end)

  it("keeps a Member fishing in the instance out of the doorway", function()
    local net, clients = crew({ "Ann", "Bob", "Cid" })
    local a, b, c = clients[1], clients[2], clients[3]
    inside(net, { b, c }, "The Deadmines")
    b.core:caught(catch(SMALLFISH))
    untilFishing(net, a, b, 70)
    local view = a.core:pocketCamp()
    assert.equal(1, #view.doorways)
    assert.same({ "Cid" }, under(view, 1))
    assert.is_nil(actorFor(view, b).doorway)
  end)

  it("widens as far as a doorway's set needs, past its max width, with them standing closer", function()
    local net, clients, ns = crew({ "Ann", "Bob", "Cid", "Dee", "Eve" })
    local a = clients[1]
    local layout = ns.Core.CAMP_LAYOUT
    inside(net, clients, "The Deadmines")
    local view = a.core:pocketCamp()
    assert.equal(layout.pocketColumns, view.maxColumns)
    assert.equal(layout.pocketColumns + 2 * layout.pocketStep, view.columns)
    assert.is_nil(view.more)
    assert.equal(1, #view.doorways)
    assert.same({ "Bob", "Cid", "Dee", "Eve", "You" }, under(view, 1))
    local xs = {}
    for i, actor in ipairs(view.actors) do xs[i] = actor.x end
    table.sort(xs)
    for i = 2, #xs do assert.equal(layout.seated + layout.doorwayGap, xs[i] - xs[i - 1]) end
  end)

  it("doesn't grow past its max width for a raid too big for one side of the widest", function()
    local names = {}
    for i = 1, 12 do names[i] = "M" .. string.char(96 + i) end
    local net, clients, ns = crew(names)
    local a = clients[1]
    local layout = ns.Core.CAMP_LAYOUT
    local raid = {}
    for i = 2, 12 do raid[#raid + 1] = clients[i] end
    inside(net, raid, "Molten Core")
    assert.equal(layout.pocketColumns, a.core:pocketCamp().columns)
    for i = 11, 12 do
      clients[i]:move({ mapId = 1429, x = 0.5, y = 0.5 })
      clients[i]:play({ zone = "Elwynn Forest" })
    end
    net:run(15)
    assert.equal(layout.pocketMaxColumns, a.core:pocketCamp().columns)
  end)

  it("seats your group outside your instance round the fire, not across from you together", function()
    local net, clients = crew({ "Ann", "Bob", "Cid", "Dee" })
    local a, b, c = clients[1], clients[2], clients[3]
    inside(net, { a }, "The Deadmines")
    a.core:group({ unit(a), unit(b), unit(c) })
    local view = a.core:pocketCamp()
    assert.same({ "You", "Bob", "Cid", "Dee" }, order(view))
    assert.are_not.equal(view.actors[1].x < 0, actorFor(view, b).x < 0)
    assert.equal(view.actors[1].x < 0, actorFor(view, c).x < 0)
  end)

  it("seats your group on your side of the fire outside an instance, filling it first", function()
    local _, clients, ns = crew({ "Ann", "Bob", "Cid", "Dee", "Eve" })
    local a, b, c, d, e = clients[1], clients[2], clients[3], clients[4], clients[5]
    a.core:group({ unit(a), unit(c), unit(e) })
    local view = a.core:pocketCamp()
    local you = view.actors[1]
    for _, client in ipairs({ c, e }) do
      local actor = actorFor(view, client)
      assert.equal(you.x < 0, actor.x < 0)
    end
    for _, client in ipairs({ b, d }) do
      assert.are_not.equal(you.x < 0, actorFor(view, client).x < 0)
    end
    a.core:setPocketCampColumns(ns.Core.CAMP_LAYOUT.pocketMaxColumns)
    a.core:group({ unit(a), unit(b), unit(c), unit(d), unit(e) })
    view = a.core:pocketCamp()
    assert.equal(ns.Core.CAMP_LAYOUT.pocketColumns, view.columns)
    local yours = 0
    for _, actor in ipairs(view.actors) do
      if (actor.x < 0) == (view.actors[1].x < 0) then yours = yours + 1 end
    end
    assert.equal(3, yours)
  end)

  it("is exactly as before when you're not in a group and nobody shares an instance", function()
    local function read(group)
      local net, clients = crew({ "Ann", "Bob", "Cid", "Dee" })
      inside(net, { clients[3] }, "The Deadmines")
      if group then clients[1].core:group(group) end
      local view = clients[1].core:pocketCamp()
      local seats = {}
      for _, actor in ipairs(view.actors) do seats[#seats + 1] = { actor.label, actor.x, actor.pose, actor.group } end
      return seats, view.columns
    end
    local before, columns = read(nil)
    local alone, aloneColumns = read({})
    assert.same(before, alone)
    assert.equal(columns, aloneColumns)
  end)

  it("redraws when the group changes, and only then", function()
    local _, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    local function redraws()
      local n = 0
      for _, event in ipairs(a.events) do
        if event[1] == "changed" then n = n + 1 end
      end
      return n
    end
    local before = redraws()
    a.core:group({ unit(a), unit(b) })
    assert.equal(before + 1, redraws())
    a.core:group({ unit(b), unit(a) })
    assert.equal(before + 1, redraws())
    a.core:group({})
    assert.equal(before + 2, redraws())
  end)

  it("sends nothing it wouldn't send without a group", function()
    local function sentBy(grouped)
      local net, clients = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      local mark = #net.wire
      if grouped then a.core:group({ unit(a), unit(b) }) end
      a.core:pocketCamp()
      skip(net, 11 * 60)
      local types = {}
      for _, message in ipairs(net:sent(mark, "Ann")) do types[#types + 1] = message.type end
      return types
    end
    assert.same(sentBy(false), sentBy(true))
  end)
end)

describe("The Spares crate", function()
  local BARB = "|cff1eff00|Hitem:5191::::::::18:::::::|h[Cruel Barb]|h|r"

  local function quietCrew()
    local ns = load()
    local net = ns.FakeNet.new({ items = { ["item:5191"] = "[Cruel Barb]" } })
    local a = net:add("Ann", { character = character("Ann", { level = 20 }) }):login()
    local b = net:add("Bob", { character = character("Bob", { level = 20 }) }):login()
    b:join(a:join())
    net:run(40)
    a.core:setChatLines(false)
    a.core:setToasts(false)
    return net, a, b
  end

  local function claimed(net, a, b)
    local id = assert(a.core:postSpare(BARB, 18))
    net:run(3)
    assert(b.core:claimSpare(a.memberId, id))
    net:run(5)
    return id
  end

  local function redraws(client)
    local n = 0
    for _, event in ipairs(client.events) do
      if event[1] == "changed" then n = n + 1 end
    end
    return n
  end

  it("isn't there while every Spare notice has been seen", function()
    local _, a = quietCrew()
    assert.equal(0, a.core:unseenSpares())
    assert.is_nil(a.core:pocketCamp().spares)
    assert.is_nil(a.core:pocketCamp().sparesTooltip)
  end)

  it("holds the unseen Spare notices' count, worded for its tooltip", function()
    local net, a, b = quietCrew()
    local before = redraws(a)
    local id = claimed(net, a, b)
    assert.is_true(redraws(a) > before)
    assert.equal(1, a.core:unseenSpares())
    local view = a.core:pocketCamp()
    assert.equal(1, view.spares)
    assert.same({ title = "1 Spare notice", hint = "Click to see it in Spares." }, view.sparesTooltip)
    assert(b.core:withdrawClaim(a.memberId, id))
    net:run(5)
    assert(b.core:claimSpare(a.memberId, id))
    net:run(5)
    local count = a.core:unseenSpares()
    assert.is_true(count > 1)
    view = a.core:pocketCamp()
    assert.equal(count, view.spares)
    assert.same({ title = count .. " Spare notices", hint = "Click to see them in Spares." }, view.sparesTooltip)
  end)

  it("goes once the Spares tab is opened, with a redraw", function()
    local net, a, b = quietCrew()
    claimed(net, a, b)
    local before = redraws(a)
    a.core:sparesSeen()
    assert.equal(before + 1, redraws(a))
    assert.is_nil(a.core:pocketCamp().spares)
    assert.is_nil(a.core:pocketCamp().sparesTooltip)
  end)

  it("isn't there with its setting off, and comes back with it on, the notices still unseen", function()
    local net, a, b = quietCrew()
    claimed(net, a, b)
    a.core:setSetting("pocketCampSpares", false)
    assert.is_nil(a.core:pocketCamp().spares)
    assert.is_nil(a.core:pocketCamp().sparesTooltip)
    assert.equal(1, a.core:unseenSpares())
    a.core:setSetting("pocketCampSpares", true)
    assert.equal(1, a.core:pocketCamp().spares)
  end)

  it("isn't there for notices already told in chat or a toast", function()
    local net, a, b = quietCrew()
    a.core:setToasts(true)
    claimed(net, a, b)
    assert.is_nil(a.core:pocketCamp().spares)
  end)

  it("sends nothing it wouldn't send without the Pocket Camp", function()
    local function sentBy(pocket)
      local net, a, b = quietCrew()
      if not pocket then a.core:setSetting("pocketCamp", false) end
      local mark = #net.wire
      claimed(net, a, b)
      a.core:pocketCamp()
      a.core:sparesSeen()
      skip(net, 6 * 60)
      local types = {}
      for _, message in ipairs(net:sent(mark, "Ann")) do types[#types + 1] = message.type end
      return types
    end
    assert.same(sentBy(false), sentBy(true))
  end)
end)

describe("The trophy cup", function()
  local HOUR = 60 * 60
  local FAKE_FINAL_BOSSES = { [101] = "The Deadmines" }

  local function pair(start)
    local ns = load()
    local net = ns.FakeNet.new({ finalBosses = FAKE_FINAL_BOSSES })
    local a = net:add("Ann", { character = character("Ann", start and start.Ann) }):login()
    local b = net:add("Bob", { character = character("Bob", start and start.Bob) }):login()
    b:join(a:join())
    net:run(40)
    return net, a, b
  end

  local function names(view)
    local list = {}
    for i, trophy in ipairs(view.trophies or {}) do list[i] = trophy.name .. " · " .. trophy.ago end
    return list
  end

  it("isn't there before a Trophy is reached", function()
    local _, a = pair()
    local view = a.core:pocketCamp()
    assert.is_nil(view.trophies)
    assert.is_nil(view.trophiesTooltip)
  end)

  it("holds a Trophy reached this session, as the Trophies tab names it, for an hour", function()
    local net, a, b = pair()
    b:play({ deaths = 25 })
    net:run(3)
    local view = a.core:pocketCamp()
    assert.same({ { name = "Crew deaths: 25", ago = "just now" } }, view.trophies)
    assert.same({
      title = "A Trophy reached",
      lines = { "Crew deaths: 25 · just now" },
      hint = "Click to see it in Trophies.",
    }, view.trophiesTooltip)
    skip(net, 58 * 60)
    assert.same({ "Crew deaths: 25 · 58m ago" }, names(a.core:pocketCamp()))
    skip(net, 2 * 60)
    assert.is_nil(a.core:pocketCamp().trophies)
    assert.is_nil(a.core:pocketCamp().trophiesTooltip)
    assert.equal("deaths", a.core:trophies().shelf[1].track)
  end)

  it("makes one cup of several, newest first", function()
    local net, a, b = pair()
    b:play({ deaths = 25 })
    net:run(3)
    skip(net, 10 * 60)
    a:play({ deaths = 25 })
    net:run(3)
    local view = a.core:pocketCamp()
    assert.same({ "Crew deaths: 50 · just now", "Crew deaths: 25 · 10m ago" }, names(view))
    assert.same({
      title = "2 Trophies reached",
      lines = { "Crew deaths: 50 · just now", "Crew deaths: 25 · 10m ago" },
      hint = "Click to see them in Trophies.",
    }, view.trophiesTooltip)
    skip(net, 50 * 60)
    assert.same({ "Crew deaths: 50 · 50m ago" }, names(a.core:pocketCamp()))
  end)

  it("holds a clear, by the time it was made", function()
    local net, a, b = pair()
    skip(net, 5 * 60)
    b.core:encounterEnded({
      encounterId = 101, success = true, instanceType = "party",
      party = { { guid = b.character.guid, name = b.character.name } },
    })
    net:run(70)
    assert.same({ "Dungeons cleared: Deadmines · 1m ago" }, names(a.core:pocketCamp()))
  end)

  it("never shows a Trophy reached while you were away, caught up at login", function()
    local net, a, b = pair()
    a:logout()
    net:run(5)
    b:play({ deaths = 25 })
    net:run(5)
    a:login()
    net:run(40)
    local shelf = a.core:trophies().shelf
    assert.equal("deaths", shelf[1].track)
    assert.is_false(shelf[1].quiet)
    assert.is_nil(a.core:pocketCamp().trophies)
  end)

  it("never shows one from before a /reload", function()
    local net, a, b = pair()
    b:play({ deaths = 25 })
    net:run(3)
    a:reload()
    net:run(5)
    assert.is_nil(a.core:pocketCamp().trophies)
    b:play({ deaths = 50 })
    net:run(3)
    assert.same({ "Crew deaths: 50 · just now" }, names(a.core:pocketCamp()))
  end)

  it("never shows a quiet Trophy", function()
    local net, a = pair({ Ann = { deaths = 25 } })
    local deaths
    for _, trophy in ipairs(a.core:trophies().shelf) do
      if trophy.track == "deaths" then deaths = trophy end
    end
    assert.is_true(deaths.quiet)
    assert.is_true(net:now() - deaths.time < HOUR)
    assert.is_nil(a.core:pocketCamp().trophies)
  end)

  it("sends nothing it wouldn't send without the Pocket Camp", function()
    local function sentBy(pocket)
      local net, a, b = pair()
      if not pocket then a.core:setSetting("pocketCamp", false) end
      local mark = #net.wire
      b:play({ deaths = 25 })
      net:run(3)
      a.core:pocketCamp()
      skip(net, 6 * 60)
      a.core:pocketCamp()
      local types = {}
      for _, message in ipairs(net:sent(mark, "Ann")) do types[#types + 1] = message.type end
      return types
    end
    assert.same(sentBy(false), sentBy(true))
  end)
end)

describe("How long a Member has been at it", function()
  local function status(viewer, client)
    local actor = actorFor(viewer.core:pocketCamp(), client)
    return actor and actor.status
  end

  local function tooltipLine(viewer, client)
    local wanted = client.name .. ": "
    for _, line in ipairs(viewer.core:pocketCamp().tooltip.lines) do
      if line:sub(1, #wanted) == wanted then return line end
    end
    return nil
  end

  it("shows no time under a minute, then the time, in the status and the tooltip", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    b.core:doing({ combat = true })
    net:run(3)
    assert.equal("fighting", status(a, b))
    assert.is_nil(actorFor(a.core:pocketCamp(), b).since)
    net:run(60)
    assert.equal("fighting · 1m", status(a, b))
    assert.equal("Bob: fighting · 1m", tooltipLine(a, b))
    assert.is_true(actorFor(a.core:pocketCamp(), b).since >= 60)
  end)

  it("isn't reset by the same DOING said again, with nobody reading in between", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    local mark = #net.wire
    b.core:doing({ combat = true })
    net:run(2 * 60 + 10)
    assert.equal(2, #net:sent(mark, "Bob", "DOING"))
    assert.equal("fighting · 2m", status(a, b))
  end)

  it("starts over when what they're doing changes", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    b.core:doing({ resting = true })
    net:run(2 * 60 + 20)
    assert.equal("resting · 2m", status(a, b))
    b.core:doing({ vendor = true })
    net:run(30)
    assert.equal("at a vendor", status(a, b))
    net:run(60)
    assert.equal("at a vendor · 1m", status(a, b))
  end)

  it("counts an instance from when the row's instance changed", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    b:move({ instance = "The Deadmines" })
    b:play({ zone = "The Deadmines" })
    net:run(15)
    assert.equal("in The Deadmines", status(a, b))
    net:run(25 * 60)
    assert.equal("in The Deadmines · 25m", status(a, b))
    b:move({ instance = "Shadowfang Keep" })
    b:play({ zone = "Shadowfang Keep" })
    net:run(15)
    assert.equal("in Shadowfang Keep", status(a, b))
  end)

  it("counts fishing on through each catch", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    b.core:caught(catch(SMALLFISH))
    untilFishing(net, a, b, 70)
    net:run(30)
    b.core:caught(catch(SMALLFISH))
    b:play({ level = 11 })
    net:run(35)
    assert.equal("fishing", poseOf(a, b))
    assert.equal("fishing · 1m", status(a, b))
  end)

  it("shows your own time too", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a = clients[1]
    a.core:doing({ resting = true })
    net:run(70)
    assert.equal("resting · 1m", status(a, a))
  end)

  it("never shows a time by the fire, in a form or not", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    skip(net, 5 * 60)
    assert.equal("by the fire", status(a, b))
    assert.is_nil(actorFor(a.core:pocketCamp(), b).since)
    b.core:doing({ form = "bear" })
    net:run(90)
    assert.equal("in bear form", status(a, b))
  end)

  it("counts from the first read after a reload", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    b.core:doing({ resting = true })
    net:run(5 * 60)
    a:reload()
    for _ = 1, 3 * 60 do
      if poseOf(a, b) == "resting" then break end
      net:step()
    end
    assert.equal("resting", status(a, b))
    net:run(60)
    assert.equal("resting · 1m", status(a, b))
  end)

  it("sends nothing it wouldn't send without the Pocket Camp", function()
    local function sentBy(pocket)
      local net, clients = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      if not pocket then a.core:setSetting("pocketCamp", false) end
      local mark = #net.wire
      a.core:doing({ resting = true })
      b.core:doing({ combat = true })
      net:run(3 * 60)
      a.core:pocketCamp()
      local types = {}
      for _, message in ipairs(net:sent(mark)) do types[#types + 1] = message.type end
      return types
    end
    assert.same(sentBy(false), sentBy(true))
  end)
end)

describe("Head pieces in the Pocket Camp", function()
  it("show on another Member's figure, and on yours", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    b.core:setLook({ hat = "cowboy" })
    a.core:setLook({ hat = "templar" })
    net:run(5)
    local view = a.core:pocketCamp()
    assert.equal("cowboy", actorFor(view, b).hat)
    assert.equal("templar", actorFor(view, a).hat)
  end)
end)

describe("Pets in the Pocket Camp", function()
  local function seats(view)
    local list = {}
    for _, actor in ipairs(view.actors) do list[#list + 1] = actor.memberId end
    return table.concat(list, " ") .. " +" .. tostring(view.more)
  end

  it("sit on the far side of their Member, and asleep beside a bedroll", function()
    local net, clients, ns = crew({ "Ann", "Bob", "Cid" })
    local layout = ns.Core.CAMP_LAYOUT
    local a, b, c = clients[1], clients[2], clients[3]
    a.core:setPocketCampColumns(layout.pocketMaxColumns)
    b.core:setLook({ pet = "dog" })
    c.core:setLook({ pet = "owl" })
    net:run(5)
    skip(net, 2 * 60)
    c:logout()
    net:run(2)
    local view = a.core:pocketCamp()
    local bob, cid = actorFor(view, b), actorFor(view, c)
    assert.equal("dog", bob.pet.key)
    assert.same({ "asleep", "owl" }, { cid.pose, cid.pet.key })
    for _, actor in ipairs({ bob, cid }) do
      local far = actor.x > 0 and actor.pet.x >= actor.x + actor.width or actor.pet.x + layout.pet <= actor.x
      assert.is_true(far)
    end
  end)

  it("shows no pet in a doorway", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    b.core:setLook({ pet = "frog" })
    b:move({ instance = "The Deadmines" })
    b:play({ zone = "The Deadmines" })
    net:run(15)
    local bob = actorFor(a.core:pocketCamp(), b)
    assert.equal("adventuring", bob.pose)
    assert.is_nil(bob.pet)
  end)

  it("drops pets before a Member goes to +N, and widens for them only when there's room", function()
    local names = { "Ann", "Bob", "Cid", "Dee", "Eve", "Fay", "Gus", "Hal", "Ivy" }
    local net, clients, ns = crew(names)
    local layout = ns.Core.CAMP_LAYOUT
    local core = clients[1].core
    local without = seats(core:pocketCamp())
    for _, client in ipairs(clients) do client.core:setLook({ pet = "fox" }) end
    net:run(5)
    local view = core:pocketCamp()
    assert.equal(without, seats(view))
    assert.equal(layout.pocketColumns, view.columns)

    core:setPocketCampColumns(layout.pocketMaxColumns)
    local wide = core:pocketCamp()
    assert.is_true(wide.columns > layout.pocketColumns)
    local petted = 0
    for _, actor in ipairs(wide.actors) do petted = petted + (actor.pet and 1 or 0) end
    assert.is_true(petted > 0)
    local half = wide.columns / 2
    for _, actor in ipairs(wide.actors) do
      if actor.pet then assert.is_true(actor.pet.x >= -half and actor.pet.x + layout.pet <= half) end
    end
  end)
end)
