local load = require("tests.load")

-- Skill line IDs.
local ALCHEMY, HERBALISM, MINING, TAILORING = 171, 182, 186, 197
local COOKING, FISHING, FIRST_AID = 185, 356, 129

local function profession(skillLine, name, skill, max, secondary)
  return { skillLine = skillLine, name = name, icon = 1000 + skillLine, skill = skill, max = max,
    secondary = secondary or nil }
end

local function alchemist()
  return {
    profession(ALCHEMY, "Alchemy", 287, 300),
    profession(HERBALISM, "Herbalism", 300, 300),
    profession(COOKING, "Cooking", 140, 150, true),
  }
end

-- A net with the given clients logged in and in one Crew, settled.
local function crew(names)
  local ns = load()
  local net = ns.FakeNet.new()
  local clients = {}
  for i, name in ipairs(names) do clients[i] = net:add(name):login() end
  local code = clients[1]:join()
  for i = 2, #clients do clients[i]:join(code) end
  net:run(40)
  return net, clients, ns
end

local function feedSize(client)
  local n = 0
  for _, day in ipairs(client.core:feed().days) do n = n + #day.entries end
  return n
end

local function sentBy(net, from, name)
  local messages = {}
  for i = from + 1, #net.wire do
    if net.wire[i].from == name then messages[#messages + 1] = net.wire[i] end
  end
  return messages
end

-- Each profession's name and skill/max, in order.
local function summary(list)
  if list == nil then return nil end
  local result = {}
  for i, p in ipairs(list) do result[i] = ("%s %d/%d"):format(p.name, p.skill, p.max) end
  return result
end

-- A fake game: GetProfessions' five slots (prof1, prof2, first aid, fishing,
-- cooking) and what GetProfessionInfo says for each index.
local function game(slots, infos, secret)
  return {
    getProfessions = function() return slots[1], slots[2], slots[3], slots[4], slots[5] end,
    getProfessionInfo = function(index)
      local info = infos[index]
      -- name, icon, rank, maxRank, numSpells, spellOffset, skillLine, rankModifier
      return info[1], info[2], info[3], info[4], 0, 0, info[5], info[6] or 0
    end,
    isSecret = secret,
  }
end

