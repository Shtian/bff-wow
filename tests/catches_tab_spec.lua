local load = require("tests.load")

-- Item IDs from the list (docs/research/fishing-catches.md).
local SMALLFISH = 6291
local LOCH_FRENZY = 6317
local CATFISH_19 = 6363
local FERALAS_AHI = 16967
local SUMMER_BASS = 13756
local TASTYFISH = 19807
local BATTERED_CHEST = 6356
local SHOE = 271647

local DAY = 86400

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

local function catch(...)
  local items = {}
  for i = 1, select("#", ...) do items[i] = { itemId = select(i, ...), quantity = 1 } end
  return { items = items, zone = "Feralas", subzone = "The Twin Colossals", mapId = 1444 }
end

-- Shares every client's catches: a level change sends the record now.
local function share(net, clients)
  for _, client in ipairs(clients) do client:play({ level = client.character.level + 1 }) end
  net:run(5)
end

local function section(tab, title)
  for _, s in ipairs(tab.sections) do
    if s.title == title then return s end
  end
end

local function titles(tab)
  local list = {}
  for _, s in ipairs(tab.sections) do list[#list + 1] = s.title end
  return list
end

local function tile(tab, itemId)
  for _, s in ipairs(tab.sections) do
    for _, t in ipairs(s.tiles) do
      if t.itemId == itemId then return t end
    end
  end
end

local function tileCount(tab)
  local n = 0
  for _, s in ipairs(tab.sections) do n = n + #s.tiles end
  return n
end

-- Every counted type's first item, so a test can catch them all.
local function countedItems(ns)
  local items = {}
  for _, t in ipairs(ns.Catches.TYPES) do
    if not t.extra then items[#items + 1] = t.itemId end
  end
  return items
end

describe("the Catches tab", function()
  describe("its top", function()
    it("counts the types caught towards the next trophy step", function()
      local _, clients = crew({ "Ann" })
      local a = clients[1]
      a.core:caught(catch(SMALLFISH, LOCH_FRENZY, SUMMER_BASS))
      local tab = a.core:catchesTab("where", "all")
      assert.equal(2, tab.caught)
      assert.equal(48, tab.total)
      assert.is_false(tab.done)
      assert.equal("2 of 48 types caught", tab.count)
      assert.equal("of 48 types caught", tab.countOf)
      assert.equal("Next trophy at 10 types: 8 more to catch", tab.next)
      assert.same({ 10 / 48, 20 / 48, 30 / 48, 40 / 48 }, tab.ticks)
    end)

    it("turns to every type caught once the Crew has them all", function()
      local net, clients, ns = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      local items = countedItems(ns)
      for i, itemId in ipairs(items) do
        local client = i % 2 == 0 and b or a
        client.core:caught(catch(itemId))
      end
      share(net, clients)
      local tab = a.core:catchesTab("where", "all")
      assert.is_true(tab.done)
      assert.equal(48, tab.caught)
      assert.equal("All 48 types caught", tab.count)
      assert.equal("Every type on the list. Extras and new finds still show up below.", tab.next)
      a.core:caught(catch(items[1]))
      assert.equal(48, a.core:catchesTab("where", "all").caught)
    end)

    it("names the last step as every type", function()
      local _, clients, ns = crew({ "Ann" })
      local a = clients[1]
      local items = countedItems(ns)
      for i = 1, 46 do a.core:caught(catch(items[i])) end
      assert.equal("Next trophy at every type: 2 more to catch", a.core:catchesTab("where", "all").next)
    end)
  end)

  describe("grouped by where to fish", function()
    it("shows each type once, in the lowest water it's found in, with counts that add up", function()
      local _, clients, ns = crew({ "Ann" })
      local a = clients[1]
      a.core:caught(catch(SMALLFISH, CATFISH_19))
      local tab = a.core:catchesTab("where", "all")
      assert.same({ "Level 1–10", "Level 10–25", "Level 20–35", "Level 30–45", "Level 40–55", "Level 50–60",
        "Extras" }, titles(tab))
      local first = section(tab, "Level 1–10")
      assert.equal("Elwynn Forest, Dun Morogh, Teldrassil, Durotar, Mulgore, Tirisfal Glades, the capitals", first.sub)
      assert.is_truthy(tile(tab, SMALLFISH))

      local seen, counted, caught = {}, 0, 0
      for _, s in ipairs(tab.sections) do
        for _, t in ipairs(s.tiles) do
          assert.is_nil(seen[t.id], tostring(t.id))
          seen[t.id] = true
        end
        if s.counted then
          counted = counted + s.counted
          caught = caught + s.got
        end
      end
      assert.equal(#ns.Catches.TYPES, tileCount(tab))
      assert.equal(48, counted)
      assert.equal(2, caught)
      -- 4 fish, 2 bloated fish and the Mud Snapper family.
      assert.equal("1 / 7", first.count)
      -- The Catfish family's first water is Level 10–25.
      assert.equal("1 / 9", section(tab, "Level 10–25").count)
    end)

    it("puts unlisted catches in their own section before Extras, not under New on Forever", function()
      local _, clients = crew({ "Ann" })
      local a = clients[1]
      assert.is_nil(section(a.core:catchesTab("where", "all"), "Not on the list yet"))

      a.core:caught(catch(SHOE))
      local tab = a.core:catchesTab("where", "all")
      assert.is_nil(section(tab, "New on Forever"))
      assert.equal("Not on the list yet", tab.sections[#tab.sections - 1].title)
      local unlisted = section(tab, "Not on the list yet")
      assert.equal("Not counted", unlisted.sub)
      assert.equal("1 caught", unlisted.count)
      assert.equal(1, #unlisted.tiles)
      assert.equal(SHOE, unlisted.tiles[1].itemId)
      assert.is_true(unlisted.tiles[1].caught)
    end)

    it("puts Extras last, never counted", function()
      local _, clients = crew({ "Ann" })
      local a = clients[1]
      a.core:caught(catch(SUMMER_BASS, TASTYFISH))
      local tab = a.core:catchesTab("where", "all")
      local extras = tab.sections[#tab.sections]
      assert.equal("Extras", extras.title)
      assert.equal("Not counted", extras.sub)
      assert.equal("2 caught", extras.count)
      assert.is_nil(extras.counted)
      assert.is_truthy(tile(tab, SUMMER_BASS).extra)
      assert.equal(0, tab.caught)
    end)
  end)

  describe("grouped by type", function()
    it("has Fish, Rare catches, unlisted catches when there are any, and Extras", function()
      local _, clients = crew({ "Ann" })
      local a = clients[1]
      a.core:caught(catch(SMALLFISH, FERALAS_AHI))
      local tab = a.core:catchesTab("type", "all")
      assert.same({ "Fish", "Rare catches", "Extras" }, titles(tab))
      assert.equal("1 / 27", section(tab, "Fish").count)
      assert.equal("1 / 21", section(tab, "Rare catches").count)
      assert.is_nil(section(tab, "Fish").sub)

      a.core:caught(catch(SHOE))
      tab = a.core:catchesTab("type", "all")
      assert.same({ "Fish", "Rare catches", "Not on the list yet", "Extras" }, titles(tab))
      local unlisted = section(tab, "Not on the list yet")
      assert.equal("Not counted", unlisted.sub)
      assert.equal("1 caught", unlisted.count)
    end)
  end)

  describe("Show", function()
    it("filters to fish, rare catches, Extras or what's not caught yet", function()
      local _, clients = crew({ "Ann" })
      local a = clients[1]
      a.core:caught(catch(SMALLFISH, SHOE))

      local fish = a.core:catchesTab("type", "fish")
      assert.is_truthy(tile(fish, SMALLFISH))
      assert.is_truthy(tile(fish, SUMMER_BASS))
      assert.is_nil(tile(fish, FERALAS_AHI))
      assert.is_nil(tile(fish, BATTERED_CHEST))
      assert.is_nil(tile(fish, SHOE))

      local rare = a.core:catchesTab("type", "rare")
      assert.is_truthy(tile(rare, FERALAS_AHI))
      assert.is_truthy(tile(rare, TASTYFISH))
      assert.is_nil(tile(rare, SMALLFISH))

      local extras = a.core:catchesTab("where", "extras")
      assert.same({ "Extras" }, titles(extras))

      local missing = a.core:catchesTab("where", "missing")
      assert.is_nil(tile(missing, SMALLFISH))
      assert.is_nil(tile(missing, SHOE))
      assert.is_truthy(tile(missing, LOCH_FRENZY))
      assert.is_nil(section(missing, "New on Forever"))
      assert.is_nil(missing.filtered)
    end)

    it("hides waters with nothing to show, but keeps counting them all", function()
      local _, clients = crew({ "Ann" })
      local a = clients[1]
      local tab = a.core:catchesTab("where", "rare")
      assert.is_nil(section(tab, "New on Forever"))
      for _, s in ipairs(tab.sections) do assert.is_true(#s.tiles > 0) end
      assert.equal("0 / 7", section(tab, "Level 1–10").count)
    end)

    it("names each choice with how many it shows, and the one picked", function()
      local _, clients = crew({ "Ann" })
      local a = clients[1]
      a.core:caught(catch(SMALLFISH))
      local tab = a.core:catchesTab("type", "fish")
      assert.equal("Show: Fish", tab.show.label)
      assert.equal("Group: Type", tab.group.label)
      local counts = {}
      for _, option in ipairs(tab.show.options) do counts[option.id] = option end
      assert.is_nil(counts.all.count)
      assert.equal(tileCount(tab), counts.fish.count)
      assert.is_true(counts.fish.picked)
      assert.is_false(counts.all.picked)
      assert.equal(tileCount(a.core:catchesTab("type", "missing")), counts.missing.count)
      assert.equal("Show names of fish not caught yet", tab.show.names.label)
    end)

    it("says so when a choice shows nothing", function()
      local _, clients, ns = crew({ "Ann" })
      local a = clients[1]
      for _, t in ipairs(ns.Catches.TYPES) do a.core:caught(catch(t.itemId)) end
      local tab = a.core:catchesTab("where", "missing")
      assert.same({}, tab.sections)
      assert.equal("The Crew has caught every type.", tab.filtered.title)
      assert.equal('Change "Show" to see more.', tab.filtered.text)
    end)

    it("falls back to where to fish and all for a choice it doesn't know", function()
      local _, clients = crew({ "Ann" })
      local tab = clients[1].core:catchesTab("nonsense", "nonsense")
      assert.equal("Group: Where to fish", tab.group.label)
      assert.equal("Show: All", tab.show.label)
    end)
  end)

  describe("names of fish not caught yet", function()
    it("are hidden until you turn them on, and that's saved", function()
      local _, clients = crew({ "Ann" })
      local a = clients[1]
      a.core:caught(catch(SMALLFISH))
      local tab = a.core:catchesTab("where", "all")
      assert.is_false(tab.show.names.value)
      assert.is_true(tile(tab, SMALLFISH).named)
      local frenzy = tile(tab, LOCH_FRENZY)
      assert.is_false(frenzy.named)
      assert.is_nil(frenzy.tooltip.note)
      assert.equal("To see its name: Show > Show names of fish not caught yet", frenzy.tooltip.hint)

      a.core:setSetting("catchesNames", true)
      a:reload()
      tab = a.core:catchesTab("where", "all")
      assert.is_true(tab.show.names.value)
      frenzy = tile(tab, LOCH_FRENZY)
      assert.is_true(frenzy.named)
      assert.equal("Only in Loch Modan", frenzy.tooltip.note)
      assert.is_nil(frenzy.tooltip.hint)
    end)
  end)

  describe("a tile's tooltip", function()
    it("says who caught it first, when and where, the Crew's count, who else and every water", function()
      local net, clients = crew({ "Ann", "Bob", "Cleo" })
      local a, b, c = clients[1], clients[2], clients[3]
      b.core:caught(catch(SMALLFISH))
      net:run(30)
      a.core:caught(catch(SMALLFISH, SMALLFISH))
      net:run(5)
      c.core:caught(catch(SMALLFISH))
      share(net, clients)
      local t = tile(a.core:catchesTab("where", "all"), SMALLFISH)
      assert.is_true(t.caught)
      local tip = t.tooltip
      assert.equal("First caught by", tip.firstBy)
      assert.equal("Bob", tip.first.who)
      assert.equal("WARRIOR", tip.first.classFilename)
      assert.equal("0m ago · Feralas, The Twin Colossals", tip.when)
      assert.equal("The Crew has caught", tip.crew)
      assert.equal(4, tip.count)
      assert.equal("Also caught by you and Cleo", tip.also)
      assert.equal("Where: Level 1–10, Level 10–25, Level 20–35", tip.where)
      assert.is_nil(tip.none)
    end)

    it("says an Extra isn't counted, and why", function()
      local _, clients = crew({ "Ann" })
      local t = tile(clients[1].core:catchesTab("where", "all"), SUMMER_BASS)
      assert.equal("Extra, not counted: only in one season", t.tooltip.extra)
      assert.equal("No one in the Crew has caught this yet.", t.tooltip.none)
    end)
  end)

  describe("fresh first catches", function()
    it("mark tiles caught in the last 3 days and list the newest 3", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      a.core:caught(catch(SMALLFISH))
      net:step(net:now() + 2 * DAY)
      b.core:caught(catch(LOCH_FRENZY))
      net:run(10)
      a.core:caught(catch(FERALAS_AHI))
      net:run(10)
      a.core:caught(catch(SHOE))
      net:run(10)
      b.core:caught(catch(CATFISH_19))
      share(net, clients)

      local tab = a.core:catchesTab("where", "all")
      assert.is_true(tile(tab, SMALLFISH).fresh)
      local recent = {}
      for i, r in ipairs(tab.recent) do recent[i] = r.itemId end
      assert.same({ 6309, SHOE, FERALAS_AHI }, recent)
      assert.equal("Bob", tab.recent[1].first.who)
      assert.equal("Feralas · 0m ago", tab.recent[1].when)
      assert.equal("Catfish (by weight)", tab.recent[1].name)

      net:step(net:now() + DAY + 60)
      tab = a.core:catchesTab("where", "all")
      assert.is_false(tile(tab, SMALLFISH).fresh)
      assert.is_true(tile(tab, LOCH_FRENZY).fresh)
    end)
  end)

  describe("a new Crew", function()
    it("sees no catches yet, with the waters for their level", function()
      local _, clients = crew({ "Ann" })
      local a = clients[1]
      a:play({ level = 22 })
      local tab = a.core:catchesTab("where", "all")
      assert.equal("No catches yet", tab.empty.title)
      assert.equal("When anyone in the Crew catches a fish, it shows up here. Start in the waters for your level: Level 20–35.",
        tab.empty.text)
      assert.same({}, tab.recent)
      assert.equal(#tab.sections, 7)
      a.core:caught(catch(SUMMER_BASS))
      assert.is_nil(a.core:catchesTab("where", "all").empty)
    end)
  end)
end)
