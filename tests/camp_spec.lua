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

local function spans(view)
  local list = {}
  for _, actor in ipairs(view.actors) do
    list[#list + 1] = { actor.x, actor.x + actor.width }
    if actor.pet then list[#list + 1] = { actor.pet.x, actor.pet.x + layout.pet } end
  end
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
    for i = 10, 4, -1 do
      local expected = (10 - i) < shown - 3
      assert.equal(expected, actorFor(view, clients[i]) ~= nil, clients[i].name)
    end
    assert.is_nil(a.core:camp(375).more)
  end)

  it("never overlaps anything, keeps it inside the band, and drops the tent when there's no room", function()
    local names = { "Ann", "Bob", "Cid", "Dee", "Eve", "Fay", "Gus", "Hal" }
    local net, clients = crew(names)
    local pets = { "cat", "dog", "owl", "frog", "rabbit", "fox", "cat", "dog" }
    for i, client in ipairs(clients) do client.core:setLook({ pet = pets[i] }) end
    net:run(5)
    clients[5]:logout()
    clients[6]:logout()
    clients[2]:play({ deaths = 2 })
    clients[6]:login()
    clients[6]:play({ deaths = 1 })
    net:run(15)
    clients[6]:logout()
    net:run(5)
    local a = clients[1]
    local sawTent, sawNoTent, sawPets = false, false, false
    for columns = 128, 375 do
      local view = a.core:camp(columns)
      local list = spans(view)
      for _, actor in ipairs(view.actors) do sawPets = sawPets or actor.pet ~= nil end
      if view.tent then
        list[#list + 1] = { view.tent.x, view.tent.x + layout.tent }
        sawTent = true
      else
        sawNoTent = true
      end
      local left, right = -math.floor(columns / 2), columns - math.floor(columns / 2)
      for i, span in ipairs(list) do
        assert.is_true(span[1] >= left and span[2] <= right, ("out of the band at %d"):format(columns))
        assert.is_true(span[2] <= -layout.fire or span[1] >= layout.fire, ("on the fire at %d"):format(columns))
        for j = i + 1, #list do
          local other = list[j]
          assert.is_true(span[2] <= other[1] or other[2] <= span[1], ("overlap at %d"):format(columns))
        end
      end
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
    assert.is_true(sawPets)
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
      assert.is_nil(lastEntry().hat)
      b.core:setLook({ hat = "fez" })
      net:run(5)
      b:play({ level = 12 })
      net:run(15)
      assert.equal("fez", lastEntry().hat)
      a.core:setSetting("camp", false)
      b:play({ level = 13 })
      net:run(15)
      assert.is_nil(lastEntry().figure)
      assert.is_nil(lastEntry().hat)
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

describe("Head pieces", function()
  local function hatOf(viewer, client)
    return actorFor(viewer.core:camp(COLUMNS), client).hat
  end

  local function receive(client, ns, net, from, record)
    record.version = record.version or net:now()
    record.characters = record.characters or {
      ["Player-0-" .. record.id] = { guid = "Player-0-" .. record.id, name = record.id, level = 20, lastPlayed = net:now() },
    }
    client.core:received(ns.Codec.encode({ type = "DATA", from = from, records = { record } }))
  end

  it("lists the pieces with their names, none first", function()
    local hats = load().Core.HATS
    assert.same({ key = "none", label = "None" }, hats[1])
    local keys = {}
    for _, hat in ipairs(hats) do keys[#keys + 1] = hat.key end
    assert.same({ "none", "templar", "centurion", "dwarf", "wolfskin", "coonskin", "cowboy", "straw", "fez", "beret",
      "circlet", "bandana", "cap", "wizard", "horns", "tophat" }, keys)
  end)

  it("are written to your record and sent, and reach the others' Camps", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    assert.is_nil(a.core:look().hat)
    local mark = #net.wire
    assert.is_true(a.core:setLook({ hat = "wizard" }))
    assert.equal("wizard", a.core:look().hat)
    net:step()
    assert.is_true(#net.wire > mark)
    net:run(5)
    assert.equal("wizard", hatOf(b, a))
    assert.equal("wizard", hatOf(a, a))
    assert.is_nil(hatOf(a, b))
  end)

  it("go back to none, and refuse a piece that isn't on the list", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    a.core:setLook({ hat = "fez" })
    net:run(5)
    assert.same({ nil, "unknownHat" }, { a.core:setLook({ hat = "crown" }) })
    assert.equal("fez", a.core:look().hat)
    assert.is_true(a.core:setLook({ hat = "none" }))
    net:run(5)
    assert.is_nil(a.core:look().hat)
    assert.is_nil(hatOf(b, a))
  end)

  it("send nothing when the piece doesn't change", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a = clients[1]
    a.core:setLook({ hat = "beret" })
    net:run(5)
    local mark = #net.wire
    assert.is_true(a.core:setLook({ hat = "beret" }))
    net:step()
    assert.equal(mark, #net.wire)
  end)

  it("read as none when unknown or malformed, keeping the rest of the record", function()
    local net, clients, ns = crew({ "Ann" })
    local a = clients[1]
    receive(a, ns, net, "newer", { id = "newer", displayName = "Newer", look = { hat = "monocle", pet = "cat" } })
    receive(a, ns, net, "junk", { id = "junk", displayName = "Junk", look = "tophat" })
    receive(a, ns, net, "badhat", { id = "badhat", displayName = "Badhat", look = { hat = 7 } })
    for _, id in ipairs({ "newer", "junk", "badhat" }) do
      local row = a:rowFor({ memberId = id })
      assert.equal(20, row.level)
      assert.is_nil(row.hat)
    end
  end)

  it("survive a merge relayed by another client, and are passed on", function()
    local net, clients, ns = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    receive(a, ns, net, "relay", { id = "far", displayName = "Far", look = { hat = "straw", pet = "cat" } })
    assert.equal("straw", a:rowFor({ memberId = "far" }).hat)
    net:run(70)
    assert.equal("straw", b:rowFor({ memberId = "far" }).hat)
  end)

  it("are kept on your record when you leave", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a = clients[1]
    a.core:setLook({ hat = "horns" })
    net:run(5)
    a.core:leaveCrew()
    net:run(5)
    assert.equal("horns", a.core:look().hat)
  end)
end)

describe("Pets", function()
  local function receive(client, ns, net, from, record)
    record.version = record.version or net:now()
    record.characters = record.characters or {
      ["Player-0-" .. record.id] = { guid = "Player-0-" .. record.id, name = record.id, level = 20, lastPlayed = net:now() },
    }
    client.core:received(ns.Codec.encode({ type = "DATA", from = from, records = { record } }))
  end

  local function seats(view)
    local list = {}
    for _, actor in ipairs(view.actors) do list[#list + 1] = actor.memberId end
    for _, grave in ipairs(view.graves) do list[#list + 1] = "grave:" .. grave.memberId end
    list[#list + 1] = view.tent and "tent" or "no tent"
    list[#list + 1] = "more:" .. tostring(view.more)
    return table.concat(list, " ")
  end

  it("lists the pets with their names, none first", function()
    local keys = {}
    for _, pet in ipairs(load().Core.PETS) do keys[#keys + 1] = pet.key end
    assert.same({ "none", "cat", "dog", "owl", "frog", "rabbit", "fox" }, keys)
    assert.same({ key = "none", label = "None" }, load().Core.PETS[1])
  end)

  it("sit beside their Member on the side away from the fire, in every Camp", function()
    local net, clients = crew({ "Ann", "Bob", "Cid" })
    local a, b, c = clients[1], clients[2], clients[3]
    b.core:setLook({ pet = "fox" })
    c.core:setLook({ pet = "owl" })
    net:run(5)
    c:logout()
    net:run(5)
    local view = a.core:camp(COLUMNS)
    for _, client in ipairs({ b, c }) do
      local actor = actorFor(view, client)
      if actor.x > 0 then
        assert.equal(actor.x + actor.width + layout.petGap, actor.pet.x)
      else
        assert.equal(actor.x - layout.petGap - layout.pet, actor.pet.x)
      end
    end
    assert.equal("fox", actorFor(view, b).pet.key)
    assert.same({ "asleep", "owl" }, { actorFor(view, c).pose, actorFor(view, c).pet.key })
    assert.is_nil(actorFor(view, a).pet)
  end)

  it("keep the Graves after them, on the far side", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    b.core:setLook({ pet = "dog" })
    b:play({ deaths = 1 })
    net:run(15)
    local view = a.core:camp(COLUMNS)
    local bob, grave = actorFor(view, b), gravesOf(view, b)[1]
    if bob.x > 0 then
      assert.is_true(grave.x >= bob.pet.x + layout.pet)
    else
      assert.is_true(grave.x + layout.grave <= bob.pet.x)
    end
  end)

  it("are left out first in a narrow band, before any Member, Grave or the tent, and come back as it widens", function()
    local names = { "Ann", "Bob", "Cid", "Dee", "Eve", "Fay", "Gus", "Hal" }
    local net, clients = crew(names)
    local a = clients[1]
    clients[2]:play({ deaths = 2 })
    net:run(15)
    local function settle()
      clients[7]:logout()
      clients[8]:logout()
      net:run(15)
    end
    settle()
    local without = {}
    for columns = 128, 375 do without[columns] = seats(a.core:camp(columns)) end
    clients[7]:login()
    clients[8]:login()
    for _, client in ipairs(clients) do client.core:setLook({ pet = "cat" }) end
    net:run(15)
    settle()
    local fewest, most = #names, 0
    for columns = 128, 375 do
      local view = a.core:camp(columns)
      assert.equal(without[columns], seats(view), ("seats changed at %d"):format(columns))
      local count = 0
      for _, actor in ipairs(view.actors) do count = count + (actor.pet and 1 or 0) end
      fewest, most = math.min(fewest, count), math.max(most, count)
    end
    assert.equal(0, fewest)
    assert.equal(#names, most)
    for _, actor in ipairs(a.core:camp(375).actors) do assert.equal("cat", actor.pet.key) end
  end)

  it("are written with your head piece, refuse a pet that isn't on the list, and go back to none", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    a.core:setLook({ hat = "fez" })
    assert.is_true(a.core:setLook({ pet = "rabbit" }))
    assert.same({ "fez", "rabbit" }, { a.core:look().hat, a.core:look().pet })
    assert.same({ nil, "unknownPet" }, { a.core:setLook({ pet = "dragon" }) })
    assert.equal("rabbit", a.core:look().pet)
    net:run(5)
    assert.same({ "fez", "rabbit" }, { actorFor(b.core:camp(COLUMNS), a).hat, actorFor(b.core:camp(COLUMNS), a).pet.key })
    assert.is_true(a.core:setLook({ pet = "none" }))
    net:run(5)
    assert.is_nil(a.core:look().pet)
    assert.equal("fez", actorFor(b.core:camp(COLUMNS), a).hat)
    assert.is_nil(actorFor(b.core:camp(COLUMNS), a).pet)
  end)

  it("send no more than a head piece does", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a = clients[1]
    local mark = #net.wire
    a.core:setLook({ hat = "beret" })
    net:step()
    local forHat = #net.wire - mark
    net:run(5)
    mark = #net.wire
    a.core:setLook({ pet = "frog" })
    net:step()
    assert.equal(forHat, #net.wire - mark)
    net:run(5)
    mark = #net.wire
    assert.is_true(a.core:setLook({ pet = "frog" }))
    for columns = 128, 375, 13 do a.core:camp(columns) end
    net:step()
    assert.equal(mark, #net.wire)
  end)

  it("read as none when unknown or malformed, keeping the head piece and the record", function()
    local net, clients, ns = crew({ "Ann" })
    local a = clients[1]
    receive(a, ns, net, "newer", { id = "newer", displayName = "Newer", look = { hat = "fez", pet = "dragon" } })
    receive(a, ns, net, "badpet", { id = "badpet", displayName = "Badpet", look = { pet = 7 } })
    local newer = a:rowFor({ memberId = "newer" })
    assert.same({ 20, "fez" }, { newer.level, newer.hat })
    assert.is_nil(newer.pet)
    assert.is_nil(a:rowFor({ memberId = "badpet" }).pet)
    assert.is_nil(actorFor(a.core:camp(COLUMNS), { memberId = "newer" }).pet)
  end)
end)
