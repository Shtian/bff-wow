local load = require("tests.load")

local DAY = 24 * 60 * 60

-- A net with the given clients logged in and in one Crew, settled. options
-- maps a name to FakeNet:add options.
local function crew(names, options)
  local ns = load()
  local net = ns.FakeNet.new()
  local clients = {}
  for i, name in ipairs(names) do
    clients[i] = net:add(name, options and options[name]):login()
  end
  local code = clients[1]:join()
  for i = 2, #clients do clients[i]:join(code) end
  net:run(20)
  return net, clients, ns, code
end

local function character(name, level, extra)
  local c = {
    guid = "Player-0-" .. name, name = name, classFilename = "WARRIOR",
    level = level, xp = 0, maxXp = 1000, zone = "Elwynn Forest", deaths = 0,
  }
  for k, v in pairs(extra or {}) do c[k] = v end
  return c
end

-- Switches the client to another Character, as a relog onto it would.
local function switchTo(client, name, level, extra)
  client.character = character(name, level, extra)
  client:play()
end

-- Jumps the clock ahead, then lets the Crew settle.
local function skip(net, seconds)
  net:step(net:now() + seconds)
  net:run(5)
end

local function names(rows)
  local result = {}
  for i, row in ipairs(rows) do result[i] = row.name end
  return result
end

local function altNames(row)
  local result = {}
  for i, alt in ipairs(row.alts) do result[i] = alt.name end
  return result
end

