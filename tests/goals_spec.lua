local load = require("tests.load")

local function playing(name, extra)
  local character = {
    guid = "Player-0-" .. name, name = name, classFilename = "WARRIOR",
    level = 10, xp = 0, maxXp = 1000, zone = "Elwynn Forest", deaths = 0,
  }
  for k, v in pairs(extra or {}) do character[k] = v end
  return character
end

-- A net with the given clients logged in and in one Crew, settled. start
-- maps a name to what its Character starts with ({ level, deaths }).
local function crew(names, start, netOptions)
  local ns = load()
  local net = ns.FakeNet.new(netOptions)
  local clients = {}
  for i, name in ipairs(names) do
    clients[i] = net:add(name, { character = playing(name, start and start[name]) }):login()
  end
  local code = clients[1]:join()
  for i = 2, #clients do clients[i]:join(code) end
  net:run(40)
  return net, clients, ns, code
end

-- The client's Goals tab rows, by track.
local function goals(client)
  local byTrack = {}
  for _, row in ipairs(client.core:goals()) do byTrack[row.track] = row end
  return byTrack
end

-- Every goal entry in the client's feed(), newest first.
local function goalEntries(client)
  local list = {}
  for _, day in ipairs(client.core:feed().days) do
    for _, entry in ipairs(day.entries) do
      if entry.kind == "goal" then list[#list + 1] = entry end
    end
  end
  return list
end

local function goalTexts(client)
  local texts = {}
  for i, entry in ipairs(goalEntries(client)) do texts[i] = entry.text end
  return texts
end

local function chatLines(client)
  local lines = {}
  for _, event in ipairs(client.events) do
    if event[1] == "feedEntry" and event[2].kind == "goal" then lines[#lines + 1] = event[2].text end
  end
  return lines
end

describe("Goal ladders", function()
  local Goals = load().Goals

  it("has Crew levels every 50, for ever", function()
    assert.same({ 50, 100, 150 }, Goals.rungs("crewLevels", 199, 60))
    assert.equal(1050, Goals.nextRung("crewLevels", 1000, 60))
  end)

  it("has Everyone at level N every 10 up to max level", function()
    assert.same({ 10, 20, 30, 40, 50, 60 }, Goals.rungs("everyone", 70, 60))
    assert.same({ 10, 20, 30, 40, 50, 55 }, Goals.rungs("everyone", 55, 55))
    assert.is_nil(Goals.nextRung("everyone", 60, 60))
  end)

  it("has Crew deaths at 25, 50, 100, 250 and on", function()
    assert.same({ 25, 50, 100, 250, 500, 1000, 2500 }, Goals.rungs("deaths", 4999, 60))
    assert.equal(5000, Goals.nextRung("deaths", 2500, 60))
    assert.equal(25, Goals.nextRung("deaths", 0, 60))
  end)

  it("works out progress from records, with each Member's highest Character only", function()
    local records = {
      { characters = {
        a = { level = 30, deaths = 4 },
        b = { level = 5, deaths = 2 },
      } },
      { characters = { c = { level = 22, deaths = 1 } } },
      -- A Member with no Characters yet doesn't count.
      { characters = {} },
    }
    local progress = Goals.progress(records)
    assert.equal(52, progress.crewLevels)
    assert.equal(22, progress.lowest)
    assert.equal(2, progress.members)
    assert.equal(7, progress.deaths)
  end)
end)

describe("Crew goals", function()
  it("count each Member's highest Character, and deaths over every Character", function()
    local net, clients = crew({ "Ann", "Bob" }, { Ann = { level = 30, deaths = 4 }, Bob = { level = 12, deaths = 2 } })
    local a = clients[1]

    -- A low Alt doesn't add to Crew levels, but its deaths count.
    a:play({ guid = "Player-0-AnnAlt", name = "Annalt", level = 3, deaths = 5 })
    net:run(3)
    local rows = goals(clients[2])
    assert.equal(42, rows.crewLevels.value)
    assert.equal(50, rows.crewLevels.rung)
    assert.equal(50, rows.crewLevels.goal)
    assert.equal(11, rows.deaths.value)
    assert.equal(25, rows.deaths.rung)
    -- Everyone at 20: one of two Members has a Character there.
    assert.equal(20, rows.everyone.rung)
    assert.equal(1, rows.everyone.value)
    assert.equal(2, rows.everyone.goal)
    assert.equal("Everyone at level 20", rows.everyone.title)
    assert.same({ "crewLevels", "everyone", "deaths" },
      { clients[2].core:goals()[1].track, clients[2].core:goals()[2].track, clients[2].core:goals()[3].track })
  end)

  it("are a silent baseline on first evaluation, shown as reached", function()
    local _, clients = crew({ "Ann", "Bob" }, { Ann = { level = 30, deaths = 30 }, Bob = { level = 25 } })
    for _, client in ipairs(clients) do
      assert.same({}, goalTexts(client))
      assert.same({}, chatLines(client))
      local rows = goals(client)
      assert.equal(50, rows.crewLevels.last.rung)
      assert.equal(20, rows.everyone.last.rung)
      assert.equal(25, rows.deaths.last.rung)
      assert.is_number(rows.deaths.last.time)
    end
  end)

  it("are a silent baseline the first time a client in a Crew has them", function()
    local net, clients = crew({ "Ann", "Bob" }, { Ann = { level = 30 }, Bob = { level = 21 } })
    local a, b = clients[1], clients[2]
    b:logout()
    -- Saved data from before Crew goals existed.
    b.db.goals = nil
    a:play({ level = 31, deaths = 26 })
    net:run(5)
    b.events = {}
    b:login()
    net:run(40)
    assert.same({}, goalTexts(b))
    assert.equal(50, goals(b).crewLevels.last.rung)
    assert.equal(25, goals(b).deaths.last.rung)
    for _, event in ipairs(b.events) do
      if event[1] == "awaySummary" then assert.same({}, event[2].goals) end
    end
  end)

  it("add one highlighted Crew-wide entry when a rung is crossed, with a chat line", function()
    local net, clients = crew({ "Ann", "Bob" }, { Ann = { level = 20 }, Bob = { level = 29 } })
    local a, b = clients[1], clients[2]

    a:play({ level = 21 })
    net:run(3)
    for _, client in ipairs({ a, b }) do
      assert.same({ "The Crew reached 50 Crew levels!" }, goalTexts(client))
      assert.same({ "The Crew reached 50 Crew levels!" }, chatLines(client))
      local entry = goalEntries(client)[1]
      assert.is_nil(entry.memberId)
      assert.is_false(entry.own)
      assert.is_false(entry.canReact)
      assert.equal(50, goals(client).crewLevels.last.rung)
      assert.equal(100, goals(client).crewLevels.rung)
    end

    b:play({ level = 30, deaths = 25 })
    a:play({ level = 30 })
    net:run(3)
    assert.same({
      "Everyone in the Crew has a Character at 30!",
      "The Crew has died 25 times together!",
      "The Crew reached 50 Crew levels!",
    }, goalTexts(b))
  end)

  it("make one entry per track for the highest of several rungs crossed at once", function()
    local net, clients = crew({ "Ann", "Bob" }, { Ann = { level = 10 }, Bob = { level = 10 } })
    local a, b = clients[1], clients[2]

    b:logout()
    net:run(5)
    a:play({ level = 45, deaths = 60 })
    net:run(5)
    b.events = {}
    b:login()
    net:run(40)
    assert.same({ "The Crew has died 50 times together!", "The Crew reached 50 Crew levels!" }, goalTexts(b))
    local rows = goals(b)
    assert.equal(50, rows.deaths.last.rung)
    -- Each rung crossed is reached.
    assert.equal(100, rows.deaths.rung)
    -- No chat line while settling: While you were away has them.
    assert.same({}, chatLines(b))
    local summary
    for _, event in ipairs(b.events) do
      if event[1] == "awaySummary" then summary = event[2] end
    end
    assert.is_table(summary)
    assert.same({ "The Crew has died 50 times together!", "The Crew reached 50 Crew levels!" },
      { summary.goals[1].text, summary.goals[2].text })
    assert.equal(1, #summary.members)
  end)

  it("keep a reached rung after progress drops, and move on to the next", function()
    local net, clients = crew({ "Ann", "Bob", "Cid" }, { Ann = { level = 30 }, Bob = { level = 21 }, Cid = { level = 2 } })
    local a, c = clients[1], clients[3]

    -- 53 Crew levels: 50 reached in the baseline.
    assert.equal(50, goals(a).crewLevels.last.rung)
    assert.is_true(a.core:removeMember(c.memberId))
    local rows = goals(a)
    assert.equal(51, rows.crewLevels.value)
    a:play({ level = 29 })
    net:run(3)
    rows = goals(a)
    assert.equal(50, rows.crewLevels.value)
    assert.equal(50, rows.crewLevels.last.rung)
    assert.equal(100, rows.crewLevels.rung)
    a:play({ level = 28 })
    net:run(3)
    a:play({ level = 30 })
    net:run(3)
    -- Only Everyone at 20, from Cid's removal.
    assert.same({ "Everyone in the Crew has a Character at 20!" }, goalTexts(a))
  end)

  it("leave out Left and Removed Members", function()
    local net, clients = crew({ "Ann", "Bob", "Cid" },
      { Ann = { level = 30, deaths = 1 }, Bob = { level = 15, deaths = 2 }, Cid = { level = 5, deaths = 3 } })
    local a, b, c = clients[1], clients[2], clients[3]
    assert.equal(50, goals(a).crewLevels.value)
    assert.equal(3, goals(a).everyone.goal)

    assert.is_true(a.core:removeMember(c.memberId))
    local rows = goals(a)
    assert.equal(45, rows.crewLevels.value)
    assert.equal(3, rows.deaths.value)
    assert.equal(2, rows.everyone.goal)
    -- Removing the lowest Member lets everyone reach 10.
    assert.same({ "Everyone in the Crew has a Character at 10!" }, goalTexts(a))

    b.core:leaveCrew()
    net:run(3)
    rows = goals(a)
    assert.equal(30, rows.crewLevels.value)
    assert.equal(1, rows.deaths.value)
    assert.equal(1, rows.everyone.goal)
  end)

  it("stop Everyone at level N at max level and show it complete", function()
    local net, clients = crew({ "Ann", "Bob" }, { Ann = { level = 60 }, Bob = { level = 59 } })
    local a = clients[1]
    assert.is_false(goals(a).everyone.complete)

    clients[2]:play({ level = 60 })
    net:run(3)
    local rows = goals(a)
    assert.is_true(rows.everyone.complete)
    assert.is_nil(rows.everyone.rung)
    assert.equal(60, rows.everyone.last.rung)
    assert.equal("Everyone at max level", rows.everyone.title)
    assert.same({ "Everyone in the Crew has a Character at max level!" }, goalTexts(a))
    -- Crew levels goes on.
    assert.equal(150, rows.crewLevels.rung)
  end)

  it("are cleared on leaving, so a new Crew starts with its own silent baseline", function()
    local net, clients = crew({ "Ann", "Bob" }, { Ann = { level = 30 }, Bob = { level = 21 } })
    local a = clients[1]
    assert.equal(50, goals(a).crewLevels.last.rung)

    a.core:leaveCrew()
    net:run(3)
    assert.is_nil(goals(a).crewLevels.last)
    -- Bob stays in the old Crew; on FakeNet's one channel he'd be heard.
    clients[2]:logout()

    local d = net:add("Dan", { character = playing("Dan", { level = 40 }) }):login()
    local code = d:join()
    a:join(code)
    net:run(40)
    assert.same({}, goalTexts(a))
    assert.equal(50, goals(a).crewLevels.last.rung)
  end)

  it("survive a reload and only announce once", function()
    local net, clients = crew({ "Ann", "Bob" }, { Ann = { level = 20 }, Bob = { level = 29 } })
    local a, b = clients[1], clients[2]
    b:reload()
    net:run(3)
    a:play({ level = 21 })
    net:run(3)
    assert.same({ "The Crew reached 50 Crew levels!" }, goalTexts(b))
    b:reload()
    net:run(15)
    assert.same({ "The Crew reached 50 Crew levels!" }, goalTexts(b))
  end)

  it("are announced as a toast-ready feedEntry with toasts on and chat lines off", function()
    local net, clients = crew({ "Ann", "Bob" }, { Ann = { level = 20 }, Bob = { level = 29 } })
    local a, b = clients[1], clients[2]
    b.core:setChatLines(false)
    a:play({ level = 21 })
    net:run(3)
    assert.same({ "The Crew reached 50 Crew levels!" }, chatLines(b))
    assert.equal(0, b.core:unseen())
  end)

  it("never name a Member", function()
    local net, clients = crew({ "Ann", "Bob" }, { Ann = { level = 20 }, Bob = { level = 29 } })
    local a, b = clients[1], clients[2]
    a:play({ level = 21, deaths = 30 })
    net:run(3)
    for _, row in ipairs(b.core:goals()) do
      for _, value in pairs(row) do
        if type(value) == "string" then
          assert.is_nil(value:find("Ann"))
          assert.is_nil(value:find("Bob"))
        end
      end
    end
    for _, text in ipairs(goalTexts(b)) do
      assert.is_nil(text:find("Ann"))
    end
  end)
end)
