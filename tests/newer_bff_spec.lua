local load = require("tests.load")

local function playing(name)
  return {
    guid = "Player-0-" .. name, name = name, classFilename = "MAGE",
    level = 10, xp = 0, maxXp = 1000, zone = "Elwynn Forest", deaths = 0,
  }
end

describe("A Member on a newer BFF", function()
  local net

  local function client(name, version, db)
    return net:add(name, { character = playing(name), version = version, db = db })
  end

  local function crew(you, ...)
    local code = you:join()
    for _, friend in ipairs({ ... }) do friend:join(code) end
    net:run(60)
    return code
  end

  local function told(c)
    local list = {}
    for _, event in ipairs(c.events) do
      if event[1] == "newerBff" then list[#list + 1] = event[2] end
    end
    return list
  end

  before_each(function()
    net = load().FakeNet.new()
  end)

  it("is told once, with the version and the friend who has it", function()
    local ann = client("Ann", "v2.2.0"):login()
    local bob = client("Bob", "v2.3.0"):login()
    crew(ann, bob)
    assert.are.same({ {
      version = "2.3.0", members = { "Bob" },
      text = "BFF 2.3.0 is out: Bob has it. Update on CurseForge to get what's new.",
    } }, told(ann))
    assert.are.same({}, told(bob))
  end)

  it("says nothing for friends on the same or an older version", function()
    local ann = client("Ann", "v2.2.0"):login()
    local bob = client("Bob", "v2.2.0"):login()
    local cat = client("Cat", "v2.1.3"):login()
    crew(ann, bob, cat)
    assert.are.same({}, told(ann))
    assert.are.same({}, told(bob))
  end)

  it("names one friend on the newest version and counts the rest", function()
    local ann = client("Ann", "v2.2.0"):login()
    local bob = client("Bob", "v2.3.0"):login()
    local cat = client("Cat", "v2.3.0"):login()
    local dee = client("Dee", "v2.3.0"):login()
    crew(ann, bob, cat, dee)
    local lines = told(ann)
    assert.are.equal(1, #lines)
    assert.are.equal(3, #lines[1].members)
    assert.are.equal(("BFF 2.3.0 is out: %s and 2 others have it. Update on CurseForge to get what's new.")
      :format(lines[1].members[1]), lines[1].text)
  end)

  it("says \"1 other\" for two friends", function()
    local ann = client("Ann", "v2.2.0"):login()
    local bob = client("Bob", "v2.3.0"):login()
    local cat = client("Cat", "v2.3.0"):login()
    crew(ann, bob, cat)
    assert.matches("and 1 other have it%.", told(ann)[1].text)
  end)

  it("names the highest version any friend runs", function()
    local ann = client("Ann", "v2.2.0"):login()
    local bob = client("Bob", "v2.3.0"):login()
    local cat = client("Cat", "v2.10.0"):login()
    crew(ann, bob, cat)
    local lines = told(ann)
    assert.are.equal(1, #lines)
    assert.are.equal("2.10.0", lines[#lines].version)
    assert.are.same({ "Cat" }, lines[#lines].members)
  end)

  it("uses the friend's display name", function()
    local ann = client("Ann", "v2.2.0"):login()
    local bob = client("Bob", "v2.3.0"):login()
    bob:join(ann:join())
    bob.core:setDisplayName("Mirelle")
    net:run(60)
    assert.are.same({ "Mirelle" }, told(ann)[1].members)
    assert.matches("Mirelle has it", told(ann)[1].text)
  end)

  it("isn't told again as more records arrive, or after a reload or a new login", function()
    local ann = client("Ann", "v2.2.0"):login()
    local bob = client("Bob", "v2.3.0"):login()
    crew(ann, bob)
    bob:play({ level = 11 })
    net:run(60)
    ann:reload()
    net:run(60)
    ann:logout()
    ann:login()
    net:run(60)
    assert.are.equal(1, #told(ann))
  end)

  it("is told again when an even newer version turns up", function()
    local ann = client("Ann", "v2.2.0"):login()
    local bob = client("Bob", "v2.3.0"):login()
    crew(ann, bob)
    bob.version = "v2.4.1"
    bob:reload()
    net:run(60)
    local lines = told(ann)
    assert.are.equal(2, #lines)
    assert.are.equal("2.4.1", lines[2].version)
  end)

  it("says nothing once you run that version or later", function()
    local ann = client("Ann", "v2.2.0", { newerBffTold = "2.3.0" }):login()
    local bob = client("Bob", "v2.3.0"):login()
    crew(ann, bob)
    assert.are.same({}, told(ann))
    ann.version = "v2.4.0"
    ann.db.newerBffTold = nil
    ann:reload()
    net:run(60)
    assert.are.same({}, told(ann))
  end)

  it("says nothing on a checkout", function()
    local ann = client("Ann", "dev"):login()
    local bob = client("Bob", "v2.3.0"):login()
    crew(ann, bob)
    assert.are.same({}, told(ann))
  end)

  it("ignores a friend on a checkout", function()
    local ann = client("Ann", "v2.2.0"):login()
    local bob = client("Bob", "dev"):login()
    crew(ann, bob)
    assert.are.same({}, told(ann))
  end)

  it("ignores Members who left or were removed", function()
    local ann = client("Ann", "dev"):login()
    local bob = client("Bob", "v2.3.0"):login()
    local cat = client("Cat", "v2.3.0"):login()
    crew(ann, bob, cat)
    bob.core:leaveCrew()
    net:run(10)
    ann.core:removeMember(cat.memberId)
    ann.version = "v2.2.0"
    ann:reload()
    net:run(120)
    assert.are.same({}, told(ann))
  end)

  it("says nothing outside a Crew", function()
    local ann = client("Ann", "v2.2.0"):login()
    net:run(60)
    assert.are.same({}, told(ann))
  end)

  it("is told once sync settles after login, for versions saved earlier", function()
    local ann = client("Ann", "dev"):login()
    local bob = client("Bob", "v2.3.0"):login()
    crew(ann, bob)
    bob:logout()
    ann:logout()
    ann.version = "v2.2.0"
    ann:login()
    net:run(1)
    assert.are.same({}, told(ann))
    net:run(120)
    assert.are.equal(1, #told(ann))
    assert.are.equal("2.3.0", told(ann)[1].version)
  end)
end)
