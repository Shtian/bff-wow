local load = require("tests.load")

local COLUMNS = 300
local SMALLFISH = 6291
local RAKSHIRI = 10200

local function character(name)
  return {
    guid = "Player-0-" .. name, name = name, classFilename = "WARRIOR",
    level = 10, xp = 0, maxXp = 1000, zone = "Elwynn Forest", deaths = 0,
  }
end

local function founder(options)
  local ns = load()
  local net = ns.FakeNet.new()
  local ann = net:add("Ann", { character = character("Ann"), db = options and options.db }):login()
  local code = ann:join()
  net:run(5)
  return net, ann, code, ns
end

local function joins(net, name, code)
  local client = net:add(name, { character = character(name) }):login()
  client:join(code)
  net:run(40)
  return client
end

local function strayOn(view)
  for _, seat in ipairs(view.lanternSeats or {}) do
    if seat.stray then return seat end
  end
  return nil
end

local function untilStray(net, client)
  for _ = 1, 400 do
    if client.core:camp(COLUMNS).stray then return client.core:camp(COLUMNS).stray end
    net:step()
  end
  error("no stray came")
end

local function petCues(client)
  local list = {}
  for _, event in ipairs(client.events) do
    if event[1] == "petCue" then list[#list + 1] = event[2] end
  end
  return list
end

local function ownPet(client)
  return client.core:look().pet
end

describe("A stray", function()
  it("comes a few minutes after login to a Member alone with no pet, and naps on a lantern seat", function()
    local net, ann = founder()
    assert.is_nil(ann.core:camp(COLUMNS).stray)
    local stray = untilStray(net, ann)
    assert.is_true(net:now() - 1000 >= 3 * 60)
    local seat = strayOn(ann.core:camp(COLUMNS))
    assert.equal(stray.key, seat.pet)
    assert.is_string(stray.tooltip.title)
    assert.is_string(stray.tooltip.hint)
    assert.is_true(strayOn(ann.core:pocketCamp()) ~= nil)
    assert.equal(stray.key, ann.core:pocketCamp().stray.key)
  end)

  it("never comes to a Member who has a pet, or who isn't alone", function()
    local net, ann = founder()
    ann.core:setLook({ pet = "cat" })
    net:run(400)
    assert.is_nil(ann.core:camp(COLUMNS).stray)

    local net2, bea, code2 = founder()
    joins(net2, "Cid", code2)
    bea.core:setLook({ pet = "none" })
    net2:run(400)
    assert.is_nil(bea.core:camp(COLUMNS).stray)
  end)

  it("never comes in combat", function()
    local net, ann = founder()
    ann.core:doing({ combat = true })
    net:run(400)
    assert.is_nil(ann.core:camp(COLUMNS).stray)
    ann.core:doing({})
    untilStray(net, ann)
  end)

  it("is kept with a click: the pet becomes yours, sent like a Look change", function()
    local net, ann = founder()
    local stray = untilStray(net, ann)
    local line = ann.core:keepStray()
    assert.equal(stray.key, ownPet(ann))
    assert.equal(("The %s stays. Change it in Settings › You › Look."):format(stray.key), line)
    local view = ann.core:camp(COLUMNS)
    assert.is_nil(view.stray)
    assert.is_nil(strayOn(view))
    assert.is_nil(ann.core:keepStray())
  end)

  it("comes at most once a session, and wanders off after 10 minutes", function()
    local net, ann = founder()
    untilStray(net, ann)
    net:run(10 * 60 - 1)
    assert.is_table(ann.core:camp(COLUMNS).stray)
    net:run(1)
    assert.is_nil(ann.core:camp(COLUMNS).stray)
    net:run(30 * 60)
    assert.is_nil(ann.core:camp(COLUMNS).stray)
  end)

  it("wanders off when the panel closes", function()
    local net, ann = founder()
    untilStray(net, ann)
    ann.core:panelClosed()
    assert.is_nil(ann.core:camp(COLUMNS).stray)
    ann.core:panelClosed()
  end)

  it("stops for the session on Not now, without counting as ignored", function()
    local net, ann = founder()
    untilStray(net, ann)
    ann.core:strayNotNow()
    assert.is_nil(ann.core:camp(COLUMNS).stray)
    for _ = 1, 2 do
      ann:reload()
      untilStray(net, ann)
      ann.core:panelClosed()
    end
    ann:reload()
    untilStray(net, ann)
  end)

  it("is never the last one, and every third ignored one pushes the next a week out", function()
    local net, ann = founder()
    local last
    for _ = 1, 3 do
      local stray = untilStray(net, ann)
      assert.are_not.equal(last, stray.key)
      last = stray.key
      ann.core:panelClosed()
      ann:reload()
    end
    net:run(400)
    assert.is_nil(ann.core:camp(COLUMNS).stray)
    net.clock = net.clock + 7 * 24 * 60 * 60
    ann:reload()
    untilStray(net, ann)
  end)

  it("leaves as soon as a friend's record is known", function()
    local net, ann, code = founder()
    untilStray(net, ann)
    joins(net, "Bob", code)
    assert.is_nil(ann.core:camp(COLUMNS).stray)
    assert.is_nil(ann.core:keepStray())
    assert.is_nil(ownPet(ann))
  end)

  it("adds no record fields: only the kept pet goes out", function()
    local net, ann = founder()
    untilStray(net, ann)
    assert.is_nil(ann.core:look().pet)
    assert.is_nil(ann.core:rows()[1].pet)
  end)
end)

describe("The pet while you're alone", function()
  local function settledWithPet()
    local net, ann, code, ns = founder()
    ann.core:setLook({ pet = "fox" })
    net:run(60)
    return net, ann, code, ns
  end

  it("hops at your ding and max level, holds a fish up at a rare find and a star at a rare kill", function()
    local net, ann = settledWithPet()
    ann:play({ level = 11 })
    ann.core:caught({ items = { { itemId = SMALLFISH, quantity = 1 } }, zone = "Westfall", mapId = 1436 })
    ann.core:rareKilled({ npcId = RAKSHIRI, zone = "Winterspring", subzone = "Everlook", mapId = 1452,
      signal = "loot" })
    net:run(1)
    local seen = petCues(ann)
    assert.equal("hop", seen[1])
    assert.equal("star", seen[#seen])
  end)

  it("curls up by your newest Grave after a death, until the next login, with no flower", function()
    local net, ann = settledWithPet()
    ann:play({ deaths = 1 })
    net:run(1)
    local view = ann.core:camp(COLUMNS)
    assert.is_table(view.mourner)
    assert.equal("fox", view.mourner.key)
    for _, seat in ipairs(view.lanternSeats) do assert.is_nil(seat.pet) end
    assert.is_nil(view.graves[1].flower)
    local grave = view.graves[1]
    assert.is_true(view.mourner.x + 13 <= grave.x or view.mourner.x >= grave.x + 8)
    ann:reload()
    net:run(60)
    assert.is_nil(ann.core:camp(COLUMNS).mourner)
  end)

  it("leaves a stray on its seat after a death: only your own pet mourns", function()
    local net, ann = founder()
    untilStray(net, ann)
    ann:play({ deaths = 1 })
    net:run(1)
    local view = ann.core:camp(COLUMNS)
    assert.is_nil(view.mourner)
    assert.is_table(strayOn(view))
  end)

  it("never brings a stray in combat, even flying or at a vendor", function()
    local net, ann = founder()
    ann.core:doing({ combat = true, vendor = true })
    net:run(400)
    assert.is_nil(ann.core:camp(COLUMNS).stray)
  end)

  it("plays nothing for news before sync has settled", function()
    local ns = load()
    local net = ns.FakeNet.new()
    local ann = net:add("Ann", { character = character("Ann") }):login()
    ann:join()
    ann.core:setLook({ pet = "fox" })
    ann:play({ level = 11, deaths = 1 })
    assert.same({}, petCues(ann))
    assert.is_nil(ann.core:camp(COLUMNS).mourner)
  end)

  it("stops reacting once another Member's record is known", function()
    local net, ann, code = settledWithPet()
    ann:play({ deaths = 1 })
    joins(net, "Bob", code)
    assert.is_nil(ann.core:camp(COLUMNS).mourner)
    ann:play({ level = 11 })
    net:run(1)
    assert.same({}, petCues(ann))
  end)

  it("watches the trophy cup and your fishing in the Pocket Camp", function()
    local net, ann = settledWithPet()
    ann.core:caught({ items = { { itemId = SMALLFISH, quantity = 1 } }, zone = "Westfall", mapId = 1436 })
    local seat = ann.core:pocketCamp().lanternSeats[1]
    assert.equal("fishing", seat.watching)
    assert.is_number(seat.faces)
    net:run(61)
    assert.is_nil(ann.core:pocketCamp().lanternSeats[1].watching)
  end)
end)
