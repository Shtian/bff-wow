local load = require("tests.load")

-- Item IDs from the list (docs/research/fishing-catches.md).
local SMALLFISH = 6291
local MACKEREL = 6303
local CATFISH_19 = 6363
local CATFISH_7 = 6309
local SUMMER_BASS = 13756
local TASTYFISH = 19807
local SHOE = 271647

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

-- A catch as Catches.read gives it: each item ID once, in Westfall.
local function catch(...)
  local items = {}
  for i = 1, select("#", ...) do items[i] = { itemId = select(i, ...), quantity = 1 } end
  return { items = items, zone = "Westfall", subzone = "The Jansen Stead", mapId = 1436 }
end

local function typeOf(view, id)
  for _, t in ipairs(view.types) do
    if t.id == id then return t end
  end
end

-- A fake game's loot window: each slot as { link, quantity, currencyID,
-- isCoin }, whether it's fishing loot, and where the Character stands.
local function game(slots, fishing, where)
  where = where or {}
  return {
    isFishingLoot = function() return fishing end,
    getNumLootItems = function() return #slots end,
    getLootSlotLink = function(slot) return slots[slot].link end,
    getLootSlotInfo = function(slot)
      local s = slots[slot]
      return 134000, "Item", s.quantity, s.currencyID, 1, false, false, nil, true, s.isCoin
    end,
    zone = function() return where.zone end,
    subzone = function() return where.subzone end,
    mapId = function() return where.mapId end,
  }
end

local function link(id)
  return ("|cffffffff|Hitem:%d::::::::20:::::::::|h[Fish]|h|r"):format(id)
end

