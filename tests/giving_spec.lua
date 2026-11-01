-- Hand-me-downs, Claims and Gives played out across a Crew.
local load = require("tests.load")

local DAY = 24 * 60 * 60
local BARB = "|cff1eff00|Hitem:5191::::::::18:::::::|h[Cruel Barb]|h|r"
local SWORD = "|cff1eff00|Hitem:15210::::::-19:1238425:30|h[Raider Shortsword of the Monkey]|h|r"
local ITEMS = {
  ["item:5191"] = "[Cruel Barb]",
  ["item:15210::::::-19:1238425"] = "[Raider Shortsword of the Monkey]",
}

local function playing(name, level, extra)
  local character = {
    guid = "Player-0-" .. name, name = name, classFilename = "WARRIOR",
    level = level or 20, xp = 0, maxXp = 1000, zone = "Elwynn Forest", deaths = 0,
  }
  for k, v in pairs(extra or {}) do character[k] = v end
  return character
end

local function crew(names, levels)
  local ns = load()
  local net = ns.FakeNet.new({ items = ITEMS })
  local clients = {}
  for i, name in ipairs(names) do
    clients[i] = net:add(name, { character = playing(name, levels and levels[name]) }):login()
  end
  local code = clients[1]:join()
  for i = 2, #clients do clients[i]:join(code) end
  net:run(40)
  return net, clients, ns, code
end

local function view(client)
  return client.core:handMeDowns()
end

-- The row another client shows for the owner's Hand-me-down.
local function crewRow(client, owner, id)
  for _, row in ipairs(view(client).crew) do
    if row.ownerId == owner.memberId and row.id == id then return row end
  end
  return nil
end

local function yourRow(client, id)
  for _, row in ipairs(view(client).yours) do
    if row.id == id then return row end
  end
  return nil
end

