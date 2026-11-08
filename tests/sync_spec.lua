local load = require("tests.load")

-- A random() that always gives the same value, to fix who replies first.
local function fixed(value)
  return function() return value end
end

-- A net with the given clients logged in and in one Crew, settled.
local function crew(names, options)
  local ns = load()
  local net = ns.FakeNet.new()
  local clients = {}
  for i, name in ipairs(names) do
    clients[i] = net:add(name, options and options[name]):login()
  end
  local code = clients[1]:join()
  for i = 2, #clients do clients[i]:join(code) end
  net:run(20)
  return net, clients, ns, code
end

-- The messages on the wire since `from` (an index into net.wire), decoded,
-- each with the sender's name.
local function sentSince(net, _, from, name, kind)
  return net:sent(from, name, kind)
end

describe("Two Members", function()
  it("see each other's row within one DIGEST round", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]

    local row = a:rowFor(b)
    assert.is_table(row)
    assert.equal("Bob", row.name)
    assert.equal("Bob", row.displayName)
    assert.is_true(row.online)
    assert.is_table(b:rowFor(a))
    assert.is_true(b:rowFor(a).online)
    assert.is_false(a.core:crew().alone)
    assert.is_true(a:count("changed") > 0)
    assert.is_number(net:now())
  end)

  it("see a ding right away, but a zone change only after 10 seconds", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]

    a:play({ level = 11 })
    net:run(2)
    assert.equal(11, b:rowFor(a).level)

    a:play({ zone = "Westfall" })
    net:run(5)
    assert.equal("Elwynn Forest", b:rowFor(a).zone)
    a:play({ zone = "Duskwood" })
    net:run(7)
    assert.equal("Duskwood", b:rowFor(a).zone)
  end)

  it("sends a death right away, and XP along with the next send", function()
    local net, clients, ns = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]

    local mark = #net.wire
    a:play({ xp = 500 })
    net:run(5)
    assert.same({}, sentSince(net, ns, mark, "Ann", "DATA"))
    assert.equal(0, b:rowFor(a).xp)

    a:play({ deaths = 1 })
    net:run(2)
    assert.equal(500, b:rowFor(a).xp)
  end)

  it("send XP and gold within a minute, without waiting for the heartbeat", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]

    net:run(5 * 60)
    a:play({ xp = 500, money = 12345 })
    net:run(61)
    assert.equal(500, b:rowFor(a).xp)
    assert.equal(12345, b:rowFor(a).money)
  end)

  it("send a heartbeat every 5 minutes, so neither goes offline", function()
    local net, clients, ns = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]

    local mark = #net.wire
    net:run(30 * 60)
    local beats = 0
    for _, message in ipairs(sentSince(net, ns, mark, "Ann")) do
      if message.type == "DATA" then beats = beats + 1 end
    end
    assert.is_true(beats >= 5 and beats <= 7, "heartbeats: " .. beats)
    assert.is_true(b:rowFor(a).online)
    assert.is_true(a:rowFor(b).online)
  end)

  it("ignore their own messages echoed back by the channel", function()
    local net, clients, ns = crew({ "Ann", "Bob" })
    local a = clients[1]
    net:run(40)
    local events = #a.events
    local mark = #net.wire
    for _, item in ipairs(net.wire) do
      if item.from == "Ann" then a.core:received(item.message) end
    end
    net:run(10)
    assert.equal(events, #a.events)
    assert.same({}, sentSince(net, ns, mark, "Ann"))
  end)

  it("mark a Member offline the moment they leave the channel", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]

    b:logout()
    net:run(1)
    assert.is_false(a:rowFor(b).online)
    assert.equal("Bob", a:rowFor(b).name)
  end)

  it("flip someone who goes quiet to offline after 12 minutes", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]

    b:logout(true)
    net:run(11 * 60)
    assert.is_true(a:rowFor(b).online)
    local changed = a:count("changed")
    net:run(2 * 60)
    assert.is_false(a:rowFor(b).online)
    assert.equal(changed + 1, a:count("changed"))
  end)

  it("send nothing at logout", function()
    local net, clients = crew({ "Ann", "Bob" })
    local mark = #net.wire
    clients[2]:logout()
    net:run(1)
    assert.equal(mark, #net.wire)
  end)
end)

