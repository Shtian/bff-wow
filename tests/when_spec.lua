local load = require("tests.load")

local HOUR, DAY = 3600, 86400
local WEEK = 7 * DAY
local MONDAY = 1792972800
local EVENING = MONDAY + 20 * HOUR

local function crew(names, options)
  local ns = load()
  local net = ns.FakeNet.new({ clock = EVENING - 120 })
  local clients = {}
  for i, name in ipairs(names) do
    clients[i] = net:add(name, options and options[name]):login()
  end
  local code = clients[1]:join()
  for i = 2, #clients do clients[i]:join(code) end
  net:run(40)
  return net, clients, ns, code
end

local function firstMonday(net)
  net:run(11 * 60 + 5 * 60)
end

local function anotherMonday(net, weeks)
  net:step(EVENING + weeks * WEEK - 30)
  net:run(30 + 11 * 60 + 5 * 60 + 10)
end

local function mondayEvening(view, hours)
  return view.grid[1][21 + (hours or 0)]
end

local function dataSince(net, ns, from, name)
  local count = 0
  for i = from + 1, #net.wire do
    local item = net.wire[i]
    if item.from == name and ns.Codec.decode(item.message).type == "DATA" then count = count + 1 end
  end
  return count
end

describe("The When tab", function()
  it("shows how many Members usually play each hour, from records synced across the Crew", function()
    local net, clients = crew({ "Ann", "Bob", "Cleo" })
    local a, b = clients[1], clients[2]
    firstMonday(net)
    local view = b.core:playTimes()
    assert.equal(0, mondayEvening(view))
    assert.is_true(view.empty)
    assert.equal("The Crew", view.title)
    assert.equal("How many of the 3 Members usually play each hour: in 2 of the last 4 weeks. Your local time.",
      view.intro)
    assert.equal("After 2 weeks of play, the hours the Crew usually plays show up here.", view.note)
    assert.equal(1, mondayEvening(b.core:playTimes(a.memberId)))

    anotherMonday(net, 1)
    view = b.core:playTimes()
    assert.equal(3, mondayEvening(view))
    assert.equal(3, view.max)
    assert.is_false(view.empty)
    assert.is_nil(view.note)
    assert.equal(0, view.grid[1][23])
    assert.equal(0, view.grid[2][21])
    local ann = b.core:playTimes(a.memberId)
    assert.equal(2, mondayEvening(ann))
    assert.equal("Ann", ann.displayName)
    assert.equal(4, ann.max)
    assert.equal("Ann", ann.title)
    assert.equal("How many of the last 4 weeks Ann played each hour. Your local time.", ann.intro)
    assert.is_nil(ann.note)
    local you = b.core:playTimes(b.memberId)
    assert.equal("You", you.title)
    assert.equal("How many of the last 4 weeks you played each hour. Your local time.", you.intro)
  end)

  it("counts only the Members your Roster shows, not Left or Removed ones", function()
    local net, clients = crew({ "Ann", "Bob", "Cleo" })
    local a, b, c = clients[1], clients[2], clients[3]
    firstMonday(net)
    anotherMonday(net, 1)
    assert.equal(3, mondayEvening(a.core:playTimes()))

    a.core:removeMember(b.memberId)
    assert.equal(2, mondayEvening(a.core:playTimes()))
    assert.equal(2, a.core:playTimes().max)
    assert.is_nil(a.core:playTimes(b.memberId))

    c.core:leaveCrew()
    net:run(3)
    assert.equal(1, mondayEvening(a.core:playTimes()))
    assert.is_nil(a.core:playTimes(c.memberId))
  end)

  it("shows the grid in the viewer's local time", function()
    local net, clients = crew({ "Ann", "Bob" }, { Bob = { utcOffset = 2 * HOUR } })
    local a, b = clients[1], clients[2]
    firstMonday(net)
    anotherMonday(net, 1)
    assert.equal(2, mondayEvening(b.core:playTimes(), 2))
    assert.equal(0, mondayEvening(b.core:playTimes()))
    assert.equal(2, mondayEvening(b.core:playTimes(a.memberId), 2))
    assert.equal(2, mondayEvening(a.core:playTimes()))
  end)

  it("ages a summary, so a Member who stopped playing fades out", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    firstMonday(net)
    anotherMonday(net, 1)
    b:logout()
    anotherMonday(net, 3)
    assert.equal(2, mondayEvening(a.core:playTimes(b.memberId)))
    anotherMonday(net, 4)
    assert.equal(1, mondayEvening(a.core:playTimes(b.memberId)))
    assert.equal(1, mondayEvening(a.core:playTimes()))
  end)

  it("says when a Member started collecting, for the first week", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    net:run(5 * 60)
    local ann = b.core:playTimes(a.memberId)
    assert.equal(EVENING - 120, ann.collectingSince)
    assert.equal("Collecting since 26 Oct: less than a week of data so far.", ann.note)
    anotherMonday(net, 1)
    assert.is_nil(b.core:playTimes(a.memberId).collectingSince)
  end)

  it("says when a Member played no hour long enough", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    b:logout()
    net:run(3)
    net:step(net:now() + 8 * DAY)
    local bob = a.core:playTimes(b.memberId)
    assert.is_true(bob.empty)
    assert.equal("No hour played for 10 minutes or more in the last 4 weeks.", bob.note)
  end)

  it("keeps records from older clients without Play times, showing no data", function()
    local net, clients, ns = crew({ "Ann", "Bob" })
    local a = clients[1]
    a.core:received(ns.Codec.encode({
      type = "DATA", from = "olderone",
      records = { {
        id = "olderone", version = net:now(), displayName = "Old",
        characters = { ["Player-0-Old"] = {
          guid = "Player-0-Old", name = "Old", level = 10, lastPlayed = net:now(),
        } },
      } },
    }))
    local view = a.core:playTimes("olderone")
    assert.is_true(view.noData)
    assert.equal("Old's BFF doesn't share Play times yet.", view.note)
    assert.equal(0, mondayEvening(view))
    assert.equal(3, a.core:playTimes().max)

    a.core:received(ns.Codec.encode({
      type = "DATA", from = "garbled1",
      records = { {
        id = "garbled1", version = net:now(), displayName = "Garbled",
        playTimes = { since = 1, week = 1, slots = "junk" },
        characters = {},
      } },
    }))
    assert.is_nil(a.core:playTimes("garbled1"))
  end)

  it("rides the next send: Play times changing alone never sends right away", function()
    local net, clients, ns = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    local unseen = b.core:unseen()
    while mondayEvening(a.core:playTimes(a.memberId)) == 0 do net:step() end
    local wire = #net.wire
    net:run(5)
    assert.equal(0, dataSince(net, ns, wire, "Ann"))
    assert.equal(0, mondayEvening(b.core:playTimes(a.memberId)))

    net:run(5 * 60)
    assert.equal(1, mondayEvening(b.core:playTimes(a.memberId)))
    assert.equal(unseen, b.core:unseen())
  end)

  it("doesn't count time twice across a reload", function()
    local net, clients = crew({ "Ann" })
    local a = clients[1]
    net:run(120 - 40 + 5 * 60)
    a:reload()
    net:run(5 * 60 - 1)
    assert.equal(0, mondayEvening(a.core:playTimes(a.memberId)))
    net:run(2)
    assert.equal(1, mondayEvening(a.core:playTimes(a.memberId)))
  end)
end)
