local load = require("tests.load")

local DAY = 24 * 60 * 60

local function playing(name, extra)
  local character = {
    guid = "Player-0-" .. name, name = name, classFilename = "WARRIOR",
    level = 10, xp = 0, maxXp = 1000, zone = "Elwynn Forest", deaths = 0,
  }
  for k, v in pairs(extra or {}) do character[k] = v end
  return character
end

-- A net with the given clients logged in and in one Crew. Settled unless
-- settle is false. start maps a name to what its Character starts with.
local function crew(names, start, settle)
  local ns = load()
  local net = ns.FakeNet.new()
  local clients = {}
  for i, name in ipairs(names) do
    clients[i] = net:add(name, { character = playing(name, start and start[name]) }):login()
  end
  local code = clients[1]:join()
  for i = 2, #clients do clients[i]:join(code) end
  net:run(settle == false and 2 or 40)
  return net, clients
end

-- Jumps the clock on by seconds, in one step.
local function later(net, seconds)
  net:step(net.clock + seconds)
end

local function labels(trophies)
  local list = {}
  for i, trophy in ipairs(trophies) do list[i] = trophy.track .. " " .. trophy.label end
  return list
end

local function profession(skillLine, name, skill)
  return { skillLine = skillLine, name = name, icon = 1000 + skillLine, skill = skill, max = 300 }
end