local function events(client, name)
  local list = {}
  for _, event in ipairs(client.events) do
    if event[1] == name then list[#list + 1] = event[2] end
  end
  return list
end

local function notices(client)
  local texts = {}
  for i, news in ipairs(events(client, "handMeDown")) do texts[i] = news.text end
  return texts
end

local function feedTexts(client, kind)
  local texts = {}
  for _, day in ipairs(client.core:feed().days) do
    for _, entry in ipairs(day.entries) do
      if entry.kind == kind then texts[#texts + 1] = entry.text end
    end
  end
  return texts
end

local function record(client)
  return client.db.records[client.memberId]
end

local function post(net, client, link, level)
  local id = assert(client.core:postHandMeDown(link or BARB, level or 18))
  net:run(3)
  return id
end

-- Claims while the claimer's messages are lost, so the Claim reaches the
-- others only once it resends (refused()).
local function claimUnheard(net, client, owner, id)
  net.drop = function(_, from, to) return from == client.name and to ~= client.name end
  assert(client.core:claimHandMeDown(owner.memberId, id))
  net:run(5)
  net.drop = nil
end

local function resend(net, client)
  client:refused()
  net:run(10)
end

describe("Hand-me-downs", function()
  it("are posted into the owner's record and show to the rest of the Crew", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    local changed = a:count("changed")
    local id = post(net, a)
    assert.is_true(a:count("changed") > changed)

    assert.equal(1, #record(a).handMeDowns)
    assert.equal("5191", record(a).handMeDowns[1].s)
    local row = crewRow(b, a, id)
    assert.equal("Ann", row.owner)
    assert.equal("item:5191", row.item)
    assert.equal("[Cruel Barb]", row.link)
    assert.equal(18, row.level)
    assert.is_true(row.usable)
    assert.is_true(row.canClaim)
    assert.equal("No claims yet", row.state)
    assert.same({}, view(a).crew)
    assert.equal(1, #view(a).yours)
    assert.equal(1, b.core:summary().handMeDowns)
    assert.equal(0, a.core:summary().handMeDowns)
    assert.same({ nil, "noClaim" }, { a.core:giveHandMeDown(id) })
    assert.is_false(yourRow(a, id).canGive)
    assert.is_true(yourRow(a, id).canWithdraw)
  end)

  it("keep a random suffix", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    local id = post(net, a, SWORD, 25)
    local row = crewRow(b, a, id)
    assert.equal("item:15210::::::-19:1238425", row.item)
    assert.equal("[Raider Shortsword of the Monkey]", row.link)
  end)

  it("refuse what isn't an item, and outside a Crew", function()
    local _, clients = crew({ "Ann" })
    local a = clients[1]
    assert.same({ nil, "invalidItem" }, { a.core:postHandMeDown("Cruel Barb", 18) })
    a.core:leaveCrew()
    assert.same({ nil, "noCrew" }, { a.core:postHandMeDown(BARB, 18) })
  end)

  it("are dimmed when none of your Characters is high enough level", function()
    local net, clients = crew({ "Ann", "Bob" }, { Bob = 10 })
    local a, b = clients[1], clients[2]
    local id = post(net, a, BARB, 18)
    assert.is_false(crewRow(b, a, id).usable)
    assert.equal(0, b.core:summary().handMeDowns)

    b.character = playing("Jaina", 30, { guid = "Player-0-Jaina" })
    b:play()
    assert.is_true(crewRow(b, a, id).usable)
    assert.equal(1, b.core:summary().handMeDowns)
  end)

  it("are withdrawn by the owner, and go from everyone's list", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    local id = post(net, a)
    assert.is_true(b.core:claimHandMeDown(a.memberId, id))
    net:run(3)
    assert.is_true(a.core:withdrawHandMeDown(id))
    net:run(3)
    assert.same({}, record(a).handMeDowns)
    assert.is_nil(crewRow(b, a, id))
    assert.same({ nil, "unknown" }, { a.core:withdrawHandMeDown(id) })
    -- Bob's Claim goes at his next write.
    b:play({ zone = "Westfall" })
    assert.same({}, record(b).claims)
  end)

  it("are at most 20 open per owner", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a = clients[1]
    for _ = 1, 20 do assert.is_number(a.core:postHandMeDown(BARB, 18)) end
    assert.same({ nil, "tooMany" }, { a.core:postHandMeDown(BARB, 18) })
    local first = view(a).yours[1].id
    a.core:withdrawHandMeDown(first)
    local id = a.core:postHandMeDown(BARB, 18)
    assert.is_number(id)
    assert.is_true(id > 20)
    net:run(3)
  end)

  it("end 30 days after posting, and are pruned at the owner's next write", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    local id = post(net, a)
    net:step(net:now() + 30 * DAY - 10)
    assert.is_table(crewRow(b, a, id))
    net:step(net:now() + 20)
    assert.is_nil(crewRow(b, a, id))
    assert.same({ nil, "unknown" }, { b.core:claimHandMeDown(a.memberId, id) })
    assert.equal(1, #record(a).handMeDowns)
    a:play({ zone = "Westfall" })
    assert.equal(0, #record(a).handMeDowns)
  end)

  describe("Claims", function()
    it("go into the claimer's record for the Character logged in, or another", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      local id = post(net, a)
      assert.is_true(b.core:claimHandMeDown(a.memberId, id))
      local claim = record(b).claims[1]
      assert.equal(a.memberId, claim.m)
      assert.equal(id, claim.i)
      assert.equal(b.character.guid, claim.c)
      assert.equal("You claimed it for Bob", crewRow(b, a, id).state)
      assert.is_true(crewRow(b, a, id).claimed)
      assert.is_false(crewRow(b, a, id).canClaim)
      net:run(3)
      assert.equal("Bob claimed it for Bob", yourRow(a, id).state)
      assert.same({ "Bob claimed [Cruel Barb] for Bob" }, notices(a))

      local other = net:add("Cid", { character = playing("Cid") }):login()
      other:join(a.core:crew().code)
      net:run(40)
      other.character = playing("Jaina", 25, { guid = "Player-0-Jaina" })
      other:play()
      other.character = playing("Cid", 20)
      other:play()
      assert.same({ nil, "unknownCharacter" }, { other.core:claimHandMeDown(a.memberId, id, "Player-0-Nobody") })
      assert.is_true(other.core:claimHandMeDown(a.memberId, id, "Player-0-Jaina"))
      assert.equal("Bob claimed it first (you claimed it for Jaina)", crewRow(other, a, id).state)
    end)

    it("are refused on your own, twice, and on a Removed Member's", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      local id = post(net, a)
      assert.same({ nil, "own" }, { a.core:claimHandMeDown(a.memberId, id) })
      assert.is_true(b.core:claimHandMeDown(a.memberId, id))
      assert.same({ nil, "claimed" }, { b.core:claimHandMeDown(a.memberId, id) })
      assert.same({ nil, "unknown" }, { b.core:claimHandMeDown(a.memberId, 99) })
      assert.same({ nil, "unknown" }, { b.core:claimHandMeDown("nobody", id) })
      assert.equal(1, #record(b).claims)

      b.core:removeMember(a.memberId)
      assert.same({}, view(b).crew)
      assert.same({ nil, "unknown" }, { b.core:claimHandMeDown(a.memberId, id) })
    end)

    it("are at most 20 open", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      local ids = {}
      for i = 1, 20 do ids[i] = a.core:postHandMeDown(BARB, 18) end
      net:run(3)
      for i = 1, 20 do assert.is_true(b.core:claimHandMeDown(a.memberId, ids[i])) end
      local c = net:add("Cid", { character = playing("Cid") }):login()
      c:join(a.core:crew().code)
      net:run(40)
      local extra = c.core:postHandMeDown(BARB, 18)
      net:run(3)
      assert.same({ nil, "tooMany" }, { b.core:claimHandMeDown(c.memberId, extra) })
      assert.equal(20, view(b).claims)
      assert.equal(20, view(b).maxClaims)

      b.core:withdrawClaim(a.memberId, ids[1])
      assert.is_true(b.core:claimHandMeDown(c.memberId, extra))
    end)

    it("are won by the earliest; withdrawing moves the next one up", function()
      local net, clients = crew({ "Ann", "Bob", "Cleo", "Dee" })
      local a, b, c, d = clients[1], clients[2], clients[3], clients[4]
      local id = post(net, a)
      claimUnheard(net, c, a, id)
      net:run(2)
      assert.is_true(b.core:claimHandMeDown(a.memberId, id))
      net:run(5)
      assert.equal(b.memberId, yourRow(a, id).winner.memberId)
      resend(net, c)
      for _, client in ipairs({ b, c, d }) do
        assert.equal(c.memberId, crewRow(client, a, id).winner.memberId)
      end
      assert.equal("Cleo claimed it first", crewRow(d, a, id).state)
      assert.equal("Cleo claimed it first (you claimed it for Bob)", crewRow(b, a, id).state)
      assert.equal("Cleo claimed it for Cleo (2 Claims)", yourRow(a, id).state)

      assert.is_true(c.core:withdrawClaim(a.memberId, id))
      net:run(5)
      assert.equal(b.memberId, yourRow(a, id).winner.memberId)
      assert.equal(b.memberId, crewRow(d, a, id).winner.memberId)
      assert.same({ nil, "unknown" }, { c.core:withdrawClaim(a.memberId, id) })
      -- Bob's and Cleo's Claims came in one DATA each: Bob first, then Cleo
      -- moved ahead of him, then she withdrew.
      assert.same({
        "Bob claimed [Cruel Barb] for Bob",
        "Cleo claimed [Cruel Barb] for Cleo",
        "Bob claimed [Cruel Barb] for Bob",
      }, notices(a))
      assert.same({}, notices(b))
      assert.same({}, notices(c))
    end)

    it("tie by Member id the same on every client", function()
      local net, clients = crew({ "Ann", "Bob", "Cleo" })
      local a, b, c = clients[1], clients[2], clients[3]
      local id = post(net, a)
      assert.is_true(b.core:claimHandMeDown(a.memberId, id))
      assert.is_true(c.core:claimHandMeDown(a.memberId, id))
      assert.equal(record(b).claims[1].t, record(c).claims[1].t)
      net:run(5)
      local first = b.memberId < c.memberId and b.memberId or c.memberId
      for _, client in ipairs({ a, b, c }) do
        local row = client == a and yourRow(a, id) or crewRow(client, a, id)
        assert.equal(first, row.winner.memberId)
      end
    end)

    it("from a Removed Member don't count", function()
      local net, clients = crew({ "Ann", "Bob", "Cleo" })
      local a, b, c = clients[1], clients[2], clients[3]
      local id = post(net, a)
      assert.is_true(c.core:claimHandMeDown(a.memberId, id))
      net:run(5)
      assert.is_true(b.core:claimHandMeDown(a.memberId, id))
      net:run(5)
      assert.equal(c.memberId, yourRow(a, id).winner.memberId)
      local before = #notices(a)
      a.core:removeMember(c.memberId)
      assert.equal(b.memberId, yourRow(a, id).winner.memberId)
      assert.equal(before, #notices(a))
      b.core:removeMember(c.memberId)
      assert.equal(b.memberId, crewRow(b, a, id).winner.memberId)
    end)

    it("aren't news on first sight of the claimer", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      net.drop = function(_, from, to) return from == "Bob" and to == "Ann" end
      local id = post(net, a)
      assert.is_true(b.core:claimHandMeDown(a.memberId, id))
      net:run(5)
      net.drop = nil
      a.core:removeMember(b.memberId)
      a.core:readdMember(b.memberId)
      net:run(10)
      assert.equal(b.memberId, yourRow(a, id).winner.memberId)
      assert.same({}, notices(a))
    end)

    it("expire after 30 days", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      local id = post(net, a)
      assert.is_true(b.core:claimHandMeDown(a.memberId, id))
      net:run(3)
      net:step(net:now() + 29 * DAY)
      b:play({ zone = "Westfall" })
      assert.equal(1, #record(b).claims)
      net:step(net:now() + 2 * DAY)
      b:play({ zone = "Duskwood" })
      assert.same({}, record(b).claims)
    end)
  end)

  describe("Giving", function()
    it("goes to the winner, is final, and makes one gave entry everywhere", function()
      local net, clients = crew({ "Ann", "Bob", "Cleo", "Dee" })
      local a, b, c, d = clients[1], clients[2], clients[3], clients[4]
      local id = post(net, a)
      -- Nobody hears Cleo's Claim until after the Give.
      claimUnheard(net, c, a, id)
      assert.is_true(b.core:claimHandMeDown(a.memberId, id))
      net:run(5)
      assert.equal(b.memberId, yourRow(a, id).winner.memberId)
      assert.same({ nil, "unknown" }, { a.core:giveHandMeDown(99) })

      assert.is_true(a.core:giveHandMeDown(id))
      local given = record(a).handMeDowns[1]
      assert.equal(b.memberId, given.r)
      assert.equal(b.character.guid, given.c)
      assert.same({ nil, "unknown" }, { a.core:giveHandMeDown(id) })
      assert.same({ nil, "unknown" }, { a.core:withdrawHandMeDown(id) })
      net:run(5)

      -- Cleo's Claim arrives later and is earlier, but the Give is final.
      resend(net, c)
      assert.equal(1, #d.core.ledger:record(c.memberId).claims)
      assert.equal(b.memberId, yourRow(a, id).given.memberId)
      assert.equal("Given to Bob (Bob)", yourRow(a, id).state)
      for _, client in ipairs({ b, c, d }) do assert.is_nil(crewRow(client, a, id)) end
      assert.same({ nil, "given" }, { b.core:withdrawClaim(a.memberId, id) })

      assert.same({ "Ann sent you [Cruel Barb]. Check Bob's mailbox." }, notices(b))
      assert.same({}, notices(c))
      assert.same({ "You gave Bob [Cruel Barb]" }, feedTexts(a, "gave"))
      assert.same({ "Ann gave you [Cruel Barb]" }, feedTexts(b, "gave"))
      assert.same({ "Ann gave Bob [Cruel Barb]" }, feedTexts(c, "gave"))
      assert.same({ "Ann gave Bob [Cruel Barb]" }, feedTexts(d, "gave"))
      for _, client in ipairs({ a, b, c, d }) do
        for _, day in ipairs(client.core:feed().days) do
          for _, entry in ipairs(day.entries) do
            if entry.kind == "gave" then
              assert.is_false(entry.canReact)
              assert.is_nil(entry.key)
            end
          end
        end
      end
      -- Live: Dee's gave entry is news; Bob's is covered by his notice.
      assert.equal(1, #events(d, "feedEntry"))
      assert.equal(0, #events(b, "feedEntry"))

      -- The Give stays in the record until the 30 days are up.
      a:play({ zone = "Westfall" })
      assert.equal(1, #record(a).handMeDowns)
      b:play({ zone = "Westfall" })
      assert.same({}, record(b).claims)
    end)

    it("make one gave entry even after skipped versions, never twice", function()
      local net, clients = crew({ "Ann", "Bob", "Cleo" })
      local a, b, c = clients[1], clients[2], clients[3]
      c:lockdown(true)
      local id = post(net, a)
      assert.is_true(b.core:claimHandMeDown(a.memberId, id))
      net:run(5)
      a.core:giveHandMeDown(id)
      net:run(3)
      a:play({ zone = "Westfall" })
      net:run(15)
      c:lockdown(false)
      net:run(10)
      assert.same({ "Ann gave Bob [Cruel Barb]" }, feedTexts(c, "gave"))
      a:play({ zone = "Duskwood" })
      net:run(15)
      assert.same({ "Ann gave Bob [Cruel Barb]" }, feedTexts(c, "gave"))
    end)

    it("reaches While you were away for the winner, and the Claim for the owner", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      local id = post(net, a)
      a:logout()
      net:run(5)
      b.core:claimHandMeDown(a.memberId, id)
      net:run(5)
      a.events = {}
      a:login()
      net:run(40)
      local summary = events(a, "awaySummary")[1]
      assert.same({ { kind = "claimed", text = "Bob claimed [Cruel Barb] for Bob" } }, (function()
        local lines = {}
        for i, line in ipairs(summary.handMeDowns) do lines[i] = { kind = line.kind, text = line.text } end
        return lines
      end)())
      assert.same({}, notices(a))
      assert.equal(0, view(a).unseen)

      b:logout()
      net:run(5)
      a.core:giveHandMeDown(id)
      net:run(5)
      b.events = {}
      b:login()
      net:run(40)
      local texts = {}
      for i, line in ipairs(events(b, "awaySummary")[1].handMeDowns) do texts[i] = line.text end
      assert.same({ "Ann sent you [Cruel Barb]. Check Bob's mailbox." }, texts)
    end)

    it("stay unseen with chat lines and toasts off until the tab is opened", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      a.core:setChatLines(false)
      a.core:setToasts(false)
      local id = post(net, a)
      b.core:claimHandMeDown(a.memberId, id)
      net:run(5)
      assert.same({}, notices(a))
      assert.equal(1, view(a).unseen)
      a.core:handMeDownsSeen()
      assert.equal(0, view(a).unseen)
    end)
  end)

  it("are relayed by a Member in between, Claims too", function()
    local net, clients = crew({ "Ann", "Bob", "Cid" })
    local a, b, c = clients[1], clients[2], clients[3]
    net.drop = function(_, from, to)
      return (from == "Ann" and to == "Cid") or (from == "Cid" and to == "Ann")
    end
    local id = post(net, a)
    b.core.gossip:askAround()
    net:run(10)
    assert.is_table(crewRow(c, a, id))
    c.core:claimHandMeDown(a.memberId, id)
    net:run(10)
    b.core.gossip:askAround()
    net:run(10)
    assert.equal(c.memberId, yourRow(a, id).winner.memberId)
  end)

  it("keep records with malformed Hand-me-downs and Claims, minus those items", function()
    local net, clients, ns = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    local id = post(net, a)
    local function send(sender, fields)
      local rec = {
        id = sender, version = net:now(), displayName = sender, joinedAt = 1,
        characters = { ["Player-0-X" .. sender] = {
          guid = "Player-0-X" .. sender, name = sender, level = 20, lastPlayed = net:now(),
        } },
      }
      for k, v in pairs(fields) do rec[k] = v end
      b.core:received(ns.Codec.encode({ type = "DATA", from = sender, records = { rec } }))
    end
    send("garbled1", {
      handMeDowns = { "junk", { i = 1, s = "bad" }, { i = 2, s = "5191", l = 18, t = net:now() } },
      claims = { "junk", { m = a.memberId, i = id, c = "Player-0-Xgarbled1", t = 1 } },
    })
    send("garbled2", { handMeDowns = "junk", claims = 7 })
    assert.is_table(b.core.ledger:record("garbled1"))
    assert.is_table(b.core.ledger:record("garbled2"))
    local owners = {}
    for _, row in ipairs(view(b).crew) do owners[#owners + 1] = row.ownerId end
    table.sort(owners)
    assert.same({ a.memberId, "garbled1" }, owners)
    assert.equal("garbled1", crewRow(b, a, id).winner.memberId)
  end)

  it("are cleared, Claims too, when you leave", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    local id = post(net, a)
    local other = post(net, b)
    a.core:claimHandMeDown(b.memberId, other)
    b.core:claimHandMeDown(a.memberId, id)
    net:run(3)
    a.core:leaveCrew()
    net:run(3)
    assert.is_nil(record(a).handMeDowns)
    assert.is_nil(record(a).claims)
    assert.same({}, view(a).yours)
    assert.is_nil(crewRow(b, a, id))
  end)
end)
