-- SpareRules, the stateless parts of Spares: item strings, what a record
-- carries, tradeability, pruning, the item-gone check and who wins.
local load = require("tests.load")

local DAY = 24 * 60 * 60

describe("SpareRules", function()
  local H
  before_each(function() H = load().SpareRules end)

  describe("item strings", function()
    it("keep the item ID and nothing unset", function()
      assert.equal("5191", H.itemString("|cff1eff00|Hitem:5191::::::::18:::::::|h[Cruel Barb]|h|r"))
      assert.equal("5191", H.itemString("item:5191:0:0:0:0:0:0:0:18"))
    end)

    it("keep the enchant when set", function()
      assert.equal("5191:1897", H.itemString("|Hitem:5191:1897:::::::18|h[Cruel Barb]|h"))
    end)

    it("keep a random suffix, and its factor when the suffix scales", function()
      assert.equal("15210::1026", H.itemString("|Hitem:15210::::::1026:12345:30|h[Raider Shortsword of the Tiger]|h"))
      assert.equal("15210::-19:1238425", H.itemString("|Hitem:15210::::::-19:1238425:30|h[Raider Shortsword of the Monkey]|h"))
    end)

    it("refuse anything that isn't an item", function()
      assert.is_nil(H.itemString("|Hspell:133|h[Fireball]|h"))
      assert.is_nil(H.itemString("Cruel Barb"))
      assert.is_nil(H.itemString(nil))
      assert.is_nil(H.itemString("item:0"))
    end)

    it("rebuild to a string the game resolves, with the suffix where it was", function()
      local original = "item:15210:0:0:0:0:0:-19:1238425:30:0"
      local trimmed = H.itemString(original)
      local rebuilt = H.fullItemString(trimmed)
      assert.equal("item:15210::::::-19:1238425", rebuilt)
      local fields = {}
      for field in (rebuilt .. ":"):gmatch("([^:]*):") do fields[#fields + 1] = field end
      assert.equal("15210", fields[2])
      assert.equal("-19", fields[8])
      assert.equal("1238425", fields[9])
      assert.equal(trimmed, H.itemString(rebuilt))
      assert.equal("item:5191:1897", H.fullItemString("5191:1897"))
      assert.equal("item:5191", H.fullItemString("5191"))
    end)

    it("validate what comes off the wire", function()
      assert.is_true(H.validItem("5191"))
      assert.is_true(H.validItem("15210::-19:1238425"))
      assert.is_false(H.validItem("abc"))
      assert.is_false(H.validItem("5191:1:2:3:4"))
      assert.is_false(H.validItem(5191))
      assert.is_false(H.validItem("5191|Hspell"))
    end)
  end)

  describe("in a record", function()
    it("read the well-formed Spares and skip the rest", function()
      local record = { spares = {
        { i = 1, s = "5191", l = 18, t = 100 },
        { i = 2, s = "nonsense", l = 18, t = 100 },
        "junk",
        { i = 3, s = "5191", l = 18, t = 100, r = "bobbobbo", c = "Player-0-Jaina" },
        { i = 4, s = "5191", l = 18, t = 100, r = "bobbobbo" },
        { i = 5, s = "5191", t = 100 },
      } }
      local list = H.inRecord(record)
      assert.equal(2, #list)
      assert.same({ id = 1, item = "5191", level = 18, time = 100 }, list[1])
      assert.same({ id = 3, item = "5191", level = 18, time = 100, to = "bobbobbo", guid = "Player-0-Jaina" }, list[2])
      assert.same({}, H.inRecord({ spares = "junk" }))
      assert.same({}, H.inRecord({}))
      assert.same({}, H.inRecord(nil))
    end)

    it("read the well-formed Claims, one per Spare, the earliest", function()
      local record = { claims = {
        { m = "annannan", i = 1, c = "Player-0-Bob", t = 100 },
        { m = "annannan", i = 1, c = "Player-0-Bob", t = 50 },
        { m = "annannan", c = "Player-0-Bob", t = 100 },
        { m = "annannan", i = 2, t = 100 },
        7,
      } }
      assert.same({ { owner = "annannan", id = 1, guid = "Player-0-Bob", time = 50 } }, H.claimsIn(record))
      assert.same({}, H.claimsIn({ claims = { m = 1 } }))
    end)
  end)

  describe("pruning", function()
    it("drops Spares 30 days after posting, given or not", function()
      local list = {
        { i = 1, s = "1", l = 1, t = 0 },
        { i = 2, s = "1", l = 1, t = 0, r = "bob", c = "g" },
        { i = 3, s = "1", l = 1, t = 2 * DAY },
        "junk",
      }
      H.prune(list, 31 * DAY)
      assert.same({ { i = 3, s = "1", l = 1, t = 2 * DAY } }, list)
    end)

    it("drops Claims whose Spare ended, and after 30 days", function()
      local list = {
        { m = "ann", i = 1, c = "g", t = 0 },
        { m = "ann", i = 2, c = "g", t = 5 * DAY },
        { m = "ann", i = 3, c = "g", t = 5 * DAY },
      }
      H.pruneClaims(list, 31 * DAY, function(owner, id) return owner == "ann" and id ~= 3 end)
      assert.same({ { m = "ann", i = 2, c = "g", t = 5 * DAY } }, list)
    end)

    it("knows when a Spare is open", function()
      assert.is_true(H.isOpen({ time = 0 }, 30 * DAY))
      assert.is_false(H.isOpen({ time = 0 }, 30 * DAY + 1))
      assert.is_false(H.isOpen({ time = 0, to = "bob" }, 10))
    end)
  end)

  describe("tradeable", function()
    it("takes an unbound item that binds on equip, or not at all", function()
      assert.is_true(H.tradeable(false, 2))
      assert.is_true(H.tradeable(false, 0))
      assert.is_true(H.tradeable(false, nil))
    end)

    it("refuses a bound item, whatever its binding says", function()
      assert.same({ nil, "bound" }, { H.tradeable(true, 2) })
      -- An heirloom reports bindType 1 and IsBound true.
      assert.same({ nil, "bound" }, { H.tradeable(true, 1) })
    end)

    it("refuses a quest item", function()
      assert.same({ nil, "questItem" }, { H.tradeable(false, 4) })
    end)

    it("refuses an account-bound item", function()
      for _, bindType in ipairs({ 7, 8, 9 }) do
        assert.same({ nil, "accountBound" }, { H.tradeable(false, bindType) })
      end
    end)
  end)

  describe("when the item has left the bags", function()
    -- isOpen, hasClaim, inInventory, isEquipped, isNextLogin
    it("keeps an item still in the bags or bank", function()
      assert.equal("keep", H.itemCheck(true, false, true, false, false))
      assert.equal("keep", H.itemCheck(true, true, true, false, true))
    end)

    it("notes a gone item during the session, Claim or not", function()
      assert.equal("note", H.itemCheck(true, false, false, false, false))
      assert.equal("note", H.itemCheck(true, true, false, false, false))
    end)

    it("counts an equipped item as gone", function()
      assert.equal("note", H.itemCheck(true, false, true, true, false))
      assert.equal("withdraw", H.itemCheck(true, false, true, true, true))
    end)

    it("withdraws a gone, unclaimed one at the next login", function()
      assert.equal("withdraw", H.itemCheck(true, false, false, false, true))
    end)

    it("asks about a gone, claimed one at the next login", function()
      assert.equal("ask", H.itemCheck(true, true, false, false, true))
    end)

    it("keeps one that has ended", function()
      assert.equal("keep", H.itemCheck(false, false, false, false, true))
    end)

    it("keeps one whose place in the bags is unknown", function()
      assert.equal("keep", H.itemCheck(true, false, nil, false, true))
    end)
  end)

  describe("the winner", function()
    it("is the earliest Claim", function()
      local winner = H.winner({
        { memberId = "bob", time = 100 },
        { memberId = "cleo", time = 90 },
      })
      assert.equal("cleo", winner.memberId)
    end)

    it("breaks a tie by Member id, whatever order the Claims come in", function()
      assert.equal("bob", H.winner({ { memberId = "cleo", time = 90 }, { memberId = "bob", time = 90 } }).memberId)
      assert.equal("bob", H.winner({ { memberId = "bob", time = 90 }, { memberId = "cleo", time = 90 } }).memberId)
    end)

    it("is nobody without Claims", function()
      assert.is_nil(H.winner({}))
    end)
  end)
end)
