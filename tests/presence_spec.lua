local load = require("tests.load")

local Presence = load().Presence

-- A Presence with its own clock, recording what it reports: every held or
-- peer message delivered and who whispered it, each ready (with why), how often a peer arrived,
-- who is gone, how often it asked for a member list, and the trace.
local function newPresence()
  local world = { time = 100, delivered = {}, from = {}, ready = {}, arrived = 0, gone = {}, asked = 0, lines = {} }
  world.presence = Presence.new({
    now = function() return world.time end,
    -- As the channel link's key does: "Name-Realm" and "name" are one.
    key = function(name) return (name:gsub("%-.*$", "")):lower() end,
    trace = function(line) world.lines[#world.lines + 1] = line end,
    deliver = function(message, name)
      world.delivered[#world.delivered + 1] = message
      world.from[#world.from + 1] = name
    end,
    ready = function(why) world.ready[#world.ready + 1] = why end,
    arrived = function() world.arrived = world.arrived + 1 end,
    gone = function(name) world.gone[#world.gone + 1] = name end,
    askList = function() world.asked = world.asked + 1 end,
  })
  -- Moves the clock on, ticking once a second as the channel link does.
  function world.advance(seconds)
    for _ = 1, seconds do
      world.time = world.time + 1
      world.presence:tick()
    end
  end
  return world, world.presence
end

-- In the channel with Bob and Cat (on another realm), ready.
local function withPeers()
  local world, presence = newPresence()
  presence:start()
  presence:listed({ "Bob", "Cat-Realm" })
  return world, presence
end

describe("Presence", function()
  describe("ready", function()
    it("comes with the first member list since joining", function()
      local world, presence = newPresence()
      presence:start()
      assert.is_false(presence:ready())
      presence:listed({ "Bob" })
      assert.is_true(presence:ready())
      assert.same({ "member list" }, world.ready)
    end)

    it("comes after 5 s without a member list", function()
      local world, presence = newPresence()
      presence:start()
      world.advance(4)
      assert.is_false(presence:ready())
      world.advance(1)
      assert.is_true(presence:ready())
      assert.same({ "no member list after 5 s" }, world.ready)
    end)

    it("is reported once, whichever comes first", function()
      local world, presence = newPresence()
      presence:start()
      presence:listed({})
      world.advance(10)
      presence:listed({ "Bob" })
      assert.same({ "member list" }, world.ready)
    end)

    it("starts over when the channel is joined again, and everyone is forgotten", function()
      local world, presence = withPeers()
      presence:start()
      assert.is_false(presence:ready())
      assert.same({}, presence:targets())
      world.advance(5)
      assert.same({ "member list", "no member list after 5 s" }, world.ready)
    end)

    it("never comes without a channel: a Crew change forgets everyone and waits for nothing", function()
      local world, presence = withPeers()
      presence:stop()
      world.advance(60)
      assert.is_false(presence:ready())
      assert.equal(0, presence:count())
    end)
  end)

  describe("who to whisper", function()
    it("is every peer, or the one named, or no one for a name that isn't a peer", function()
      local _, presence = withPeers()
      assert.same({ "Bob", "Cat-Realm" }, presence:targets())
      assert.same({ "Cat-Realm" }, presence:targets("cat"))
      assert.same({}, presence:targets("Dan"))
      assert.equal(2, presence:count())
      assert.is_true(presence:has("Bob"))
      assert.is_false(presence:has("Dan"))
    end)

    it("only ever grows with a member list, which may come in parts", function()
      local _, presence = withPeers()
      presence:listed({ "Dan" })
      assert.same({ "Bob", "Cat-Realm", "Dan" }, presence:targets())
    end)

    it("gains a Character on their join notice and loses them on their leave notice", function()
      local world, presence = withPeers()
      presence:joined("Dan")
      assert.same({ "Bob", "Cat-Realm", "Dan" }, presence:targets())
      presence:left("Bob")
      assert.same({ "Cat-Realm", "Dan" }, presence:targets())
      assert.same({ "Bob" }, world.gone)
    end)

    it("reports a leave notice as gone even for a name it never knew", function()
      local world, presence = withPeers()
      presence:left("Dan")
      assert.same({ "Dan" }, world.gone)
    end)
  end)

  describe("arrived", function()
    it("is reported when a member list shows someone new while ready", function()
      local world, presence = withPeers()
      presence:listed({ "Bob", "Dan" })
      assert.equal(1, world.arrived)
    end)

    it("isn't reported for the first list, a list with no one new, or a join notice", function()
      local world, presence = withPeers()
      presence:listed({ "Bob", "Cat-Realm" })
      presence:joined("Dan")
      assert.equal(0, world.arrived)
    end)
  end)

  it("knows a peer by any spelling of their name", function()
    local _, presence = withPeers()
    assert.equal("Cat-Realm", presence:peer("cat"))
    assert.is_nil(presence:peer("Dan"))
  end)

  describe("a whisper", function()
    it("from a peer is delivered at once", function()
      local world, presence = withPeers()
      presence:heard("Bob", "one")
      assert.same({ "one" }, world.delivered)
      assert.same({ "Bob" }, world.from)
      assert.equal(0, world.asked)
    end)

    it("from a stranger is held, and delivered when a member list shows them", function()
      local world, presence = withPeers()
      presence:heard("Dan", "one")
      presence:heard("Dan", "two")
      assert.same({}, world.delivered)
      assert.equal(1, world.asked)
      world.advance(9)
      presence:listed({ "Dan" })
      assert.same({ "one", "two" }, world.delivered)
      presence:heard("Dan", "three")
      assert.same({ "one", "two", "three" }, world.delivered)
      assert.same({ "Dan", "Dan", "Dan" }, world.from)
    end)

    it("from a stranger is dropped when no member list shows them within 10 s", function()
      local world, presence = withPeers()
      presence:heard("Dan", "one")
      world.advance(10)
      presence:listed({ "Dan" })
      assert.same({}, world.delivered)
    end)

    it("from a stranger is held up to 20 messages; the rest are dropped", function()
      local world, presence = withPeers()
      for i = 1, 25 do presence:heard("Dan", "message " .. i) end
      presence:joined("Dan")
      assert.equal(20, #world.delivered)
      assert.equal("message 1", world.delivered[1])
      assert.equal("message 20", world.delivered[20])
    end)

    it("held is forgotten when the channel is joined again", function()
      local world, presence = withPeers()
      presence:heard("Dan", "one")
      presence:start()
      presence:listed({ "Dan" })
      assert.same({}, world.delivered)
    end)
  end)

  describe("No player named", function()
    it("drops the peer, reports them gone and is ours", function()
      local world, presence = withPeers()
      assert.is_true(presence:hidesNotFound("Bob"))
      presence:notFound("Bob")
      assert.same({ "Bob" }, world.gone)
      assert.same({ "Cat-Realm" }, presence:targets())
    end)

    it("stays ours for 30 s after the drop, so repeats are hidden, then no longer", function()
      local world, presence = withPeers()
      presence:notFound("Bob")
      world.advance(29)
      assert.is_true(presence:hidesNotFound("Bob"))
      presence:notFound("Bob")
      assert.same({ "Bob" }, world.gone)
      world.advance(1)
      assert.is_false(presence:hidesNotFound("Bob"))
    end)

    it("for a name that was never whispered isn't ours, and drops no one", function()
      local world, presence = withPeers()
      assert.is_false(presence:hidesNotFound("Dan Smith"))
      presence:notFound("Dan Smith")
      assert.same({}, world.gone)
      assert.equal("notice: No player named Dan Smith · not a peer (peers: bob, cat)", world.lines[#world.lines])
    end)

    -- The member list can go on showing a Character who logged out.
    describe("then a member list that still names them", function()
      it("doesn't add them again for 5 minutes", function()
        local world, presence = withPeers()
        presence:notFound("Bob")
        world.advance(299)
        presence:listed({ "Bob", "Cat-Realm" })
        assert.same({ "Cat-Realm" }, presence:targets())
        assert.equal(0, world.arrived)
      end)

      it("adds them again after 5 minutes", function()
        local world, presence = withPeers()
        presence:notFound("Bob")
        world.advance(300)
        presence:listed({ "Bob", "Cat-Realm" })
        assert.same({ "Bob", "Cat-Realm" }, presence:targets())
        assert.equal(1, world.arrived)
      end)

      it("still adds anyone else it names", function()
        local world, presence = withPeers()
        presence:notFound("Bob")
        presence:listed({ "Bob", "Dan" })
        assert.same({ "Cat-Realm", "Dan" }, presence:targets())
        assert.equal(1, world.arrived)
      end)
    end)

    it("then a whisper from them adds them again at once, and is delivered", function()
      local world, presence = withPeers()
      presence:notFound("Bob")
      presence:heard("Bob", "one")
      assert.same({ "one" }, world.delivered)
      assert.same({ "Bob", "Cat-Realm" }, presence:targets())
      assert.equal(0, world.asked)
      -- Back for good: the next member list changes nothing.
      presence:listed({ "Bob", "Cat-Realm" })
      assert.equal(0, world.arrived)
    end)

    it("then their join notice adds them again at once", function()
      local _, presence = withPeers()
      presence:notFound("Bob")
      presence:joined("Bob")
      assert.same({ "Bob", "Cat-Realm" }, presence:targets())
    end)

    it("is forgotten when the channel is joined again: the first list adds them", function()
      local _, presence = withPeers()
      presence:notFound("Bob")
      presence:start()
      presence:listed({ "Bob" })
      assert.same({ "Bob" }, presence:targets())
    end)

    it("then a whisper from them after 5 minutes waits for a member list like any stranger's", function()
      local world, presence = withPeers()
      presence:notFound("Bob")
      world.advance(300)
      presence:heard("Bob", "one")
      assert.same({}, world.delivered)
      presence:listed({ "Bob" })
      assert.same({ "one" }, world.delivered)
    end)

    -- #178: a peer's leaving doesn't cancel the whispers queued for them.
    it("is ours for a Character who left while a whisper to them is queued, however long", function()
      local world, presence = withPeers()
      presence:whispered("Bob")
      presence:left("Bob")
      world.advance(120)
      assert.is_true(presence:hidesNotFound("Bob"))
    end)

    it("is ours for 30 s after the last chunk to a Character who left went out", function()
      local world, presence = withPeers()
      presence:whispered("Bob")
      presence:left("Bob")
      presence:chunk("Bob", true, false)
      world.advance(120)
      assert.is_true(presence:hidesNotFound("Bob"))
      presence:chunk("Bob", false, false)
      world.advance(29)
      assert.is_true(presence:hidesNotFound("Bob"))
      world.advance(1)
      assert.is_false(presence:hidesNotFound("Bob"))
    end)

    it("stays ours for a queued whisper across joining the channel again", function()
      local _, presence = withPeers()
      presence:whispered("Bob")
      presence:start()
      assert.is_true(presence:hidesNotFound("Bob"))
    end)
  end)

  describe("Player is offline", function()
    it("is put down to the one peer a send failed to within 3 s: gone, and ours", function()
      local world, presence = withPeers()
      presence:chunk("Bob", false, true)
      world.advance(2)
      assert.is_true(presence:hidesOffline())
      presence:offline()
      assert.same({ "Bob" }, world.gone)
      assert.same({ "Cat-Realm" }, presence:targets())
      -- The chat filter may run after the event.
      assert.is_true(presence:hidesOffline())
      world.advance(3)
      assert.is_false(presence:hidesOffline())
    end)

    it("is put down to no one after failures to several peers", function()
      local world, presence = withPeers()
      presence:chunk("Bob", false, true)
      presence:chunk("Cat-Realm", false, true)
      presence:offline()
      assert.same({}, world.gone)
      assert.is_false(presence:hidesOffline())
    end)

    it("is put down to no one 3 s after the failed send, or with none", function()
      local world, presence = withPeers()
      presence:offline()
      presence:chunk("Bob", false, true)
      world.advance(3)
      presence:offline()
      assert.same({}, world.gone)
      assert.is_false(presence:hidesOffline())
    end)

    it("is put down to no one when the failed send was to someone who isn't a peer", function()
      local world, presence = withPeers()
      presence:chunk("Dan", false, true)
      presence:offline()
      assert.same({}, world.gone)
      assert.is_false(presence:hidesOffline())
    end)
  end)

  describe("an unreadable notice", function()
    it("within 5 s of a whisper says how long after it came", function()
      local world, presence = withPeers()
      presence:whispered("Bob")
      world.advance(4)
      assert.equal(4, presence:unreadable())
    end)

    it("later than that, or with nothing whispered, is no one's", function()
      local world, presence = withPeers()
      assert.is_nil(presence:unreadable())
      presence:whispered("Bob")
      world.advance(5)
      assert.is_nil(presence:unreadable())
    end)
  end)

  -- A peer who is unreachable with no notice saying so: in a dungeon, or
  -- logged out with a leave notice that never came.
  describe("silence", function()
    -- With the link up, and a whisper to everyone a minute as the DIGEST is.
    local function minutes(world, presence, count)
      for _ = 1, count do
        for _, name in ipairs(presence:targets()) do presence:whispered(name) end
        world.advance(60)
      end
    end

    local function listening()
      local world, presence = withPeers()
      presence:listening(true)
      return world, presence
    end

    it("stops whispers to a peer who hasn't answered for 3 minutes", function()
      local world, presence = listening()
      presence:whispered("Bob")
      world.advance(179)
      assert.same({ "Bob" }, presence:targets("Bob"))
      world.advance(1)
      assert.same({}, presence:targets("Bob"))
      assert.same({ "Cat-Realm" }, presence:targets())
    end)

    it("never reports the peer gone: they stay a peer", function()
      local world, presence = listening()
      minutes(world, presence, 4)
      assert.same({}, presence:targets())
      assert.same({}, world.gone)
      assert.equal(2, presence:count())
      assert.is_true(presence:has("Bob"))
    end)

    it("ends with the next whisper from them, which is delivered", function()
      local world, presence = listening()
      minutes(world, presence, 4)
      presence:heard("Bob", "one")
      assert.same({ "one" }, world.delivered)
      assert.same({ "Bob" }, presence:targets())
      assert.equal(0, world.arrived)
    end)

    it("never comes for a peer who is heard every minute", function()
      local world, presence = listening()
      for _ = 1, 10 do
        minutes(world, presence, 1)
        presence:heard("Bob", "digest")
      end
      assert.same({ "Bob" }, presence:targets())
    end)

    it("counts from the first whisper they didn't answer, not from when they were last heard", function()
      local world, presence = listening()
      -- Nothing whispered (as while Paused): no one has failed to answer.
      world.advance(600)
      assert.same({ "Bob", "Cat-Realm" }, presence:targets())
      presence:whispered("Bob")
      world.advance(60)
      presence:whispered("Bob")
      world.advance(119)
      assert.same({ "Bob" }, presence:targets("Bob"))
      world.advance(1)
      assert.same({}, presence:targets("Bob"))
    end)

    it("doesn't count time with the link down, when no one can be heard", function()
      local world, presence = listening()
      presence:whispered("Bob")
      world.advance(100)
      presence:listening(false)
      world.advance(1200)
      presence:listening(true)
      world.advance(79)
      assert.same({ "Bob" }, presence:targets("Bob"))
      world.advance(1)
      assert.same({}, presence:targets("Bob"))
    end)

    -- Two peers who each lost the other's whispers would otherwise both
    -- wait for the other to speak first.
    it("still lets one whisper through every 5 minutes", function()
      local world, presence = listening()
      presence:whispered("Bob")
      world.advance(180 + 299)
      assert.same({}, presence:targets("Bob"))
      world.advance(1)
      assert.same({ "Bob" }, presence:targets("Bob"))
      assert.same({ "Bob", "Cat-Realm" }, presence:targets())
      presence:whispered("Bob")
      assert.same({}, presence:targets("Bob"))
      world.advance(300)
      assert.same({ "Bob" }, presence:targets("Bob"))
    end)

    it("lets one whisper through as soon as the link comes back up", function()
      local world, presence = listening()
      minutes(world, presence, 4)
      presence:listening(false)
      world.advance(30)
      assert.same({}, presence:targets())
      presence:listening(true)
      assert.same({ "Bob", "Cat-Realm" }, presence:targets())
      presence:whispered("Bob")
      presence:whispered("Cat-Realm")
      assert.same({}, presence:targets())
    end)

    it("is forgotten when they leave and join again", function()
      local world, presence = listening()
      minutes(world, presence, 4)
      presence:left("Bob")
      presence:joined("Bob")
      assert.same({ "Bob" }, presence:targets("Bob"))
    end)

    it("isn't ended by a member list that still names them", function()
      local world, presence = listening()
      minutes(world, presence, 4)
      presence:listed({ "Bob", "Cat-Realm" })
      assert.same({}, presence:targets())
    end)

    it("is traced when it starts and ends", function()
      local world, presence = listening()
      presence:whispered("Bob")
      world.advance(180)
      presence:heard("Bob", "one")
      assert.same({
        "peer silent: Bob (no whisper from them for 180 s)",
        "peer heard again: Bob",
      }, { world.lines[#world.lines - 1], world.lines[#world.lines] })
    end)
  end)

  it("traces peers coming and going in the sync trace's words", function()
    local world, presence = withPeers()
    presence:heard("Dan", "one")
    presence:joined("Dan")
    presence:left("Cat")
    presence:notFound("Bob")
    presence:start()
    assert.same({
      "peer added: Bob (member list)",
      "peer added: Cat-Realm (member list)",
      "holding whispers from Dan: not in the member list yet",
      "peer added: Dan (joined the channel)",
      "  delivering 1 held whispers from Dan",
      "peer removed: Cat-Realm (left the channel)",
      "notice: No player named Bob",
      "peer removed: Bob (No player named)",
      "peers cleared (joined the channel)",
    }, world.lines)
  end)
end)