describe("Gossip", function()
  it("lets C learn A's ding from B while D stays quiet", function()
    local net, clients, ns = crew({ "Ann", "Bob", "Cat", "Dan" }, {
      Bob = { random = fixed(0) },
      Dan = { random = fixed(0.99) },
    })
    local a, c = clients[1], clients[3]

    c:logout()
    net:run(1)
    a:play({ level = 11 })
    net:run(2)
    a:logout()
    net:run(1)

    local mark = #net.wire
    c:login()
    net:run(10)

    assert.equal(11, c:rowFor(a).level)
    assert.is_false(c:rowFor(a).online)
    assert.same({}, sentSince(net, ns, mark, "Dan", "DATA"))
    local fromB = sentSince(net, ns, mark, "Bob", "DATA")
    assert.equal(1, #fromB)
    assert.equal("DATA", fromB[1].type)
  end)

  it("drops messages during lockdown and catches up with a DIGEST after it", function()
    local net, clients, ns = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]

    b:lockdown(true)
    a:play({ level = 11 })
    net:run(5)
    assert.equal(10, b:rowFor(a).level)

    local mark = #net.wire
    b:lockdown(false)
    local fromB = sentSince(net, ns, mark, "Bob")
    assert.equal(1, #fromB)
    assert.equal("DIGEST", fromB[1].type)
    net:run(6)
    assert.equal(11, b:rowFor(a).level)
  end)

  it("sends changes made during lockdown after one DIGEST once it clears", function()
    local net, clients, ns = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]

    a:lockdown(true)
    local mark = #net.wire
    a:play({ level = 11 })
    net:run(30)
    assert.same({}, sentSince(net, ns, mark, "Ann"))

    a:lockdown(false)
    net:run(1)
    assert.equal(11, b:rowFor(a).level)
    local fromA = sentSince(net, ns, mark, "Ann")
    assert.equal("DIGEST", fromA[1].type)
    assert.equal("DATA", fromA[2].type)
  end)

  it("recovers a lost send at the next up()", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]

    net.drop = function(_, from, to) return from == "Ann" and to == "Bob" end
    a:play({ level = 11 })
    net:run(2)
    net.drop = nil
    assert.equal(10, b:rowFor(a).level)

    a:relink()
    net:run(15)
    assert.equal(11, b:rowFor(a).level)
  end)

  it("keeps sync through a reload", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]

    a:reload()
    net:run(5)
    assert.is_true(a:rowFor(b).online)
    a:play({ level = 11 })
    net:run(2)
    assert.equal(11, b:rowFor(a).level)
  end)

  it("lets a crashed Member's next version win over what was lost", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]

    a:reload()
    a:play({ level = 11 })
    net:run(2)
    a:crash()
    net:run(60)
    a:play({ level = 12 }):login()
    net:run(5)
    assert.equal(12, b:rowFor(a).level)

    -- And a crash that lost a ding: the game still knows the real level.
    a:play({ level = 13 })
    net:run(2)
    a:crash()
    net:run(60)
    a:login()
    net:run(5)
    assert.equal(13, b:rowFor(a).level)
  end)

  it("keeps a paused Member silent and offline, and catches up on resume", function()
    local net, clients, ns = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]

    a.core:setPaused(true)
    assert.is_true(a.core:isPaused())
    local mark = #net.wire
    a:play({ level = 11 })
    net:run(13 * 60)
    assert.same({}, sentSince(net, ns, mark, "Ann"))
    assert.is_false(b:rowFor(a).online)
    assert.equal(10, b:rowFor(a).level)
    b:play({ level = 14 })
    net:run(2)
    assert.equal(14, a:rowFor(b).level)

    a:reload()
    assert.is_true(a.core:isPaused())
    a.core:setPaused(false)
    net:run(5)
    assert.equal(11, b:rowFor(a).level)
    assert.is_true(b:rowFor(a).online)
  end)

  it("fits ten Members with three Characters each in one DIGEST", function()
    local names = {}
    for i = 1, 10 do names[i] = "Member" .. i end
    local net, clients, ns = crew(names)
    for _, client in ipairs(clients) do
      for n = 1, 2 do
        net:run(1)
        client:play({ guid = client.character.guid .. "-" .. n, name = client.name .. "alt" .. n })
      end
    end
    net:run(60)

    local first = clients[1]
    for i = 2, 10 do
      local row = first:rowFor(clients[i])
      assert.is_table(row)
      assert.equal(2, #row.alts)
    end

    local mark = #net.wire
    first:relink()
    local digest = sentSince(net, ns, mark, first.name)[1]
    assert.equal("DIGEST", digest.type)
    local entries = 0
    for _ in pairs(digest.versions) do entries = entries + 1 end
    assert.equal(10, entries)
    assert.is_true(digest.size <= 255, "DIGEST is " .. digest.size .. " bytes")
  end)

  it("shows one out of date notice for messages from a newer BFF", function()
    local _, clients, ns = crew({ "Ann", "Bob" })
    local a = clients[1]
    local newer = (ns.Codec.PROTOCOL + 1) .. "|whatever"
    a.core:received(newer)
    a.core:received(newer)
    assert.equal(1, a:count("notice", "outOfDate"))
  end)

  it("ignores garbage", function()
    local _, clients = crew({ "Ann", "Bob" })
    local a = clients[1]
    local rows = a.core:rows()
    a.core:received("1|junk")
    a.core:received("")
    assert.same(rows, a.core:rows())
  end)
end)

