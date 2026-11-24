local load = require("tests.load")

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

local function countEvents(deps, name, arg)
  local n = 0
  for _, e in ipairs(deps.events) do
    if e[1] == name and (arg == nil or e[2] == arg) then n = n + 1 end
  end
  return n
end

local function record(id, version, fields)
  local result = { id = id, version = version, displayName = id, characters = {} }
  for k, v in pairs(fields or {}) do result[k] = v end
  return result
end

local function sentOwn(ns, deps)
  for i = #deps.sent, 1, -1 do
    local decoded = ns.Codec.decode(deps.sent[i])
    for _, sent in ipairs(type(decoded) == "table" and decoded.records or {}) do
      if sent.id == decoded.from then return sent end
    end
  end
  return nil
end

local function receive(ns, core, from, records)
  core:received(ns.Codec.encode({ type = "DATA", from = from, records = records }), from)
end

describe("Channel generations", function()
  it("start at generation 0, the channel a Crew always had", function()
    local ns = load()
    local deps = newDeps()
    local core = ns.Core.new(deps)
    core:up()
    local crew = core:startCrew("Stian")
    local channel, password = ns.CrewCode.channel(crew.code)
    assert.equal(0, crew.generation)
    assert.equal(channel, crew.channel)
    assert.equal(password, crew.password)
    assert.is_table(sentOwn(ns, deps))
    assert.is_nil(sentOwn(ns, deps).generation)
  end)

  it("name generation N from the code and N, with the generation 0 password", function()
    local CrewCode = load().CrewCode
    local zero, password = CrewCode.channel("K3F9-A2QX", 0)
    local one, onePassword = CrewCode.channel("K3F9-A2QX", 1)
    local two = CrewCode.channel("K3F9-A2QX", 2)
    assert.equal(CrewCode.channel("K3F9-A2QX"), zero)
    assert.equal(one, (CrewCode.channel("K3F9-A2QX#1")))
    assert.are_not.equal(zero, one)
    assert.are_not.equal(one, two)
    assert.equal(password, onePassword)
    assert.matches("^BFF[0-9A-Z]+$", one)
    assert.equal(10, #one)
  end)

  it("step up one when the game breaks the channel, saved and written into your own record", function()
    local ns = load()
    local db = {}
    local deps = newDeps(db)
    local core = ns.Core.new(deps)
    local code = core:startCrew("Stian").code
    core:up()
    deps.sent = {}

    core:channelBroken()
    local crew = core:crew()
    assert.equal(1, crew.generation)
    assert.equal(ns.CrewCode.channel(code, 1), crew.channel)
    assert.equal(1, crew.moves)
    assert.equal("moved this session", crew.generationFrom)
    assert.equal(2, countEvents(deps, "crewChanged"))
    core:tick()
    assert.equal(1, sentOwn(ns, deps).generation)

    local again = ns.Core.new(newDeps(db))
    assert.equal(1, again:crew().generation)
    assert.equal("saved", again:crew().generationFrom)
  end)

  it("stop after 5 steps in a session, say so once, and try again from the next login", function()
    local ns = load()
    local db = {}
    local deps = newDeps(db)
    local core = ns.Core.new(deps)
    core:startCrew("Stian")
    for _ = 1, 5 do core:channelBroken() end
    assert.equal(5, core:crew().generation)
    assert.is_false(core:crew().capped)

    core:channelBroken()
    core:channelBroken()
    local crew = core:crew()
    assert.equal(5, crew.generation)
    assert.is_true(crew.capped)
    assert.equal("The game won't let BFF into any channel for your Crew. Try again later.", crew.status)
    assert.is_true(crew.waiting)
    assert.equal(6, countEvents(deps, "crewChanged"))
    assert.equal(1, countEvents(deps, "notice", "noChannel"))

    local reloaded = ns.Core.new((function()
      local d = newDeps(db)
      d.initialLogin = false
      return d
    end)())
    reloaded:channelBroken()
    assert.equal(5, reloaded:crew().generation)

    local deps2 = newDeps(db)
    local nextLogin = ns.Core.new(deps2)
    assert.equal(0, nextLogin:crew().moves)
    assert.is_false(nextLogin:crew().capped)
    nextLogin:channelBroken()
    assert.equal(6, nextLogin:crew().generation)
  end)

  it("keep counting moves across leaving and rejoining, and say it once across a reload", function()
    local ns = load()
    local db = {}
    local deps = newDeps(db)
    local core = ns.Core.new(deps)
    local code = core:startCrew("Stian").code
    for _ = 1, 5 do core:channelBroken() end
    core:leaveCrew()
    core:up()
    core:joinCrew(code)
    assert.equal(5, core:crew().moves)
    core:channelBroken()
    assert.is_true(core:crew().capped)

    local reloadDeps = newDeps(db)
    reloadDeps.initialLogin = false
    local reloaded = ns.Core.new(reloadDeps)
    reloaded:channelBroken()
    assert.is_true(reloaded:crew().capped)
    assert.equal(1, countEvents(deps, "notice", "noChannel"))
    assert.equal(0, countEvents(reloadDeps, "notice", "noChannel"))
  end)

  it("finish a leave started once capped, since the link won't come up", function()
    local deps = newDeps()
    local core = load().Core.new(deps)
    core:startCrew("Stian")
    for _ = 1, 6 do core:channelBroken() end
    core:leaveCrew()
    assert.is_nil(core:crew())
    assert.same({ "notice", "leftCrew" }, deps.events[#deps.events])
  end)

  it("finish a waiting leave at the cap, since the link won't come up", function()
    local deps = newDeps()
    local core = load().Core.new(deps)
    core:startCrew("Stian")
    for _ = 1, 5 do core:channelBroken() end
    core:leaveCrew()
    core:channelBroken()
    assert.is_nil(core:crew())
    assert.same({ "notice", "leftCrew" }, deps.events[#deps.events])
  end)

  it("join the highest generation in a current Member's record, and never go down", function()
    local ns = load()
    local deps = newDeps()
    local core = ns.Core.new(deps)
    local code = core:startCrew("Stian").code

    receive(ns, core, "ann", { record("ann", 2000, { generation = 2 }) })
    local crew = core:crew()
    assert.equal(2, crew.generation)
    assert.equal(ns.CrewCode.channel(code, 2), crew.channel)
    assert.equal("ann's record", crew.generationFrom)
    assert.equal(0, crew.moves)
    assert.equal(2, countEvents(deps, "crewChanged"))

    receive(ns, core, "bob", { record("bob", 2000, { generation = 1 }) })
    assert.equal(2, core:crew().generation)
    assert.equal(2, countEvents(deps, "crewChanged"))
  end)

  it("join a Crew's current generation at login from a record received earlier", function()
    local ns = load()
    local db = {}
    local core = ns.Core.new(newDeps(db))
    core:startCrew("Stian")
    db.records.ann = record("ann", 2000, { generation = 3 })

    local deps = newDeps(db)
    local again = ns.Core.new(deps)
    assert.equal(3, again:crew().generation)
    assert.equal("ann's record", again:crew().generationFrom)
    assert.equal(0, countEvents(deps, "crewChanged"))
  end)

  it("never take a generation from a left or Removed Member", function()
    local ns = load()
    local core = ns.Core.new(newDeps())
    core:startCrew("Stian")
    receive(ns, core, "ann", { record("ann", 2000, { generation = 4, left = true }) })
    assert.equal(0, core:crew().generation)

    receive(ns, core, "bob", { record("bob", 2000) })
    assert.is_true(core:removeMember("bob"))
    receive(ns, core, "cat", { record("bob", 3000, { generation = 4 }) })
    assert.equal(0, core:crew().generation)

    local db = {}
    local first = ns.Core.new(newDeps(db))
    first:startCrew("Stian")
    db.records.ann = record("ann", 2000, { generation = 4, left = true })
    assert.equal(0, ns.Core.new(newDeps(db)):crew().generation)
  end)

  it("reject a record whose generation isn't a whole number from 0", function()
    local ns = load()
    local core = ns.Core.new(newDeps())
    core:startCrew("Stian")
    receive(ns, core, "ann", { record("ann", 2000, { generation = 1.5 }) })
    receive(ns, core, "bob", { record("bob", 2000, { generation = -1 }) })
    receive(ns, core, "cat", { record("cat", 2000, { generation = "2" }) })
    assert.equal(0, core:crew().generation)
    assert.is_true(core:crew().alone)
  end)

  it("bring two Members together when only one of them can't use the channel", function()
    local ns = load()
    local net = ns.FakeNet.new({ channels = true })
    local ann = net:add("Ann"):login()
    local bob = net:add("Bob"):login()
    local code = ann:join()
    bob:join(code)
    net:run(20)
    assert.is_table(ann:rowFor(bob))
    assert.is_table(bob:rowFor(ann))

    bob.core:channelBroken()
    net:run(1)
    assert.are_not.equal(ann.core:crew().channel, bob.core:crew().channel)

    net.sees = function(from, to) return from == "Ann" and to == "Bob" end
    net:run(180)

    assert.equal(1, ann.core:crew().generation)
    assert.equal(1, bob.core:crew().generation)
    assert.equal(ann.core:crew().channel, bob.core:crew().channel)
    assert.is_true(ann:rowFor(bob).online)
    assert.is_true(bob:rowFor(ann).online)
  end)
end)
