local load = require("tests.load")

local ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

local function newDeps(db)
  local deps = {
    sent = {},
    events = {},
    db = db or {},
    clock = 1000,
    random = math.random,
    initialLogin = true,
    maxLevel = 60,
  }
  deps.now = function() return deps.clock end
  deps.link = { send = function(message) deps.sent[#deps.sent + 1] = message end }
  deps.listener = function(...) deps.events[#deps.events + 1] = { ... } end
  return deps
end

local function character()
  return {
    guid = "Player-1-0000AAAA", name = "Thrallbane", classFilename = "WARRIOR",
    level = 24, xp = 1200, maxXp = 2000, zone = "Stranglethorn Vale", deaths = 3,
  }
end

local function countEvents(deps, name)
  local n = 0
  for _, e in ipairs(deps.events) do
    if e[1] == name then n = n + 1 end
  end
  return n
end

local function withCheck(body)
  local sum = 0
  for i = 1, 7 do
    local value = ALPHABET:find(body:sub(i, i), 1, true) - 1
    sum = sum + value * (2 * i - 1)
  end
  local check = sum % 32 + 1
  local code = body .. ALPHABET:sub(check, check)
  return code:sub(1, 4) .. "-" .. code:sub(5, 8)
end

describe("Crew codes", function()
  it("starts a Crew with a fresh code like K3F9-A2QX", function()
    local deps = newDeps()
    local core = load().Core.new(deps)

    local crew = core:startCrew("Stian")
    assert.is_table(crew)
    assert.matches("^[0-9A-HJKMNP-TV-Z]+%-[0-9A-HJKMNP-TV-Z]+$", crew.code)
    assert.equal(9, #crew.code)
    assert.same(crew, core:crew())
    assert.equal(1, countEvents(deps, "crewChanged"))
  end)

  it("gives a code whose check character another client accepts", function()
    local code = load().Core.new(newDeps()):startCrew("AA").code
    local other = load().Core.new(newDeps())
    assert.equal(code, other:joinCrew(code, "BB").code)
  end)

  it("generates different codes for different Crews", function()
    local seen = {}
    for _ = 1, 50 do
      local code = load().Core.new(newDeps()):startCrew("AA").code
      assert.is_nil(seen[code])
      seen[code] = true
    end
  end)

  it("reads typed codes forgivingly", function()
    local code = withCheck("01K3F9A")
    local typed = "  o" .. "i" .. code:sub(3, 4):lower() .. " " .. code:sub(6, 9):lower() .. " "
    local core = load().Core.new(newDeps())
    assert.equal(code, core:joinCrew(typed, "BB").code)

    local withL = load().Core.new(newDeps())
    assert.equal(code, withL:joinCrew("0L" .. code:sub(3), "BB").code)
  end)

  it("rejects every single mistyped character, and joins nothing", function()
    local code = withCheck("K3F9A2Q")
    local plain = code:gsub("-", "")
    for i = 1, 8 do
      for j = 1, #ALPHABET do
        local c = ALPHABET:sub(j, j)
        if c ~= plain:sub(i, i) then
          local typo = plain:sub(1, i - 1) .. c .. plain:sub(i + 1)
          local deps = newDeps()
          local core = load().Core.new(deps)
          local crew, reason = core:joinCrew(typo, "BB")
          assert.is_nil(crew)
          assert.equal("invalidCode", reason)
          assert.is_nil(core:crew())
          assert.equal(0, countEvents(deps, "crewChanged"))
        end
      end
    end
  end)

  it("rejects codes of the wrong length or with letters outside the alphabet", function()
    local core = load().Core.new(newDeps())
    for _, typo in ipairs({ "", "K3F9", "K3F9-A2QXZ", "K3F9-A2QU", "K3F9_A2QX", 42 }) do
      assert.same({ nil, "invalidCode" }, { core:joinCrew(typo, "BB") })
    end
    assert.is_nil(core:crew())
  end)

  it("hashes the code into a channel name and password that don't contain it", function()
    local code = withCheck("K3F9A2Q")
    local crew = load().Core.new(newDeps()):joinCrew(code, "BB")

    assert.matches("^BFF[0-9A-HJKMNP-TV-Z]+$", crew.channel)
    assert.equal(10, #crew.channel)
    assert.matches("^[0-9A-HJKMNP-TV-Z]+$", crew.password)
    assert.equal(7, #crew.password)
    assert.not_equal(crew.channel:sub(4), crew.password)
    local plain = code:gsub("-", "")
    assert.is_nil(crew.channel:find(plain:sub(1, 4), 1, true))

    local again = load().Core.new(newDeps()):joinCrew(code, "CC")
    assert.equal(crew.channel, again.channel)
    assert.equal(crew.password, again.password)
    local other = load().Core.new(newDeps()):joinCrew(withCheck("K3F9A2R"), "BB")
    assert.not_equal(crew.channel, other.channel)
    assert.not_equal(crew.password, other.password)
  end)
end)

describe("One Crew at a time", function()
  it("refuses to join or start another Crew while in one", function()
    local deps = newDeps()
    local core = load().Core.new(deps)
    local crew = core:joinCrew(withCheck("K3F9A2Q"), "BB")

    assert.same({ nil, "inCrew" }, { core:joinCrew(withCheck("ABCDEFG"), "BB") })
    assert.same({ nil, "inCrew" }, { core:startCrew("B") })
    assert.same(crew, core:crew())
    assert.equal(1, countEvents(deps, "crewChanged"))
  end)

  it("does nothing when joining the Crew you're already in", function()
    local deps = newDeps()
    local core = load().Core.new(deps)
    local code = withCheck("K3F9A2Q")
    core:joinCrew(code, "BB")
    assert.same(core:crew(), core:joinCrew(code:lower(), "BB"))
    assert.equal(1, countEvents(deps, "crewChanged"))
  end)

  it("is alone until another Member is known", function()
    local core = load().Core.new(newDeps())
    core:updateOwn(character())
    assert.is_true(core:startCrew("Stian").alone)
  end)

  it("knows whether you joined it with a code or started it", function()
    local started = load().Core.new(newDeps())
    started:updateOwn(character())
    assert.is_false(started:startCrew("Stian").joined)
    local joined = load().Core.new(newDeps())
    joined:updateOwn(character())
    assert.is_true(joined:joinCrew(withCheck("K3F9A2Q"), "BB").joined)
  end)

  it("words its status: leaving, then appearing offline, then waiting for the Crew", function()
    local core = load().Core.new(newDeps())
    core:updateOwn(character())
    core:startCrew("Stian")
    local WAITING = "Waiting for your Crew. Members show up when they or someone who has seen them is online."
    local PAUSED = "You appear offline: the others don't see you. Change it in Settings."
    local LEAVING = "Leaving the Crew. It finishes once BFF's channel is reachable."
    assert.equal(WAITING, core:crew().status)
    assert.is_true(core:crew().waiting)
    core:setPaused(true)
    assert.equal(PAUSED, core:crew().status)
    assert.is_nil(core:crew().waiting)
    core:leaveCrew()
    assert.equal(LEAVING, core:crew().status)
  end)

  it("remembers the Crew across a reload", function()
    local db = {}
    local crew = load().Core.new(newDeps(db)):startCrew("AA")
    assert.same(crew, load().Core.new(newDeps(db)):crew())
  end)
end)

describe("Display name", function()
  it("is 2 to 16 characters, counted as UTF-8 characters", function()
    local core = load().Core.new(newDeps())
    assert.same({ nil, "invalidName" }, { core:startCrew("A") })
    assert.same({ nil, "invalidName" }, { core:startCrew("ABCDEFGHIJKLMNOPQ") })
    assert.same({ nil, "invalidName" }, { core:startCrew("   ") })
    assert.is_nil(core:crew())

    assert.is_true(core:setDisplayName("Bø"))
    assert.is_true(core:setDisplayName(("ø"):rep(16)))
    assert.same({ nil, "invalidName" }, { core:setDisplayName(("ø"):rep(17)) })
    assert.same({ nil, "invalidName" }, { core:setDisplayName(nil) })
  end)

  it("is trimmed, and nil until set", function()
    local core = load().Core.new(newDeps())
    assert.is_nil(core:displayName())
    core:startCrew("  Stian ")
    assert.equal("Stian", core:displayName())
  end)

  it("is kept when joining without one", function()
    local core = load().Core.new(newDeps())
    core:setDisplayName("Stian")
    assert.is_table(core:startCrew())
  end)

  it("is needed to start or join", function()
    local core = load().Core.new(newDeps())
    assert.same({ nil, "invalidName" }, { core:startCrew() })
  end)
end)

describe("Leaving the Crew", function()
  local function tombstone(ns, message)
    local decoded = ns.Codec.decode(message)
    assert.is_table(decoded)
    assert.equal("DATA", decoded.type)
    return decoded.records[1]
  end

  it("sends the tombstone right away when the link is up, then forgets the Crew", function()
    local ns = load()
    local deps = newDeps()
    local core = ns.Core.new(deps)
    core:updateOwn(character())
    core:startCrew("Stian")
    core:up()
    deps.sent = {}
    local id = core:rows()[1].memberId

    deps.clock = deps.clock + 60
    assert.is_true(core:leaveCrew())

    assert.equal(1, #deps.sent)
    local record = tombstone(ns, deps.sent[1])
    assert.is_true(record.left)
    assert.equal("Stian", record.displayName)
    assert.equal(id, record.id)
    assert.equal(1060, record.version)
    assert.is_nil(record.characters)
    assert.is_nil(core:crew())
    assert.equal(2, countEvents(deps, "crewChanged"))
    assert.same({ "notice", "leftCrew" }, deps.events[#deps.events])
  end)

  it("keeps the Crew while the link is down, and finishes on the next up()", function()
    local ns = load()
    local deps = newDeps()
    local core = ns.Core.new(deps)
    local crew = core:startCrew("Stian")

    assert.is_true(core:leaveCrew())
    assert.same({}, deps.sent)
    local leaving = core:crew()
    assert.equal(crew.channel, leaving.channel)
    assert.is_true(leaving.leaving)
    assert.equal(1, countEvents(deps, "crewChanged"))

    core:up()
    assert.equal(1, #deps.sent)
    assert.is_true(tombstone(ns, deps.sent[1]).left)
    assert.is_nil(core:crew())
    assert.equal(2, countEvents(deps, "crewChanged"))
  end)

  it("waits out lockdown: down() after up() keeps it leaving", function()
    local deps = newDeps()
    local core = load().Core.new(deps)
    core:startCrew("Stian")
    core:up()
    core:down()
    deps.sent = {}
    core:leaveCrew()
    assert.same({}, deps.sent)
    assert.is_true(core:crew().leaving)
  end)

  it("survives a logout and finishes after the next login", function()
    local ns = load()
    local db = {}
    local first = ns.Core.new(newDeps(db))
    first:updateOwn(character())
    first:startCrew("Stian")
    first:leaveCrew()

    local deps = newDeps(db)
    deps.clock = 5000
    local second = ns.Core.new(deps)
    assert.is_true(second:crew().leaving)
    second:up()
    local record = tombstone(ns, deps.sent[1])
    assert.is_true(record.left)
    assert.equal(1003, record.version)
    assert.is_nil(second:crew())
    assert.equal(1, countEvents(deps, "crewChanged"))
  end)

  it("still shows your Character after leaving, and brings your Member id back on rejoining", function()
    local deps = newDeps()
    local core = load().Core.new(deps)
    core:updateOwn(character())
    local code = core:startCrew("Stian").code
    local before = core:rows()
    core:leaveCrew()
    core:up()

    local left = core:rows()
    assert.equal(1, #left)
    assert.equal("Thrallbane", left[1].name)
    assert.equal(24, left[1].level)
    assert.are_not.equal(before[1].memberId, left[1].memberId)
    assert.is_table(core:joinCrew(code))
    assert.same(before, core:rows())
  end)

  it("gives a different Crew a new Member id, named as given", function()
    local core = load().Core.new(newDeps())
    core:updateOwn(character())
    core:startCrew("Stian")
    local first = core:rows()[1].memberId
    core:leaveCrew()
    core:up()

    assert.is_table(core:joinCrew(withCheck("K3F9A2Q"), "Thrall"))
    local row = core:rows()[1]
    assert.are_not.equal(first, row.memberId)
    assert.equal("Thrall", row.displayName)
    assert.equal("Thrallbane", row.name)
  end)

  it("keeps your display name after leaving, for the next Crew you start or join", function()
    local core = load().Core.new(newDeps())
    core:updateOwn(character())
    core:startCrew("Stian")
    core:leaveCrew()
    core:up()

    assert.equal("Stian", core:displayName())
    assert.is_table(core:startCrew())
    assert.equal("Stian", core:rows()[1].displayName)
  end)

  it("leaves the left Crew alone when a different one is refused for its name", function()
    local core = load().Core.new(newDeps())
    core:updateOwn(character())
    local code = core:startCrew("Stian").code
    local first = core:rows()[1].memberId
    core:leaveCrew()
    core:up()

    assert.same({ nil, "invalidName" }, { core:joinCrew(withCheck("K3F9A2Q"), "A") })
    assert.same({ nil, "invalidName" }, { core:startCrew("A") })
    assert.is_table(core:joinCrew(code))
    assert.equal(first, core:rows()[1].memberId)
  end)

  it("lets you join another Crew once leaving has finished", function()
    local core = load().Core.new(newDeps())
    core:startCrew("Stian")
    core:leaveCrew()
    assert.same({ nil, "inCrew" }, { core:joinCrew(withCheck("K3F9A2Q"), "BB") })
    core:up()
    assert.is_table(core:joinCrew(withCheck("K3F9A2Q"), "BB"))
  end)

  it("is cancelled by rejoining the same Crew before it finished", function()
    local ns = load()
    local deps = newDeps()
    local core = ns.Core.new(deps)
    local code = core:startCrew("Stian").code
    core:leaveCrew()
    local crew = core:joinCrew(code)
    assert.is_nil(crew.leaving)
    core:up()
    for _, message in ipairs(deps.sent) do
      local decoded = ns.Codec.decode(message)
      for _, record in ipairs(decoded.records or {}) do assert.is_nil(record.left) end
    end
    assert.same(crew, core:crew())
  end)

  it("still leaves after a rename while leaving", function()
    local ns = load()
    local deps = newDeps()
    local core = ns.Core.new(deps)
    core:startCrew("Stian")
    core:leaveCrew()
    core:setDisplayName("Renamed")
    core:up()
    local record = tombstone(ns, deps.sent[1])
    assert.is_true(record.left)
    assert.equal("Renamed", record.displayName)
  end)

  it("redraws while a leave waits for the link, so views can hide Leave Crew", function()
    local deps = newDeps()
    local core = load().Core.new(deps)
    core:startCrew("Stian")
    local before = countEvents(deps, "changed")
    core:leaveCrew()
    assert.is_true(core:crew().leaving)
    assert.equal(before + 1, countEvents(deps, "changed"))
  end)

  it("finishes without the link once joining failed on a wrong password, and sends nothing", function()
    local deps = newDeps()
    local core = load().Core.new(deps)
    core:updateOwn(character())
    core:startCrew("Stian")
    core:joinFailed("wrongPassword")
    assert.same({ "notice", "wrongPassword" }, deps.events[#deps.events])
    deps.sent = {}

    assert.is_true(core:leaveCrew())
    assert.same({}, deps.sent)
    assert.is_nil(core:crew())
    assert.equal(2, countEvents(deps, "crewChanged"))
    assert.same({ "notice", "leftCrew" }, deps.events[#deps.events])
    assert.is_table(core:startCrew("Stian"))
  end)

  it("finishes a leave already waiting when joining then fails on too many channels", function()
    local deps = newDeps()
    local core = load().Core.new(deps)
    core:startCrew("Stian")
    core:leaveCrew()
    deps.sent = {}

    core:joinFailed("tooManyChannels")
    assert.same({}, deps.sent)
    assert.is_nil(core:crew())
    assert.same({ "notice", "leftCrew" }, deps.events[#deps.events])
    assert.equal(1, countEvents(deps, "notice"))
    assert.is_table(core:joinCrew(withCheck("K3F9A2Q"), "BB"))
  end)

  it("finishes a leave pending at login once that login's join fails", function()
    local ns = load()
    local db = {}
    local first = ns.Core.new(newDeps(db))
    first:startCrew("Stian")
    first:leaveCrew()

    local deps = newDeps(db)
    local second = ns.Core.new(deps)
    assert.is_true(second:crew().leaving)
    second:joinFailed("wrongPassword")
    assert.same({}, deps.sent)
    assert.is_nil(second:crew())
    assert.same({ "notice", "leftCrew" }, deps.events[#deps.events])
    assert.is_table(second:startCrew("Stian"))
  end)

  it("still waits for the link after a failure in a Crew since left and joined again", function()
    local deps = newDeps()
    local core = load().Core.new(deps)
    core:startCrew("Stian")
    core:joinFailed("wrongPassword")
    core:leaveCrew()
    core:joinCrew(withCheck("K3F9A2Q"), "BB")
    core:leaveCrew()
    assert.is_true(core:crew().leaving)
  end)

  it("ignores a join failure outside a Crew, or of a kind it doesn't know", function()
    local deps = newDeps()
    local core = load().Core.new(deps)
    core:joinFailed("wrongPassword")
    assert.is_nil(core:joinFailure())
    core:startCrew("Stian")
    core:joinFailed("bogus")
    core:leaveCrew()
    assert.is_true(core:crew().leaving)
    assert.is_nil(core:joinFailure())
  end)

  it("needs a Crew to leave", function()
    local core = load().Core.new(newDeps())
    assert.same({ nil, "noCrew" }, { core:leaveCrew() })
  end)
end)

describe("The last join failure", function()
  it("is saved with its kind and time, kept across a reload, and cleared once the link is up", function()
    local ns = load()
    local db = {}
    local deps = newDeps(db)
    local core = ns.Core.new(deps)
    assert.is_nil(core:joinFailure())
    core:startCrew("Stian")
    core:joinFailed("tooManyChannels")
    assert.same({ kind = "tooManyChannels", at = 1000 }, core:joinFailure())

    local again = ns.Core.new(newDeps(db))
    assert.same({ kind = "tooManyChannels", at = 1000 }, again:joinFailure())
    again:up()
    assert.is_nil(again:joinFailure())
  end)

  it("is saved for a channel the game left BFF half in, and tells the player", function()
    local deps = newDeps({})
    local core = load().Core.new(deps)
    core:startCrew("Stian")
    core:joinFailed("stuckChannel")
    assert.same({ kind = "stuckChannel", at = 1000 }, core:joinFailure())
    assert.same({ "notice", "stuckChannel" }, deps.events[#deps.events])
  end)

  it("is kept after leaving the Crew it failed in", function()
    local core = load().Core.new(newDeps())
    core:startCrew("Stian")
    core:joinFailed("wrongPassword")
    core:leaveCrew()
    assert.same({ kind = "wrongPassword", at = 1000 }, core:joinFailure())
  end)
end)

describe("Leaving and rejoining the same Crew", function()
  local function crewOfThree()
    local ns = load()
    local net = ns.FakeNet.new()
    local ann = net:add("Ann"):login()
    local bob = net:add("Bob"):login()
    local cat = net:add("Cat"):login()
    local code = ann:join()
    bob:join(code)
    cat:join(code)
    net:run(20)
    bob:play({ level = 11 })
    net:run(20)
    assert.is_true(ann.core:removeMember(cat.memberId))
    ann.core:channelBroken()
    return net, ann, bob, code
  end

  local function entries(client)
    local all = {}
    for _, day in ipairs(client.core:feed().days) do
      for _, entry in ipairs(day.entries) do
        local reactors = {}
        for _, reactor in ipairs(entry.reactors or {}) do reactors[#reactors + 1] = reactor.displayName or reactor.name end
        all[#all + 1] = { text = entry.text, reactors = reactors }
      end
    end
    return all
  end

  local function react(client)
    for _, day in ipairs(client.core:feed().days) do
      for _, entry in ipairs(day.entries) do
        if entry.key and client.core:react(entry.key) then return true end
      end
    end
    return false
  end

  local function removedNames(client)
    local names = {}
    for _, member in ipairs(client.core:removed()) do names[#names + 1] = member.displayName end
    return names
  end

  local function members(client)
    local names = {}
    for _, row in ipairs(client.core:rows("name")) do names[#names + 1] = row.displayName end
    return names
  end

  local function reached(client)
    local result = {}
    for _, row in ipairs(client.core:goals()) do result[row.track] = row.reached end
    return result
  end

  local function contains(list, wanted)
    for _, item in ipairs(list) do
      if item.text == wanted.text then
        assert.same(wanted, item)
        return
      end
    end
    error("missing feed entry " .. tostring(wanted.text))
  end

  it("keeps the Crew's data out of sight, and brings it all back", function()
    local net, ann, _, code = crewOfThree()
    assert.is_true(react(ann))
    net:run(5)
    local feed, goals = entries(ann), reached(ann)
    assert.same({ "Ann", "Bob" }, members(ann))
    assert.same({ "Cat" }, removedNames(ann))
    assert.is_true(#feed > 0)
    local reactedTo = false
    for _, entry in ipairs(feed) do reactedTo = reactedTo or #entry.reactors > 0 end
    assert.is_true(reactedTo)
    assert.equal(1, ann.core:crew().generation)

    ann.core:leaveCrew()
    net:run(5)
    assert.is_nil(ann.core:crew())
    assert.same({ "Ann" }, members(ann))
    assert.same({}, removedNames(ann))
    assert.same({}, entries(ann))

    ann:join(code)
    assert.same({ "Ann", "Bob" }, members(ann))
    assert.same({ "Cat" }, removedNames(ann))
    assert.same(goals, reached(ann))
    assert.equal(1, ann.core:crew().generation)
    local after = entries(ann)
    for _, entry in ipairs(feed) do contains(after, entry) end
  end)

  it("brings it back after a logout too", function()
    local net, ann, _, code = crewOfThree()
    local id = ann.memberId
    ann.core:leaveCrew()
    net:run(5)
    ann:logout()
    net:run(5)
    ann:login()
    assert.is_nil(ann.core:crew())
    ann:join(code)
    assert.same({ "Ann", "Bob" }, members(ann))
    assert.equal(1, ann.core:crew().generation)
    assert.equal(id, ann.memberId)
  end)

  it("comes back under the same Member id for the others, with no second row", function()
    local net, ann, bob, code = crewOfThree()
    local id = ann.memberId
    ann.core:leaveCrew()
    net:run(5)
    assert.is_nil(bob:rowFor(ann))
    ann:join(code)
    net:run(20)
    assert.equal(id, ann.memberId)
    assert.same({ "Bob", "Ann", "Cat" }, members(bob))
    assert.is_table(bob:rowFor(ann))
  end)

  it("shows a different Crew's Members you as someone new", function()
    local net, ann, bob = crewOfThree()
    local id = ann.memberId
    ann.core:leaveCrew()
    net:run(5)
    local code = ann:join()
    bob.core:leaveCrew()
    net:run(5)
    bob:join(code)
    net:run(20)
    assert.are_not.equal(id, ann.memberId)
    assert.equal("Ann", bob:rowFor(ann).displayName)
  end)

  it("keeps it through starting or joining a different Crew", function()
    local net, ann, _, code = crewOfThree()
    local original = ann.memberId
    ann.core:leaveCrew()
    net:run(5)
    ann:join()
    assert.same({ "Ann" }, members(ann))
    assert.same({}, removedNames(ann))
    assert.equal(0, ann.core:crew().generation)

    ann.core:leaveCrew()
    net:run(5)
    ann:join(withCheck("K3F9A2Q"))
    assert.same({ "Ann" }, members(ann))
    ann.core:leaveCrew()
    net:run(5)
    ann:join(code)
    assert.same({ "Ann", "Bob" }, members(ann))
    assert.same({ "Cat" }, removedNames(ann))
    assert.equal(1, ann.core:crew().generation)
    assert.equal(original, ann.memberId)
  end)
end)
