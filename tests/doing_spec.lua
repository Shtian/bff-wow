local load = require("tests.load")
local ROOM = load().Framing.ROOM

local function character(name, extra)
  local c = {
    guid = "Player-0-" .. name, name = name, classFilename = "WARRIOR",
    level = 10, xp = 0, maxXp = 1000, zone = "Elwynn Forest", deaths = 0,
  }
  for k, v in pairs(extra or {}) do c[k] = v end
  return c
end

local function crew(names)
  local ns = load()
  local net = ns.FakeNet.new()
  local clients = {}
  for i, name in ipairs(names) do
    clients[i] = net:add(name, { character = character(name) }):login()
  end
  local code = clients[1]:join()
  for i = 2, #clients do clients[i]:join(code) end
  net:run(40)
  return net, clients, ns
end

local function actorFor(view, client)
  for _, actor in ipairs(view.actors) do
    if actor.memberId == client.memberId then return actor end
  end
  return nil
end

local function shown(viewer, client)
  local actor = actorFor(viewer.core:pocketCamp(), client)
  return actor and { actor.pose, actor.status }
end

local function poseOf(viewer, client)
  local actor = actorFor(viewer.core:pocketCamp(), client)
  return actor and actor.pose
end

local ALCHEMY, HERBALISM, MINING, SKINNING, FISHING = 171, 182, 186, 393, 356
local BLACKSMITHING, TAILORING, COOKING, FIRST_AID = 164, 197, 185, 129
local SMALLFISH = 6291
local MINING_SPELL, HERBALISM_SPELL, SKINNING_SPELL = 2576, 11993, 8613

local function profession(skillLine, name, skill)
  return { skillLine = skillLine, name = name, icon = 1000 + skillLine, skill = skill, max = 300 }
end

