local load = require("tests.load")

local DAY = 24 * 60 * 60
local HEARTBEAT = 5 * 60

local ELWYNN = { mapId = 1429, x = 0.412, y = 0.655 }

-- A net with the given clients logged in and in one Crew, settled. options
-- maps a name to FakeNet:add options; every client starts in Elwynn Forest
-- unless its options say otherwise.
local function crew(names, options)
  local ns = load()
  local net = ns.FakeNet.new()
  local clients = {}
  for i, name in ipairs(names) do
    local o = options and options[name] or {}
    if o.location == nil and not o.nowhere then o.location = ELWYNN end
    clients[i] = net:add(name, o):login()
  end
  local code = clients[1]:join()
  for i = 2, #clients do clients[i]:join(code) end
  net:run(20)
  return net, clients, ns, code
end

local function character(name, level, extra)
  local c = {
    guid = "Player-0-" .. name, name = name, classFilename = "WARRIOR",
    level = level, xp = 0, maxXp = 1000, zone = "Elwynn Forest", deaths = 0,
  }
  for k, v in pairs(extra or {}) do c[k] = v end
  return c
end

-- Jumps the clock ahead, then lets the Crew settle.
local function skip(net, seconds)
  net:step(net:now() + seconds)
  net:run(5)
end

-- The pin the client's Core shows for another client, or nil.
local function pinFor(client, other)
  for _, pin in ipairs(client.core:mapPins()) do
    if pin.memberId == other.memberId then return pin end
  end
  return nil
end