describe("Catches", function()
  describe("the list", function()
    it("counts 46 types and never the Extras", function()
      local ns = load()
      local counted, extras = 0, 0
      for _, t in ipairs(ns.Catches.TYPES) do
        if t.extra then extras = extras + 1 else counted = counted + 1 end
      end
      assert.equal(46, counted)
      assert.equal(46, ns.Catches.TOTAL)
      assert.is_true(extras > 0)
    end)

    it("gives every type waters that exist, and every item ID one type", function()
      local ns = load()
      local waters, seen = {}, {}
      for _, w in ipairs(ns.Catches.WATERS) do waters[w.id] = true end
      for _, t in ipairs(ns.Catches.TYPES) do
        assert.is_true(#t.waters > 0, t.name)
        for _, w in ipairs(t.waters) do assert.is_true(waters[w], t.name .. " " .. w) end
        for _, id in ipairs(t.items) do
          assert.is_nil(seen[id], "item " .. id)
          seen[id] = true
          assert.equal(t.id, ns.Catches.typeOf(id))
        end
      end
      assert.is_nil(ns.Catches.typeOf(SHOE))
    end)
  end)

  describe("reading the loot window", function()
    it("reads each fished item and where the Character stands", function()
      local ns = load()
      local read = ns.Catches.read(game({
        { link = link(SMALLFISH), quantity = 2 },
        { link = link(CATFISH_19), quantity = 1 },
      }, true, { zone = "Westfall", subzone = "The Jansen Stead", mapId = 1436 }))
      assert.same({
        items = { { itemId = SMALLFISH, quantity = 2 }, { itemId = CATFISH_19, quantity = 1 } },
        zone = "Westfall", subzone = "The Jansen Stead", mapId = 1436,
      }, read)
    end)

    it("reads nothing when the loot isn't from fishing", function()
      local ns = load()
      assert.is_nil(ns.Catches.read(game({ { link = link(SMALLFISH), quantity = 1 } }, false)))
    end)

    it("skips coin, currency and slots without an item link", function()
      local ns = load()
      local read = ns.Catches.read(game({
        { quantity = 0, isCoin = true },
        { link = "|cffffffff|Hcurrency:1:|h[Coin]|h|r", quantity = 1, currencyID = 1 },
        { link = link(MACKEREL), quantity = 0 },
      }, true, { zone = "Durotar", subzone = "" }))
      assert.same({ items = { { itemId = MACKEREL, quantity = 1 } }, zone = "Durotar" }, read)
    end)

    it("reads nothing from an empty window, a secret value or an error", function()
      local ns = load()
      assert.is_nil(ns.Catches.read(game({}, true)))
      local secret = game({ { link = link(SMALLFISH), quantity = 1 } }, true)
      secret.isSecret = function(value) return type(value) == "string" end
      assert.is_nil(ns.Catches.read(secret))
      local broken = game({ { link = link(SMALLFISH), quantity = 1 } }, true)
      broken.getLootSlotLink = function() error("no") end
      assert.is_nil(ns.Catches.read(broken))
    end)
  end)

  describe("in your own record", function()
    it("keeps the first catch of a type, with time and zone, and counts later ones", function()
      local net, clients = crew({ "Ann" })
      local a = clients[1]
      local first = net:now()
      assert.is_true(a.core:caught(catch(SMALLFISH)))
      net:run(60)
      local later = catch(SMALLFISH)
      later.zone, later.subzone = "Elwynn Forest", nil
      later.items[1].quantity = 3
      assert.is_true(a.core:caught(later))

      local view = a.core:catches()
      local t = typeOf(view, SMALLFISH)
      assert.equal(4, t.count)
      assert.equal(first, t.first.time)
      assert.equal("1m ago", t.first.since)
      assert.equal("Westfall", t.first.zone)
      assert.equal("The Jansen Stead", t.first.subzone)
      assert.equal(1436, t.first.mapId)
      assert.equal("Ann", t.first.displayName)
      assert.is_true(t.first.own)
      assert.equal("Ann", t.first.character)
      assert.equal("WARRIOR", t.first.classFilename)
      assert.equal(1, view.caught)
      assert.equal(46, view.total)
    end)

    it("are kept before you join a Crew", function()
      local ns = load()
      local net = ns.FakeNet.new()
      local a = net:add("Ann"):login()
      assert.is_true(a.core:caught(catch(SMALLFISH)))
      assert.equal(1, a.core:catches().caught)
    end)

    it("never keep a catch that isn't fishing loot", function()
      local net, clients, ns = crew({ "Ann" })
      local a = clients[1]
      local notFishing = ns.Catches.read(game({ { link = link(SMALLFISH), quantity = 1 } }, false))
      assert.is_false(a.core:caught(notFishing))
      assert.is_false(a.core:caught({ items = {} }))
      assert.is_false(a.core:caught({ items = { { itemId = "junk", quantity = 1 } } }))
      net:run(2)
      local view = a.core:catches()
      assert.equal(0, view.caught)
      assert.is_nil(typeOf(view, SMALLFISH).first)
      assert.equal(0, typeOf(view, SMALLFISH).count)
    end)

    it("count every weight of a fish family as that one type", function()
      local net, clients = crew({ "Ann" })
      local a = clients[1]
      a.core:caught(catch(CATFISH_19))
      net:run(5)
      a.core:caught(catch(CATFISH_7))
      local view = a.core:catches()
      local family = typeOf(view, "catfish")
      assert.equal(2, family.count)
      assert.equal(1, view.caught)
      assert.equal(0, #view.unlisted)
      assert.same({ 6309, 6310, 6311, 6363, 6364 }, family.items)
    end)

    it("keep fished items not on the list as unlisted catches, up to a cap", function()
      local net, clients, ns = crew({ "Ann" })
      local a = clients[1]
      a.core:caught(catch(SHOE))
      a.core:caught(catch(SHOE))
      local view = a.core:catches()
      assert.equal(0, view.caught)
      assert.equal(1, #view.unlisted)
      assert.equal(SHOE, view.unlisted[1].itemId)
      assert.equal(2, view.unlisted[1].count)
      assert.equal("Westfall", view.unlisted[1].first.zone)

      for i = 1, ns.Catches.UNLISTED_CAP + 5 do a.core:caught(catch(900000 + i)) end
      net:run(1)
      assert.equal(ns.Catches.UNLISTED_CAP, #a.core:catches().unlisted)
      -- Listed types still go in once the cap is reached.
      assert.is_true(a.core:caught(catch(SMALLFISH)))
      assert.equal(1, a.core:catches().caught)
    end)

    it("never count Extras towards the types caught", function()
      local _, clients = crew({ "Ann" })
      local a = clients[1]
      a.core:caught(catch(SUMMER_BASS, TASTYFISH))
      local view = a.core:catches()
      assert.equal(0, view.caught)
      assert.equal(1, typeOf(view, SUMMER_BASS).count)
      assert.equal("season", typeOf(view, SUMMER_BASS).extra)
      assert.equal("contest", typeOf(view, TASTYFISH).extra)
    end)

    it("go out with the next send rather than right away", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      a.core:caught(catch(SMALLFISH))
      net:run(5)
      assert.is_nil(typeOf(b.core:catches(), SMALLFISH).first)
      a:play({ level = 11 })
      net:run(3)
      assert.equal("Ann", typeOf(b.core:catches(), SMALLFISH).first.displayName)
    end)
  end)

  describe("the Crew's catches", function()
    it("arrive through sync and name the earliest catcher of each type, with the Crew's count", function()
      local net, clients = crew({ "Ann", "Bob", "Cleo" })
      local a, b, c = clients[1], clients[2], clients[3]
      b.core:caught(catch(SMALLFISH))
      net:run(30)
      a.core:caught(catch(SMALLFISH, MACKEREL))
      a.core:caught(catch(SMALLFISH))
      c.core:caught(catch(SHOE))
      for _, client in ipairs(clients) do client:play({ level = 12 }) end
      net:run(5)

      for _, client in ipairs(clients) do
        local view = client.core:catches()
        local smallfish = typeOf(view, SMALLFISH)
        assert.equal("Bob", smallfish.first.displayName)
        assert.equal(client == b, smallfish.first.own)
        assert.equal(3, smallfish.count)
        assert.equal("Ann", typeOf(view, MACKEREL).first.displayName)
        assert.equal(2, view.caught)
        assert.equal(1, #view.unlisted)
        assert.equal("Cleo", view.unlisted[1].first.displayName)
      end
    end)

    it("leave out Members who left the Crew", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      b.core:caught(catch(SMALLFISH))
      b:play({ level = 12 })
      net:run(5)
      assert.equal(1, a.core:catches().caught)
      b.core:leaveCrew()
      net:run(5)
      assert.equal(0, a.core:catches().caught)
    end)

    it("ignore a malformed catches field, keeping the rest of the record", function()
      local net, clients, ns = crew({ "Ann" })
      local a = clients[1]
      local function send(id, catches)
        local guid = "Player-0-" .. id
        a.core:received(ns.Codec.encode({
          type = "DATA", from = id,
          records = { { id = id, version = net:now(), displayName = id, catches = catches, characters = {
            [guid] = { guid = guid, name = id, level = 20, lastPlayed = net:now() },
          } } },
        }))
      end
      local good = { t = 500, n = 2, z = "Westfall" }
      send("junkfield", "junk")
      send("badentry", {
        [SMALLFISH] = { t = "yesterday", n = 1 },
        [MACKEREL] = { t = 400, n = -1 },
        [CATFISH_19] = { t = 400, n = 1, z = 7 },
        unknownfamily = good,
        [-5] = good,
        ["catfish"] = good,
      })
      local view = a.core:catches()
      assert.equal(1, view.caught)
      assert.equal("badentry", typeOf(view, "catfish").first.displayName)
      assert.is_nil(typeOf(view, SMALLFISH).first)
      assert.equal(0, #view.unlisted)
      assert.equal(20, a:rowFor({ memberId = "junkfield" }).level)
      assert.equal(20, a:rowFor({ memberId = "badentry" }).level)
    end)
  end)
end)
