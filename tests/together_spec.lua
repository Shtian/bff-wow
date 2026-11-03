local load = require("tests.load")

-- The Together tab, read through Core's together(): friends and dungeons
-- on one level line, and the answer line on top.

local function character(name, level, extra)
  local c = {
    guid = "Player-0-" .. name, name = name, classFilename = "WARRIOR",
    level = level, xp = 0, maxXp = 1000, zone = "Elwynn Forest", deaths = 0,
  }
  for k, v in pairs(extra or {}) do c[k] = v end
  return c
end

-- A Crew of Members, all logged in and settled. members is a list of
-- { name, level }, the first being you.
local function crew(members)
  local ns = load()
  local net = ns.FakeNet.new()
  local clients = {}
  for i, member in ipairs(members) do
    clients[i] = net:add(member[1], { character = character(member[1], member[2]) }):login()
  end
  local code = clients[1]:join()
  for i = 2, #clients do clients[i]:join(code) end
  net:run(20)
  return net, clients, ns
end

-- Gives a client an Alt and plays it, keeping the first Character as Main.
local function playAlt(net, client, name, level)
  assert(client.core:setMain(client.character.guid))
  client.character = character(name, level)
  client:play()
  net:run(10)
end

-- A line's text, its segments joined.
local function text(line)
  local parts = {}
  for i, segment in ipairs(line) do parts[i] = segment.text end
  return table.concat(parts)
end

