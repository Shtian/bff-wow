local load = require("tests.load")

local function character(name, extra)
  local c = {
    guid = "Player-0-" .. name, name = name, classFilename = "WARRIOR",
    level = 10, xp = 0, maxXp = 1000, zone = "Elwynn Forest", deaths = 0,
  }
  for k, v in pairs(extra or {}) do c[k] = v end
  return c
end

-- A net with the given clients logged in and in one Crew, settled, each
-- with the Pocket Camp on.
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
  for _, client in ipairs(clients) do client.core:setSetting("pocketCamp", true) end
  return net, clients, ns
end

local function actorFor(view, client)
  for _, actor in ipairs(view.actors) do
    if actor.memberId == client.memberId then return actor end
  end
  return nil
end

-- How the viewer's Pocket Camp shows the client: its pose and status.
local function shown(viewer, client)
  local actor = actorFor(viewer.core:pocketCamp(), client)
  return actor and { actor.pose, actor.status }
end

local function poseOf(viewer, client)
  local actor = actorFor(viewer.core:pocketCamp(), client)
  return actor and actor.pose
end

-- Skill line IDs.
local ALCHEMY, MINING, FISHING = 171, 186, 356

local function profession(skillLine, name, skill)
  return { skillLine = skillLine, name = name, icon = 1000 + skillLine, skill = skill, max = 300 }
end

