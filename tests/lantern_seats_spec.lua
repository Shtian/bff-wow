local load = require("tests.load")

local COLUMNS = 300

local function character(name)
  return {
    guid = "Player-0-" .. name, name = name, classFilename = "WARRIOR",
    level = 10, xp = 0, maxXp = 1000, zone = "Elwynn Forest", deaths = 0,
  }
end

local function founder()
  local ns = load()
  local net = ns.FakeNet.new()
  local ann = net:add("Ann", { character = character("Ann") }):login()
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

local function actorFor(view, client)
  for _, actor in ipairs(view.actors) do
    if actor.memberId == client.memberId then return actor end
  end
  return nil
end

local layout = load().Core.CAMP_LAYOUT

local function spans(view)
  local list = {}
  for _, actor in ipairs(view.actors) do list[#list + 1] = { actor.x, actor.x + actor.width } end
  for _, seat in ipairs(view.lanternSeats or {}) do list[#list + 1] = { seat.x, seat.x + layout.lantern } end
  if view.tent then list[#list + 1] = { view.tent.x, view.tent.x + layout.tent } end
  return list
end

local function assertApart(view)
  local list = spans(view)
  local left, right = -math.floor(view.columns / 2), view.columns - math.floor(view.columns / 2)
  for i, span in ipairs(list) do
    assert.is_true(span[1] >= left and span[2] <= right, "out of the band")
    assert.is_true(span[2] <= -layout.fire or span[1] >= layout.fire, "on the fire")
    for j = i + 1, #list do
      local other = list[j]
      assert.is_true(span[2] <= other[1] or other[2] <= span[1], "overlap")
    end
  end
end

describe("Lantern seats", function()
  it("saves two seats in the Camp while you're alone, not counted by the fire", function()
    local _, ann, code = founder()
    local view = ann.core:camp(COLUMNS)
    assert.equal(2, #view.lanternSeats)
    assert.equal(1, #view.actors)
    assert.is_nil(view.more)
    assertApart(view)
    assert.equal("1 of 1 by the fire", ann.core:rosterCounts().header)
    assert.equal("Join my Crew in BFF: /bff join " .. code, view.saved.invite)
    assert.equal(code, view.saved.code)
    assert.equal("Saved for your Crew", view.saved.tooltip.title)
    assert.same({ "Friends join with /bff join " .. code }, view.saved.tooltip.lines)
    assert.is_string(view.saved.tooltip.hint)
  end)

  it("places them before the tent, on both sides of the fire", function()
    local _, ann = founder()
    local view = ann.core:camp(COLUMNS)
    local right, left = view.lanternSeats[1], view.lanternSeats[2]
    assert.is_true(right.x > 0)
    assert.is_true(left.x < 0)
    assert.is_table(view.tent)
    assert.is_true(math.abs(view.tent.x) > math.abs(right.x))
  end)

  it("lets your pet nap on the seat on your side", function()
    local _, ann = founder()
    ann.core:setLook({ pet = "fox" })
    local view = ann.core:camp(COLUMNS)
    local you = actorFor(view, ann)
    assert.is_nil(you.pet)
    local napping
    for _, seat in ipairs(view.lanternSeats) do
      if seat.pet then napping = seat end
    end
    assert.equal("fox", napping.pet)
    assert.equal(you.x < 0, napping.x < 0)
  end)

  it("tells a Member who joined that the seats are saved, with no code", function()
    local net, ann, code = founder()
    ann:logout()
    net:run(2)
    local bob = net:add("Bob", { character = character("Bob") }):login()
    bob:join(code)
    net:run(5)
    local view = bob.core:camp(COLUMNS)
    assert.equal(2, #view.lanternSeats)
    assert.is_nil(view.saved.code)
    assert.is_nil(view.saved.invite)
    assert.same({ "They sit here once you hear from one of them." }, view.saved.tooltip.lines)
  end)

  it("goes once another Member's record arrives, and the first friend walks in", function()
    local net, ann, code = founder()
    ann.core:setLook({ pet = "fox" })
    local bob = joins(net, "Bob", code)
    local view = ann.core:camp(COLUMNS)
    assert.is_nil(view.lanternSeats)
    assert.is_nil(view.saved)
    assert.equal("fox", actorFor(view, ann).pet.key)
    assert.equal(bob.memberId, view.walkIn.memberId)
    assert.equal(2, #view.walkIn.seats)
    assert.equal("fox", view.walkIn.seats[2].pet)
    assert.equal(bob.memberId, ann.core:pocketCamp().walkIn.memberId)
  end)

  it("keeps the walk-in across a reload and plays it once", function()
    local net, ann, code = founder()
    local bob = joins(net, "Bob", code)
    ann:reload()
    net:run(5)
    assert.equal(bob.memberId, ann.core:camp(COLUMNS).walkIn.memberId)
    ann.core:walkedIn()
    assert.is_nil(ann.core:camp(COLUMNS).walkIn)
    ann:reload()
    net:run(5)
    assert.is_nil(ann.core:camp(COLUMNS).walkIn)
  end)

  it("walks an offline friend in to a bedroll", function()
    local net, ann, code = founder()
    local bob = joins(net, "Bob", code)
    bob:logout()
    net:run(2)
    local view = ann.core:camp(COLUMNS)
    assert.equal("asleep", actorFor(view, bob).pose)
    assert.equal(bob.memberId, view.walkIn.memberId)
  end)

  it("never walks in a friend for a Member who already knew the Crew", function()
    local net, ann, code = founder()
    joins(net, "Bob", code)
    ann.core:walkedIn()
    joins(net, "Cid", code)
    assert.is_nil(ann.core:camp(COLUMNS).walkIn)
  end)

  it("saves one seat in the Pocket Camp", function()
    local _, ann = founder()
    ann.core:setLook({ pet = "fox" })
    local view = ann.core:pocketCamp()
    assert.equal(1, #view.lanternSeats)
    assert.equal("fox", view.lanternSeats[1].pet)
    assert.is_nil(actorFor(view, ann).pet)
    assert.is_table(view.saved)
  end)

  it("shows none while the camp is off or you're leaving", function()
    local _, ann = founder()
    ann.core:setSetting("camp", false)
    assert.is_nil(ann.core:camp(COLUMNS))
    ann.core:setSetting("camp", true)
    ann.core:leaveCrew()
    local view = ann.core:camp(COLUMNS)
    assert.is_true(view == nil or view.lanternSeats == nil)
  end)
end)