describe("Trophies", function()
  it("are nothing until the first sync has settled", function()
    local _, clients = crew({ "Ann", "Bob" }, { Ann = { level = 30 }, Bob = { level = 25 } }, false)
    local trophies = clients[1].core:trophies()
    assert.is_false(trophies.settled)
    assert.same({}, trophies.shelf)
    assert.same({}, trophies.cabinet)
    assert.equal(0, trophies.count)
    assert.is_nil(trophies.latest)
  end)

  it("are settled with nothing reached in a Crew that hasn't reached a rung", function()
    local _, clients = crew({ "Ann" }, { Ann = { level = 5 } })
    local trophies = clients[1].core:trophies()
    assert.is_true(trophies.settled)
    assert.same({}, trophies.shelf)
    assert.is_nil(trophies.latest)
  end)

  it("put every reached rung on the shelf with its date, newest first", function()
    local net, clients = crew({ "Ann", "Bob" }, { Ann = { level = 30 }, Bob = { level = 21 } })
    local a, b = clients[1], clients[2]
    later(net, 2 * DAY)
    a:play({ level = 31, deaths = 25 })
    net:run(3)
    local reachedAt = net.clock - 3
    later(net, DAY)
    b:play({ level = 30 })
    net:run(3)

    local shelf = b.core:trophies().shelf
    assert.same({
      "everyone 30", "deaths 25", "crewLevels 50", "everyone 20", "everyone 10",
    }, labels(shelf))
    -- The baseline's, together.
    assert.equal(shelf[3].time, shelf[5].time)
    assert.is_true(shelf[5].time < shelf[2].time)
    assert.is_true(shelf[2].time >= reachedAt and shelf[2].time <= reachedAt + 3)
    assert.equal("The Crew has died 25 times together!", shelf[2].text)
    assert.equal("Everyone in the Crew has a Character at 30!", shelf[1].text)
    assert.equal("Crew deaths", shelf[2].title)
    assert.matches("^%d+ %a%a%a$", shelf[2].date)
    assert.equal(5, b.core:trophies().count)
  end)

  it("tier a track's rungs by how many it has reached, in item quality", function()
    local net, clients = crew({ "Ann" }, { Ann = { level = 5 } })
    local a = clients[1]
    a:play({ deaths = 2500 })
    net:run(3)
    local cabinet = a.core:trophies().cabinet
    assert.equal(1, #cabinet)
    assert.equal("deaths", cabinet[1].track)
    assert.equal("Crew deaths", cabinet[1].title)
    local qualities = {}
    for i, trophy in ipairs(cabinet[1].trophies) do qualities[i] = trophy.label .. " " .. trophy.quality end
    assert.same({
      "25 uncommon", "50 uncommon", "100 rare", "250 rare", "500 epic", "1,000 epic", "2,500 legendary",
    }, qualities)
  end)

  it("group by track for the cabinet, oldest first, leaving out tracks with none", function()
    local net, clients = crew({ "Ann", "Bob" }, { Ann = { level = 30 }, Bob = { level = 21 } })
    local a, b = clients[1], clients[2]
    later(net, DAY)
    a:play({ level = 31, deaths = 25 })
    net:run(3)
    later(net, DAY)
    b:play({ level = 30 })
    net:run(3)

    local trophies = b.core:trophies()
    local tracks = {}
    for i, group in ipairs(trophies.cabinet) do tracks[i] = group.track .. " " .. #group.trophies end
    assert.same({ "crewLevels 1", "everyone 3", "deaths 1" }, tracks)
    assert.same({ "everyone 10", "everyone 20", "everyone 30" }, labels(trophies.cabinet[2].trophies))
    assert.equal(5, trophies.count)
  end)

  it("give Every profession's medals the profession's icon and name, all one tier", function()
    local net, clients = crew({ "Ann" }, { Ann = { level = 5 } })
    local a = clients[1]
    a:play({ professions = { profession(171, "Alchemy", 40) } })
    a:play({ level = 6 })
    net:run(3)
    later(net, DAY)
    a:play({ professions = { profession(171, "Alchemy", 40), profession(202, "Engineering", 1) } })
    a:play({ level = 7 })
    net:run(3)

    local group = a.core:trophies().cabinet[1]
    assert.equal("professions", group.track)
    assert.same({ "professions Alchemy", "professions Engineering" }, labels(group.trophies))
    assert.equal(1202, group.trophies[2].icon)
    assert.equal("rare", group.trophies[1].quality)
    assert.equal("rare", group.trophies[2].quality)
    assert.equal("The Crew has an Engineer now!", group.trophies[2].text)
  end)

  it("are fresh for 3 days after they're reached", function()
    local net, clients = crew({ "Ann" }, { Ann = { level = 10 } })
    local a = clients[1]
    a:play({ deaths = 25 })
    net:run(3)
    assert.is_true(a.core:trophies().shelf[1].fresh)
    later(net, 3 * DAY - 10)
    assert.is_true(a.core:trophies().shelf[1].fresh)
    later(net, 20)
    assert.is_false(a.core:trophies().shelf[1].fresh)
  end)

  it("lead with the latest win and how many others were reached since the tab was opened", function()
    local net, clients = crew({ "Ann", "Bob" }, { Ann = { level = 30 }, Bob = { level = 21 } })
    local a, b = clients[1], clients[2]

    -- Never opened: nothing counts as since.
    local trophies = b.core:trophies()
    -- The baseline's rungs together: by track, the highest first.
    assert.equal("crewLevels 50", trophies.latest.track .. " " .. trophies.latest.label)
    assert.equal(0, trophies.sinceSeen)

    b.core:openGoals()
    b.core:leaveGoals()
    later(net, DAY)
    a:play({ level = 31, deaths = 25 })
    net:run(3)
    later(net, DAY)
    b:play({ level = 30 })
    net:run(3)

    b.core:openGoals()
    trophies = b.core:trophies()
    assert.equal("Everyone in the Crew has a Character at 30!", trophies.latest.text)
    -- Crew deaths 25, besides the latest.
    assert.equal(1, trophies.sinceSeen)
    -- Through the visit, redraws keep the count.
    b.core:openGoals()
    assert.equal(1, b.core:trophies().sinceSeen)
    b.core:leaveGoals()
    b.core:openGoals()
    assert.equal(0, b.core:trophies().sinceSeen)
  end)

  it("aren't news when reached quietly: not fresh, nor counted since the tab was opened", function()
    local net, clients = crew({ "Ann", "Bob" }, { Ann = { level = 30, deaths = 30 }, Bob = { level = 21 } }, false)
    local a = clients[1]
    -- Opened while the Crew is still being counted.
    a.core:openGoals()
    a.core:leaveGoals()
    net:run(40)
    a:play({ deaths = 50 })
    net:run(3)
    a.core:openGoals()
    local trophies = a.core:trophies()
    assert.equal("deaths 50", trophies.latest.track .. " " .. trophies.latest.label)
    assert.is_true(trophies.latest.fresh)
    -- The baseline's rungs: reached, but not news.
    assert.equal(0, trophies.sinceSeen)
    for i = 2, #trophies.shelf do assert.is_false(trophies.shelf[i].fresh) end
  end)

  it("count how many rungs each track has reached on the Goals tab", function()
    local net, clients = crew({ "Ann" }, { Ann = { level = 30 } })
    local a = clients[1]
    a:play({ deaths = 60 })
    net:run(3)
    local rows = {}
    for _, row in ipairs(a.core:goals()) do rows[row.track] = row end
    assert.equal(3, rows.everyone.reached)
    assert.equal(2, rows.deaths.reached)
    assert.equal(0, rows.crewLevels.reached)
    assert.matches("^%d+ %a%a%a$", rows.deaths.last.date)
  end)

  it("start again in a new Crew", function()
    local net, clients = crew({ "Ann" }, { Ann = { level = 30 } })
    local a = clients[1]
    a.core:openGoals()
    a.core:leaveCrew()
    net:run(3)
    a:join()
    net:run(2)
    local trophies = a.core:trophies()
    assert.is_false(trophies.settled)
    assert.same({}, trophies.shelf)
  end)
end)