-- The animations the client's Core fired, as "kind:Name".
local function animations(client, clients)
  local names = {}
  for _, other in ipairs(clients) do names[other.memberId] = other.name end
  local list = {}
  for _, event in ipairs(client.events) do
    if event[1] == "pocketCampAnimation" then
      list[#list + 1] = event[2].kind .. ":" .. tostring(names[event[2].memberId])
    end
  end
  return list
end

local function doings(net, mark, name)
  return net:sent(mark, name, "DOING")
end

describe("What a Member is doing", function()
  it("shows on your own figure at once, in words too", function()
    local _, clients = crew({ "Ann", "Bob" })
    local a = clients[1]
    assert.same({ "seated", "by the fire" }, shown(a, a))
    a.core:doing({ vendor = true })
    assert.same({ "vendor", "at a vendor" }, shown(a, a))
    a.core:doing({ auction = true })
    assert.same({ "auction", "at the auction house" }, shown(a, a))
    a.core:doing({ resting = true })
    assert.same({ "resting", "resting" }, shown(a, a))
    a.core:doing({ flying = true })
    assert.same({ "flying", "flying" }, shown(a, a))
    a.core:doing({ combat = true })
    assert.same({ "fighting", "fighting" }, shown(a, a))
    assert.same({ "You: fighting", "Bob: by the fire" }, a.core:pocketCamp().tooltip.lines)
  end)

  it("reaches the Crew in one small message that is no part of your record", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    local mark = #net.wire
    b.core:doing({ vendor = true })
    net:run(3)
    assert.same({ "vendor", "at a vendor" }, shown(a, b))
    local sent = doings(net, mark, "Bob")
    assert.equal(1, #sent)
    assert.equal("vendor", sent[1].doing)
    assert.is_true(sent[1].size <= 255)
    -- The record didn't change: over the next DIGESTs no one asks for it.
    net:run(70)
    assert.equal(0, #net:sent(mark, nil, "DATA"))
    assert.same({ "vendor", "at a vendor" }, shown(a, b))

    b.core:doing({})
    net:run(20)
    assert.same({ "seated", "by the fire" }, shown(a, b))
  end)

  it("shows the first of flying, the auction house, a vendor, fighting and resting", function()
    local _, clients = crew({ "Ann", "Bob" })
    local a = clients[1]
    a.core:doing({ combat = true, vendor = true, auction = true, resting = true, flying = true })
    assert.equal("flying", poseOf(a, a))
    a.core:doing({ combat = true, vendor = true, auction = true, resting = true })
    assert.equal("auction", poseOf(a, a))
    a.core:doing({ combat = true, vendor = true, resting = true })
    assert.equal("vendor", poseOf(a, a))
    a.core:doing({ combat = true, resting = true })
    assert.equal("fighting", poseOf(a, a))
    a.core:doing({ resting = true })
    -- Fighting lasts a little past the end of combat.
    assert.equal("fighting", poseOf(a, a))
  end)

  it("keeps fighting for 20 s past the end of combat, so pull after pull is one spell", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    local mark = #net.wire
    b.core:doing({ combat = true })
    net:run(8)
    b.core:doing({})
    net:run(12)
    b.core:doing({ combat = true })
    net:run(6)
    b.core:doing({})
    net:run(19)
    assert.equal("fighting", poseOf(b, b))
    assert.equal("fighting", poseOf(a, b))
    assert.equal(1, #doings(net, mark, "Bob"))
    local before = b:count("changed")
    net:run(1)
    assert.equal("seated", poseOf(b, b))
    -- Bob's own Pocket Camp is told to redraw.
    assert.equal(before + 1, b:count("changed"))
    net:run(3)
    assert.equal("seated", poseOf(a, b))
    assert.equal(2, #doings(net, mark, "Bob"))
  end)

  it("sends only changes, the latest one, and no more often than every 15 s", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    local mark = #net.wire
    b.core:doing({ vendor = true })
    net:run(2)
    b.core:doing({ vendor = true })
    b.core:doing({ auction = true })
    b.core:doing({ resting = true })
    net:run(10)
    assert.equal(1, #doings(net, mark, "Bob"))
    assert.equal("vendor", poseOf(a, b))
    net:run(5)
    local sent = doings(net, mark, "Bob")
    assert.same({ "vendor", "resting" }, { sent[1].doing, sent[2].doing })
    assert.equal("resting", poseOf(a, b))
  end)

  it("grows the gap between DOINGs with the Crew: 5 s per other Member online", function()
    local net, clients = crew({ "Ann", "Bob", "Cid", "Dee", "Eve" })
    local b = clients[2]
    local mark = #net.wire
    b.core:doing({ vendor = true })
    net:run(2)
    b.core:doing({})
    net:run(17)
    assert.equal(1, #doings(net, mark, "Bob"))
    net:run(3)
    assert.equal(2, #doings(net, mark, "Bob"))
  end)

  it("says it again every 2 minutes while it lasts, and runs out 5 minutes after it was last heard", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    local mark = #net.wire
    b.core:doing({ resting = true })
    net:run(4 * 60 + 5)
    assert.equal(3, #doings(net, mark, "Bob"))
    assert.equal("resting", poseOf(a, b))

    -- The DOING that ends it is lost: it runs out by itself.
    net.drop = function(message)
      local decoded = load().Codec.decode(message)
      return type(decoded) == "table" and decoded.type == "DOING"
    end
    b.core:doing({})
    net:run(3 * 60)
    assert.equal("resting", poseOf(a, b))
    local before = a:count("changed")
    net:run(2 * 60)
    assert.equal("seated", poseOf(a, b))
    assert.is_true(a:count("changed") > before)
  end)

  it("tells a Member who comes online what you're doing, and forgets it when you go offline", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    a:logout()
    net:run(5)
    b.core:doing({ vendor = true })
    net:run(30)
    a:login()
    net:run(30)
    assert.equal("vendor", poseOf(a, b))

    b:logout()
    net:run(5)
    b:login()
    net:run(30)
    assert.equal("seated", poseOf(a, b))
  end)

  it("clears what the Crew held from before a reload", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    b.core:doing({ vendor = true })
    net:run(3)
    assert.equal("vendor", poseOf(a, b))
    -- The window is gone after a reload, and the new session knows of no vendor.
    b:reload()
    b.core:setSetting("pocketCamp", true)
    net:run(20)
    assert.equal("seated", poseOf(a, b))
  end)

  it("sends nothing while paused, alone or in lockdown, and catches up after", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    local mark = #net.wire
    b.core:setPaused(true)
    b.core:doing({ vendor = true })
    net:run(30)
    assert.equal(0, #doings(net, mark, "Bob"))
    b.core:setPaused(false)
    net:run(30)
    assert.equal("vendor", poseOf(a, b))

    mark = #net.wire
    b:lockdown(true)
    b.core:doing({ combat = true })
    net:run(30)
    assert.equal(0, #doings(net, mark, "Bob"))
    b:lockdown(false)
    net:run(5)
    assert.equal("fighting", poseOf(a, b))

    a:logout()
    net:run(5)
    mark = #net.wire
    b.core:doing({ flying = true })
    net:run(30)
    assert.equal(0, #doings(net, mark, "Bob"))
    assert.equal("flying", poseOf(b, b))
  end)

  it("shows a Member by the fire when a newer BFF says something this one doesn't know", function()
    local net, clients, ns = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    b.core:doing({ vendor = true })
    net:run(3)
    net:broadcast(b, ns.Codec.encode({ type = "DOING", from = b.memberId, doing = "dancing", at = net:now() + 1 }))
    net:run(2)
    assert.same({ "seated", "by the fire" }, shown(a, b))
    -- An older one, arriving late, changes nothing; nor does one that isn't a DOING at all.
    net:broadcast(b, ns.Codec.encode({ type = "DOING", from = b.memberId, doing = "vendor", at = net:now() - 60 }))
    net:broadcast(b, ns.Codec.encode({ type = "DOING", from = b.memberId, doing = "vendor" }))
    net:run(2)
    assert.equal("seated", poseOf(a, b))
  end)

  it("redraws the Pocket Camp when what someone is doing changes, only while it shows", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    local before = a:count("changed")
    b.core:doing({ vendor = true })
    net:run(3)
    assert.equal(before + 1, a:count("changed"))
    a.core:doing({ resting = true })
    assert.equal(before + 2, a:count("changed"))
    a.core:doing({ resting = true })
    assert.equal(before + 2, a:count("changed"))

    b.core:setSetting("pocketCamp", false)
    local quiet = b:count("changed")
    a.core:doing({})
    net:run(20)
    b.core:doing({})
    assert.equal(quiet, b:count("changed"))
  end)

  describe("a quest handed in", function()
    it("plays on your own figure at once and on the Crew's, once", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      a.events, b.events = {}, {}
      local mark = #net.wire
      b.core:questHandedIn()
      assert.same({ "quest:Bob" }, animations(b, clients))
      -- A hub's worth of quests is one DOING.
      b.core:questHandedIn()
      b.core:questHandedIn()
      net:run(20)
      assert.same({ "quest:Bob" }, animations(a, clients))
      assert.equal(1, #doings(net, mark, "Bob"))
      -- It left what Bob is doing alone.
      assert.equal("seated", poseOf(a, b))
    end)

    it("isn't told late, and plays nothing while the Pocket Camp is off", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      a.events = {}
      b:lockdown(true)
      b.core:questHandedIn()
      net:run(100)
      b:lockdown(false)
      net:run(30)
      assert.same({}, animations(a, clients))

      a.core:setSetting("pocketCamp", false)
      b.core:setSetting("pocketCamp", false)
      b.events = {}
      b.core:questHandedIn()
      net:run(20)
      assert.same({}, animations(a, clients))
      assert.same({}, animations(b, clients))
    end)
  end)

  describe("a profession", function()
    -- Both share their professions first: the first share is a baseline.
    local function withProfessions()
      local net, clients = crew({ "Ann", "Bob" })
      for _, client in ipairs(clients) do
        client:play({ professions = { profession(ALCHEMY, "Alchemy", 10), profession(MINING, "Mining", 10),
          profession(FISHING, "Fishing", 10) } })
        client:play({ level = 11 })
      end
      net:run(5)
      return net, clients
    end

    it("shows a Member crafting or gathering for 60 s after its skill is seen to grow", function()
      local net, clients = withProfessions()
      local a, b = clients[1], clients[2]
      assert.equal("seated", poseOf(a, b))
      -- The ding takes the new skill out with it at once.
      b:play({ professions = { profession(ALCHEMY, "Alchemy", 11), profession(MINING, "Mining", 10),
        profession(FISHING, "Fishing", 10) }, level = 12 })
      assert.same({ "crafting", "crafting" }, shown(b, b))
      net:run(3)
      assert.same({ "crafting", "crafting" }, shown(a, b))
      net:run(54)
      assert.equal("crafting", poseOf(a, b))
      net:run(6)
      assert.equal("seated", poseOf(a, b))

      b:play({ professions = { profession(ALCHEMY, "Alchemy", 12), profession(MINING, "Mining", 11),
        profession(FISHING, "Fishing", 10) }, level = 13 })
      net:run(3)
      assert.same({ "gathering", "gathering" }, shown(a, b))
    end)

    it("makes nothing of fishing skill, a first share or a login's catch-up", function()
      local net, clients = withProfessions()
      local a, b = clients[1], clients[2]
      b:play({ professions = { profession(ALCHEMY, "Alchemy", 10), profession(MINING, "Mining", 10),
        profession(FISHING, "Fishing", 11) }, level = 12 })
      net:run(3)
      assert.equal("seated", poseOf(a, b))

      a:logout()
      net:run(5)
      b:play({ professions = { profession(ALCHEMY, "Alchemy", 20), profession(MINING, "Mining", 10),
        profession(FISHING, "Fishing", 11) }, level = 13 })
      net:run(70)
      a:login()
      net:run(40)
      assert.equal("seated", poseOf(a, b))
    end)
  end)

  describe("with the rest of the Pocket Camp", function()
    it("gives way to an instance, whatever was said before going in", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      b.core:doing({ vendor = true })
      net:run(3)
      assert.equal("vendor", poseOf(a, b))
      -- The DOING that ends the visit is lost; the record says where Bob is.
      b:move({ instance = "The Deadmines" })
      b:play({ zone = "The Deadmines" })
      b.core:doing({ combat = true })
      net:run(15)
      local bob = actorFor(a.core:pocketCamp(), b)
      assert.same({ "adventuring", "in The Deadmines", nil }, { bob.pose, bob.status, bob.raid })
      assert.equal("adventuring", poseOf(b, b))
    end)

    it("marks a raid", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      b:move({ instance = "Molten Core" })
      b:play({ zone = "Molten Core" })
      net:run(15)
      local bob = actorFor(a.core:pocketCamp(), b)
      assert.same({ "adventuring", "in Molten Core", true }, { bob.pose, bob.status, bob.raid })
    end)

    it("gives a flying figure its griffin's room: clear of the fire and of its neighbours", function()
      local names = { "Ann", "Bob", "Cid", "Dee", "Eve", "Fay" }
      local net, clients, ns = crew(names)
      local a = clients[1]
      local layout = ns.Core.CAMP_LAYOUT
      assert.equal(6, #a.core:pocketCamp().actors)
      clients[2].core:doing({ flying = true })
      net:run(3)
      local view = a.core:pocketCamp()
      -- The griffin takes a second seat on its side.
      assert.equal(5, #view.actors)
      assert.same({ 1, "+1" }, { view.more, view.moreText })
      local bob = actorFor(view, clients[2])
      assert.equal(layout.seated, bob.width)
      -- From its beak to its tail, on the side of the fire it's on.
      local function span(actor)
        if actor.pose ~= "flying" then return actor.x, actor.x + actor.width end
        if actor.x > 0 then return actor.x - layout.griffinFore, actor.x + actor.width + layout.griffinAft end
        return actor.x - layout.griffinAft, actor.x + actor.width + layout.griffinFore
      end
      local half = layout.pocketColumns / 2
      for i, actor in ipairs(view.actors) do
        local from, to = span(actor)
        assert.is_true(from >= -half and to <= half)
        assert.is_true(to <= -layout.fire or from >= layout.fire)
        for j = i + 1, #view.actors do
          local otherFrom, otherTo = span(view.actors[j])
          assert.is_true(to <= otherFrom or otherTo <= from)
        end
      end
    end)
  end)
end)