-- The text of a line's segments with the given style.
local function styled(line, style)
  local parts = {}
  for _, segment in ipairs(line) do
    if segment.style == style then parts[#parts + 1] = segment.text end
  end
  return parts
end

local function groupAt(view, level)
  for _, group in ipairs(view.groups) do
    if group.level == level then return group end
  end
  return nil
end

local function barFor(view, name)
  for _, bar in ipairs(view.bars) do
    if bar.name == name then return bar end
  end
  return nil
end

describe("Together", function()
  describe("the dungeon table", function()
    it("has the nine new Forever dungeons as Blizzard gives them", function()
      local ns = load()
      local forever = {}
      for _, dungeon in ipairs(ns.Core.DUNGEONS) do
        if dungeon.new and dungeon.kind == "dungeon" then
          forever[dungeon.name] = ("%d-%d %s"):format(dungeon.from, dungeon.to, dungeon.where)
        end
      end
      assert.same({
        ["Hall of Thanes"] = "13-18 beneath Ironforge",
        ["Ruins of Lordaeron"] = "15-20 Tirisfal Glades",
        ["Excavation Site"] = "24-29 Wetlands",
        ["City of Dalaran"] = "28-33 Alterac Mountains (needs an attunement)",
        ["The Drowned City"] = "35-40 off Stranglethorn",
        ["Krol'dok Stronghold"] = "40-45 Riverglades",
        ["Alcaz Prison"] = "48-53 Dustwallow Marsh",
        ["Blackmaw Hold"] = "55-60 Azshara",
        ["Shaper's Terrace"] = "58-60 Un'Goro Crater",
      }, forever)
    end)

    it("has the Onyxia attunement and five raids at 60", function()
      local ns = load()
      local raids, attunements = {}, {}
      for _, dungeon in ipairs(ns.Core.DUNGEONS) do
        if dungeon.kind == "raid" then
          raids[#raids + 1] = dungeon.name
          assert.equal(60, dungeon.from)
          assert.equal(60, dungeon.to)
        elseif dungeon.kind == "attunement" then
          attunements[#attunements + 1] = ("%s %d-%d"):format(dungeon.name, dungeon.from, dungeon.to)
        end
      end
      table.sort(raids)
      assert.same({ "Hyjal Summit", "Molten Core", "Onyxia's Lair", "The Barrow Deeps", "Zul'Gurub" }, raids)
      assert.same({ "Onyxia attunement 55-60" }, attunements)
    end)

    it("gives every entry a name, a range inside 1-60, a kind and where it is", function()
      local ns = load()
      for _, dungeon in ipairs(ns.Core.DUNGEONS) do
        assert.is_string(dungeon.name)
        assert.is_string(dungeon.where)
        assert.truthy(dungeon.from >= 1 and dungeon.from <= dungeon.to and dungeon.to <= 60, dungeon.name)
        assert.truthy(dungeon.kind == "dungeon" or dungeon.kind == "attunement" or dungeon.kind == "raid")
        assert.is_boolean(dungeon.new)
      end
    end)
  end)

  describe("the line", function()
    it("is centred on the Character you play, with the can-play band around it", function()
      local _, clients = crew({ { "Gahz", 24 } })
      local view = clients[1].core:together()
      assert.equal(24, view.as.level)
      assert.equal("Gahz", view.as.name)
      assert.is_false(view.as.alt)
      local x24
      for _, tick in ipairs(view.ticks) do
        if tick.level == 24 then x24 = tick.x end
      end
      assert.equal(x24, view.you)
      assert.truthy(view.band.left < x24 and view.band.right > x24)
      assert.equal(60, #view.ticks)
    end)

    it("numbers every 5 levels, level 1 and your level", function()
      local _, clients = crew({ { "Gahz", 24 } })
      local numbered = {}
      for _, tick in ipairs(clients[1].core:together().ticks) do
        if tick.number then numbered[#numbered + 1] = tick.level end
      end
      assert.same({ 1, 5, 10, 15, 20, 24, 25, 30, 35, 40, 45, 50, 55, 60 }, numbered)
    end)

    it("is nil before you play a Character", function()
      local ns = load()
      local core = ns.Core.new({
        db = {}, now = function() return 1000 end, random = math.random,
        link = { send = function() end }, listener = function() end, maxLevel = 60,
      })
      assert.is_nil(core:together())
    end)
  end)

  describe("friends", function()
    it("merge per level into one label, you first, then whoever is online", function()
      local net, clients = crew({ { "Gahz", 25 }, { "Simba", 25 }, { "Krogg", 25 } })
      clients[3]:logout()
      net:run(5)
      local view = clients[1].core:together()
      local group = groupAt(view, 25)
      assert.equal("You", group.label)
      assert.is_true(group.own)
      assert.equal(2, group.more)
      assert.equal(3, #group.characters)
      assert.same({ "Gahz", "Simba", "Krogg" }, { group.characters[1].name, group.characters[2].name,
        group.characters[3].name })
      assert.is_true(group.characters[2].online)
      assert.is_false(group.characters[3].online)
    end)

    it("show Mains and played Characters, not other Alts", function()
      local net, clients = crew({ { "Gahz", 24 }, { "Simbad", 27 }, { "Simone", 41 } })
      playAlt(net, clients[2], "Simbalt", 22)
      playAlt(net, clients[3], "Simonette", 19)
      clients[3]:logout()
      net:run(5)
      local view = clients[1].core:together()

      -- Simbad plays an Alt: both it and the Main show.
      assert.equal("Simbad", groupAt(view, 22).label)
      assert.is_true(groupAt(view, 22).alt)
      assert.is_true(groupAt(view, 22).online)
      assert.equal("Simbad", groupAt(view, 27).label)
      assert.is_false(groupAt(view, 27).alt)
      -- Simone is offline: her Main shows, her Alt doesn't.
      assert.is_not_nil(groupAt(view, 41))
      assert.is_false(groupAt(view, 41).online)
      assert.is_nil(groupAt(view, 19))
      assert.equal("1 alt hidden", view.hidden)
    end)

    it("say how far each Character is from you", function()
      local _, clients = crew({ { "Gahz", 24 }, { "Simba", 26 }, { "Simone", 41 }, { "Linn", 14 } })
      local view = clients[1].core:together()
      assert.equal("can play", groupAt(view, 26).characters[1].apart)
      assert.is_true(groupAt(view, 26).characters[1].canPlay)
      assert.equal("17 ahead", groupAt(view, 41).characters[1].apart)
      assert.equal("10 behind", groupAt(view, 14).characters[1].apart)
      assert.is_false(groupAt(view, 14).characters[1].canPlay)
      assert.is_nil(groupAt(view, 24).characters[1].apart)
    end)

    it("leave out Characters the Roster hides", function()
      local net, clients = crew({ { "Gahz", 24 }, { "Simba", 30 } })
      clients[2]:logout()
      net:step(net:now() + 31 * 24 * 60 * 60)
      net:run(5)
      local view = clients[1].core:together()
      assert.is_nil(groupAt(view, 30))
    end)
  end)

  describe("the answer line", function()
    it("names who can play with you, counting each Member once", function()
      local net, clients = crew({ { "Gahz", 24 }, { "Simba", 25 }, { "Simbad", 27 }, { "Simone", 41 } })
      playAlt(net, clients[3], "Simbalt", 22)
      local answer = clients[1].core:together().answer
      assert.equal("Simba and Simbad (alt) can play with you", text(answer[1]))
      assert.same({ "can play" }, styled(answer[1], "highlight"))
    end)

    it("counts more than three, with how many are online", function()
      local net, clients = crew({ { "Gahz", 24 }, { "Ann", 23 }, { "Bob", 25 }, { "Cleo", 26 }, { "Dan", 22 } })
      clients[5]:logout()
      net:run(5)
      local answer = clients[1].core:together().answer
      assert.equal("4 friends can play with you · 3 online now", text(answer[1]))
      assert.same({ "can play" }, styled(answer[1], "highlight"))
    end)

    it("names the best dungeon together, then another", function()
      -- At 24, with friends at 25 and 22: both fit The Deadmines and
      -- Shadowfang Keep, and the lower one comes first.
      local _, clients = crew({ { "Gahz", 24 }, { "Simba", 25 }, { "Krogg", 22 } })
      local answer = clients[1].core:together().answer
      assert.equal("Best together: The Deadmines with Simba and Krogg · also Shadowfang Keep", text(answer[2]))
      assert.same({ "The Deadmines" }, styled(answer[2], "text"))
    end)

    it("names the nearest Member when nobody can play", function()
      local net, clients = crew({ { "Gahz", 24 }, { "Simone", 41 }, { "Oskar", 60 } })
      playAlt(net, clients[2], "Simonette", 28)
      local answer = clients[1].core:together().answer
      assert.equal("Nobody is within 3 levels of you.", text(answer[1]))
      assert.equal("Nearest: Simone's alt Simonette, 4 ahead.", text(answer[2]))
      assert.same({}, styled(answer[1], "highlight"))
    end)

    it("names a Main as just the Member", function()
      local _, clients = crew({ { "Gahz", 24 }, { "Oskar", 60 } })
      assert.equal("Nearest: Oskar, 36 ahead.", text(clients[1].core:together().answer[2]))
    end)

    it("invites friends when you're alone in the Crew", function()
      local _, clients = crew({ { "Gahz", 24 } })
      local answer = clients[1].core:together().answer
      assert.equal("You're the only one in the Crew so far.", text(answer[1]))
      assert.equal("Share your Crew code from Settings to bring friends in.", text(answer[2]))
    end)
  end)

  describe("dungeons", function()
    it("say whether you fit, need levels or have outlevelled them", function()
      local _, clients = crew({ { "Gahz", 24 } })
      local view = clients[1].core:together()
      local function you(name)
        for _, bar in ipairs(view.bars) do
          if bar.name == name then return bar.tooltip.you end
        end
        for _, chip in ipairs(view.chips) do
          for _, item in ipairs(chip.items) do
            if item.name == name then return item.tooltip.you end
          end
        end
      end
      assert.equal("You fit", you("Shadowfang Keep"))
      assert.equal("You need 34 more levels", you("Scholomance"))
      assert.equal("You've outlevelled it", you("Ragefire Chasm"))
      assert.is_true(barFor(view, "Shadowfang Keep").fits)
    end)

    it("show a dot per Member who fits, their Character closest to your level", function()
      local net, clients = crew({ { "Gahz", 24 }, { "Simba", 25 }, { "Simbad", 29 }, { "Simone", 41 } })
      playAlt(net, clients[3], "Simbalt", 23)
      local bar = barFor(clients[1].core:together(), "Shadowfang Keep")
      assert.equal(2, #bar.dots)
      local fitters = {}
      for i, fitter in ipairs(bar.tooltip.fitters) do
        fitters[i] = ("%s %s %d"):format(fitter.member, fitter.name, fitter.level)
      end
      table.sort(fitters)
      assert.same({ "Simba Simba 25", "Simbad Simbalt 23" }, fitters)
    end)

    it("say who fits but is far from you, and who is almost there", function()
      local _, clients = crew({ { "Gahz", 24 }, { "Simba", 30 }, { "Simone", 20 } })
      local tooltip = barFor(clients[1].core:together(), "Shadowfang Keep").tooltip
      assert.equal(1, #tooltip.fitters)
      assert.equal("fits, but 6 levels from you", tooltip.fitters[1].far)
      assert.equal("Almost: Simone (2 short)", tooltip.almost)
    end)

    it("mark new Forever dungeons and the attunement, and hide raids", function()
      local _, clients = crew({ { "Gahz", 57 } })
      local view = clients[1].core:together()
      assert.is_true(barFor(view, "Blackmaw Hold").new)
      assert.equal("New in WoW: Forever", barFor(view, "Blackmaw Hold").tooltip.new)
      local shown = {}
      for _, bar in ipairs(view.bars) do shown[bar.name] = bar end
      for _, chip in ipairs(view.chips) do
        for _, item in ipairs(chip.items) do shown[item.name] = item end
      end
      assert.equal("attunement", shown["Onyxia attunement"].kind)
      assert.is_nil(shown["Molten Core"])
      assert.is_nil(shown["Hyjal Summit"])
    end)

    it("place the ones you fit first, in at most 5 lanes, the rest in +N here chips", function()
      local _, clients = crew({ { "Gahz", 58 } })
      local view = clients[1].core:together()
      local placed = 0
      for _, bar in ipairs(view.bars) do
        assert.truthy(bar.lane >= 1 and bar.lane <= 5)
        placed = placed + 1
      end
      local folded = 0
      for _, chip in ipairs(view.chips) do
        assert.truthy(chip.lane >= 1 and chip.lane <= 5)
        assert.equal(("+%d here"):format(#chip.items), chip.text)
        folded = folded + #chip.items
      end
      assert.truthy(folded > 0)
      local shown = 0
      for _, dungeon in ipairs(load().Core.DUNGEONS) do
        if dungeon.kind ~= "raid" then shown = shown + 1 end
      end
      assert.equal(shown, placed + folded)
      -- Nothing in a lane overlaps.
      local spans = {}
      for _, bar in ipairs(view.bars) do spans[#spans + 1] = bar end
      for _, chip in ipairs(view.chips) do spans[#spans + 1] = chip end
      for i, a in ipairs(spans) do
        for j = i + 1, #spans do
          local b = spans[j]
          if a.lane == b.lane then
            assert.truthy(a.x + a.width <= b.x or b.x + b.width <= a.x, ("%s and %s overlap"):format(
              a.name or a.text, b.name or b.text))
          end
        end
      end
      -- The ones you fit are placed first, so the first five get a lane.
      local fitting = 0
      for _, bar in ipairs(view.bars) do
        if bar.fits then fitting = fitting + 1 end
      end
      assert.truthy(fitting >= 5)
    end)
  end)

  describe("a crowd around one level", function()
    it("keeps labels in at most 4 rows, merged per level", function()
      local members = { { "Gahz", 24 } }
      local names = { "Bartholomew", "Krogg", "Theodora", "Wilhelmina", "Ulfric", "Sven", "Mirabelle",
        "Annaliese", "Simba", "Simbad", "Simone" }
      local levels = { 24, 25, 25, 24, 23, 24, 26, 22, 25, 27, 21 }
      for i, name in ipairs(names) do members[#members + 1] = { name, levels[i] } end
      local _, clients = crew(members)
      local view = clients[1].core:together(function(label) return #label * 7 end)

      local seen, rows = {}, {}
      for _, group in ipairs(view.groups) do
        assert.is_nil(seen[group.level], "one group per level")
        seen[group.level] = true
        if group.row then
          assert.truthy(group.row >= 1 and group.row <= 4)
          rows[group.row] = rows[group.row] or {}
          table.insert(rows[group.row], group)
        else
          assert.truthy(group.count >= 1)
        end
      end
      for _, row in pairs(rows) do
        for i, a in ipairs(row) do
          for j = i + 1, #row do
            local b = row[j]
            assert.truthy(a.labelX + a.labelWidth <= b.labelX or b.labelX + b.labelWidth <= a.labelX)
          end
        end
      end
      -- Your own label is placed, nearest the axis.
      assert.equal(1, groupAt(view, 24).row)
      assert.equal("11 friends can play with you · 11 online now", text(view.answer[1]))
    end)
  end)
end)