describe("Roster", function()
  describe("Main", function()
    it("is the most recently played Character while no Main is set", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      net:run(5)
      switchTo(a, "Annalt", 4)
      net:run(5)

      local row = b:rowFor(a)
      assert.equal("Annalt", row.name)
      assert.is_true(row.main)
      assert.is_false(row.onAlt)
      assert.same({ "Ann" }, altNames(row))
      assert.is_false(row.alts[1].main)
      assert.is_false(row.mainSet)
    end)

    it("is the Character set as Main, shown while offline, everywhere after sync", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      net:run(5)
      switchTo(a, "Annalt", 4)
      net:run(5)
      assert.is_true(a.core:setMain("Player-0-Ann"))
      net:run(5)

      local own = a.core:rows()[1]
      assert.is_true(own.mainSet)
      assert.equal("Annalt", own.name)
      assert.is_true(own.onAlt)
      assert.is_true(own.alts[1].main)

      local row = b:rowFor(a)
      assert.equal("Annalt", row.name)
      assert.is_true(row.onAlt)
      assert.is_false(row.main)
      assert.is_true(row.playing)
      assert.is_false(row.alts[1].playing)

      a:logout()
      net:run(2)
      row = b:rowFor(a)
      assert.is_false(row.online)
      assert.equal("Ann", row.name)
      assert.is_true(row.main)
      assert.is_false(row.onAlt)
      assert.is_false(row.playing)
      assert.same({ "Annalt" }, altNames(row))
    end)

    it("goes back to the most recently played when cleared", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      net:run(5)
      switchTo(a, "Annalt", 4)
      a.core:setMain("Player-0-Ann")
      net:run(5)
      assert.is_true(a.core:setMain(nil))
      net:run(5)
      assert.is_false(a.core:rows()[1].mainSet)
      a:logout()
      net:run(2)

      assert.equal("Annalt", b:rowFor(a).name)
    end)

    it("can only be one of your own Characters", function()
      local _, clients = crew({ "Ann", "Bob" })
      local a = clients[1]
      local ok, reason = a.core:setMain("Player-0-Bob")
      assert.is_nil(ok)
      assert.equal("unknownCharacter", reason)
    end)
  end)

  describe("online", function()
    it("shows the row with an online dot, and Last seen from the owner's clock", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      assert.is_true(b:rowFor(a).online)

      net:run(60)
      a:logout()
      local loggedOut = net:now()
      net:run(2)
      local row = b:rowFor(a)
      assert.is_false(row.online)
      assert.is_true(row.lastSeen <= loggedOut)
      assert.is_true(row.lastSeen >= loggedOut - 5 * 60)
      assert.equal(row.lastSeen, row.lastPlayed)
      assert.equal(net:now() - row.lastSeen, row.sinceSeen)
    end)
  end)

  describe("can play with you", function()
    local function levels(annLevel, bobLevel)
      return crew({ "Ann", "Bob" }, {
        Ann = { character = character("Ann", annLevel) },
        Bob = { character = character("Bob", bobLevel) },
      })
    end

    it("marks a Character within 3 levels of the one you play", function()
      local _, clients = levels(20, 23)
      local a, b = clients[1], clients[2]
      assert.is_true(a:rowFor(b).canPlay)
      assert.is_true(b:rowFor(a).canPlay)
      assert.is_false(a.core:rows()[1].canPlay)
    end)

    it("does not mark one 4 levels away", function()
      local _, clients = levels(20, 24)
      assert.is_false(clients[1]:rowFor(clients[2]).canPlay)
    end)

    it("counts Alts, and says when only a hidden Alt matches", function()
      local net, clients = levels(20, 40)
      local a, b = clients[1], clients[2]
      net:run(5)
      switchTo(b, "Bobalt", 18)
      net:run(5)
      b.core:setMain("Player-0-Bob")
      net:run(5)
      b:logout()
      net:run(2)

      local row = a:rowFor(b)
      assert.equal("Bob", row.name)
      assert.is_false(row.canPlay)
      assert.is_true(row.altsCanPlay)
      assert.is_true(row.alts[1].canPlay)
    end)
  end)

  describe("sorting", function()
    -- Ann (you, 20); Bea online at 30, Cid online at 21, Dot offline at 19
    -- seen long ago, Eve offline at 45 and Fay offline at 50 seen since.
    local function fiveOthers()
      local net, clients = crew({ "Ann", "Bea", "Cid", "Dot", "Eve", "Fay" }, {
        Ann = { character = character("Ann", 20) },
        Bea = { character = character("Bea", 30) },
        Cid = { character = character("Cid", 21) },
        Dot = { character = character("Dot", 19) },
        Eve = { character = character("Eve", 45) },
        Fay = { character = character("Fay", 50) },
      })
      clients[4]:logout()
      skip(net, DAY)
      clients[5]:logout()
      skip(net, 60 * 60)
      clients[6]:logout()
      net:run(60)
      return net, clients
    end

    it("puts your own row first, then online, can play and Last seen", function()
      local _, clients = fiveOthers()
      local expected = { "Ann", "Cid", "Bea", "Dot", "Fay", "Eve" }
      assert.same(expected, names(clients[1].core:rows()))
      assert.same(expected, names(clients[1].core:rows("online")))
      assert.is_true(clients[1].core:rows()[1].own)
    end)

    it("sorts by level, highest first", function()
      local _, clients = fiveOthers()
      assert.same({ "Ann", "Fay", "Eve", "Bea", "Cid", "Dot" }, names(clients[1].core:rows("level")))
    end)

    it("sorts by display name", function()
      local _, clients = fiveOthers()
      assert.same({ "Ann", "Bea", "Cid", "Dot", "Eve", "Fay" }, names(clients[1].core:rows("name")))
    end)
  end)

  describe("30-day hide", function()
    it("hides Characters unseen for 30 days and counts them", function()
      local net, clients = crew({ "Ann", "Bob", "Cid" })
      local a, b, c = clients[1], clients[2], clients[3]
      switchTo(b, "Bobalt", 12)
      net:run(5)
      b:logout()
      c:logout()
      skip(net, 29 * DAY)
      assert.same({ "Bob" }, altNames(a:rowFor(b)))
      assert.equal(0, a.core:summary().hidden)

      b:login()
      skip(net, 2 * DAY)
      -- Bob's Main went unseen 30 days, and Cid has nothing left to show.
      assert.same({}, a:rowFor(b).alts)
      assert.is_nil(a:rowFor(c))
      assert.equal(2, a.core:summary().hidden)
    end)

    it("hides your own Alts too", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a = clients[1]
      switchTo(a, "Annalt", 12)
      net:run(5)
      skip(net, 31 * DAY)
      assert.same({}, a.core:rows()[1].alts)
      assert.equal(1, a.core:summary().hidden)
    end)
  end)

  describe("summary", function()
    it("counts Members online, all Members, and who can play with you now", function()
      local net, clients = crew({ "Ann", "Bob", "Cid", "Dan" }, {
        Ann = { character = character("Ann", 20) },
        Bob = { character = character("Bob", 21) },
        Cid = { character = character("Cid", 40) },
        Dan = { character = character("Dan", 22) },
      })
      clients[4]:logout()
      net:run(2)
      assert.same({ online = 2, members = 3, canPlay = 1, hidden = 0 }, clients[1].core:summary())
    end)
  end)

  describe("tooltip details", function()
    it("gives deaths, XP and who the news came through", function()
      local net, clients = crew({ "Ann", "Bob", "Cid" })
      local a, b, c = clients[1], clients[2], clients[3]
      c:logout()
      a:play({ level = 11, deaths = 2, xp = 40 })
      net:run(5)
      a:logout()
      net:run(2)
      c:login()
      net:run(20)

      local row = c:rowFor(a)
      assert.equal(11, row.level)
      assert.equal(2, row.deaths)
      assert.equal(40, row.xp)
      assert.equal("Bob", row.via)
      assert.is_nil(c:rowFor(b).via)
    end)

    it("stops naming the relay once the owner's own copy arrives", function()
      local net, clients = crew({ "Ann", "Bob", "Cid" })
      local a, c = clients[1], clients[3]
      c:logout()
      a:play({ level = 11 })
      net:run(5)
      a:logout()
      net:run(2)
      c:login()
      net:run(20)
      assert.equal("Bob", c:rowFor(a).via)

      a:login()
      net:run(20)
      assert.is_nil(c:rowFor(a).via)
    end)
  end)

  describe("Remove", function()
    it("hides a Member locally only, and stops relaying them", function()
      local net, clients, ns = crew({ "Ann", "Bob", "Cid" })
      local a, b, c = clients[1], clients[2], clients[3]
      assert.is_true(a.core:removeMember(b.memberId))
      assert.is_nil(a:rowFor(b))
      assert.same({ { memberId = b.memberId, displayName = "Bob" } }, a.core:removed())
      net:run(2)
      assert.is_table(c:rowFor(b))

      -- Bob dings while Ann is the only one online to hear it.
      c:logout()
      b:play({ level = 11 })
      net:run(5)
      assert.is_nil(a:rowFor(b))
      b:logout()
      net:run(2)

      -- Cid comes back and learns nothing about Bob from Ann.
      local mark = #net.wire
      c:login()
      net:run(20)
      assert.equal(10, c:rowFor(b).level)
      for i = mark + 1, #net.wire do
        local message = ns.Codec.decode(net.wire[i].message)
        if net.wire[i].from == "Ann" and message.type == "DATA" then
          for _, record in ipairs(message.records) do
            assert.are_not.equal(b.memberId, record.id)
          end
        end
      end
    end)

    it("sends no DIGEST meant only to fetch a Member removed meanwhile", function()
      local net, clients, ns = crew({ "Ann", "Bob", "Cid" })
      local a, b, c = clients[1], clients[2], clients[3]
      -- Only Cid hears Bob's ding.
      a:logout()
      b:play({ level = 11 })
      net:run(5)
      b:logout()
      c:logout()
      net:run(2)
      a:login()
      net:run(10)

      -- Cid's DIGEST tells Ann about Bob's newer version; Ann removes Bob
      -- before her own DIGEST asking for it goes out.
      c:login()
      net:step()
      a.core:removeMember(b.memberId)
      local mark = #net.wire
      net:run(10)
      for k = mark + 1, #net.wire do
        if net.wire[k].from == "Ann" then
          assert.are_not.equal("DIGEST", ns.Codec.decode(net.wire[k].message).type)
        end
      end
    end)

    it("keeps the Member out across a reload, even when others relay them", function()
      local net, clients = crew({ "Ann", "Bob", "Cid" })
      local a, b = clients[1], clients[2]
      a.core:removeMember(b.memberId)
      a:reload()
      b:play({ level = 11 })
      net:run(20)
      assert.is_nil(a:rowFor(b))
    end)

    it("brings the Member back on re-add, from whoever holds them", function()
      local net, clients = crew({ "Ann", "Bob", "Cid" })
      local a, b = clients[1], clients[2]
      a.core:removeMember(b.memberId)
      b:play({ level = 11 })
      net:run(5)
      b:logout()
      net:run(2)

      assert.is_true(a.core:readdMember(b.memberId))
      assert.same({}, a.core:removed())
      net:run(10)
      local row = a:rowFor(b)
      assert.is_table(row)
      assert.equal(11, row.level)
    end)

    it("can't remove yourself or someone unknown", function()
      local _, clients = crew({ "Ann", "Bob" })
      local a = clients[1]
      assert.same({ nil, "unknownMember" }, { a.core:removeMember(a.memberId) })
      assert.same({ nil, "unknownMember" }, { a.core:removeMember("nobody") })
      assert.same({ nil, "unknownMember" }, { a.core:readdMember("nobody") })
    end)
  end)
end)