-- The number of entries in a DIGEST.
local function size(versions)
  local n = 0
  for _ in pairs(versions) do n = n + 1 end
  return n
end

-- A Crew of `count` Members, Member1 to MemberN.
local function bigCrew(count, options)
  local names = {}
  for i = 1, count do names[i] = "Member" .. i end
  return crew(names, options)
end

describe("Lost and failed sends", function()
  it("bring a lost ding to the friend who missed it within a minute", function()
    local net, clients = crew({ "Ann", "Bob", "Cat" })
    local a, b, c = clients[1], clients[2], clients[3]
    net:run(60)

    local lost = 0
    net.drop = function(_, from, to)
      if from == "Ann" and to == "Bob" then
        lost = lost + 1
        return true
      end
    end
    a:play({ level = 11 })
    net:run(2)
    net.drop = nil
    assert.equal(1, lost)
    assert.equal(11, c:rowFor(a).level)
    assert.equal(10, b:rowFor(a).level)

    net:run(60)
    assert.equal(11, b:rowFor(a).level)
  end)

  it("follow own DATA with a DIGEST 20 to 30 seconds later", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a = clients[1]
    net:run(120)

    local mark = #net.wire
    a:play({ level = 11 })
    net:run(31)
    local digests = net:sent(mark, "Ann", "DIGEST")
    assert.equal(1, #digests)
    local data = net:sent(mark, "Ann", "DATA")
    assert.equal(1, #data)
  end)

  it("send a DIGEST about every minute while the link is up", function()
    local net = crew({ "Ann", "Bob" })
    net:run(120)
    local mark = #net.wire
    net:run(10 * 60)
    local digests = net:sent(mark, "Ann", "DIGEST")
    assert.is_true(#digests >= 9 and #digests <= 12, "DIGESTs: " .. #digests)
    for _, digest in ipairs(digests) do assert.is_nil(digest.to) end
  end)

  it("keep a failed send to one friend from stalling the others", function()
    local net, clients = crew({ "Ann", "Bob", "Cat" })
    local a, b, c = clients[1], clients[2], clients[3]
    net:run(60)

    -- Cat logs in having missed Ann's ding, so Ann owes Cat DATA; then a
    -- send from Ann to Bob fails.
    c:logout()
    net:run(1)
    a:play({ level = 11 })
    net:run(2)
    c:login()
    local failed = 0
    net.fail = function(_, from, to)
      if from == "Ann" and to == "Bob" and failed == 0 then
        failed = 1
        return true
      end
    end
    a:play({ deaths = 1 })
    net:run(2)
    net.fail = nil
    assert.equal(1, failed)
    assert.equal(0, b:rowFor(a).deaths)

    local mark = #net.wire
    net:run(10)
    -- Cat still got what Ann owed, and Bob a DIGEST of his own that fetched
    -- the death.
    assert.equal(11, c:rowFor(a).level)
    assert.equal(1, c:rowFor(a).deaths)
    assert.equal(1, b:rowFor(a).deaths)
    local toBob = {}
    for _, digest in ipairs(net:sent(mark, "Ann", "DIGEST")) do
      if digest.to then toBob[#toBob + 1] = digest.to end
    end
    assert.same({ "Bob" }, toBob)
  end)

  it("send a friend whose sends keep failing at most one DIGEST of their own a minute", function()
    local net, clients = crew({ "Ann", "Bob", "Cat" })
    local a, c = clients[1], clients[3]
    net:run(60)
    net.fail = function(_, from, to) return from == "Ann" and to == "Bob" end

    local mark = #net.wire
    net:run(10 * 60)
    local own = 0
    for _, digest in ipairs(net:sent(mark, "Ann", "DIGEST")) do
      if digest.to == "Bob" then own = own + 1 end
    end
    assert.is_true(own >= 1 and own <= 10, "DIGESTs to Bob: " .. own)
    a:play({ level = 11 })
    net:run(2)
    assert.equal(11, c:rowFor(a).level)
  end)

  it("send no DIGEST of their own to a friend who logged out", function()
    local net, clients = crew({ "Ann", "Bob", "Cat" })
    local b = clients[2]
    net:run(60)
    net.fail = function(_, from, to) return from == "Ann" and to == "Bob" end
    clients[1]:play({ level = 11 })
    net:run(1)
    net.fail = nil
    b:logout()
    local mark = #net.wire
    net:run(10)
    for _, digest in ipairs(net:sent(mark, "Ann", "DIGEST")) do assert.is_nil(digest.to) end
  end)
end)

describe("In a Crew of more than ten Members", function()
  it("every record is listed in some DIGEST within two rounds", function()
    local net, clients = bigCrew(14)
    local first = clients[1]
    net:run(120)

    local mark = #net.wire
    net:run(2 * 66)
    local listed, rounds = {}, 0
    for _, digest in ipairs(net:sent(mark, first.name, "DIGEST")) do
      rounds = rounds + 1
      assert.equal(10, size(digest.versions))
      assert.is_true(digest.partial)
      assert.is_true(digest.size <= 255, "DIGEST is " .. digest.size .. " bytes")
      for id in pairs(digest.versions) do listed[id] = true end
    end
    assert.is_true(rounds >= 2, "rounds: " .. rounds)
    for _, client in ipairs(clients) do
      assert.is_true(listed[client.memberId], client.name .. " never listed")
    end
  end)

  it("records left off a full DIGEST don't make friends send DATA", function()
    local net, clients = bigCrew(14)
    net:run(6 * 60)

    local mark = #net.wire
    net:run(4 * 60)
    for _, data in ipairs(net:sent(mark, nil, "DATA")) do
      local sender
      for _, client in ipairs(clients) do
        if client.name == data.sender then sender = client end
      end
      assert.equal(1, #data.records)
      assert.equal(sender.memberId, data.records[1].id, data.sender .. " sent someone else's record")
    end
  end)

  it("a Member who logs in late still learns every record", function()
    local net, clients = bigCrew(14)
    local late = clients[14]
    late:logout()
    net:run(2)
    for i = 1, 13 do clients[i]:play({ level = 20 + i }) end
    net:run(2)
    late:login()
    net:run(5 * 60)
    for i = 1, 13 do assert.equal(20 + i, late:rowFor(clients[i]).level, clients[i].name) end
  end)
end)

describe("Traffic", function()
  -- Whispers (chunks, one per friend) each Member sends a minute over ten
  -- minutes: the busiest Member's and the whole Crew's. Grinding, one
  -- Member gains XP every 5 s, dings every 2 minutes and changes zone every
  -- 3; idle, nobody plays.
  local function whispersPerMinute(count, grinding)
    local net, clients = bigCrew(count)
    net:run(120)
    local mark = #net.wire
    local grinder = clients[1]
    for second = 1, 10 * 60 do
      if grinding then
        if second % 5 == 0 then grinder:play({ xp = second }) end
        if second % 120 == 0 then grinder:play({ level = grinder.character.level + 1 }) end
        if second % 180 == 0 then grinder:play({ zone = "Zone" .. second }) end
      end
      net:step()
    end
    local busiest, total = 0, 0
    for _, client in ipairs(clients) do
      local whispers = 0
      for _, message in ipairs(net:sent(mark, client.name)) do
        local chunks = message.size <= 255 and 1 or math.ceil(message.size / 254)
        whispers = whispers + chunks * (message.to and 1 or count - 1)
      end
      busiest = math.max(busiest, whispers / 10)
      total = total + whispers / 10
    end
    return busiest, total
  end

  for _, count in ipairs({ 4, 6 }) do
    it(("stays well under the throttle in a Crew of %d"):format(count), function()
      for _, grinding in ipairs({ false, true }) do
        local busiest, total = whispersPerMinute(count, grinding)
        -- The server allows about one addon message a second per prefix
        -- (and may not count whispers at all outside instances).
        assert.is_true(busiest < 30, ("busiest Member: %.1f whispers a minute"):format(busiest))
        if os.getenv("BFF_TRAFFIC") then
          print(("Crew of %d, %s: busiest Member %.1f whispers/min, Crew %.1f"):format(
            count, grinding and "grinding" or "idle", busiest, total))
        end
      end
    end)
  end
end)

-- Gossip as an older BFF had it (tests/fixtures/legacy_gossip.lua).
local function legacyGossip()
  local legacy = {}
  assert(loadfile("tests/fixtures/legacy_gossip.lua"))("BFF", legacy)
  return legacy.Gossip
end

describe("A Crew with a Member on an older BFF", function()
  it("syncs both ways, and a lost ding still arrives within a minute", function()
    local net, clients = crew({ "Ann", "Bob", "Cat" }, { Bob = { gossip = legacyGossip() } })
    local a, b, c = clients[1], clients[2], clients[3]
    net:run(60)

    a:play({ level = 11 })
    b:play({ level = 12 })
    net:run(3)
    assert.equal(11, b:rowFor(a).level)
    assert.equal(12, a:rowFor(b).level)
    assert.equal(12, c:rowFor(b).level)

    -- Lost from the older client to Ann, and from Ann to the older client.
    net.drop = function(_, from, to)
      return (from == "Bob" and to == "Ann") or (from == "Ann" and to == "Bob")
    end
    a:play({ level = 13 })
    b:play({ level = 14 })
    net:run(2)
    net.drop = nil
    assert.equal(11, b:rowFor(a).level)
    assert.equal(12, a:rowFor(b).level)
    net:run(60)
    assert.equal(13, b:rowFor(a).level)
    assert.equal(14, a:rowFor(b).level)
  end)

  it("syncs in a Crew of more than ten Members", function()
    local old = legacyGossip()
    local net, clients = bigCrew(13, { Member13 = { gossip = old }, Member12 = { gossip = old } })
    local late = clients[13]
    late:logout()
    net:run(2)
    for i = 1, 12 do clients[i]:play({ level = 20 + i }) end
    net:run(2)
    late:login()
    late:play({ level = 40 })
    net:run(5 * 60)
    for i = 1, 12 do
      assert.equal(20 + i, late:rowFor(clients[i]).level, clients[i].name)
      assert.equal(40, clients[i]:rowFor(late).level, clients[i].name)
    end
  end)

  it("keeps traffic under the throttle in a Crew of more than ten", function()
    local old = legacyGossip()
    local net, clients = bigCrew(14, { Member13 = { gossip = old }, Member14 = { gossip = old } })
    net:run(140)
    local mark = #net.wire
    net:run(10 * 60)
    for _, client in ipairs(clients) do
      local whispers = 0
      for _, message in ipairs(net:sent(mark, client.name)) do
        local chunks = message.size <= 255 and 1 or math.ceil(message.size / 254)
        whispers = whispers + chunks * (message.to and 1 or 13)
      end
      assert.is_true(whispers / 10 < 30, ("%s: %.1f whispers a minute"):format(client.name, whispers / 10))
    end
  end)
end)
