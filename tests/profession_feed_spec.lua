local load = require("tests.load")

-- Skill line IDs.
local ALCHEMY, TAILORING, COOKING = 171, 197, 185

local function profession(skillLine, name, skill, max, secondary)
  return { skillLine = skillLine, name = name, icon = 1000 + skillLine, skill = skill, max = max,
    secondary = secondary or nil }
end

local function alchemy(skill, max) return profession(ALCHEMY, "Alchemy", skill, max or 300) end
local function tailoring(skill, max) return profession(TAILORING, "Tailoring", skill, max or 75) end
local function cooking(skill, max) return profession(COOKING, "Cooking", skill, max or 300, true) end

-- A net with the given clients logged in and in one Crew, settled, each
-- already sharing professions (the first share is a silent baseline).
local function crew(names, professions)
  local ns = load()
  local net = ns.FakeNet.new()
  local clients = {}
  for i, name in ipairs(names) do clients[i] = net:add(name):login() end
  local code = clients[1]:join()
  for i = 2, #clients do clients[i]:join(code) end
  net:run(40)
  for _, client in ipairs(clients) do client:play({ professions = professions or {} }) end
  -- Professions alone wait for the next send.
  for _, client in ipairs(clients) do client:play({ level = 11 }) end
  net:run(5)
  return net, clients, ns
end

