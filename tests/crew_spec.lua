local load = require("tests.load")

local ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

local function newDeps(db)
  local deps = {
    sent = {},
    events = {},
    db = db or {},
    clock = 1000,
    random = math.random,
    receiveOnly = false,
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

-- A code whose check character is right, built from 7 chosen characters.
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

    -- The same code always gives the same channel, a different one doesn't.
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

describe("Receive-only accounts", function()
  it("can join a Crew but not start one", function()
    local deps = newDeps()
    deps.receiveOnly = true
    local core = load().Core.new(deps)
    assert.is_true(core:isReceiveOnly())
    assert.same({ nil, "receiveOnly" }, { core:startCrew("AA") })
    assert.is_table(core:joinCrew(withCheck("K3F9A2Q"), "AA"))
  end)
end)

describe("Leaving the Crew", function()
  local function tombstone(ns, message)
    local decoded = ns.Codec.decode(message)
    assert.is_table(decoded)
    assert.equal("DATA", decoded.type)
    return decoded.record
  end

  it("sends the tombstone right away when the link is up, then forgets the Crew", function()
    local ns = load()
    local deps = newDeps()
    local core = ns.Core.new(deps)
    core:updateOwn(character())
    core:startCrew("Stian")
    core:up()
    deps.sent = {}

    deps.clock = deps.clock + 60
    assert.is_true(core:leaveCrew())

    assert.equal(1, #deps.sent)
    local record = tombstone(ns, deps.sent[1])
    assert.is_true(record.left)
    assert.equal("Stian", record.displayName)
    assert.equal(core:rows()[1].memberId, record.id)
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
    assert.equal(1002, record.version)
    assert.is_nil(second:crew())
    assert.equal(1, countEvents(deps, "crewChanged"))
  end)

  it("keeps your own Member id and Characters for rejoining", function()
    local deps = newDeps()
    local core = load().Core.new(deps)
    core:updateOwn(character())
    local before = core:rows()
    local code = core:startCrew("Stian").code
    core:leaveCrew()
    core:up()

    assert.same(before, core:rows())
    assert.is_table(core:joinCrew(code))
    assert.same(before, core:rows())
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
    local deps = newDeps()
    local core = load().Core.new(deps)
    local code = core:startCrew("Stian").code
    core:leaveCrew()
    local crew = core:joinCrew(code)
    assert.is_nil(crew.leaving)
    core:up()
    assert.same({}, deps.sent)
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

  it("needs a Crew to leave", function()
    local core = load().Core.new(newDeps())
    assert.same({ nil, "noCrew" }, { core:leaveCrew() })
  end)
end)
