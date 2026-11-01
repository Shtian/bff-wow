local load = require("tests.load")

local HOUR, DAY = 3600, 86400
local WEEK = 7 * DAY
-- Monday 2026-10-26 00:00 UTC.
local MONDAY = 1792972800
-- Monday 20:00 UTC, the hour the Crew plays in these specs.
local EVENING = MONDAY + 20 * HOUR

-- A net with the given clients logged in and in one Crew, settled shortly
-- before Monday 20:00 UTC. options maps a name to FakeNet:add options.
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

-- Plays this Monday evening, 20:00–20:11 UTC, and stays on until the
-- heartbeat has shared it.
local function firstMonday(net)
  net:run(11 * 60 + 5 * 60)
end

-- Plays the next Monday evening, `weeks` weeks on: everyone online plays
-- 20:00–20:11 UTC, then stays on until the heartbeat has shared it.
local function anotherMonday(net, weeks)
  net:step(EVENING + weeks * WEEK - 30)
  net:run(30 + 11 * 60 + 5 * 60 + 10)
end

-- Monday 20:00 UTC in a grid shifted by `hours`.
local function mondayEvening(view, hours)
  return view.grid[1][21 + (hours or 0)]
end

-- The DATA messages a client put on the wire since `from`.
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
    -- One Monday evening isn't "usually".
    firstMonday(net)
    local view = b.core:playTimes()
    assert.equal(0, mondayEvening(view))
    assert.is_true(view.empty)
    assert.equal(1, mondayEvening(b.core:playTimes(a.memberId)))

    -- Two are, for each of the three Members, counted once each.
    anotherMonday(net, 1)
    view = b.core:playTimes()
    assert.equal(3, mondayEvening(view))
    assert.equal(3, view.max)
    assert.is_false(view.empty)
    assert.equal(0, view.grid[1][23])
    assert.equal(0, view.grid[2][21])
    local ann = b.core:playTimes(a.memberId)
    assert.equal(2, mondayEvening(ann))
    assert.equal("Ann", ann.displayName)
    assert.equal(4, ann.max)
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
    -- 20:00 UTC is 22:00 for Bob.
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
    -- Two weeks on, Bob's last two Mondays still count; three weeks on, one does.
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
    assert.equal(EVENING - 120, b.core:playTimes(a.memberId).collectingSince)
    anotherMonday(net, 1)
    assert.is_nil(b.core:playTimes(a.memberId).collectingSince)
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
    assert.equal(0, mondayEvening(view))
    assert.equal(3, a.core:playTimes().max)

    -- Malformed Play times aren't kept.
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
    -- Play until Ann's own record has her first ten minutes at 20:00.
    while mondayEvening(a.core:playTimes(a.memberId)) == 0 do net:step() end
    local wire = #net.wire
    net:run(5)
    assert.equal(0, dataSince(net, ns, wire, "Ann"))
    assert.equal(0, mondayEvening(b.core:playTimes(a.memberId)))

    -- The heartbeat brings it.
    net:run(5 * 60)
    assert.equal(1, mondayEvening(b.core:playTimes(a.memberId)))
    -- No Feed entry for it.
    assert.equal(unseen, b.core:unseen())
  end)

  it("doesn't count time twice across a reload", function()
    local net, clients = crew({ "Ann" })
    local a = clients[1]
    -- Up to 20:05, a reload, then to 20:09:59: not quite ten minutes.
    net:run(120 - 40 + 5 * 60)
    a:reload()
    net:run(5 * 60 - 1)
    assert.equal(0, mondayEvening(a.core:playTimes(a.memberId)))
    net:run(2)
    assert.equal(1, mondayEvening(a.core:playTimes(a.memberId)))
  end)
end)