local function entries(client)
  local all = {}
  for _, day in ipairs(client.core:feed().days) do
    for _, entry in ipairs(day.entries) do all[#all + 1] = entry end
  end
  return all
end

-- The texts of the client's profession entries, newest first.
local function texts(client)
  local result = {}
  for _, entry in ipairs(entries(client)) do
    if entry.kind:find("^newProfession") or entry.kind:find("^profession") then
      result[#result + 1] = entry.text
    end
  end
  return result
end

local function chatLines(client)
  local lines = {}
  for _, event in ipairs(client.events) do
    if event[1] == "feedEntry" then lines[#lines + 1] = event[2].text end
  end
  return lines
end

local function events(client, name)
  local list = {}
  for _, event in ipairs(client.events) do
    if event[1] == name then list[#list + 1] = event[2] end
  end
  return list
end

describe("Profession Feed entries", function()
  it("tell the Crew a Character picked up a profession, with its icon and a Cheer", function()
    local net, clients = crew({ "Ann", "Bob" }, { alchemy(1) })
    local a, b = clients[1], clients[2]
    b.events = {}
    a:play({ professions = { alchemy(1), tailoring(1) } })
    net:run(2)
    assert.same({ "Ann picked up Tailoring" }, chatLines(b))
    local entry = entries(b)[1]
    assert.equal("newProfession", entry.kind)
    assert.equal(1000 + TAILORING, entry.icon)
    assert.equal("cheer", entry.reaction)
    assert.is_true(entry.canReact)
    -- Your own is in your Feed, seen.
    assert.same({ "You picked up Tailoring" }, texts(a))
    assert.is_true(entries(a)[1].seen)
  end)

  it("go out right away, without waiting for the next send", function()
    local net, clients = crew({ "Ann", "Bob" }, { alchemy(149) })
    local a, b = clients[1], clients[2]
    a:play({ professions = { alchemy(150) } })
    net:run(2)
    assert.same({ "Ann reached 150 Alchemy" }, texts(b))
  end)

  it("are made at 75, 150 and 225, on secondary professions too, and only once each", function()
    local net, clients = crew({ "Ann", "Bob" }, { alchemy(74), cooking(149) })
    local a, b = clients[1], clients[2]
    b.events = {}
    a:play({ professions = { alchemy(75), cooking(149) } })
    net:run(2)
    a:play({ professions = { alchemy(76), cooking(150) } })
    net:run(2)
    a:play({ professions = { alchemy(224), cooking(151) } })
    net:run(2)
    a:play({ professions = { alchemy(225), cooking(151) } })
    net:run(2)
    assert.same({ "Ann reached 75 Alchemy", "Ann reached 150 Cooking", "Ann reached 150 Alchemy",
      "Ann reached 225 Alchemy" }, chatLines(b))
    assert.equal("professionSkill", entries(b)[1].kind)
    assert.same({ "You reached 225 Alchemy", "You reached 150 Alchemy", "You reached 150 Cooking",
      "You reached 75 Alchemy" }, texts(a))
  end)

  it("say maxed at 300, in gold", function()
    local net, clients = crew({ "Ann", "Bob" }, { alchemy(299) })
    local a, b = clients[1], clients[2]
    a:play({ professions = { alchemy(300) } })
    net:run(2)
    assert.same({ "Ann maxed Alchemy" }, texts(b))
    assert.equal("professionMaxed", entries(b)[1].kind)
  end)

  it("collapse skipped versions to the highest milestone crossed", function()
    local net, clients = crew({ "Ann", "Bob", "Cid" }, { alchemy(140), tailoring(10) })
    local a, c = clients[1], clients[3]
    c:logout()
    net:run(2)
    a:play({ professions = { alchemy(160), tailoring(60) } })
    net:run(2)
    a:play({ professions = { alchemy(230), tailoring(300) } })
    net:run(2)
    c:login()
    net:run(40)
    assert.same({ "Ann maxed Tailoring", "Ann reached 225 Alchemy" }, (function()
      local list = texts(c)
      table.sort(list)
      return list
    end)())
    for _, entry in ipairs(entries(c)) do
      if entry.kind == "professionSkill" then assert.equal(140, entry.from) end
    end
  end)

  it("make nothing for a drop, unlearning, or a first share", function()
    local net, clients = crew({ "Ann", "Bob" }, { alchemy(160), tailoring(80) })
    local a, b = clients[1], clients[2]
    a:play({ professions = { alchemy(10) } })
    net:run(2)
    a:play({ professions = { alchemy(20) } })
    net:run(2)
    assert.same({}, texts(b))
    assert.same({}, texts(a))
  end)

  it("make nothing on a new Character but the new Character entry", function()
    local net, clients = crew({ "Ann", "Bob" }, { alchemy(1) })
    local a, b = clients[1], clients[2]
    a:play({ guid = "Player-0-AnnAlt", name = "Annalt", level = 5, professions = { tailoring(80) } })
    net:run(2)
    assert.same({}, texts(b))
  end)

  it("name Alts the usual way", function()
    local net, clients = crew({ "Ann", "Bob" }, { alchemy(1) })
    local a, b = clients[1], clients[2]
    a.core:setMain("Player-0-Ann")
    a:play({ guid = "Player-0-AnnAlt", name = "Annalt", level = 5, professions = { tailoring(74) } })
    net:run(2)
    a:play({ professions = { tailoring(75) } })
    a:play({ professions = { tailoring(75), cooking(1) } })
    net:run(2)
    assert.same({ "Ann's Alt Annalt picked up Cooking", "Ann's Alt Annalt reached 75 Tailoring" }, texts(b))
    assert.same({ "Your Alt Annalt picked up Cooking", "Your Alt Annalt reached 75 Tailoring" }, texts(a))
  end)

  it("take Cheers, matched across clients, and tell the owner", function()
    local net, clients = crew({ "Ann", "Bob", "Cid" }, { alchemy(140) })
    local a, b, c = clients[1], clients[2], clients[3]
    c:logout()
    net:run(2)
    a:play({ professions = { alchemy(150) } })
    net:run(2)
    a:play({ professions = { alchemy(225) } })
    net:run(2)
    -- Bob cheers the 150, which Cid only sees inside "reached 225".
    local cheered = entries(b)[2]
    assert.equal("Ann reached 150 Alchemy", cheered.text)
    assert.is_true(b.core:react(cheered.key))
    net:run(2)
    c:login()
    net:run(40)
    local collapsed = entries(c)
    local found
    for _, entry in ipairs(collapsed) do
      if entry.kind == "professionSkill" then found = entry end
    end
    assert.equal("Ann reached 225 Alchemy", found.text)
    assert.equal("Bob", found.reactors[1].name)

    local reaction = events(a, "reaction")
    assert.equal("Bob cheered your 150 Alchemy", reaction[#reaction].text)
    -- Cheering the maxed and picked-up kinds too.
    a:play({ professions = { alchemy(300), tailoring(1) } })
    net:run(2)
    for _, entry in ipairs(entries(b)) do
      if entry.kind == "professionMaxed" or entry.kind == "newProfession" then
        assert.is_true(b.core:react(entry.key))
      end
    end
    net:run(2)
    reaction = events(a, "reaction")
    local said = {}
    for _, item in ipairs(reaction) do said[item.text] = true end
    assert.is_true(said["Bob cheered you maxing Alchemy"])
    assert.is_true(said["Bob cheered you picking up Tailoring"])
  end)

  it("show in While you were away, each with a Cheer", function()
    local net, clients = crew({ "Ann", "Bob" }, { alchemy(140) })
    local a, b = clients[1], clients[2]
    b:logout()
    net:run(2)
    a:play({ professions = { alchemy(150), tailoring(1) } })
    net:run(2)
    b.events = {}
    b:login()
    net:run(40)
    local summary = events(b, "awaySummary")[1]
    assert.equal(2, summary.count)
    assert.same({}, summary.members)
    assert.equal(2, #summary.professions)
    local said = {}
    for i, item in ipairs(summary.professions) do
      said[i] = item.text
      assert.is_table(item.cheer.key)
      assert.is_false(item.cheer.reacted)
    end
    table.sort(said)
    assert.same({ "Ann picked up Tailoring", "Ann reached 150 Alchemy" }, said)
    assert.equal(1000 + TAILORING, (summary.professions[1].kind == "newProfession" and summary.professions[1]
      or summary.professions[2]).icon)
  end)
end)
