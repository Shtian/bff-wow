local load = require("tests.load")

-- Skill line IDs.
local ALCHEMY, ENGINEERING, MINING, TAILORING = 171, 202, 186, 197
local COOKING, FISHING, FIRST_AID = 185, 356, 129
local ALL = {
  { 171, "Alchemy" }, { 164, "Blacksmithing" }, { 333, "Enchanting" }, { 202, "Engineering" },
  { 182, "Herbalism" }, { 165, "Leatherworking" }, { 186, "Mining" }, { 393, "Skinning" },
  { 197, "Tailoring" }, { 185, "Cooking", true }, { 356, "Fishing", true }, { 129, "First Aid", true },
}

local function profession(skillLine, name, skill, secondary)
  return { skillLine = skillLine, name = name, icon = 1000 + skillLine, skill = skill, max = 300,
    secondary = secondary or nil }
end

local function alchemy(skill) return profession(ALCHEMY, "Alchemy", skill) end
local function engineering(skill) return profession(ENGINEERING, "Engineering", skill) end
local function mining(skill) return profession(MINING, "Mining", skill) end
local function tailoring(skill) return profession(TAILORING, "Tailoring", skill) end
local function cooking(skill) return profession(COOKING, "Cooking", skill, true) end
local function fishing(skill) return profession(FISHING, "Fishing", skill, true) end
local function firstAid(skill) return profession(FIRST_AID, "First Aid", skill, true) end

-- A net with the given clients logged in, in one Crew and settled, then
-- each sharing its professions for the first time (by name; none known for
-- a name left out).
local function crew(names, professions)
  local ns = load()
  local net = ns.FakeNet.new()
  local clients = {}
  for i, name in ipairs(names) do clients[i] = net:add(name):login() end
  local code = clients[1]:join()
  for i = 2, #clients do clients[i]:join(code) end
  net:run(40)
  for i, name in ipairs(names) do
    if professions[name] then
      clients[i]:play({ professions = professions[name] })
      -- Professions alone wait for the next send.
      clients[i]:play({ level = 11 })
    end
  end
  net:run(5)
  return net, clients, ns
end

local function goals(client)
  local byTrack = {}
  for _, row in ipairs(client.core:goals()) do byTrack[row.track] = row end
  return byTrack
end