local function animations(client, clients)
  local names = {}
  for _, other in ipairs(clients) do names[other.memberId] = other.name end
  local list = {}
  for _, event in ipairs(client.events) do
    if event[1] == "pocketCampAnimation" then
      list[#list + 1] = event[2].kind .. ":" .. tostring(names[event[2].memberId])
    end
  end
  return list
end

local function doings(net, mark, name)
  return net:sent(mark, name, "DOING")
end

describe("What a Member is doing", function()
  it("shows on your own figure at once, in words too", function()
    local _, clients = crew({ "Ann", "Bob" })
    local a = clients[1]
    assert.same({ "seated", "by the fire" }, shown(a, a))
    a.core:doing({ vendor = true })
    assert.same({ "vendor", "at a vendor" }, shown(a, a))
    a.core:doing({ auction = true })
    assert.same({ "auction", "at the auction house" }, shown(a, a))
    a.core:doing({ resting = true })
    assert.same({ "resting", "resting" }, shown(a, a))
    a.core:doing({ afk = true })
    assert.same({ "afk", "away" }, shown(a, a))
    a.core:doing({ flying = true })
    assert.same({ "flying", "flying" }, shown(a, a))
    a.core:doing({ combat = true })
    assert.same({ "fighting", "fighting" }, shown(a, a))
    assert.same({ "You: fighting", "Bob: by the fire" }, a.core:pocketCamp().tooltip.lines)
  end)

  it("reaches the Crew in one small message that is no part of your record", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    local mark = #net.wire
    b.core:doing({ vendor = true })
    net:run(3)
    assert.same({ "vendor", "at a vendor" }, shown(a, b))
    local sent = doings(net, mark, "Bob")
    assert.equal(1, #sent)
    assert.equal("vendor", sent[1].doing)
    assert.is_true(sent[1].size <= ROOM)
    net:run(70)
    assert.equal(0, #net:sent(mark, nil, "DATA"))
    assert.same({ "vendor", "at a vendor · 1m" }, shown(a, b))

    b.core:doing({})
    net:run(20)
    assert.same({ "seated", "by the fire" }, shown(a, b))
  end)

  it("shows the first of flying, the auction house, a vendor, fighting, away and resting", function()
    local _, clients = crew({ "Ann", "Bob" })
    local a = clients[1]
    a.core:doing({ combat = true, vendor = true, auction = true, resting = true, flying = true })
    assert.equal("flying", poseOf(a, a))
    a.core:doing({ combat = true, vendor = true, auction = true, resting = true })
    assert.equal("auction", poseOf(a, a))
    a.core:doing({ combat = true, vendor = true, resting = true })
    assert.equal("vendor", poseOf(a, a))
    a.core:doing({ combat = true, resting = true })
    assert.equal("fighting", poseOf(a, a))
    a.core:doing({ afk = true, resting = true })
    assert.equal("fighting", poseOf(a, a))
  end)

  it("shows away under a vendor and fighting but over resting, and tells the Crew", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    b.core:doing({ afk = true, vendor = true })
    assert.equal("vendor", poseOf(b, b))
    b.core:doing({ afk = true, combat = true })
    assert.equal("fighting", poseOf(b, b))
    b.core:doing({ afk = true, resting = true })
    assert.equal("fighting", poseOf(b, b))
    net:run(25)
    b.core:doing({ afk = true, resting = true })
    assert.equal("afk", poseOf(b, b))
    net:run(3)
    assert.same({ "afk", "away" }, shown(a, b))
    b.core:doing({ resting = true })
    net:run(20)
    assert.same({ "resting", "resting" }, shown(a, b))
  end)

  it("keeps fighting for 20 s past the end of combat, so pull after pull is one spell", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    local mark = #net.wire
    b.core:doing({ combat = true })
    net:run(8)
    b.core:doing({})
    net:run(12)
    b.core:doing({ combat = true })
    net:run(6)
    b.core:doing({})
    net:run(19)
    assert.equal("fighting", poseOf(b, b))
    assert.equal("fighting", poseOf(a, b))
    assert.equal(1, #doings(net, mark, "Bob"))
    local before = b:count("changed")
    net:run(1)
    assert.equal("seated", poseOf(b, b))
    assert.equal(before + 1, b:count("changed"))
    net:run(3)
    assert.equal("seated", poseOf(a, b))
    assert.equal(2, #doings(net, mark, "Bob"))
  end)

  it("sends only changes, the latest one, and no more often than every 15 s", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    local mark = #net.wire
    b.core:doing({ vendor = true })
    net:run(2)
    b.core:doing({ vendor = true })
    b.core:doing({ auction = true })
    b.core:doing({ resting = true })
    net:run(10)
    assert.equal(1, #doings(net, mark, "Bob"))
    assert.equal("vendor", poseOf(a, b))
    net:run(5)
    local sent = doings(net, mark, "Bob")
    assert.same({ "vendor", "resting" }, { sent[1].doing, sent[2].doing })
    assert.equal("resting", poseOf(a, b))
  end)

  it("grows the gap between DOINGs with the Crew: 5 s per other Member online", function()
    local net, clients = crew({ "Ann", "Bob", "Cid", "Dee", "Eve" })
    local b = clients[2]
    local mark = #net.wire
    b.core:doing({ vendor = true })
    net:run(2)
    b.core:doing({})
    net:run(17)
    assert.equal(1, #doings(net, mark, "Bob"))
    net:run(3)
    assert.equal(2, #doings(net, mark, "Bob"))
  end)

  it("says it again every 2 minutes while it lasts, and runs out 5 minutes after it was last heard", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    local mark = #net.wire
    b.core:doing({ resting = true })
    net:run(4 * 60 + 5)
    assert.equal(3, #doings(net, mark, "Bob"))
    assert.equal("resting", poseOf(a, b))

    net.drop = function(message)
      local decoded = load().Codec.decode(message)
      return type(decoded) == "table" and decoded.type == "DOING"
    end
    b.core:doing({})
    net:run(3 * 60)
    assert.equal("resting", poseOf(a, b))
    local before = a:count("changed")
    net:run(2 * 60)
    assert.equal("seated", poseOf(a, b))
    assert.is_true(a:count("changed") > before)
  end)

  it("tells a Member who comes online what you're doing, and forgets it when you go offline", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    a:logout()
    net:run(5)
    b.core:doing({ vendor = true })
    net:run(30)
    a:login()
    net:run(30)
    assert.equal("vendor", poseOf(a, b))

    b:logout()
    net:run(5)
    b:login()
    net:run(30)
    assert.equal("seated", poseOf(a, b))
  end)

  it("clears what the Crew held from before a reload", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    b.core:doing({ vendor = true })
    net:run(3)
    assert.equal("vendor", poseOf(a, b))
    b:reload()
    net:run(20)
    assert.equal("seated", poseOf(a, b))
  end)

  it("sends nothing while paused, alone or in lockdown, and catches up after", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    local mark = #net.wire
    b.core:setPaused(true)
    b.core:doing({ vendor = true })
    net:run(30)
    assert.equal(0, #doings(net, mark, "Bob"))
    b.core:setPaused(false)
    net:run(30)
    assert.equal("vendor", poseOf(a, b))

    mark = #net.wire
    b:lockdown(true)
    b.core:doing({ combat = true })
    net:run(30)
    assert.equal(0, #doings(net, mark, "Bob"))
    b:lockdown(false)
    net:run(5)
    assert.equal("fighting", poseOf(a, b))

    a:logout()
    net:run(5)
    mark = #net.wire
    b.core:doing({ flying = true })
    net:run(30)
    assert.equal(0, #doings(net, mark, "Bob"))
    assert.equal("flying", poseOf(b, b))
  end)

  describe("a profession's window", function()
    it("shows the profession on your figure at once and on a Member's with the next DOING", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      local mark = #net.wire
      b.core:doing({ profession = 171 })
      assert.same({ "alchemy", "brewing potions" }, shown(b, b))
      net:run(3)
      assert.same({ "alchemy", "brewing potions" }, shown(a, b))
      assert.equal("alchemy", doings(net, mark, "Bob")[1].doing)
      net:run(70)
      assert.same({ "alchemy", "brewing potions · 1m" }, shown(a, b))

      b.core:doing({})
      assert.same({ "seated", "by the fire" }, shown(b, b))
      net:run(20)
      assert.same({ "seated", "by the fire" }, shown(a, b))
    end)

    it("shows crafting for a window it can't name, or a line it doesn't know", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      b.core:doing({ profession = true })
      assert.same({ "crafting", "crafting" }, shown(b, b))
      b.core:doing({ profession = 755 })
      assert.same({ "crafting", "crafting" }, shown(b, b))
      net:run(3)
      assert.same({ "crafting", "crafting" }, shown(a, b))
      b.core:doing({ profession = MINING })
      assert.same({ "mining", "mining" }, shown(b, b))
    end)

    it("comes after flying, the auction house and a vendor, and before fighting, away and resting", function()
      local _, clients = crew({ "Ann", "Bob" })
      local a = clients[1]
      a.core:doing({ profession = COOKING, vendor = true })
      assert.equal("vendor", poseOf(a, a))
      a.core:doing({ profession = COOKING, combat = true, afk = true, resting = true })
      assert.equal("cooking", poseOf(a, a))
    end)

    it("wins over a fishing or profession spell, as a Member's choice", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      b:play({ professions = { profession(ALCHEMY, "Alchemy", 10), profession(MINING, "Mining", 10) }, level = 11 })
      net:run(70)
      b:play({ professions = { profession(ALCHEMY, "Alchemy", 10), profession(MINING, "Mining", 11) }, level = 12 })
      net:run(3)
      assert.equal("mining", poseOf(a, b))
      b.core:doing({ profession = ALCHEMY })
      net:run(20)
      assert.equal("alchemy", poseOf(a, b))
    end)

    it("wins over fishing, on your figure and a Member's", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      b.core:caught({ items = { { itemId = SMALLFISH, quantity = 1 } }, zone = "Westfall", mapId = 1436 })
      b:play({ level = 11 })
      for _ = 1, 70 do
        if poseOf(a, b) == "fishing" then break end
        net:run(1)
      end
      assert.equal("fishing", poseOf(a, b))
      b.core:doing({ profession = COOKING })
      assert.equal("cooking", poseOf(b, b))
      net:run(20)
      assert.equal("cooking", poseOf(a, b))
    end)

    it("is left out in an instance, as other DOINGs are", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      b.core:doing({ profession = ALCHEMY })
      b:move({ instance = "The Deadmines" })
      b:play({ zone = "The Deadmines" })
      net:run(15)
      assert.equal("adventuring", poseOf(a, b))
    end)

    it("means nothing to a BFF that doesn't know the profession", function()
      local net, clients, ns = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      net:broadcast(b, ns.Codec.encode({ type = "DOING", from = b.memberId, doing = "jewelcrafting", at = net:now() + 1 }))
      net:run(2)
      assert.same({ "seated", "by the fire" }, shown(a, b))
    end)
  end)

  it("shows a Member by the fire when a newer BFF says something this one doesn't know", function()
    local net, clients, ns = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    b.core:doing({ vendor = true })
    net:run(3)
    net:broadcast(b, ns.Codec.encode({ type = "DOING", from = b.memberId, doing = "dancing", at = net:now() + 1 }))
    net:run(2)
    assert.same({ "seated", "by the fire" }, shown(a, b))
    net:broadcast(b, ns.Codec.encode({ type = "DOING", from = b.memberId, doing = "vendor", at = net:now() - 60 }))
    net:broadcast(b, ns.Codec.encode({ type = "DOING", from = b.memberId, doing = "vendor" }))
    net:run(2)
    assert.equal("seated", poseOf(a, b))
  end)

  it("redraws the Pocket Camp when what someone is doing changes, only while it shows", function()
    local net, clients = crew({ "Ann", "Bob" })
    local a, b = clients[1], clients[2]
    local before = a:count("changed")
    b.core:doing({ vendor = true })
    net:run(3)
    assert.equal(before + 1, a:count("changed"))
    a.core:doing({ resting = true })
    assert.equal(before + 2, a:count("changed"))
    a.core:doing({ resting = true })
    assert.equal(before + 2, a:count("changed"))

    b.core:setSetting("pocketCamp", false)
    local quiet = b:count("changed")
    a.core:doing({})
    net:run(20)
    b.core:doing({})
    assert.equal(quiet, b:count("changed"))
  end)

  describe("a gathering cast", function()
    it("shows the profession on your figure at once and on a Member's with the next DOING, for 60 s", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      local mark = #net.wire
      b.core:gathered(MINING_SPELL)
      assert.same({ "mining", "mining" }, shown(b, b))
      net:run(3)
      assert.same({ "mining", "mining" }, shown(a, b))
      assert.equal("mining", doings(net, mark, "Bob")[1].doing)
      net:run(56)
      assert.equal("mining", poseOf(b, b))
      net:run(1)
      assert.same({ "seated", "by the fire" }, shown(b, b))
      net:run(20)
      assert.same({ "seated", "by the fire" }, shown(a, b))
    end)

    it("lasts 60 s from the latest cast", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a = clients[1]
      a.core:gathered(HERBALISM_SPELL)
      net:run(40)
      a.core:gathered(HERBALISM_SPELL)
      net:run(40)
      assert.equal("herbalism", poseOf(a, a))
    end)

    it("knows every rank and leaves other spells alone", function()
      local _, clients = crew({ "Ann", "Bob" })
      local a = clients[1]
      a.core:gathered(1299348)
      assert.equal("seated", poseOf(a, a))
      a.core:gathered(10768)
      assert.equal("skinning", poseOf(a, a))
      a.core:gathered(nil)
      assert.equal("skinning", poseOf(a, a))
    end)

    it("comes after a profession's window and before fighting, so skinning a kill shows", function()
      local _, clients = crew({ "Ann", "Bob" })
      local a = clients[1]
      a.core:doing({ combat = true })
      a.core:doing({})
      a.core:gathered(SKINNING_SPELL)
      assert.equal("skinning", poseOf(a, a))
      a.core:doing({ profession = COOKING })
      assert.equal("cooking", poseOf(a, a))
      a.core:doing({ vendor = true })
      assert.equal("vendor", poseOf(a, a))
      a.core:doing({ flying = true })
      assert.equal("flying", poseOf(a, a))
    end)

    it("ends when combat starts, so being attacked while mining shows fighting", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a = clients[1]
      a.core:gathered(MINING_SPELL)
      a.core:doing({ combat = true })
      assert.equal("fighting", poseOf(a, a))
      a.core:doing({})
      net:run(21)
      a.core:doing({})
      assert.equal("seated", poseOf(a, a))
    end)
  end)

  describe("a quest handed in", function()
    it("plays on your own figure at once and on the Crew's, once", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      a.events, b.events = {}, {}
      local mark = #net.wire
      b.core:questHandedIn()
      assert.same({ "quest:Bob" }, animations(b, clients))
      b.core:questHandedIn()
      b.core:questHandedIn()
      net:run(20)
      assert.same({ "quest:Bob" }, animations(a, clients))
      assert.equal(1, #doings(net, mark, "Bob"))
      assert.equal("seated", poseOf(a, b))
    end)

    it("isn't told late, and plays nothing while the Pocket Camp is off", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      a.events = {}
      b:lockdown(true)
      b.core:questHandedIn()
      net:run(100)
      b:lockdown(false)
      net:run(30)
      assert.same({}, animations(a, clients))

      a.core:setSetting("pocketCamp", false)
      b.core:setSetting("pocketCamp", false)
      b.events = {}
      b.core:questHandedIn()
      net:run(20)
      assert.same({}, animations(a, clients))
      assert.same({}, animations(b, clients))
    end)
  end)

  describe("a profession", function()
    local function withProfessions()
      local net, clients = crew({ "Ann", "Bob" })
      for _, client in ipairs(clients) do
        client:play({ professions = { profession(ALCHEMY, "Alchemy", 10), profession(MINING, "Mining", 10),
          profession(FISHING, "Fishing", 10) } })
        client:play({ level = 11 })
      end
      net:run(5)
      return net, clients
    end

    it("shows a Member crafting or gathering for 60 s after its skill is seen to grow", function()
      local net, clients = withProfessions()
      local a, b = clients[1], clients[2]
      assert.equal("seated", poseOf(a, b))
      b:play({ professions = { profession(ALCHEMY, "Alchemy", 11), profession(MINING, "Mining", 10),
        profession(FISHING, "Fishing", 10) }, level = 12 })
      assert.same({ "alchemy", "brewing potions" }, shown(b, b))
      net:run(3)
      assert.same({ "alchemy", "brewing potions" }, shown(a, b))
      net:run(54)
      assert.equal("alchemy", poseOf(a, b))
      net:run(6)
      assert.equal("seated", poseOf(a, b))

      b:play({ professions = { profession(ALCHEMY, "Alchemy", 11), profession(MINING, "Mining", 11),
        profession(FISHING, "Fishing", 10) }, level = 13 })
      assert.same({ "mining", "mining" }, shown(b, b))
      net:run(3)
      assert.same({ "mining", "mining" }, shown(a, b))
    end)

    it("names the crafting, yours and a Member's, for 60 s after its skill is seen to grow", function()
      local net, clients = withProfessions()
      local a, b = clients[1], clients[2]
      local made = { [TAILORING] = 10, [FIRST_AID] = 10 }
      local function make(skillLine)
        made[skillLine] = made[skillLine] + 1
        b:play({ professions = { profession(TAILORING, "Tailoring", made[TAILORING]),
          profession(FIRST_AID, "First Aid", made[FIRST_AID]) }, level = b.character.level + 1 })
      end
      b:play({ professions = { profession(TAILORING, "Tailoring", 10), profession(FIRST_AID, "First Aid", 10) },
        level = 12 })
      net:run(70)

      make(TAILORING)
      assert.same({ "tailoring", "tailoring" }, shown(b, b))
      net:run(3)
      assert.same({ "tailoring", "tailoring" }, shown(a, b))
      net:run(60)
      assert.equal("seated", poseOf(a, b))

      make(FIRST_AID)
      assert.same({ "firstAid", "making bandages" }, shown(b, b))
      net:run(3)
      assert.same({ "firstAid", "making bandages" }, shown(a, b))
      net:run(54)
      assert.equal("firstAid", poseOf(a, b))
      net:run(6)
      assert.equal("seated", poseOf(a, b))
    end)

    it("names the gathering, yours and a Member's, for 60 s after its skill is seen to grow", function()
      local net, clients = withProfessions()
      local a, b = clients[1], clients[2]
      local gathered = { [HERBALISM] = 10, [SKINNING] = 10 }
      local function gather(skillLine)
        gathered[skillLine] = gathered[skillLine] + 1
        b:play({ professions = { profession(HERBALISM, "Herbalism", gathered[HERBALISM]),
          profession(SKINNING, "Skinning", gathered[SKINNING]) }, level = b.character.level + 1 })
      end
      b:play({ professions = { profession(HERBALISM, "Herbalism", 10), profession(SKINNING, "Skinning", 10) },
        level = 12 })
      net:run(70)

      gather(HERBALISM)
      assert.same({ "herbalism", "picking herbs" }, shown(b, b))
      net:run(3)
      assert.same({ "herbalism", "picking herbs" }, shown(a, b))
      net:run(54)
      assert.equal("herbalism", poseOf(a, b))
      net:run(6)
      assert.equal("seated", poseOf(a, b))

      gather(SKINNING)
      assert.same({ "skinning", "skinning" }, shown(b, b))
      net:run(3)
      assert.same({ "skinning", "skinning" }, shown(a, b))
      net:run(60)
      assert.equal("seated", poseOf(a, b))
    end)

    it("makes nothing of fishing skill, a first share or a login's catch-up", function()
      local net, clients = withProfessions()
      local a, b = clients[1], clients[2]
      b:play({ professions = { profession(ALCHEMY, "Alchemy", 10), profession(MINING, "Mining", 10),
        profession(FISHING, "Fishing", 11) }, level = 12 })
      net:run(3)
      assert.equal("seated", poseOf(a, b))

      a:logout()
      net:run(5)
      b:play({ professions = { profession(ALCHEMY, "Alchemy", 20), profession(MINING, "Mining", 10),
        profession(FISHING, "Fishing", 11) }, level = 13 })
      net:run(70)
      a:login()
      net:run(40)
      assert.equal("seated", poseOf(a, b))
    end)
  end)

  describe("a shapeshift form", function()
    local function formOf(viewer, client)
      local actor = actorFor(viewer.core:pocketCamp(), client)
      return actor and actor.form
    end

    it("shows on your own figure at once, in words too, and goes at once", function()
      local _, clients = crew({ "Ann", "Bob" })
      local a = clients[1]
      a.core:doing({ form = "bear" })
      assert.same({ "seated", "in bear form" }, shown(a, a))
      assert.equal("bear", formOf(a, a))
      a.core:doing({ form = "wolf" })
      assert.same({ "seated", "a ghost wolf" }, shown(a, a))
      a.core:doing({ form = "seal" })
      assert.same({ "seated", "in aquatic form" }, shown(a, a))
      a.core:doing({})
      assert.same({ "seated", "by the fire" }, shown(a, a))
      assert.is_nil(formOf(a, a))
    end)

    it("sends a combat form or Ghost Wolf at once, in the same small DOING", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      local mark = #net.wire
      b.core:doing({ form = "cat" })
      net:run(3)
      assert.equal("cat", formOf(a, b))
      local sent = doings(net, mark, "Bob")
      assert.equal(1, #sent)
      assert.same({ "cat", nil }, { sent[1].form, sent[1].doing })
      assert.is_true(sent[1].size <= ROOM)
      b.core:doing({ form = "wolf" })
      net:run(5)
      assert.equal("cat", formOf(a, b))
      net:run(12)
      assert.equal("wolf", formOf(a, b))
      assert.equal(2, #doings(net, mark, "Bob"))
    end)

    it("sends a travel form only once it's been held for 30 s", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      local mark = #net.wire
      b.core:doing({ form = "travel" })
      net:run(20)
      b.core:doing({})
      net:run(60)
      assert.equal(0, #doings(net, mark, "Bob"))
      assert.is_nil(formOf(a, b))

      b.core:doing({ form = "seal" })
      net:run(28)
      assert.equal(0, #doings(net, mark, "Bob"))
      net:run(5)
      assert.equal("seal", formOf(a, b))
      assert.equal(1, #doings(net, mark, "Bob"))
    end)

    it("never sends the end of a form: what's heard runs out 2.5 min after it was last heard", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      local mark = #net.wire
      b.core:doing({ form = "bear" })
      net:run(3)
      b.core:doing({})
      net:run(2 * 60)
      assert.equal(1, #doings(net, mark, "Bob"))
      assert.equal("bear", formOf(a, b))
      local before = a:count("changed")
      net:run(40)
      assert.is_nil(formOf(a, b))
      assert.same({ "seated", "by the fire" }, shown(a, b))
      assert.is_true(a:count("changed") > before)
      assert.equal(1, #doings(net, mark, "Bob"))

      b.core:doing({ form = "bear" })
      net:run(3)
      assert.equal("bear", formOf(a, b))
    end)

    it("says it again every 2 minutes while it's held", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      local mark = #net.wire
      b.core:doing({ form = "moonkin" })
      net:run(5 * 60 + 5)
      assert.equal(3, #doings(net, mark, "Bob"))
      assert.equal("moonkin", formOf(a, b))
    end)

    it("goes when a DOING says nothing of it, as an older BFF's does", function()
      local net, clients, ns = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      b.core:doing({ form = "bear" })
      net:run(3)
      assert.equal("bear", formOf(a, b))
      net:broadcast(b, ns.Codec.encode({ type = "DOING", from = b.memberId, doing = "vendor", at = net:now() + 1 }))
      net:run(2)
      assert.same({ "vendor", "at a vendor" }, shown(a, b))
      assert.is_nil(formOf(a, b))
      net:broadcast(b, ns.Codec.encode({ type = "DOING", from = b.memberId, form = "tree", at = net:now() + 2 }))
      net:run(2)
      assert.same({ "seated", "by the fire" }, shown(a, b))
      assert.is_nil(formOf(a, b))
    end)

    it("is told with what you're doing, which a form shows over only by the fire or fighting", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      b.core:doing({ form = "bear", combat = true })
      net:run(3)
      assert.same({ "fighting", "fighting" }, shown(a, b))
      assert.equal("bear", formOf(a, b))
      b.core:doing({ form = "travel", vendor = true })
      assert.same({ "vendor", "at a vendor" }, shown(b, b))
      assert.is_nil(formOf(b, b))
      net:run(20)
      assert.same({ "vendor", "at a vendor" }, shown(a, b))
      assert.is_nil(formOf(a, b))
    end)

    it("gives a form its room: clear of the fire and of its neighbours, trotting away from the fire", function()
      local names = { "Ann", "Bob", "Cid", "Dee", "Eve", "Fay" }
      local net, clients, ns = crew(names)
      local a = clients[1]
      local layout = ns.Core.CAMP_LAYOUT
      a.core:doing({ form = "bear" })
      clients[2].core:doing({ form = "wolf" })
      clients[3].core:doing({ form = "cat" })
      net:run(3)
      local view = a.core:pocketCamp()
      local function span(actor)
        if not actor.form then return actor.x, actor.x + actor.width end
        local fore, aft = layout.formFore, layout.formAft + (actor.trots and layout.formTrot or 0)
        if actor.x > 0 then return actor.x - fore, actor.x + actor.width + aft end
        return actor.x - aft, actor.x + actor.width + fore
      end
      assert.is_true(actorFor(view, clients[2]).trots)
      assert.is_nil(actorFor(view, clients[3]).trots)
      local half = view.columns / 2
      for i, actor in ipairs(view.actors) do
        local from, to = span(actor)
        assert.is_true(from >= -half and to <= half)
        assert.is_true(to <= -layout.fire or from >= layout.fire)
        for j = i + 1, #view.actors do
          local otherFrom, otherTo = span(view.actors[j])
          assert.is_true(to <= otherFrom or otherTo <= from)
        end
      end
    end)
  end)

  describe("with the rest of the Pocket Camp", function()
    it("gives way to an instance, whatever was said before going in", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      b.core:doing({ vendor = true })
      net:run(3)
      assert.equal("vendor", poseOf(a, b))
      b:move({ instance = "The Deadmines" })
      b:play({ zone = "The Deadmines" })
      b.core:doing({ combat = true })
      net:run(15)
      local bob = actorFor(a.core:pocketCamp(), b)
      assert.same({ "adventuring", "in The Deadmines", nil }, { bob.pose, bob.status, bob.raid })
      assert.equal("adventuring", poseOf(b, b))
    end)

    it("marks a raid", function()
      local net, clients = crew({ "Ann", "Bob" })
      local a, b = clients[1], clients[2]
      b:move({ instance = "Molten Core" })
      b:play({ zone = "Molten Core" })
      net:run(15)
      local bob = actorFor(a.core:pocketCamp(), b)
      assert.same({ "adventuring", "in Molten Core", true }, { bob.pose, bob.status, bob.raid })
    end)

    local function working(skillLines)
      local net, clients, ns = crew({ "Ann", "Bob", "Cid", "Dee" })
      local a = clients[1]
      local layout = ns.Core.CAMP_LAYOUT
      local function seats()
        local xs = {}
        for _, actor in ipairs(a.core:pocketCamp().actors) do xs[actor.memberId] = actor.x end
        return xs
      end
      local before = seats()
      for i, skillLine in ipairs(skillLines) do
        clients[i + 1]:play({ professions = { profession(skillLine, "Work", 10) }, level = 11 })
      end
      net:run(70)
      for i, skillLine in ipairs(skillLines) do
        clients[i + 1]:play({ professions = { profession(skillLine, "Work", 11) }, level = 12 })
      end
      net:run(3)
      local view = a.core:pocketCamp()
      assert.equal(4, #view.actors + (view.more or 0))
      local function span(actor)
        local room = layout.working[actor.pose] or { fore = 0, aft = 0 }
        if actor.x > 0 then return actor.x - room.fore, actor.x + actor.width + room.aft end
        return actor.x - room.aft, actor.x + actor.width + room.fore
      end
      local half = view.columns / 2
      local poses = {}
      for i, actor in ipairs(view.actors) do
        poses[#poses + 1] = actor.pose
        local from, to = span(actor)
        assert.is_true(from >= -half and to <= half)
        assert.is_true(to <= -layout.fire or from >= layout.fire)
        for j = i + 1, #view.actors do
          local otherFrom, otherTo = span(view.actors[j])
          assert.is_true(to <= otherFrom or otherTo <= from)
        end
      end
      table.sort(poses)
      local function moved(i)
        return math.abs(actorFor(view, clients[i + 1]).x) - math.abs(before[clients[i + 1].memberId])
      end
      return poses, moved
    end

    it("gives a gatherer its animation's room: clear of the fire and of its neighbours", function()
      local poses, moved = working({ SKINNING, HERBALISM, MINING })
      assert.same({ "herbalism", "mining", "seated", "skinning" }, poses)
      assert.is_true(moved(1) > 0)
    end)

    it("gives a crafter its animation's room: clear of the fire and of its neighbours", function()
      local poses, moved = working({ FIRST_AID, BLACKSMITHING })
      assert.same({ "blacksmithing", "firstAid", "seated", "seated" }, poses)
      assert.is_true(moved(1) > 0)
    end)

    it("leaves a figure out rather than crowd crafters that need more room than the Pocket Camp has", function()
      local poses = working({ FIRST_AID, COOKING, BLACKSMITHING })
      assert.equal(3, #poses)
    end)

    it("gives a flying figure its griffin's room: clear of the fire and of its neighbours", function()
      local names = { "Ann", "Bob", "Cid", "Dee", "Eve", "Fay" }
      local net, clients, ns = crew(names)
      local a = clients[1]
      local layout = ns.Core.CAMP_LAYOUT
      assert.equal(6, #a.core:pocketCamp().actors)
      clients[2].core:doing({ flying = true })
      net:run(3)
      local view = a.core:pocketCamp()
      assert.equal(5, #view.actors)
      assert.same({ 1, "+1" }, { view.more, view.moreText })
      local bob = actorFor(view, clients[2])
      assert.equal(layout.seated, bob.width)
      local function span(actor)
        if actor.pose ~= "flying" then return actor.x, actor.x + actor.width end
        if actor.x > 0 then return actor.x - layout.mountFore, actor.x + actor.width + layout.mountAft end
        return actor.x - layout.mountAft, actor.x + actor.width + layout.mountFore
      end
      local half = layout.pocketColumns / 2
      for i, actor in ipairs(view.actors) do
        local from, to = span(actor)
        assert.is_true(from >= -half and to <= half)
        assert.is_true(to <= -layout.fire or from >= layout.fire)
        for j = i + 1, #view.actors do
          local otherFrom, otherTo = span(view.actors[j])
          assert.is_true(to <= otherFrom or otherTo <= from)
        end
      end
    end)
  end)
end)