describe("Professions", function()
  describe("read from the game", function()
    local Professions
    before_each(function() Professions = load().Professions end)

    it("lists the main professions, then first aid, fishing and cooking", function()
      local api = game({ 3, 7, nil, 9, 2 }, {
        [3] = { "Alchemy", 136240, 287, 300, ALCHEMY, 15 },
        [7] = { "Herbalism", 136246, 300, 300, HERBALISM },
        [9] = { "Fishing", 136245, 75, 75, FISHING },
        [2] = { "Cooking", 133971, 140, 150, COOKING },
      })
      assert.same({
        { skillLine = ALCHEMY, name = "Alchemy", icon = 136240, skill = 287, max = 300 },
        { skillLine = HERBALISM, name = "Herbalism", icon = 136246, skill = 300, max = 300 },
        { skillLine = FISHING, name = "Fishing", icon = 136245, skill = 75, max = 75, secondary = true },
        { skillLine = COOKING, name = "Cooking", icon = 133971, skill = 140, max = 150, secondary = true },
      }, Professions.read(api))
    end)

    it("reads none as an empty list", function()
      assert.same({}, Professions.read(game({}, {})))
    end)

    it("keeps the last good list when a value reads secret", function()
      local last = { profession(MINING, "Mining", 10, 75) }
      local api = game({ 1 }, { [1] = { "Mining", 136248, "secret", 75, MINING } },
        function(value) return value == "secret" end)
      assert.equal(last, Professions.read(api, last))
      assert.is_nil(Professions.read(api, nil))
    end)

    it("keeps the last good list when a value couldn't be stored", function()
      local last = { profession(MINING, "Mining", 10, 75) }
      local api = game({ 1 }, { [1] = { "Mining", 136248, 0, 0, MINING } })
      assert.equal(last, Professions.read(api, last))
    end)

    it("keeps the last good list when the read errors", function()
      local last = { profession(MINING, "Mining", 10, 75) }
      local api = { getProfessions = function() error("restricted") end, getProfessionInfo = function() end }
      assert.equal(last, Professions.read(api, last))
      assert.is_nil(Professions.read({}, nil))
    end)
  end)

  describe("ranks", function()
    it("come from the max skill", function()
      local Professions = load().Professions
      assert.equal("Apprentice", Professions.rank(75))
      assert.equal("Journeyman", Professions.rank(150))
      assert.equal("Expert", Professions.rank(225))
      assert.equal("Artisan", Professions.rank(300))
      assert.is_nil(Professions.rank(1))
    end)
  end)

  describe("in records", function()
    it("reach the rest of the Crew on the right Character, shown and Alt", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      a:play({ professions = alchemist(), level = 11 })
      net:run(2)
      a:play({ guid = "Player-0-AnnAlt", name = "Annalt", level = 5,
        professions = { profession(TAILORING, "Tailoring", 1, 75) } })
      net:run(2)

      local row = b:rowFor(a)
      assert.equal("Annalt", row.name)
      assert.same({ "Tailoring 1/75" }, summary(row.professions))
      assert.same({ "Alchemy 287/300", "Herbalism 300/300", "Cooking 140/150" }, summary(row.alts[1].professions))
      local alchemy = row.alts[1].professions[1]
      assert.same({ skillLine = ALCHEMY, name = "Alchemy", icon = 1000 + ALCHEMY, skill = 287, max = 300,
        secondary = false, rank = "Artisan", full = false, capped = false }, alchemy)
      local herbalism = row.alts[1].professions[2]
      assert.is_true(herbalism.full)
      assert.is_true(herbalism.capped)
      assert.is_true(row.alts[1].professions[3].secondary)
      assert.equal("Journeyman", row.alts[1].professions[3].rank)
    end)

    it("list main professions first", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      a:play({ level = 11, professions = {
        profession(COOKING, "Cooking", 1, 75, true),
        profession(MINING, "Mining", 2, 75),
        profession(FIRST_AID, "First Aid", 3, 75, true),
        profession(FISHING, "Fishing", 4, 75, true),
      } })
      net:run(2)
      assert.same({ "Mining 2/75", "Cooking 1/75", "Fishing 4/75", "First Aid 3/75" },
        summary(b:rowFor(a).professions))
    end)

    it("are a full skill only at the max skill, and capped only at 300", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      a:play({ level = 11, professions = { profession(MINING, "Mining", 150, 150) } })
      net:run(2)
      local mining = b:rowFor(a).professions[1]
      assert.is_true(mining.full)
      assert.is_false(mining.capped)
    end)

    it("send a professions-only change only along with the next send", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      a:play({ professions = alchemist(), level = 11 })
      net:run(2)
      local events = a:count("changed")
      local mark = #net.wire
      local better = alchemist()
      better[1].skill = 288
      a:play({ professions = better })
      assert.is_true(a:count("changed") > events)
      net:run(30)
      assert.same({}, sentBy(net, mark, "Ann"))
      assert.equal(287, b:rowFor(a).professions[1].skill)

      a:play({ deaths = 1 })
      net:run(2)
      assert.equal(288, b:rowFor(a).professions[1].skill)
    end)

    it("aren't a change when read again the same", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a = clients[1]
      a:play({ professions = alchemist() })
      net:run(2)
      local events = a:count("changed")
      a:play({ professions = alchemist() })
      assert.equal(events, a:count("changed"))
    end)

    it("are kept when none could be read, as after a reload into a secret read", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      a:play({ level = 11, professions = alchemist() })
      net:run(2)
      a:reload()
      a:play({ level = 12, professions = false })
      net:run(2)
      assert.equal(12, b:rowFor(a).level)
      assert.same({ "Alchemy 287/300", "Herbalism 300/300", "Cooking 140/150" }, summary(b:rowFor(a).professions))
      assert.same({ "Alchemy 287/300", "Herbalism 300/300", "Cooking 140/150" }, summary(a.core:rows()[1].professions))
    end)

    it("add no Feed entry when first shared", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      a:play({ level = 11 })
      net:run(2)
      local own, theirs = feedSize(a), feedSize(b)
      a:play({ professions = alchemist() })
      a:play({ level = 12 })
      net:run(2)
      assert.is_table(b:rowFor(a).professions)
      assert.equal(own + 1, feedSize(a))
      assert.equal(theirs + 1, feedSize(b))
    end)

    it("are unknown for a Character whose client never shared them, and empty for none", function()
      local net, clients = crew({ "Ann", "Bob", "Cleo" })
      local a, b, c = clients[1], clients[2], clients[3]
      c:play({ level = 11, professions = {} })
      net:run(2)
      assert.is_nil(b:rowFor(a).professions)
      assert.same({}, b:rowFor(c).professions)
    end)

    it("are ignored for a Character when malformed, keeping the rest of the record", function()
      local net, clients, ns = crew({ "Ann" })
      local a = clients[1]
      local function send(id, professions)
        local guid = "Player-0-" .. id
        a.core:received(ns.Codec.encode({
          type = "DATA", from = id,
          records = { { id = id, version = net:now(), displayName = id, characters = {
            [guid] = { guid = guid, name = id, level = 20, lastPlayed = net:now(), professions = professions },
          } } },
        }))
      end
      local good = { id = MINING, n = "Mining", i = 136248, k = 50, m = 75 }
      send("junklist", "junk")
      send("badentry", { good, { id = ALCHEMY, n = "Alchemy", k = "lots", m = 75 } })
      send("toomany1", { good, good, good, good, good, good })
      send("goodlist", { good, { id = COOKING, n = "Cooking", k = 1, m = 75, s = true } })
      local function professionsOf(id) return a:rowFor({ memberId = id }).professions end
      assert.is_nil(professionsOf("junklist"))
      assert.is_nil(professionsOf("badentry"))
      assert.is_nil(professionsOf("toomany1"))
      assert.same({ "Mining 50/75", "Cooking 1/75" }, summary(professionsOf("goodlist")))
      assert.equal(20, a:rowFor({ memberId = "junklist" }).level)
    end)

    it("are relayed unchanged by a client that doesn't read them", function()
      local net, clients, ns = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      local guid = "Player-0-Future"
      local future = { { id = MINING, n = "Mining", k = 50, m = 75, x = "later field" } }
      a.core:received(ns.Codec.encode({
        type = "DATA", from = "future01",
        records = { { id = "future01", version = net:now(), displayName = "Future", characters = {
          [guid] = { guid = guid, name = "Future", level = 20, lastPlayed = net:now(), professions = future },
        } } },
      }))
      -- Bob learns of them from Ann.
      b:logout()
      net:run(2)
      b:login()
      net:run(20)
      assert.same({ "Mining 50/75" }, summary(b:rowFor({ memberId = "future01" }).professions))
    end)
  end)

  describe("the Professions tab", function()
    local function names(view)
      local result = {}
      for i, p in ipairs(view.professions) do result[i] = p.name end
      return result
    end

    -- Each profession with any holders as "name: holder skill, ...".
    local function held(view)
      local result = {}
      for _, p in ipairs(view.professions) do
        if #p.holders > 0 then
          local holders = {}
          for i, h in ipairs(p.holders) do holders[i] = ("%s %d"):format(h.name, h.skill) end
          result[#result + 1] = p.name .. ": " .. table.concat(holders, ", ")
        end
      end
      return result
    end

    local function professionNamed(view, name)
      for _, p in ipairs(view.professions) do
        if p.name == name then return p end
      end
    end

    it("lists all twelve, with who has each, best first", function()
      local net, clients = crew({ "Ann", "Bob", "Cleo" })
      local a, b = clients[1], clients[2]
      a:play({ professions = alchemist(), level = 11 })
      net:run(2)
      b:play({ professions = { profession(MINING, "Mining", 75, 75), profession(COOKING, "Cooking", 150, 150, true) } })
      net:run(2)
      -- Bob plays an Alt now; his Main still comes before it.
      b:play({ guid = "Player-0-BobAlt", name = "Bobalt", level = 3,
        professions = { profession(MINING, "Mining", 20, 75), profession(TAILORING, "Tailoring", 20, 75) } })
      b.core:setMain("Player-0-Bob")
      net:run(2)

      local view = a.core:professions()
      assert.same({ "Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Herbalism", "Leatherworking",
        "Mining", "Skinning", "Tailoring", "Cooking", "Fishing", "First Aid" }, names(view))
      assert.same({
        "Alchemy: Ann 287",
        "Herbalism: Ann 300",
        "Mining: Bob 75, Bobalt 20",
        "Tailoring: Bobalt 20",
        "Cooking: Bob 150, Ann 140",
      }, held(view))

      local enchanting = professionNamed(view, "Enchanting")
      assert.same({}, enchanting.holders)
      assert.equal("Interface\\Icons\\Trade_Engraving", enchanting.icon)
      assert.is_false(enchanting.secondary)
      assert.is_true(professionNamed(view, "Fishing").secondary)
      -- Someone has it: their client's icon.
      assert.equal(1000 + ALCHEMY, professionNamed(view, "Alchemy").icon)

      local mining = professionNamed(view, "Mining")
      local bob, bobalt = mining.holders[1], mining.holders[2]
      assert.same({ memberId = b.memberId, own = false, displayName = "Bob", name = "Bob",
        classFilename = "WARRIOR", alt = false, skill = 75, max = 75, rank = "Apprentice", full = true,
        capped = false }, bob)
      assert.is_true(bobalt.alt)
      assert.is_true(professionNamed(view, "Alchemy").holders[1].own)

      assert.same({ { memberId = clients[3].memberId, own = false, displayName = "Cleo", name = "Cleo",
        classFilename = "WARRIOR" } }, view.unshared)
    end)

    it("lists one outside the twelve after its kind", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      b:play({ level = 11, professions = {
        profession(999, "Jewelcrafting", 10, 75), profession(998, "Archaeology", 5, 75, true),
      } })
      net:run(2)
      local list = names(a.core:professions())
      assert.equal("Jewelcrafting", list[10])
      assert.equal("Cooking", list[11])
      assert.equal("Archaeology", list[14])
    end)

    it("follows the Roster's order between equal skills", function()
      local net, clients = crew({ "Ann", "Bob", "Cleo" })
      local a, b, c = clients[1], clients[2], clients[3]
      b:play({ level = 5, professions = { profession(MINING, "Mining", 1, 75) } })
      c:play({ level = 30, professions = { profession(MINING, "Mining", 1, 75) } })
      net:run(2)
      local function miners(order)
        local result = {}
        for _, h in ipairs(professionNamed(a.core:professions(order), "Mining").holders) do
          result[#result + 1] = h.name
        end
        return result
      end
      assert.same({ "Cleo", "Bob" }, miners("level"))
      assert.same({ "Bob", "Cleo" }, miners("name"))
    end)

    it("is the twelve, held by nobody, without Characters", function()
      local core = load().Core.new({
        db = {}, now = function() return 1000 end, random = math.random,
        link = { send = function() end }, listener = function() end, maxLevel = 60,
      })
      local view = core:professions()
      assert.equal(12, #view.professions)
      assert.same({}, held(view))
      assert.same({}, view.unshared)
    end)
  end)
end)