local function goalTexts(client)
  local texts = {}
  for _, day in ipairs(client.core:feed().days) do
    for _, entry in ipairs(day.entries) do
      if entry.kind == "goal" then texts[#texts + 1] = entry.text end
    end
  end
  return texts
end

local function chatLines(client)
  local lines = {}
  for _, event in ipairs(client.events) do
    if event[1] == "feedEntry" and event[2].kind == "goal" then lines[#lines + 1] = event[2].text end
  end
  return lines
end

local function lit(row)
  local names = {}
  for _, p in ipairs(row.professions) do
    if p.lit then names[#names + 1] = p.name end
  end
  return names
end

describe("Profession goal ladders", function()
  local Goals = load().Goals

  it("have Crew skill at 500, 1000, 2500 and on, for ever", function()
    assert.same({ 500, 1000, 2500, 5000, 10000, 25000 }, Goals.rungs("crewSkill", 49999, 60))
    assert.equal(500, Goals.nextRung("crewSkill", 0, 60))
    assert.equal(50000, Goals.nextRung("crewSkill", 25000, 60))
  end)

  it("have Everyone a Journeyman at each rank, complete at Artisan", function()
    assert.same({ 75, 150, 225, 300 }, Goals.rungs("everyoneRank", 300, 60))
    assert.is_nil(Goals.nextRung("everyoneRank", 300, 60))
  end)

  it("work out profession progress from records, with no professions known as none", function()
    local records = {
      { characters = {
        a = { level = 30, professions = { { id = ALCHEMY, n = "Alchemy", k = 160, m = 225 } } },
        b = { level = 5, professions = { { id = COOKING, n = "Cooking", k = 40, m = 75, s = true } } },
      } },
      { characters = { c = { level = 22, professions = {} } } },
      -- Never shared: none.
      { characters = { d = { level = 40 } } },
      -- Malformed: unknown.
      { characters = { e = { level = 40, professions = { { id = "x" } } } } },
    }
    local progress = Goals.progress(records)
    assert.equal(200, progress.skill)
    assert.same({ 160, 0, 0, 0 }, progress.best)
    assert.equal(0, progress.lowestBest)
    progress = Goals.progress({ records[1], records[2] })
    assert.same({ 160, 0 }, progress.best)
    assert.is_truthy(progress.covered[ALCHEMY])
    assert.is_truthy(progress.covered[COOKING])
    assert.is_nil(progress.covered[TAILORING])
  end)
end)

describe("Profession Crew goals", function()
  it("show every profession in the Crew, Crew skill and Everyone a rank on the Goals tab", function()
    local _, clients = crew({ "Ann", "Bob" }, {
      Ann = { alchemy(160), mining(40), cooking(10) },
      Bob = { tailoring(90) },
    })
    local rows = goals(clients[2])

    local coverage = rows.professions
    assert.equal("Every profession in the Crew", coverage.title)
    assert.equal(4, coverage.value)
    assert.equal(12, coverage.goal)
    assert.equal(12, #coverage.professions)
    -- The twelve in order: main professions by name, then cooking, fishing
    -- and first aid, the covered ones lit, with their own icon.
    for i, p in ipairs(coverage.professions) do
      assert.equal(ALL[i][1], p.skillLine)
      assert.equal(ALL[i][2], p.name)
      assert.is_not_nil(p.icon)
    end
    assert.same({ "Alchemy", "Mining", "Tailoring", "Cooking" }, lit(coverage))
    assert.equal(1000 + ALCHEMY, coverage.professions[1].icon)

    assert.equal("Crew skill", rows.crewSkill.title)
    assert.equal(300, rows.crewSkill.value)
    assert.equal(500, rows.crewSkill.goal)

    -- Ann's best is 160, Bob's 90: both Apprentices, one a Journeyman.
    assert.equal("Everyone a Journeyman", rows.everyoneRank.title)
    assert.equal(1, rows.everyoneRank.value)
    assert.equal(2, rows.everyoneRank.goal)
    assert.equal("Members", rows.everyoneRank.unit)
    assert.equal(75, rows.everyoneRank.last.rung)
    assert.equal("Apprentice", rows.everyoneRank.last.label)

    assert.same({ "crewLevels", "everyone", "deaths", "professions", "crewSkill", "everyoneRank" },
      (function()
        local tracks = {}
        for i, row in ipairs(clients[2].core:goals()) do tracks[i] = row.track end
        return tracks
      end)())
  end)

  it("are reached quietly on a Member's first share of professions", function()
    local net, clients = crew({ "Ann", "Bob" }, { Ann = { alchemy(250) } })
    local a, b = clients[1], clients[2]
    assert.same({}, goalTexts(b))
    b.events = {}
    b:play({ professions = { tailoring(260), cooking(20) } })
    b:play({ level = 12 })
    net:run(3)
    -- Tailoring and Cooking, 530 skill and Everyone an Expert, all quiet.
    for _, client in ipairs({ a, b }) do
      assert.same({}, goalTexts(client))
      local rows = goals(client)
      assert.equal(3, rows.professions.value)
      assert.equal(500, rows.crewSkill.last.rung)
      assert.equal("500", rows.crewSkill.last.label)
      assert.equal(225, rows.everyoneRank.last.rung)
    end
    assert.same({}, chatLines(b))
  end)

  it("tell the Crew it has a profession nobody had", function()
    local net, clients = crew({ "Ann", "Bob" }, { Ann = { alchemy(10) }, Bob = { alchemy(10) } })
    local a, b = clients[1], clients[2]
    a:play({ professions = { alchemy(10), engineering(1) } })
    net:run(3)
    assert.same({ "The Crew has an Engineer now!" }, goalTexts(b))
    assert.same({ "The Crew has an Engineer now!" }, chatLines(b))
    local last = goals(b).professions.last
    assert.equal("Engineering", last.label)
    assert.is_number(last.time)

    -- One somebody already has isn't news.
    b:play({ professions = { alchemy(10), engineering(1) } })
    net:run(3)
    assert.same({ "The Crew has an Engineer now!" }, goalTexts(a))
  end)

  it("name every profession first had at once in one entry", function()
    local net, clients = crew({ "Ann", "Bob" }, { Ann = { alchemy(10) }, Bob = { alchemy(10) } })
    local a, b = clients[1], clients[2]
    b:logout()
    net:run(3)
    a:play({ professions = { alchemy(10), engineering(1), cooking(1) } })
    net:run(3)
    a:play({ professions = { alchemy(10), engineering(1), cooking(1), firstAid(1) } })
    net:run(3)
    b:login()
    net:run(40)
    assert.same({ "The Crew has an Engineer, a Cook and a First Aider now!" }, goalTexts(b))
  end)

  it("keep a profession lit after the Character that had it drops it", function()
    local net, clients = crew({ "Ann", "Bob" }, { Ann = { alchemy(10), tailoring(10) }, Bob = {} })
    local a, b = clients[1], clients[2]
    a:play({ professions = { alchemy(10) } })
    net:run(3)
    assert.same({ "Alchemy", "Tailoring" }, lit(goals(b).professions))
    assert.equal(2, goals(b).professions.value)
    a:play({ professions = { alchemy(10), tailoring(1) } })
    net:run(3)
    assert.same({}, goalTexts(b))
  end)

  it("say the Crew has every profession once all twelve are had", function()
    local net, clients = crew({ "Ann", "Bob", "Cid" }, {
      Ann = { alchemy(1), engineering(1), cooking(1), fishing(1), firstAid(1) },
      Bob = { mining(1), tailoring(1) },
      Cid = {
        profession(164, "Blacksmithing", 1), profession(333, "Enchanting", 1),
      },
    })
    local a, b, c = clients[1], clients[2], clients[3]
    -- Herbalism, Leatherworking and Skinning are missing.
    b:play({ professions = { mining(1), tailoring(1), profession(182, "Herbalism", 1) } })
    net:run(3)
    assert.same({ "The Crew has a Herbalist now!" }, goalTexts(a))
    a:play({ guid = "Player-0-AnnAlt", name = "Annalt", level = 5, professions = {} })
    net:run(3)
    a:play({ professions = { profession(165, "Leatherworking", 1), profession(393, "Skinning", 1) } })
    net:run(3)
    assert.same({ "The Crew has every profession!", "The Crew has a Herbalist now!" }, goalTexts(c))
    local row = goals(c).professions
    assert.is_true(row.complete)
    assert.is_nil(row.rung)
    assert.equal(12, #lit(row))
  end)

  it("add up profession skill over every Character, Alts included", function()
    local net, clients = crew({ "Ann", "Bob" }, { Ann = { alchemy(200) }, Bob = { tailoring(225) } })
    local a, b = clients[1], clients[2]
    a:play({ guid = "Player-0-AnnAlt", name = "Annalt", level = 5, professions = {} })
    net:run(3)
    a:play({ professions = { tailoring(74) } })
    net:run(3)
    assert.same({}, goalTexts(b))
    a:play({ professions = { tailoring(75) } })
    net:run(3)
    assert.same({ "The Crew has 500 profession skill together!" }, goalTexts(b))
    assert.equal(1000, goals(b).crewSkill.rung)
  end)

  it("write big Crew skill with thousands separators", function()
    local professions = {}
    for _, name in ipairs({ "Ann", "Bob", "Cid", "Dan", "Eve", "Fay", "Gus", "Hal" }) do
      professions[name] = { alchemy(150), mining(150) }
    end
    local net, clients = crew({ "Ann", "Bob", "Cid", "Dan", "Eve", "Fay", "Gus", "Hal" }, professions)
    -- 2,400: 100 more makes 2,500.
    clients[1]:play({ professions = { alchemy(225), mining(175) } })
    net:run(3)
    assert.same({ "The Crew has 2,500 profession skill together!" }, goalTexts(clients[2]))
  end)

  it("say when everyone is a Journeyman at something, from each Member's best on any Character", function()
    local net, clients = crew({ "Ann", "Bob" }, { Ann = { alchemy(160) }, Bob = { tailoring(149), cooking(20) } })
    local a, b = clients[1], clients[2]
    -- Bob's Alt gets there first.
    b:play({ guid = "Player-0-BobAlt", name = "Bobalt", level = 5, professions = {} })
    net:run(3)
    b:play({ professions = { tailoring(150) } })
    net:run(3)
    assert.same({ "Everyone in the Crew is a Journeyman at something!" }, goalTexts(a))
    assert.equal("Everyone an Expert", goals(a).everyoneRank.title)
  end)

  it("complete Everyone a rank at Artisan", function()
    local net, clients = crew({ "Ann", "Bob" }, { Ann = { alchemy(300) }, Bob = { tailoring(299) } })
    local a, b = clients[1], clients[2]
    b:play({ professions = { tailoring(300) } })
    net:run(3)
    assert.same({ "Everyone in the Crew is an Artisan at something!" }, goalTexts(a))
    local row = goals(a).everyoneRank
    assert.is_true(row.complete)
    assert.equal("Everyone an Artisan", row.title)
    assert.equal(300, row.last.rung)
  end)

  it("wait for Members whose professions are unknown, as having none", function()
    local _, clients = crew({ "Ann", "Bob" }, { Ann = { alchemy(300) } })
    local row = goals(clients[2]).everyoneRank
    assert.equal(75, row.rung)
    assert.equal(1, row.value)
    assert.equal(2, row.goal)
    assert.is_nil(row.last)
  end)

  it("never name a Member", function()
    local net, clients = crew({ "Ann", "Bob" }, { Ann = { alchemy(10) }, Bob = { alchemy(10) } })
    local a, b = clients[1], clients[2]
    a:play({ professions = { alchemy(10), engineering(1) } })
    net:run(3)
    for _, row in ipairs(b.core:goals()) do
      for _, value in pairs(row) do
        if type(value) == "string" then
          assert.is_nil(value:find("Ann"))
        end
      end
    end
    for _, text in ipairs(goalTexts(b)) do assert.is_nil(text:find("Ann")) end
  end)
end)
