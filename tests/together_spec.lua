local load = require("tests.load")

-- The Together tab, read through Core's together(): friends and dungeons
-- on one level line.

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

-- Every dungeon entry shown, by name.
local function entries(view)
  local shown = {}
  for _, bar in ipairs(view.bars) do shown[bar.name] = bar end
  return shown
end

local function sorted(list)
  local out = {}
  for name in pairs(list) do out[#out + 1] = name end
  table.sort(out)
  return out
end

local function idOf(clients, i)
  return clients[1]:rowFor(clients[i]).memberId
end

describe("Together", function()
  describe("the dungeon table", function()
    it("has the nine new Forever dungeons as Blizzard gives them", function()
      local ns = load()
      local forever = {}
      for _, dungeon in ipairs(ns.Core.DUNGEONS) do
        if dungeon.forever and dungeon.kind == "dungeon" then
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
        assert.is_boolean(dungeon.forever)
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

    it("shades every other ten levels, from 11", function()
      local _, clients = crew({ { "Gahz", 24 } })
      local view = clients[1].core:together()
      local spans = {}
      for i, decade in ipairs(view.decades) do
        spans[i] = ("%d-%d"):format(decade.from, decade.to)
      end
      assert.same({ "11-20", "31-40", "51-60" }, spans)
      local x11, x20
      for _, tick in ipairs(view.ticks) do
        if tick.level == 11 then x11 = tick.x end
        if tick.level == 20 then x20 = tick.x end
      end
      assert.equal(x11 - 12, view.decades[1].left)
      assert.equal(x20 + 12, view.decades[1].right)
    end)

    it("marks every tenth level for the overview", function()
      local _, clients = crew({ { "Gahz", 24 } })
      local marked = {}
      for _, tick in ipairs(clients[1].core:together().ticks) do
        if tick.decade then marked[#marked + 1] = tick.level end
      end
      assert.same({ 10, 20, 30, 40, 50, 60 }, marked)
    end)

    it("says how many dungeons shown fit each level, for hovering the line", function()
      local _, clients = crew({ { "Gahz", 24 } })
      local view = clients[1].core:together()
      local at24 = 0
      for _, bar in ipairs(view.bars) do
        if bar.from <= 24 and bar.to >= 24 then at24 = at24 + 1 end
      end
      assert.equal(("24 · %d dungeons"):format(at24), view.levels[24])
      assert.equal("1 · no dungeons", view.levels[1])
      assert.equal(60, #view.levels)
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

  describe("dungeons", function()
    it("say whether you fit, need levels or have outlevelled them", function()
      local _, clients = crew({ { "Gahz", 24 } })
      local view = clients[1].core:together()
      local function you(name) return barFor(view, name).tooltip.you end
      assert.equal("You fit", you("Shadowfang Keep"))
      assert.equal("You need 34 more levels", you("Scholomance"))
      assert.equal("You've outlevelled it", you("Ragefire Chasm"))
      assert.is_true(barFor(view, "Shadowfang Keep").fits)
    end)

    it("show a dot per Member who fits, their Character closest to your level", function()
      local net, clients = crew({ { "Gahz", 24 }, { "Simba", 25 }, { "Simbad", 29 }, { "Simone", 41 } })
      playAlt(net, clients[3], "Simbalt", 23)
      clients[2]:play({ lastName = "Stormgaard" })
      -- A last name alone goes out with the next unhurried DATA.
      net:run(70)
      local bar = barFor(clients[1].core:together(), "Shadowfang Keep")
      assert.equal(2, #bar.dots)
      local fitters = {}
      for i, fitter in ipairs(bar.tooltip.fitters) do
        fitters[i] = ("%s %s %d"):format(fitter.member, fitter.fullName, fitter.level)
      end
      table.sort(fitters)
      assert.same({ "Simba Simba Stormgaard 25", "Simbad Simbalt 23" }, fitters)
    end)

    it("say who fits but is far from you, and who is almost there", function()
      local _, clients = crew({ { "Gahz", 24 }, { "Simba", 30 }, { "Simone", 20 } })
      local tooltip = barFor(clients[1].core:together(), "Shadowfang Keep").tooltip
      assert.equal(1, #tooltip.fitters)
      assert.equal("fits, but 6 levels from you", tooltip.fitters[1].far)
      assert.equal("Almost: Simone (2 short)", tooltip.almost)
    end)

    it("plate their level range, and are as wide as their content past it", function()
      local _, clients = crew({ { "Gahz", 24 } })
      local view = clients[1].core:together(function(text) return #text * 7 end)
      local layout = load().Core.TOGETHER_LAYOUT
      local keep = barFor(view, "Shadowfang Keep")
      assert.equal((30 - 22) * layout.level, keep.range)
      local chasm = barFor(view, "Ragefire Chasm")
      assert.equal((18 - 13) * layout.level, chasm.range)
      for _, bar in ipairs(view.bars) do
        assert.truthy(bar.range <= bar.width, bar.name)
      end
    end)

    it("mark the ones you've outlevelled", function()
      local _, clients = crew({ { "Gahz", 24 } })
      local view = clients[1].core:together()
      assert.is_true(barFor(view, "Ragefire Chasm").past)
      assert.is_false(barFor(view, "Shadowfang Keep").past)
      assert.is_false(barFor(view, "Scholomance").past)
    end)

    it("plate the whole raids entry, a single level", function()
      local _, clients = crew({ { "Gahz", 60 } })
      clients[1].core:setSetting("togetherRaids", true)
      local raids = barFor(clients[1].core:together(), "Raids 5")
      assert.equal(raids.width, raids.range)
    end)

    it("mark new Forever dungeons and the attunement, and hide raids", function()
      local _, clients = crew({ { "Gahz", 57 } })
      local view = clients[1].core:together()
      assert.is_true(barFor(view, "Blackmaw Hold").forever)
      assert.equal("New in WoW: Forever", barFor(view, "Blackmaw Hold").tooltip.forever)
      local shown = entries(view)
      assert.equal("attunement", shown["Onyxia attunement"].kind)
      assert.is_nil(shown["Molten Core"])
      assert.is_nil(shown["Hyjal Summit"])
    end)

    it("give every dungeon shown a lane, as many as they need, the ones you fit first", function()
      local _, clients = crew({ { "Gahz", 58 } })
      local view = clients[1].core:together()
      local shown = 0
      for _, dungeon in ipairs(load().Core.DUNGEONS) do
        if dungeon.kind ~= "raid" then shown = shown + 1 end
      end
      assert.equal(shown, #view.bars)
      assert.truthy(view.lanes > 5)
      local most = 0
      for _, bar in ipairs(view.bars) do
        assert.truthy(bar.lane >= 1 and bar.lane <= view.lanes, bar.name)
        most = math.max(most, bar.lane)
      end
      assert.equal(view.lanes, most)
      -- Nothing in a lane overlaps.
      for i, a in ipairs(view.bars) do
        for j = i + 1, #view.bars do
          local b = view.bars[j]
          if a.lane == b.lane then
            assert.truthy(a.x + a.width <= b.x or b.x + b.width <= a.x, ("%s and %s overlap"):format(a.name, b.name))
          end
        end
      end
      -- The ones you fit are placed first: where one you fit and one you
      -- don't would overlap, yours is nearer the axis.
      for _, a in ipairs(view.bars) do
        for _, b in ipairs(view.bars) do
          if a.fits and not b.fits and a.x < b.x + b.width and b.x < a.x + a.width then
            assert.truthy(a.lane < b.lane, ("%s below %s"):format(a.name, b.name))
          end
        end
      end
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
      for _, bar in ipairs(view.bars) do assert.truthy(bar.lane >= 1 and bar.lane <= view.lanes) end
      -- Your own label is placed, nearest the axis.
      assert.equal(1, groupAt(view, 24).row)
    end)

    it("says how many label rows are used, so the rest give their room to the lanes", function()
      local _, alone = crew({ { "Gahz", 24 } })
      assert.equal(1, alone[1].core:together().rows)
      local members = { { "Gahz", 24 } }
      for i, name in ipairs({ "Bartholomew", "Theodora", "Wilhelmina", "Mirabelle" }) do
        members[#members + 1] = { name, 24 + i }
      end
      local _, clients = crew(members)
      local view = clients[1].core:together(function(label) return #label * 7 end)
      local most = 0
      for _, group in ipairs(view.groups) do most = math.max(most, group.row or 0) end
      assert.equal(most, view.rows)
      assert.truthy(view.rows > 1)
    end)
  end)
  describe("selecting friends", function()
    it("outlines the dungeons you and the Member fit, and fades the rest", function()
      local _, clients = crew({ { "Gahz", 24 }, { "Simba", 25 }, { "Simbad", 30 } })
      local view = clients[1].core:together(nil, { idOf(clients, 2) })
      local shared = {}
      for name, entry in pairs(entries(view)) do
        assert.equal(not entry.shared, entry.faded, name)
        if entry.shared then shared[name] = true end
      end
      assert.same({ "Blackfathom Deeps", "Excavation Site", "Shadowfang Keep", "The Deadmines", "The Stockade" },
        sorted(shared))
      assert.is_false(groupAt(view, 24).faded)
      assert.is_false(groupAt(view, 25).faded)
      assert.is_true(groupAt(view, 30).faded)
      assert.same({ idOf(clients, 2) }, view.selected)
      assert.equal("Clear", view.clear)
    end)

    it("fades every dungeon when none fits you both", function()
      local _, clients = crew({ { "Gahz", 24 }, { "Simone", 41 } })
      local view = clients[1].core:together(nil, { idOf(clients, 2) })
      for name, entry in pairs(entries(view)) do assert.is_true(entry.faded, name) end
    end)

    it("counts any of a selected Member's Characters, and every selected Member", function()
      local net, clients = crew({ { "Gahz", 24 }, { "Simone", 41 }, { "Oskar", 60 } })
      playAlt(net, clients[2], "Simonette", 25)
      local view = clients[1].core:together(nil, { idOf(clients, 2) })
      assert.is_true(entries(view)["Shadowfang Keep"].shared)

      local both = clients[1].core:together(nil, { idOf(clients, 2), idOf(clients, 3) })
      for name, entry in pairs(entries(both)) do assert.is_false(entry.shared, name) end
    end)

    it("ignores Members it doesn't know, and is off with nothing selected", function()
      local _, clients = crew({ { "Gahz", 24 }, { "Simba", 25 } })
      local view = clients[1].core:together(nil, { "nobody" })
      assert.same({}, view.selected)
      assert.is_nil(view.clear)
      for name, entry in pairs(entries(view)) do
        assert.is_false(entry.faded, name)
        assert.is_false(entry.shared, name)
      end
      assert.is_false(groupAt(view, 25).faded)
    end)

    it("gives each label the Members a click selects: everyone merged in it, never you", function()
      local _, clients = crew({ { "Gahz", 24 }, { "Ann", 24 }, { "Simba", 25 }, { "Krogg", 25 } })
      local view = clients[1].core:together()
      local merged = groupAt(view, 25).memberIds
      table.sort(merged)
      local expected = { idOf(clients, 3), idOf(clients, 4) }
      table.sort(expected)
      assert.same(expected, merged)
      assert.same({ idOf(clients, 2) }, groupAt(view, 24).memberIds)
    end)

    it("selects on click, adds on shift-click, and clears on the same click again", function()
      local ns = load()
      local select = ns.Core.selectTogether
      assert.same({ "a" }, select({}, { "a" }))
      assert.same({ "b" }, select({ "a" }, { "b" }))
      assert.same({ "a", "b" }, select({ "a" }, { "b" }, true))
      assert.same({ "a", "b" }, select({ "a" }, { "a", "b" }, true))
      assert.same({}, select({ "a" }, { "a" }))
      assert.same({}, select({ "a", "b" }, { "b", "a" }))
      assert.same({ "a", "b" }, select({ "a", "b" }, { "a" }, true))
      -- Your own dot selects nobody.
      assert.same({ "a" }, select({ "a" }, {}))
      assert.same({ "a" }, select({ "a" }, {}, true))
    end)
  end)

  describe("the Show menu", function()
    it("lists the five options with their defaults, the key and the help line", function()
      local _, clients = crew({ { "Gahz", 24 } })
      local show = clients[1].core:together().show
      assert.equal("Show", show.label)
      local sections = {}
      for i, section in ipairs(show.sections) do
        local options = {}
        for j, option in ipairs(section.options) do
          options[j] = ("%s=%s %s"):format(option.key, tostring(option.value), option.label)
        end
        sections[i] = { title = section.title, options = options }
      end
      assert.same({
        { title = "FRIENDS", options = {
          "togetherOffline=true Offline friends",
          "togetherAlts=false Alts",
        } },
        { title = "DUNGEONS", options = {
          "togetherNear=false Only near your level (±10)",
          "togetherAttunements=true Attunements",
          "togetherRaids=false Raids",
        } },
      }, sections)
      assert.equal("KEY", show.key.title)
      local key = {}
      for i, item in ipairs(show.key.items) do key[i] = item.kind .. " " .. item.text end
      assert.same({ "fits Fits your level", "attunement Attunement", "forever New in WoW: Forever",
        "fitters Friends who fit it" }, key)
      assert.equal("Drag or scroll to move along the levels. Click a friend to see where you fit together.", show.help)
    end)

    it("keeps its choices across a reload", function()
      local _, clients = crew({ { "Gahz", 24 } })
      clients[1].core:setSetting("togetherRaids", true)
      clients[1].core:setSetting("togetherOffline", false)
      clients[1]:reload()
      local view = clients[1].core:together()
      assert.is_true(view.show.sections[2].options[3].value)
      assert.is_false(view.show.sections[1].options[1].value)
      assert.is_not_nil(entries(view)["Raids 5"])
    end)

    it("leaves its choices off the Settings page", function()
      local _, clients = crew({ { "Gahz", 24 } })
      for _, section in ipairs(clients[1].core:settings()) do
        for _, setting in ipairs(section.settings) do
          assert.is_nil(setting.key:match("^together"), setting.key)
        end
      end
    end)
  end)

  describe("filters", function()
    it("hide offline friends' Characters, and say how many", function()
      local net, clients = crew({ { "Gahz", 24 }, { "Simba", 27 }, { "Simone", 41 }, { "Oskar", 50 } })
      clients[3]:logout()
      clients[4]:logout()
      net:run(5)
      clients[1].core:setSetting("togetherOffline", false)
      local view = clients[1].core:together()
      assert.is_not_nil(groupAt(view, 27))
      assert.is_nil(groupAt(view, 41))
      assert.is_nil(groupAt(view, 50))
      assert.equal("2 offline hidden", view.hidden)
    end)

    it("show Alts when asked, yours too", function()
      local net, clients = crew({ { "Gahz", 24 }, { "Simbad", 27 } })
      playAlt(net, clients[2], "Simbalt", 22)
      clients[2].character = character("Simbonus", 10)
      clients[2]:play()
      playAlt(net, clients[1], "Gahzalt", 30)
      local hidden = clients[1].core:together()
      assert.is_nil(groupAt(hidden, 22))
      assert.is_nil(groupAt(hidden, 24))
      -- Simbad plays Simbonus: only Simbalt is hidden. Your own aren't counted.
      assert.equal("1 alt hidden", hidden.hidden)

      clients[1].core:setSetting("togetherAlts", true)
      local view = clients[1].core:together()
      assert.is_not_nil(groupAt(view, 22))
      assert.is_not_nil(groupAt(view, 10))
      assert.equal("You", groupAt(view, 24).label)
      assert.is_nil(view.hidden)
    end)

    it("word the hidden note for every combination", function()
      local net, clients = crew({ { "Gahz", 24 }, { "Simbad", 27 }, { "Simone", 41 } })
      playAlt(net, clients[2], "Simbalt", 22)
      clients[2].character = character("Simbonus", 10)
      clients[2]:play()
      playAlt(net, clients[3], "Simonette", 19)
      clients[3]:logout()
      net:run(5)
      local core = clients[1].core
      local function note(offline, alts)
        core:setSetting("togetherOffline", offline)
        core:setSetting("togetherAlts", alts)
        return core:together().hidden
      end
      -- Simbad plays Simbonus: Simbalt is hidden. Simone is offline with
      -- an Alt.
      assert.equal("2 alts hidden", note(true, false))
      assert.equal("1 alt, 1 offline hidden", note(false, false))
      assert.equal("1 offline hidden", note(false, true))
      assert.is_nil(note(true, true))
    end)

    it("leave who fits counting everyone", function()
      local net, clients = crew({ { "Gahz", 24 }, { "Simba", 25 } })
      clients[2]:logout()
      net:run(5)
      clients[1].core:setSetting("togetherOffline", false)
      local view = clients[1].core:together()
      assert.equal(1, entries(view)["Shadowfang Keep"].count)
    end)

    it("hide attunements when off", function()
      local _, clients = crew({ { "Gahz", 57 } })
      assert.is_not_nil(entries(clients[1].core:together())["Onyxia attunement"])
      clients[1].core:setSetting("togetherAttunements", false)
      assert.is_nil(entries(clients[1].core:together())["Onyxia attunement"])
    end)

    it("show raids as one entry at 60, listing each raid", function()
      local _, clients = crew({ { "Gahz", 60 }, { "Oskar", 60 } })
      assert.is_nil(entries(clients[1].core:together())["Raids 5"])
      clients[1].core:setSetting("togetherRaids", true)
      local view = clients[1].core:together()
      local raids = entries(view)["Raids 5"]
      assert.equal("raids", raids.kind)
      assert.equal(60, raids.from)
      assert.is_true(raids.fits)
      assert.equal(1, raids.count)
      assert.is_nil(entries(view)["Molten Core"])
      assert.equal("Raids at 60", raids.tooltip.title)
      local listed = {}
      for i, raid in ipairs(raids.tooltip.raids) do
        listed[i] = ("%s · %s%s"):format(raid.name, raid.detail, raid.forever and " forever" or "")
      end
      assert.same({
        "Molten Core · 40-player · Blackrock Mountain",
        "Onyxia's Lair · 40-player · Dustwallow Marsh",
        "Zul'Gurub · 20-player · Stranglethorn Vale",
        "The Barrow Deeps · 10-player · Mount Hyjal forever",
        "Hyjal Summit · 20-player · Mount Hyjal forever",
      }, listed)
    end)

    it("keep only dungeons near your level, and mark the stretches left empty", function()
      local _, clients = crew({ { "Gahz", 40 } })
      local core = clients[1].core
      assert.is_nil(core:together().empty)
      core:setSetting("togetherNear", true)
      local view = core:together()
      for name, entry in pairs(entries(view)) do
        assert.truthy(entry.to >= 30 and entry.from <= 50, name)
      end
      assert.is_not_nil(entries(view)["Shadowfang Keep"])
      assert.is_nil(entries(view)["Scholomance"])
      assert.is_nil(entries(view)["Ragefire Chasm"])

      assert.equal("No dungeons shown at these levels", view.empty.text)
      assert.equal("Show all levels", view.empty.action)
      assert.equal("togetherNear", view.empty.setting)
      local xOf = function(level) return view.ticks[level].x end
      local function inSpan(x)
        for _, span in ipairs(view.empty.spans) do
          if x >= span.left and x <= span.right then return true end
        end
        return false
      end
      assert.is_true(inSpan(xOf(5)))
      assert.is_true(inSpan(xOf(15)))
      assert.is_false(inSpan(xOf(40)))
      -- No span overlaps anything in a lane.
      for _, span in ipairs(view.empty.spans) do
        for _, item in ipairs(view.bars) do
          assert.truthy(span.right <= item.x or span.left >= item.x + item.width)
        end
      end
    end)
  end)
end)