describe("Map pins", function()
  it("show where another Member was last seen, and never yourself", function()
    local _, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]

    local pin = pinFor(a, b)
    assert.same({
      memberId = b.memberId,
      displayName = "Bob",
      name = "Bob",
      fullName = "Bob",
      classFilename = "WARRIOR",
      level = 10,
      mapId = 1429,
      x = 0.412,
      y = 0.655,
      zone = "Elwynn Forest",
      figure = "WARRIOR",
      size = "medium",
      online = true,
      sinceSeen = 20,
      lastSeenText = "online",
    }, pin)
    assert.is_nil(pinFor(a, a))
    assert.equal(1, #a.core:mapPins())
  end)

  it("name a Character by first and last name once a last name is shared", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    b:play({ lastName = "Stormgaard" })
    -- A last name alone goes out with the next unhurried DATA.
    net:run(70)

    local pin = pinFor(a, b)
    assert.equal("Bob", pin.name)
    assert.equal("Bob Stormgaard", pin.fullName)
    assert.equal("Bob Stormgaard", a:rowFor(b).fullName)
  end)

  it("round the position to 0.1%, inside the map", function()
    local _, clients = crew({ "Ann", "Bob", "Cid" }, {
      Bob = { location = { mapId = 1429, x = 0.123456, y = 0.98765 } },
      Cid = { location = { mapId = 1429, x = -0.002, y = 1.004 } },
    })
    local pin = pinFor(clients[1], clients[2])
    assert.equal(0.123, pin.x)
    assert.equal(0.988, pin.y)
    pin = pinFor(clients[1], clients[3])
    assert.same({ 0, 1 }, { pin.x, pin.y })
  end)

  it("follow a Member who moves, with a small WHERE and no DATA", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]

    local mark = #net.wire
    local moved = a:count("moved")
    b:move({ mapId = 1429, x = 0.5, y = 0.5 })
    net:run(15)
    assert.same({}, net:sent(mark, b.name, "DATA"))
    local where = net:sent(mark, b.name, "WHERE")
    assert.equal(1, #where)
    assert.same({ 1429, 0.5, 0.5 }, { where[1].mapId, where[1].x, where[1].y })
    assert.equal(0.5, pinFor(a, b).x)
    assert.is_true(a:count("moved") > moved)
  end)

  it("send no WHERE while standing still, or with no one else online", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]

    local mark = #net.wire
    net:run(120)
    assert.same({}, net:sent(mark, nil, "WHERE"))

    a:logout()
    net:run(5)
    mark = #net.wire
    b:move({ mapId = 1429, x = 0.6, y = 0.6 })
    net:run(30)
    assert.same({}, net:sent(mark, b.name, "WHERE"))
  end)

  it("send no WHERE for a shuffle on the spot", function()
    local net, clients = crew({ "Ann", "Bob" })
    local b = clients[2]

    local mark = #net.wire
    b:move({ mapId = 1429, x = 0.4125, y = 0.6555 })
    net:run(30)
    assert.same({}, net:sent(mark, b.name, "WHERE"))
  end)

  it("send a WHERE at most every 10 s while moving, less often in a bigger Crew", function()
    local function wheres(names)
      local net, clients = crew(names)
      local b = clients[2]
      local mark = #net.wire
      for i = 1, 60 do
        b:move({ mapId = 1429, x = 0.1 + i * 0.01, y = 0.5 })
        net:run(1)
      end
      return #net:sent(mark, b.name, "WHERE")
    end
    local few = wheres({ "Ann", "Bob" })
    assert.is_true(few >= 5 and few <= 6, few)
    -- Five others online: one every 15 s.
    local many = wheres({ "Ann", "Bob", "Cid", "Dot", "Eve", "Fay" })
    assert.is_true(many >= 3 and many <= 4, many)
  end)

  it("send no WHERE while paused", function()
    local net, clients = crew({ "Ann", "Bob" })
    local b = clients[2]
    b.core:setPaused(true)

    local mark = #net.wire
    b:move({ mapId = 1429, x = 0.5, y = 0.5 })
    net:run(30)
    assert.same({}, net:sent(mark, b.name, "WHERE"))
  end)

  it("give way to a newer record, and the record's spot rides the heartbeat", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]

    b:move({ mapId = 1429, x = 0.5, y = 0.5 })
    net:run(15)
    b:move({ mapId = 1436, x = 0.3, y = 0.4 })
    b:play({ zone = "Westfall" })
    net:run(12)
    assert.same({ 1436, 0.3, 0.4 }, { pinFor(a, b).mapId, pinFor(a, b).x, pinFor(a, b).y })

    -- A Member who joins later gets the spot from the record alone.
    local c = net:add("Cid", { location = ELWYNN }):login()
    c:join(a.core:crew().code)
    net:run(20)
    assert.same({ 1436, 0.3, 0.4 }, { pinFor(c, b).mapId, pinFor(c, b).x, pinFor(c, b).y })
  end)

  it("keep the last spot heard outside when a Member enters an instance", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]

    b:move({ mapId = 1436, x = 0.42, y = 0.71 })
    net:run(4)
    b:move({ instance = "The Deadmines" })
    b:play({ zone = "The Deadmines" })
    net:run(12)
    local pin = pinFor(a, b)
    assert.equal("The Deadmines", pin.instance)
    assert.same({ 1436, 0.42, 0.71 }, { pin.mapId, pin.x, pin.y })
  end)

  it("ignore a WHERE that's malformed, for another Character, or from a removed Member", function()
    local net, clients, ns = crew({ "Ann", "Bob", "Cid" })
    local a, b, c = clients[1], clients[2], clients[3]
    local function where(from, fields)
      local message = { type = "WHERE", from = from.memberId, character = from.character.guid,
        mapId = 1436, x = 0.2, y = 0.3, at = net:now() }
      for k, v in pairs(fields or {}) do message[k] = v end
      a.core:received(ns.Codec.encode(message))
    end
    where(b, { x = 1.5 })
    where(b, { mapId = "Westfall" })
    where(b, { at = "now" })
    where(b, { character = "Player-0-Someone" })
    assert.same({ 1429, 0.412, 0.655 }, { pinFor(a, b).mapId, pinFor(a, b).x, pinFor(a, b).y })

    a.core:removeMember(c.memberId)
    where(c)
    assert.is_nil(pinFor(a, c))

    where(b)
    assert.same({ 1436, 0.2, 0.3 }, { pinFor(a, b).mapId, pinFor(a, b).x, pinFor(a, b).y })
  end)

  it("are refreshed when a zone change goes out", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]

    b:move({ mapId = 1436, x = 0.3, y = 0.4 })
    b:play({ zone = "Westfall" })
    net:run(12)
    local pin = pinFor(a, b)
    assert.equal("Westfall", pin.zone)
    assert.same({ 1436, 0.3, 0.4 }, { pin.mapId, pin.x, pin.y })
  end)

  it("keep the last known spot while the position can't be read", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]

    b:move(nil)
    b:play({ zone = "Duskwood" })
    net:run(12)
    local pin = pinFor(a, b)
    assert.equal("Duskwood", pin.zone)
    assert.same({ 1429, 0.412, 0.655 }, { pin.mapId, pin.x, pin.y })
  end)

  it("keep the last open-world spot inside an instance, and name the instance", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]

    b:move({ instance = "The Deadmines" })
    b:play({ zone = "The Deadmines" })
    net:run(12)
    local pin = pinFor(a, b)
    assert.equal("The Deadmines", pin.instance)
    assert.same({ 1429, 0.412, 0.655 }, { pin.mapId, pin.x, pin.y })

    b:move({ mapId = 1436, x = 0.42, y = 0.71 })
    b:play({ zone = "Westfall" })
    net:run(12)
    pin = pinFor(a, b)
    assert.is_nil(pin.instance)
    assert.same({ 1436, 0.42, 0.71 }, { pin.mapId, pin.x, pin.y })
  end)

  it("keep each Character's own spot", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]

    -- Bob relogs onto an Alt in Westfall, then back onto his Main.
    b.character = character("Bobalt", 12, { zone = "Westfall" })
    b:move({ mapId = 1436, x = 0.3, y = 0.4 })
    b:play()
    net:run(12)
    assert.equal("Bobalt", pinFor(a, b).name)
    assert.equal(1436, pinFor(a, b).mapId)

    b.character = character("Bob", 10)
    b:move(nil)
    b:play()
    net:run(HEARTBEAT)
    assert.equal("Bob", pinFor(a, b).name)
    assert.same({ 1429, 0.412, 0.655 }, { pinFor(a, b).mapId, pinFor(a, b).x, pinFor(a, b).y })
  end)

  it("show an offline Member at their Main, faded by being offline", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]

    b.core:setMain(b.character.guid)
    b.character = character("Bobalt", 12, { zone = "Westfall" })
    b:move({ mapId = 1436, x = 0.3, y = 0.4 })
    b:play()
    net:run(12)
    assert.equal("Bobalt", pinFor(a, b).name)

    b:logout()
    net:run(5)
    local pin = pinFor(a, b)
    assert.is_false(pin.online)
    assert.equal("Bob", pin.name)
    assert.equal(1429, pin.mapId)
    assert.equal(17, pin.sinceSeen)
  end)

  it("leave out Members who left, were removed, or whose Characters are hidden", function()
    local net, clients = crew({ "Ann", "Bob", "Cid", "Dot" })
    local a, b, c, d = clients[1], clients[2], clients[3], clients[4]

    b.core:leaveCrew()
    a.core:removeMember(c.memberId)
    net:run(5)
    assert.is_nil(pinFor(a, b))
    assert.is_nil(pinFor(a, c))
    assert.is_table(pinFor(a, d))

    d:logout()
    skip(net, 31 * DAY)
    assert.is_nil(pinFor(a, d))
  end)

  it("leave out a Member whose record has no spot, though their row shows", function()
    local _, clients = crew({ "Ann", "Bob" }, { Bob = { nowhere = true } })
    local a, b = clients[1], clients[2]
    assert.is_table(a:rowFor(b))
    assert.is_nil(pinFor(a, b))
  end)

  it("reach a third Member through a relay", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    b:logout()
    net:run(5)

    local c = net:add("Cid", { location = ELWYNN }):login()
    c:join(a.core:crew().code)
    net:run(20)
    local pin = pinFor(c, b)
    assert.is_table(pin)
    assert.same({ 1429, 0.412, 0.655 }, { pin.mapId, pin.x, pin.y })
  end)

  it("show the Member's Camp figure only while the Camp is on", function()
    local _, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    assert.equal("WARRIOR", pinFor(a, b).figure)
    a.core:setSetting("camp", false)
    assert.is_nil(pinFor(a, b).figure)
  end)

  it("carry the map pin size setting", function()
    local _, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    a.core:setSetting("mapPinSize", "small")
    assert.equal("small", pinFor(a, b).size)
  end)

  it("are all gone while the map setting is off", function()
    local _, clients = crew({ "Ann", "Bob" })
    local a = clients[1]
    a.core:setSetting("mapPins", false)
    assert.same({}, a.core:mapPins())
    a.core:setSetting("mapPins", true)
    assert.equal(1, #a.core:mapPins())
  end)

  it("drop a record whose spot is off the map", function()
    local net, clients, ns = crew({ "Ann" })
    local a = clients[1]
    local function send(id, spot)
      local c = character(id, 10)
      for k, v in pairs(spot) do c[k] = v end
      c.guid, c.lastPlayed = "Player-0-" .. id, net:now()
      a.core:received(ns.Codec.encode({
        type = "DATA", from = id,
        records = { { id = id, version = net:now(), displayName = id, characters = { [c.guid] = c } } },
      }))
    end
    send("offmap01", { mapId = 1429, x = 1.5, y = 0.2 })
    send("onmap001", { mapId = 1429, x = 0.5, y = 0.2, instance = "The Deadmines" })
    local pins = a.core:mapPins()
    assert.equal(1, #pins)
    assert.equal("onmap001", pins[1].memberId)
    assert.equal("The Deadmines", pins[1].instance)
  end)
end)
