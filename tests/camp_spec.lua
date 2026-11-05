local load = require("tests.load")

local DAY = 24 * 60 * 60
local COLUMNS = 300

local function character(name, extra)
  local c = {
    guid = "Player-0-" .. name, name = name, classFilename = "WARRIOR",
    level = 10, xp = 0, maxXp = 1000, zone = "Elwynn Forest", deaths = 0,
  }
  for k, v in pairs(extra or {}) do c[k] = v end
  return c
end

-- A net with the given clients logged in and in one Crew, settled. options
-- maps a name to FakeNet:add options.
local function crew(names, options)
  local ns = load()
  local net = ns.FakeNet.new()
  local clients = {}
  for i, name in ipairs(names) do
    local o = options and options[name] or {}
    o.character = o.character or character(name)
    clients[i] = net:add(name, o):login()
  end
  local code = clients[1]:join()
  for i = 2, #clients do clients[i]:join(code) end
  net:run(40)
  return net, clients, ns, code
end

-- Jumps the clock ahead, then lets the Crew settle.
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

local function gravesOf(view, client)
  local list = {}
  for _, grave in ipairs(view.graves) do
    if grave.memberId == client.memberId then list[#list + 1] = grave end
  end
  return list
end

-- Every entry in the client's feed(), newest first.
local function entries(client)
  local all = {}
  for _, day in ipairs(client.core:feed().days) do
    for _, entry in ipairs(day.entries) do all[#all + 1] = entry end
  end
  return all
end

local function entry(client, text)
  for _, candidate in ipairs(entries(client)) do
    if candidate.text == text then return candidate end
  end
  error(("%s has no entry %q"):format(client.name, text))
end

local layout = load().Core.CAMP_LAYOUT

-- Every figure and grave in the view as { left, right } in art pixels.
local function spans(view)
  local list = {}
  for _, actor in ipairs(view.actors) do list[#list + 1] = { actor.x, actor.x + actor.width } end
  for _, grave in ipairs(view.graves) do
    list[#list + 1] = { grave.x, grave.x + layout.grave }
  end
  return list
end

describe("The Camp", function()
  it("seats online Members by the fire and puts offline ones to sleep", function()
    local net, clients = crew({ "Ann", "Bob", "Cid" })
    local a, b, c = clients[1], clients[2], clients[3]
    local view = a.core:camp(COLUMNS)
    assert.equal("seated", actorFor(view, b).pose)
    assert.equal("seated", actorFor(view, c).pose)

    b:logout()
    net:run(2)
    view = a.core:camp(COLUMNS)
    assert.equal("asleep", actorFor(view, b).pose)

    -- Cid goes quiet without leaving the channel: asleep after 12 minutes.
    c.ticks = false
    c:lockdown(true)
    skip(net, 13 * 60)
    assert.equal("asleep", actorFor(a.core:camp(COLUMNS), c).pose)

    c:lockdown(false)
    c.ticks = true
    net:run(10)
    assert.equal("seated", actorFor(a.core:camp(COLUMNS), c).pose)
  end)

  it("always seats you, labelled You, and others by display name", function()
    local net, clients = crew({ "Ann", "Bob" }, { Bob = { character = character("Bobby", { classFilename = "MAGE" }) } })
    local a, b = clients[1], clients[2]
    a:lockdown(true)
    skip(net, 20 * 60)
    local view = a.core:camp(COLUMNS)
    local you = view.actors[1]
    assert.same({ "seated", "You", true }, { you.pose, you.label, you.you })
    local bob = actorFor(view, b)
    assert.equal("Bob", bob.label)
    assert.equal("MAGE", bob.classFilename)
    assert.is_nil(bob.you)
  end)

  it("leaves out Members who left, were Removed or are hidden after 30 days", function()
    local net, clients = crew({ "Ann", "Bob", "Cid", "Dee" })
    local a, b, c, d = clients[1], clients[2], clients[3], clients[4]
    assert.equal(4, #a.core:camp(COLUMNS).actors)
    b.core:leaveCrew()
    net:run(10)
    a.core:removeMember(c.memberId)
    d:logout()
    skip(net, 31 * DAY)
    local view = a.core:camp(COLUMNS)
    assert.equal(1, #view.actors)
    assert.is_true(view.actors[1].you)
  end)

  it("shows a Member once, with the class of the Character the Roster shows", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    b:play(character("Bobalt", { guid = "Player-0-Bobalt", classFilename = "PRIEST" }))
    net:run(15)
    local view = a.core:camp(COLUMNS)
    assert.equal(2, #view.actors)
    assert.equal("PRIEST", actorFor(view, b).classFilename)

    b:logout()
    net:run(2)
    assert.equal(a:rowFor(b).classFilename, actorFor(a.core:camp(COLUMNS), b).classFilename)
  end)

  it("fits online Members first, then the most recently seen sleepers, and counts the rest", function()
    local names = { "Ann", "Bob", "Cid", "Dee", "Eve", "Fay", "Gus", "Hal", "Ivy", "Jon" }
    local net, clients = crew(names)
    local a = clients[1]
    -- Everyone but Bob and Cid logs out, one a minute, Jon last.
    for i = 4, 10 do
      clients[i]:logout()
      net:run(60)
    end
    local view = a.core:camp(128)
    assert.equal("seated", actorFor(view, clients[2]).pose)
    assert.equal("seated", actorFor(view, clients[3]).pose)
    local shown = #view.actors
    assert.is_true(shown < 10)
    assert.equal(10 - shown, view.more)
    assert.equal(("+%d more"):format(10 - shown), view.moreText)
    -- The sleepers shown are the most recently seen.
    for i = 10, 4, -1 do
      local expected = (10 - i) < shown - 3
      assert.equal(expected, actorFor(view, clients[i]) ~= nil, clients[i].name)
    end
    assert.is_nil(a.core:camp(375).more)
  end)

  it("never overlaps anything, keeps it inside the band, and drops the tent when there's no room", function()
    local names = { "Ann", "Bob", "Cid", "Dee", "Eve", "Fay", "Gus", "Hal" }
    local net, clients = crew(names)
    clients[5]:logout()
    clients[6]:logout()
    clients[2]:play({ deaths = 2 })
    clients[6]:login()
    clients[6]:play({ deaths = 1 })
    net:run(15)
    clients[6]:logout()
    net:run(5)
    local a = clients[1]
    local sawTent, sawNoTent = false, false
    for columns = 128, 375 do
      local view = a.core:camp(columns)
      local list = spans(view)
      if view.tent then
        list[#list + 1] = { view.tent.x, view.tent.x + layout.tent }
        sawTent = true
      else
        sawNoTent = true
      end
      local left, right = -math.floor(columns / 2), columns - math.floor(columns / 2)
      for i, span in ipairs(list) do
        assert.is_true(span[1] >= left and span[2] <= right, ("out of the band at %d"):format(columns))
        -- The fire stays clear.
        assert.is_true(span[2] <= -layout.fire or span[1] >= layout.fire, ("on the fire at %d"):format(columns))
        for j = i + 1, #list do
          local other = list[j]
          assert.is_true(span[2] <= other[1] or other[2] <= span[1], ("overlap at %d"):format(columns))
        end
      end
      -- Names never run into each other.
      local labels = {}
      for _, actor in ipairs(view.actors) do
        local centre = actor.x + actor.width / 2
        labels[#labels + 1] = { centre - actor.labelWidth / 2, centre + actor.labelWidth / 2 }
      end
      for i, label in ipairs(labels) do
        for j = i + 1, #labels do
          assert.is_true(label[2] <= labels[j][1] or labels[j][2] <= label[1], ("labels overlap at %d"):format(columns))
        end
      end
    end
    assert.is_true(sawTent)
    assert.is_true(sawNoTent)
  end)

  describe("graves", function()
    it("mark each death in the last day, beside the Member, and go after it", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      b:play({ deaths = 1 })
      net:run(15)
      local view = a.core:camp(COLUMNS)
      local graves = gravesOf(view, b)
      assert.equal(1, #graves)
      local bob = actorFor(view, b)
      local gap = math.min(math.abs(graves[1].x - (bob.x + bob.width)), math.abs(bob.x - (graves[1].x + layout.grave)))
      assert.is_true(gap <= 4)

      b:play({ deaths = 2 })
      net:run(15)
      assert.equal(2, #gravesOf(a.core:camp(COLUMNS), b))

      skip(net, DAY)
      assert.equal(0, #gravesOf(a.core:camp(COLUMNS), b))
    end)

    it("count a death entry as its deaths, capped at 2 a Member and 4 in all", function()
      local net, clients = crew({ "Ann", "Bob", "Cid", "Dee" })
      local a, b, c, d = clients[1], clients[2], clients[3], clients[4]
      b:play({ deaths = 3 })
      net:run(15)
      assert.equal("Bob died 3 times", entry(a, "Bob died 3 times").text)
      assert.equal(2, #gravesOf(a.core:camp(COLUMNS), b))
      c:play({ deaths = 2 })
      net:run(15)
      d:play({ deaths = 1 })
      net:run(15)
      local view = a.core:camp(COLUMNS)
      assert.equal(4, #view.graves)
      -- Newest first: Dee's and Cid's graves, then one of Bob's.
      assert.equal(1, #gravesOf(view, d))
      assert.equal(2, #gravesOf(view, c))
      assert.equal(1, #gravesOf(view, b))
    end)

    it("include your own deaths", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a = clients[1]
      a:play({ deaths = 1 })
      net:run(5)
      assert.equal(1, #gravesOf(a.core:camp(COLUMNS), a))
    end)

    it("get a flower once you pay Respects", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      b:play({ deaths = 1 })
      net:run(15)
      assert.is_nil(gravesOf(a.core:camp(COLUMNS), b)[1].flower)
      assert.is_true(a.core:react(entry(a, "Bob died").key))
      assert.is_true(gravesOf(a.core:camp(COLUMNS), b)[1].flower)
    end)

    it("get a flower from anyone's Respects, gossiped while you were offline, yours included", function()
      local net, clients = crew({ "Ann", "Bob", "Cid" })
      local a, b, c = clients[1], clients[2], clients[3]
      a:play({ deaths = 1 })
      net:run(15)
      b:play({ deaths = 1 })
      net:run(15)
      a:logout()
      net:run(5)
      assert.is_true(c.core:react(entry(c, "Ann died").key))
      assert.is_true(c.core:react(entry(c, "Bob died").key))
      net:run(15)
      a:login()
      net:run(40)
      local view = a.core:camp(COLUMNS)
      assert.is_true(gravesOf(view, a)[1].flower)
      assert.is_true(gravesOf(view, b)[1].flower)
    end)
  end)

  describe("sparks", function()
    it("mark a max level in the last day, and go after it; a ding makes none", function()
      local net, clients = crew({ "Ann", "Bob", "Cid" })
      local a, b, c = clients[1], clients[2], clients[3]
      b:play({ level = 60 })
      c:play({ level = 11 })
      net:run(15)
      local view = a.core:camp(COLUMNS)
      assert.is_true(actorFor(view, b).spark)
      assert.is_nil(actorFor(view, c).spark)
      skip(net, DAY)
      assert.is_nil(actorFor(a.core:camp(COLUMNS), b).spark)
    end)
  end)

  describe("While you were away", function()
    local function summaryOf(client)
      for _, event in ipairs(client.events) do
        if event[1] == "awaySummary" then return event[2] end
      end
      return nil
    end

    it("opens on the Camp, with what each Main gained and max level highlighted", function()
      local net, clients, ns = crew({ "Ann", "Bob", "Cid", "Dee" })
      local a, b, c, d = clients[1], clients[2], clients[3], clients[4]
      a:logout()
      net:run(5)
      b:play({ level = 13 })
      c:play({ level = 60 })
      net:run(15)
      a.events = {}
      a:login()
      net:run(40)
      local summary = summaryOf(a)
      assert.equal(("The fire kept burning. %d things happened in camp."):format(summary.count), summary.intro)
      local camp = summary.camp
      assert.equal(ns.Core.CAMP_LAYOUT.awayColumns, camp.columns)
      assert.is_nil(camp.tent)
      assert.same({ "+3", nil }, { actorFor(camp, b).gained, actorFor(camp, b).highlight })
      assert.same({ "+50", true }, { actorFor(camp, c).gained, actorFor(camp, c).highlight })
      local dee = actorFor(camp, d)
      if dee then assert.is_nil(dee.gained) end
      assert.is_nil(actorFor(camp, a).gained)
    end)
  end)

  describe("setting", function()
    it("is on by default, and off gives no Camp and today's wording", function()
      local net, clients = crew({ "Ann", "Bob", "Cid" })
      local a, b, c = clients[1], clients[2], clients[3]
      c:logout()
      net:run(5)
      assert.is_true(a.core:setting("camp"))
      assert.equal("2 of 3 by the fire", a.core:summary().header)
      assert.equal("by the fire", a:rowFor(b).status)
      assert.equal("asleep · 0m ago", a:rowFor(c).status)
      assert.equal("BY THE FIRE", a:rowFor(b).section)
      assert.equal("ASLEEP IN CAMP", a:rowFor(c).section)
      assert.equal("CREW", a.core:rows("level")[2].section)
      assert.is_nil(a.core:rows()[1].status)
      -- Alt lines keep plain Last seen.
      assert.equal("online", a:rowFor(b).lastSeenText)

      a.events = {}
      a.core:setSetting("camp", false)
      assert.same({ "settingChanged", "camp", false }, a.events[1])
      assert.is_nil(a.core:camp(COLUMNS))
      assert.equal("1 of 2 online", a.core:summary().header)
      assert.equal("online", a:rowFor(b).status)
      assert.equal("0m ago", a:rowFor(c).status)
      assert.equal("CREW", a:rowFor(c).section)
    end)

    it("off leaves the summary as today's", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      a.core:setSetting("camp", false)
      a:logout()
      net:run(5)
      b:play({ level = 11 })
      net:run(15)
      a.events = {}
      a:login()
      net:run(40)
      local summary
      for _, event in ipairs(a.events) do
        if event[1] == "awaySummary" then summary = event[2] end
      end
      assert.is_nil(summary.camp)
      assert.equal("1 thing happened while you were away.", summary.intro)
    end)

    it("puts the Member's figure on a toast about them only while on", function()
      local net, clients = crew({ "Ann", "Bob" }, { Bob = { character = character("Bob", { classFilename = "MAGE" }) } })
      local a, b = clients[1], clients[2]
      local function lastEntry()
        local found
        for _, event in ipairs(a.events) do
          if event[1] == "feedEntry" then found = event[2] end
        end
        return found
      end
      b:play({ level = 11 })
      net:run(15)
      assert.equal("MAGE", lastEntry().figure)
      a.core:setSetting("camp", false)
      b:play({ level = 12 })
      net:run(15)
      assert.is_nil(lastEntry().figure)
    end)
  end)

  it("changes no record and sends nothing when read", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    b:play({ deaths = 1 })
    net:run(15)
    a.events = {}
    local mark = #net.wire
    for columns = 128, 375, 13 do a.core:camp(columns) end
    a.core:rows()
    a.core:summary()
    net:step()
    assert.equal(mark, #net.wire)
    assert.same({}, a.events)
  end)
end)
