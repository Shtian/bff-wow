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
local function sentSince(net, ns, from, name)
  local messages = {}
  for i = from + 1, #net.wire do
    local item = net.wire[i]
    if name == nil or item.from == name then
      local decoded = ns.Codec.decode(item.message)
      decoded.sender = item.from
      decoded.size = #item.message
      messages[#messages + 1] = decoded
    end
  end
  return messages
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

  it("sends a death right away, and XP only along with the next send", function()
    local net, clients, ns = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]

    local mark = #net.wire
    a:play({ xp = 500 })
    net:run(30)
    assert.same({}, sentSince(net, ns, mark, "Ann"))
    assert.equal(0, b:rowFor(a).xp)

    a:play({ deaths = 1 })
    net:run(2)
    assert.equal(500, b:rowFor(a).xp)
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
    assert.same({}, sentSince(net, ns, mark, "Dan"))
    local fromB = sentSince(net, ns, mark, "Bob")
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

  it("recovers a refused send at the next up()", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]

    net.drop = function(_, from, to) return from == "Ann" and to == "Bob" end
    a:play({ level = 11 })
    net:run(2)
    net.drop = nil
    assert.equal(10, b:rowFor(a).level)

    a:refused()
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
    first:refused()
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
