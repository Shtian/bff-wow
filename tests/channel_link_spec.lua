local wow = require("tests.wow_stubs")

local CHANNEL = "BFFABCDEFG"

local function fakeCore()
  local core = { calls = {} }
  for _, method in ipairs({ "up", "down", "gone", "sendFailed", "received" }) do
    core[method] = function(_, ...)
      core.calls[#core.calls + 1] = { method, ... }
    end
  end
  core.known, core.asked = {}, {}
  function core.fromKnownMember(_, message)
    core.asked[#core.asked + 1] = message
    return core.known[message] == true
  end
  function core.count(method, arg)
    local n = 0
    for _, call in ipairs(core.calls) do
      if call[1] == method and (arg == nil or call[2] == arg) then n = n + 1 end
    end
    return n
  end
  return core
end

local function linked()
  local game = wow()
  local ns = game.load("Game/ChannelLink.lua", {})
  local link = ns.ChannelLink
  local core = fakeCore()
  link.start(core, function() end)
  link.setCrew({ channel = CHANNEL, password = "pw" })
  game.advance(11)
  game.fire("CHAT_MSG_CHANNEL_LIST", "*Bob, Cat-Realm", nil, nil, "5. " .. CHANNEL, nil, nil, nil, nil, CHANNEL)
  assert.equal(1, core.count("up"))
  return game, link, core, ns
end

local function targets(game, mark)
  local names = {}
  for i = (mark or 0) + 1, #game.whispers do names[#names + 1] = game.whispers[i].target end
  table.sort(names)
  return names
end

local function chunksOf(ns, message)
  return ns.Framing.new({ now = function() return 0 end }):split(message)
end

describe("The channel link", function()
  it("never whispers to your own Character when it has a last name", function()
    local game = wow()
    game.player = { "Moorwyn", "Stormgaard" }
    local link = game.load("Game/ChannelLink.lua", {}).ChannelLink
    local core = fakeCore()
    link.start(core, function() end)
    link.setCrew({ channel = CHANNEL, password = "pw" })
    game.advance(11)
    game.fire("CHAT_MSG_CHANNEL_LIST", "*Moorwyn Stormgaard, Gawd Zillah", nil, nil, "5. " .. CHANNEL,
      nil, nil, nil, nil, CHANNEL)
    link.send("1|short")
    assert.same({ "Gawd Zillah" }, targets(game))
  end)

  it("whispers a message to every peer, or to one", function()
    local game, link = linked()
    link.send("1|short")
    assert.same({ "Bob", "Cat-Realm" }, targets(game))

    local mark = #game.whispers
    link.send("1|short", "Cat")
    assert.same({ "Cat-Realm" }, targets(game, mark))

    mark = #game.whispers
    link.send("1|short", "Dan")
    assert.same({}, targets(game, mark))
  end)

  it("sends a one-chunk message at ALERT and a longer one at NORMAL", function()
    local game, link = linked()
    link.send("1|" .. ("x"):rep(200), "Bob")
    link.send("1|" .. ("x"):rep(400), "Bob")
    assert.equal("ALERT", game.whispers[1].priority)
    assert.equal("NORMAL", game.whispers[2].priority)
  end)

  describe("sending", function()
    local long = "1|" .. ("x"):rep(600)

    it("hands ChatThrottleLib one chunk of a long message at a time, in a queue per peer", function()
      local game, link = linked()
      link.send(long)
      assert.same({ "Bob", "Cat-Realm" }, targets(game))
      assert.are_not.equal(game.whispers[1].queue, game.whispers[2].queue)

      game.sent(game.whispers[1])
      assert.same({ "Bob" }, targets(game, 2))
      game.sent(game.whispers[3])
      assert.same({ "Bob" }, targets(game, 3))
      game.sent(game.whispers[4])
      assert.equal(4, #game.whispers)
      for _, whisper in ipairs(game.whispers) do assert.is_true(#whisper.text <= 255) end
    end)

    it("sends chunks another BFF puts back together", function()
      local game, link, _, ns = linked()
      link.send(long, "Bob")
      local receiver = ns.Framing.new({ now = function() return 0 end })
      local whole
      for i = 1, 3 do
        whole = receiver:receive("Me", game.whispers[i].text)
        game.sent(game.whispers[i])
      end
      assert.equal(long, whole)
    end)

    it("sends every chunk in order when ChatThrottleLib sends each at once", function()
      local game, link, _, ns = linked()
      game.instant = true
      link.send(long)
      link.send("1|digest")
      link.send(long, "Bob")
      assert.equal(11, #game.whispers)
      local receiver = ns.Framing.new({ now = function() return 0 end })
      local whole = {}
      for _, whisper in ipairs(game.whispers) do
        if whisper.target == "Bob" then whole[#whole + 1] = receiver:receive("Me", whisper.text) end
      end
      assert.same({ long, "1|digest", long }, whole)
      game.fire("CHAT_MSG_CHANNEL_LEAVE", "", "Bob", nil, "5. " .. CHANNEL, nil, nil, nil, 5, CHANNEL)
      game.advance(31)
      assert.is_false(game.filters.CHAT_MSG_SYSTEM(nil, "CHAT_MSG_SYSTEM", "No player named 'Bob' is currently playing."))
    end)

    it("sends a second long message to a peer only after the first", function()
      local game, link = linked()
      link.send(long, "Bob")
      link.send(long, "Bob")
      for i = 1, 6 do
        assert.equal(i, #game.whispers)
        game.sent(game.whispers[i])
      end
      assert.equal(6, #game.whispers)
    end)

    it("lets a one-chunk message jump the queue", function()
      local game, link = linked()
      link.send(long, "Bob")
      link.send("1|digest", "Bob")
      assert.equal(2, #game.whispers)
      assert.equal("ALERT", game.whispers[2].priority)
    end)

    it("drops a peer's unsent chunks when they leave", function()
      local game, link = linked()
      local lines = {}
      link.setTrace(function(line) lines[#lines + 1] = line end)
      link.send(long)
      game.fire("CHAT_MSG_CHANNEL_LEAVE", "", "Bob", nil, "5. " .. CHANNEL, nil, nil, nil, 5, CHANNEL)
      game.sent(game.whispers[1])
      assert.same({}, targets(game, 2))
      assert.truthy(table.concat(lines, "\n"):find("\n  dropped 2 unsent chunks to Bob (gone)\n", 1, true))

      game.sent(game.whispers[2])
      assert.same({ "Cat-Realm" }, targets(game, 2))
    end)

    it("drops everyone's unsent chunks when the link goes down", function()
      local game, link = linked()
      link.send(long)
      game.lockdown = true
      game.fire("ADDON_RESTRICTION_STATE_CHANGED", 1, 1)
      game.sent(game.whispers[1])
      game.sent(game.whispers[2])
      assert.equal(2, #game.whispers)
    end)

    it("drops the rest of a message when a chunk of it fails, and tells Core", function()
      local game, link, core = linked()
      local lines = {}
      link.setTrace(function(line) lines[#lines + 1] = line end)
      link.send(long, "Bob")
      link.send(long, "Bob")
      game.failed(game.whispers[1], 7)
      game.advance(0)
      assert.equal(1, core.count("sendFailed", "Bob"))
      assert.equal("  chunk 1/3 to Bob · 255 B · failed (result 7)", lines[3])
      assert.equal("  dropped 2 unsent chunks to Bob (a chunk failed)", lines[4])

      assert.equal(2, #game.whispers)
      game.sent(game.whispers[2])
      assert.equal("  chunk 1/3 to Bob · 255 B · sent", lines[#lines])
      assert.equal(3, #game.whispers)
    end)
  end)

  describe("receiving", function()
    local long = "2|" .. ("y"):rep(700)

    local function whisperFrom(game, sender, message)
      game.onComm("BFF", message, "WHISPER", sender)
    end

    it("delivers a message once all its chunks are in, in any order", function()
      local game, _, core, ns = linked()
      local chunks = chunksOf(ns, long)
      assert.equal(3, #chunks)
      whisperFrom(game, "Bob", chunks[3])
      whisperFrom(game, "Bob", chunks[1])
      assert.equal(0, core.count("received"))
      whisperFrom(game, "Bob", chunks[2])
      assert.equal(1, core.count("received", long))
    end)

    it("delivers a one-chunk message at once", function()
      local game, _, core, ns = linked()
      whisperFrom(game, "Bob", chunksOf(ns, "2|digest")[1])
      assert.equal(1, core.count("received", "2|digest"))
    end)

    it("tells Core the sender's bare Character name with each message", function()
      local game, _, core, ns = linked()
      local chunks = chunksOf(ns, long)
      for _, chunk in ipairs(chunks) do whisperFrom(game, "Cat-Realm", chunk) end
      whisperFrom(game, "Bob", "1|digest")
      assert.same({ "received", long, "Cat" }, core.calls[#core.calls - 1])
      assert.same({ "received", "1|digest", "Bob" }, core.calls[#core.calls])
    end)

    it("still reads a protocol 1 message AceComm put together", function()
      local game, _, core = linked()
      local older = "1|" .. ("y"):rep(700)
      whisperFrom(game, "Bob", older)
      whisperFrom(game, "Bob", "1|digest")
      assert.equal(1, core.count("received", older))
      assert.equal(1, core.count("received", "1|digest"))
    end)

    it("asks a peer again when a message from them stays incomplete for 30 s", function()
      local game, link, core, ns = linked()
      local lines = {}
      link.setTrace(function(line) lines[#lines + 1] = line end)
      local chunks = chunksOf(ns, long)
      whisperFrom(game, "Cat-Realm", chunks[1])
      whisperFrom(game, "Cat-Realm", chunks[3])
      game.advance(29)
      assert.equal(0, core.count("sendFailed"))
      game.advance(1)
      assert.equal(1, core.count("sendFailed", "Cat"))
      assert.equal(0, core.count("received"))
      assert.equal("message from Cat-Realm lost: 2 of 3 chunks after 30 s", lines[#lines])
    end)

    it("forgets a half-received message when its sender leaves or the link goes down", function()
      local game, _, core, ns = linked()
      local chunks = chunksOf(ns, long)
      whisperFrom(game, "Bob", chunks[1])
      whisperFrom(game, "Cat-Realm", chunks[1])
      game.fire("CHAT_MSG_CHANNEL_LEAVE", "", "Bob", nil, "5. " .. CHANNEL, nil, nil, nil, 5, CHANNEL)
      game.lockdown = true
      game.fire("ADDON_RESTRICTION_STATE_CHANGED", 1, 1)
      game.lockdown = false
      game.fire("ADDON_RESTRICTION_STATE_CHANGED", 1, 0)
      game.advance(60)
      assert.equal(0, core.count("sendFailed"))
    end)
  end)

  it("keeps the link up after a failed send, and tells Core who it failed to", function()
    local game, link, core = linked()
    link.send("1|data")
    for _, whisper in ipairs(game.whispers) do
      if whisper.target == "Cat-Realm" then game.failed(whisper) end
    end
    game.advance(0)
    assert.equal(0, core.count("down"))
    assert.equal(1, core.count("sendFailed", "Cat"))
    assert.equal(0, core.count("sendFailed", "Bob"))

    local mark = #game.whispers
    link.send("1|more")
    assert.same({ "Bob", "Cat-Realm" }, targets(game, mark))
  end)

  it("drops a peer when Player is offline follows a failed send to them", function()
    local game, link, core = linked()
    link.send("1|data")
    for _, whisper in ipairs(game.whispers) do
      if whisper.target == "Bob" then game.failed(whisper) end
    end
    game.advance(0)
    game.advance(1)
    game.fire("CHAT_MSG_SYSTEM", "Player is offline.")
    assert.equal(1, core.count("gone", "Bob"))
    assert.is_true(game.filters.CHAT_MSG_SYSTEM(nil, "CHAT_MSG_SYSTEM", "Player is offline."))

    local mark = #game.whispers
    link.send("1|more")
    assert.same({ "Cat-Realm" }, targets(game, mark))
  end)

  it("keeps everyone when Player is offline follows failures to several peers", function()
    local game, link, core = linked()
    link.send("1|data")
    for _, whisper in ipairs(game.whispers) do game.failed(whisper) end
    game.advance(0)
    game.fire("CHAT_MSG_SYSTEM", "Player is offline.")
    assert.equal(0, core.count("gone"))
    assert.is_false(game.filters.CHAT_MSG_SYSTEM(nil, "CHAT_MSG_SYSTEM", "Player is offline."))
  end)

  it("keeps everyone after a Player is offline with no failed send near it", function()
    local game, link, core = linked()
    link.send("1|data")
    game.failed(game.whispers[1])
    game.advance(10)
    game.fire("CHAT_MSG_SYSTEM", "Player is offline.")
    assert.equal(0, core.count("gone"))
    assert.is_false(game.filters.CHAT_MSG_SYSTEM(nil, "CHAT_MSG_SYSTEM", "Player is offline."))

    local mark = #game.whispers
    link.send("1|more")
    assert.same({ "Bob", "Cat-Realm" }, targets(game, mark))
  end)

  it("drops a peer on No player named, and ignores their failed chunks after", function()
    local game, link, core = linked()
    link.send("1|data", "Bob")
    game.fire("CHAT_MSG_SYSTEM", "No player named 'Bob' is currently playing.")
    game.failed(game.whispers[1])
    game.advance(0)
    assert.equal(1, core.count("gone", "Bob"))
    assert.equal(0, core.count("sendFailed"))
  end)

  local function whisperFrom(game, sender, message)
    game.onComm("BFF", message or "1|digest", "WHISPER", sender)
  end

  it("stops whispering a peer who hasn't answered for 3 minutes, until they whisper again", function()
    local game, link, core = linked()
    for _ = 1, 4 do
      link.send("1|digest")
      whisperFrom(game, "Cat-Realm")
      game.advance(60)
    end
    local mark = #game.whispers
    link.send("1|digest")
    link.send("1|digest", "Bob")
    assert.same({ "Cat-Realm" }, targets(game, mark))
    assert.equal(0, core.count("gone"))
    assert.equal(0, core.count("down"))
    assert.equal(2, link.state().peers)

    whisperFrom(game, "Bob")
    mark = #game.whispers
    link.send("1|digest")
    assert.same({ "Bob", "Cat-Realm" }, targets(game, mark))
  end)

  it("asks for the member list when a restriction lifts, not while one starts", function()
    -- WoW: on a boss pull, InChatMessagingLockdown turns true only after the
    -- ADDON_RESTRICTION_STATE_CHANGED events (seen in a trace).
    local game = linked()
    local mark = #game.listed
    game.fire("ADDON_RESTRICTION_STATE_CHANGED", 1, 1)
    game.fire("ADDON_RESTRICTION_STATE_CHANGED", 5, 1)
    whisperFrom(game, "Dan")
    assert.equal(mark, #game.listed)
    game.lockdown = true
    game.advance(0)
    game.fire("ADDON_RESTRICTION_STATE_CHANGED", 0, 1)
    game.advance(60)
    assert.equal(mark, #game.listed)

    game.lockdown = false
    game.fire("ADDON_RESTRICTION_STATE_CHANGED", 0, 0)
    assert.same({ CHANNEL }, { select(mark + 1, unpack(game.listed)) })
  end)

  it("asks for the member list again a frame after a restriction that doesn't lock chat starts", function()
    local game = linked()
    game.fire("ADDON_RESTRICTION_STATE_CHANGED", 0, 1)
    game.advance(0)
    local mark = #game.listed
    whisperFrom(game, "Dan")
    assert.same({ CHANNEL }, { select(mark + 1, unpack(game.listed)) })
  end)

  it("doesn't count silence while the link is down", function()
    local game, link = linked()
    link.send("1|digest")
    game.lockdown = true
    game.fire("ADDON_RESTRICTION_STATE_CHANGED", 1, 1)
    game.advance(1200)
    game.lockdown = false
    game.fire("ADDON_RESTRICTION_STATE_CHANGED", 1, 0)
    local mark = #game.whispers
    link.send("1|digest")
    assert.same({ "Bob", "Cat-Realm" }, targets(game, mark))
  end)

  it("leaves a peer dropped on No player named out when the member list still names them", function()
    local game, link, core = linked()
    link.send("1|data", "Bob")
    game.fire("CHAT_MSG_SYSTEM", "No player named 'Bob' is currently playing.")
    game.advance(60)
    game.fire("CHAT_MSG_CHANNEL_LIST", "*Bob, Cat-Realm", nil, nil, "5. " .. CHANNEL, nil, nil, nil, nil, CHANNEL)
    assert.equal(1, link.state().peers)
    assert.equal(0, core.count("down"))
    assert.equal(1, core.count("up"))

    whisperFrom(game, "Bob")
    assert.equal(2, link.state().peers)
    assert.equal(1, core.count("received"))
  end)

  it("holds a whisper from a stranger until a member list shows them", function()
    local game, _, core = linked()
    whisperFrom(game, "Dan")
    assert.equal(0, core.count("received"))
    game.fire("CHAT_MSG_CHANNEL_LIST", "Dan", nil, nil, "5. " .. CHANNEL, nil, nil, nil, nil, CHANNEL)
    assert.equal(1, core.count("received"))
    assert.equal(1, core.count("down"))
    assert.equal(2, core.count("up"))
  end)

  describe("a whisper from a stranger", function()
    local function listless()
      local game = wow()
      local ns = game.load("Game/ChannelLink.lua", {})
      local link = ns.ChannelLink
      local core = fakeCore()
      local lines = {}
      link.setTrace(function(line) lines[#lines + 1] = line end)
      link.start(core, function() end)
      link.setCrew({ channel = CHANNEL, password = "pw" })
      game.advance(16)
      assert.equal(1, core.count("up"))
      assert.equal(0, link.state().peers)
      return game, link, core, ns, lines
    end

    it("from a known Member is delivered at once, and they are whispered from then on", function()
      local game, link, core, _, lines = listless()
      core.known["1|digest"] = true
      whisperFrom(game, "Dan Duke")
      assert.same({ "received", "1|digest", "Dan Duke" }, core.calls[#core.calls])
      assert.equal(1, link.state().peers)
      assert.truthy(table.concat(lines, "\n"):find("peer added: Dan Duke (known Member)", 1, true))
      link.send("1|short")
      assert.same({ "Dan Duke" }, targets(game))
    end)

    it("of several chunks from a known Member is delivered once, when whole", function()
      local game, link, core, ns = listless()
      local long = "2|" .. ("y"):rep(700)
      core.known[long] = true
      local chunks = chunksOf(ns, long)
      assert.equal(3, #chunks)
      for _, chunk in ipairs(chunks) do whisperFrom(game, "Dan", chunk) end
      assert.equal(1, core.count("received"))
      assert.same({ "received", long, "Dan" }, core.calls[#core.calls])
      assert.equal(1, link.state().peers)
      local again = "2|" .. ("z"):rep(700)
      for _, chunk in ipairs(chunksOf(ns, again)) do whisperFrom(game, "Dan", chunk) end
      assert.equal(2, core.count("received"))
      assert.same({ "received", again, "Dan" }, core.calls[#core.calls])
    end)

    it("from an unknown Member is dropped after 10 s, as before", function()
      local game, link, core = listless()
      whisperFrom(game, "Dan")
      assert.same({ "1|digest" }, core.asked)
      game.advance(10)
      assert.equal(0, core.count("received"))
      assert.equal(0, link.state().peers)
      game.fire("CHAT_MSG_CHANNEL_LIST", "Dan", nil, nil, "5. " .. CHANNEL, nil, nil, nil, nil, CHANNEL)
      assert.equal(0, core.count("received"))
    end)

    it("from a peer isn't asked about", function()
      local game, _, core = linked()
      whisperFrom(game, "Bob")
      assert.same({}, core.asked)
    end)
  end)

  it("comes up 5 s after joining when no member list arrives", function()
    local game = wow()
    local link = game.load("Game/ChannelLink.lua", {}).ChannelLink
    local core = fakeCore()
    link.start(core, function() end)
    link.setCrew({ channel = CHANNEL, password = "pw" })
    game.advance(15)
    assert.equal(0, core.count("up"))
    game.advance(1)
    assert.equal(1, core.count("up"))
  end)

  describe("after a peer left the channel", function()
    local NOT_FOUND = "No player named 'Bob' is currently playing."

    local function hidden(game)
      return game.filters.CHAT_MSG_SYSTEM(nil, "CHAT_MSG_SYSTEM", NOT_FOUND)
    end

    local function left(game)
      game.fire("CHAT_MSG_CHANNEL_LEAVE", "", "Bob", nil, "5. " .. CHANNEL, nil, nil, nil, 5, CHANNEL)
    end

    it("hides No player named while a whisper to them is still queued, however long", function()
      local game, link, core = linked()
      link.send("1|data", "Bob")
      left(game)
      assert.equal(1, core.count("gone", "Bob"))
      game.advance(120)
      assert.is_true(hidden(game))
    end)

    it("hides it for a while after their last chunk went out, then no longer", function()
      local game, link = linked()
      link.send("1|data", "Bob")
      left(game)
      game.sent(game.whispers[1])
      game.advance(5)
      assert.is_true(hidden(game))
      game.advance(30)
      assert.is_false(hidden(game))
    end)

    it("keeps hiding it until the chunk already handed over went out", function()
      local game, link = linked()
      link.send("1|" .. ("x"):rep(600), "Bob")
      left(game)
      game.advance(120)
      assert.is_true(hidden(game))
      game.sent(game.whispers[1])
      assert.equal(1, #game.whispers)
      game.advance(31)
      assert.is_false(hidden(game))
    end)

    it("keeps hiding it until every message queued for them went out", function()
      local game, link = linked()
      link.send("1|one", "Bob")
      link.send("1|two", "Bob")
      left(game)
      game.sent(game.whispers[1])
      game.advance(120)
      assert.is_true(hidden(game))
      game.sent(game.whispers[2])
      game.advance(31)
      assert.is_false(hidden(game))
    end)

    it("counts a message whose last chunk failed as out of the queue", function()
      local game, link = linked()
      link.send("1|data", "Bob")
      left(game)
      game.failed(game.whispers[1])
      game.advance(31)
      assert.is_false(hidden(game))
    end)

    it("shows it when nothing was whispered to them", function()
      local game = linked()
      left(game)
      assert.is_false(hidden(game))
    end)
  end)

  describe("trace", function()
    local function traced(link)
      local lines = {}
      link.setTrace(function(line) lines[#lines + 1] = line end)
      return lines
    end

    local function containing(lines, text)
      local found = {}
      for _, line in ipairs(lines) do
        if line:find(text, 1, true) then found[#found + 1] = line end
      end
      return found
    end

    it("reports a No player named it could read but that names no peer, with the peers compared", function()
      local game, link, core = linked()
      local lines = traced(link)
      game.fire("CHAT_MSG_SYSTEM", "No player named 'Dan Smith' is currently playing.")
      assert.same({ "notice: No player named Dan Smith · not a peer (peers: bob, cat)" }, lines)
      assert.equal(0, core.count("gone"))
    end)

    it("reports a No player named for a peer who left with a whisper queued as already gone", function()
      local game, link = linked()
      local lines = traced(link)
      link.send("1|data", "Bob")
      game.fire("CHAT_MSG_CHANNEL_LEAVE", "", "Bob", nil, "5. " .. CHANNEL, nil, nil, nil, 5, CHANNEL)
      game.fire("CHAT_MSG_SYSTEM", "No player named 'Bob' is currently playing.")
      assert.equal(1, #containing(lines, "notice: No player named Bob (already gone)"))
    end)

    it("still reports a No player named for a peer as before", function()
      local game, link = linked()
      local lines = traced(link)
      game.fire("CHAT_MSG_SYSTEM", "No player named 'Bob' is currently playing.")
      assert.equal(1, #containing(lines, "notice: No player named Bob"))
      assert.equal(0, #containing(lines, "not a peer"))
    end)

    it("reports an unreadable system message shortly after a whisper, without reading it", function()
      local game, link = linked()
      local lines = traced(link)
      game.instance = { true, "party" }
      link.send("1|short")
      game.lockdown = true
      game.advance(1)
      game.fire("CHAT_MSG_SYSTEM", game.secret())
      local found = containing(lines, "notice: unreadable system message")
      assert.equal(1, #found)
      assert.truthy(found[1]:find("1.0 s after a whisper", 1, true), found[1])
      assert.truthy(found[1]:find("in instance: party", 1, true), found[1])
      assert.truthy(found[1]:find("lockdown: yes", 1, true), found[1])
      assert.is_false(game.filters.CHAT_MSG_SYSTEM(nil, "CHAT_MSG_SYSTEM", game.secret()))
    end)

    it("leaves out an unreadable system message long after any whisper", function()
      local game, link = linked()
      local lines = traced(link)
      game.fire("CHAT_MSG_SYSTEM", game.secret())
      link.send("1|short")
      game.advance(30)
      game.fire("CHAT_MSG_SYSTEM", game.secret())
      assert.equal(0, #containing(lines, "unreadable"))
    end)

    it("reports entering and leaving an instance", function()
      local game, link = linked()
      local lines = traced(link)
      game.fire("PLAYER_ENTERING_WORLD", false, false)
      game.instance = { true, "party" }
      game.fire("PLAYER_ENTERING_WORLD", false, false)
      game.fire("PLAYER_ENTERING_WORLD", false, false)
      game.instance = { false, "none" }
      game.fire("PLAYER_ENTERING_WORLD", false, false)
      assert.same({ "entered an instance (party)", "left an instance (party)" }, lines)
    end)

    it("reports leaving the group or the group disbanding", function()
      local game, link = linked()
      local lines = traced(link)
      game.fire("GROUP_LEFT")
      assert.same({ "left the group, or it disbanded" }, lines)
    end)
  end)

  it("tells whether the link is up, why not, and how many peers it has", function()
    local game = wow()
    local link = game.load("Game/ChannelLink.lua", {}).ChannelLink
    link.start(fakeCore(), function() end)
    assert.same({ up = false, reason = "no Crew", peers = 0, lockdown = false }, link.state())

    link.setCrew({ channel = CHANNEL, password = "pw" })
    game.advance(11)
    game.fire("CHAT_MSG_CHANNEL_LIST", "*Bob, Cat-Realm", nil, nil, "5. " .. CHANNEL, nil, nil, nil, nil, CHANNEL)
    assert.same({ up = true, peers = 2, lockdown = false }, link.state())

    game.instance = { true, "party" }
    game.lockdown = true
    game.fire("ADDON_RESTRICTION_STATE_CHANGED", 1, 1)
    assert.same({ up = false, reason = "lockdown", peers = 2, instance = "party", lockdown = true }, link.state())
  end)

  -- WoW: channel join and leave notices carry text, sender, language, then
  -- arg 4 channel name, arg 8 channel index, arg 9 base name.
  local function notice(sender, arg4, index, base)
    return "", sender, "", arg4, sender, "", 0, index, base
  end

  it("traces every join and leave notice with its channel arguments, for any channel", function()
    local game, link = linked()
    local lines = {}
    link.setTrace(function(line) lines[#lines + 1] = line end)
    game.fire("CHAT_MSG_CHANNEL_LEAVE", notice("Bob", "7. Friends", 7, "Friends"))
    game.fire("CHAT_MSG_CHANNEL_JOIN", notice("Dan", "5", 5, ""))
    game.fire("CHAT_MSG_CHANNEL_LEAVE", notice("Cat-Realm", "5. " .. CHANNEL, 5, CHANNEL))
    assert.same({
      'channel leave: Bob · arg 4 "7. Friends" · arg 8 7 · arg 9 "Friends" (other channel)',
      'channel join: Dan · arg 4 "5" · arg 8 5 · arg 9 "" (other channel)',
      'channel leave: Cat-Realm · arg 4 "5. ' .. CHANNEL .. '" · arg 8 5 · arg 9 "' .. CHANNEL .. '" (Crew channel)',
      "peer removed: Cat-Realm (left the channel)",
    }, lines)
  end)

  it("traces secret channel arguments without reading them", function()
    local game, link = linked()
    local lines = {}
    link.setTrace(function(line) lines[#lines + 1] = line end)
    game.fire("CHAT_MSG_CHANNEL_LEAVE", notice(game.secret(), game.secret(), game.secret(), nil))
    assert.same({ "channel leave: secret · arg 4 secret · arg 8 secret · arg 9 nil (other channel)" }, lines)
  end)

  describe("member list trace", function()
    -- WoW: a channel member list carries text, then arg 4 channel name,
    -- arg 8 channel index, arg 9 base name.
    local function list(text, arg4, index, base)
      return text, "", "", arg4, "", "", 0, index, base
    end

    local function joining()
      local game = wow()
      local link = game.load("Game/ChannelLink.lua", {}).ChannelLink
      local lines = {}
      link.setTrace(function(line) lines[#lines + 1] = line end)
      link.start(fakeCore(), function() end)
      link.setCrew({ channel = CHANNEL, password = "pw" })
      return game, lines
    end

    local function listLines(lines)
      local found = {}
      for _, line in ipairs(lines) do
        if line:find("^member list") then found[#found + 1] = line end
      end
      return found
    end

    it("traces the first Crew member list after joining, with its channel arguments, and no later one", function()
      local game, lines = joining()
      game.advance(11)
      game.fire("CHAT_MSG_CHANNEL_LIST", list("*Bob, Cat-Realm", "5. " .. CHANNEL, 5, CHANNEL))
      game.fire("CHAT_MSG_CHANNEL_LIST", list("*Bob, Cat-Realm, Dan", "5. " .. CHANNEL, 5, CHANNEL))
      assert.same({
        'member list: 2 names · arg 4 "5. ' .. CHANNEL .. '" · arg 8 5 · arg 9 "' .. CHANNEL .. '" (Crew channel)',
      }, listLines(lines))
    end)

    it("traces each member list it ignores, and why, once per channel arguments and why", function()
      local game, lines = joining()
      game.fire("CHAT_MSG_CHANNEL_LIST", list("Bob", "5. " .. CHANNEL, 5, CHANNEL))
      game.advance(11)
      game.fire("CHAT_MSG_CHANNEL_LIST", list("Bob, Dan", "7. Friends", 7, "Friends"))
      game.fire("CHAT_MSG_CHANNEL_LIST", list("Bob", "7. Friends", 7, "Friends"))
      game.fire("CHAT_MSG_CHANNEL_LIST", list("Bob", "8. Trade", 8, "Trade"))
      game.fire("CHAT_MSG_CHANNEL_LIST", list(game.secret(), "5. " .. CHANNEL, 5, CHANNEL))
      game.fire("CHAT_MSG_CHANNEL_LIST", list(game.secret(), "5. " .. CHANNEL, 5, CHANNEL))
      game.fire("CHAT_MSG_CHANNEL_LIST", list(game.secret(), game.secret(), game.secret(), game.secret()))
      local crew = '"5. ' .. CHANNEL .. '" · arg 8 5 · arg 9 "' .. CHANNEL .. '"'
      assert.same({
        "member list: 1 name · arg 4 " .. crew .. " (ignored: not in the Crew channel yet)",
        'member list: 2 names · arg 4 "7. Friends" · arg 8 7 · arg 9 "Friends" (other channel)',
        'member list: 1 name · arg 4 "8. Trade" · arg 8 8 · arg 9 "Trade" (other channel)',
        "member list: text unreadable · arg 4 " .. crew .. " (Crew channel, ignored: text unreadable)",
        "member list: text unreadable · arg 4 secret · arg 8 secret · arg 9 secret (other channel)",
      }, listLines(lines))
    end)

    it("traces them again after joining the channel again", function()
      local game, lines = joining()
      game.advance(11)
      game.fire("CHAT_MSG_CHANNEL_LIST", list("Bob", "7. Friends", 7, "Friends"))
      game.fire("CHAT_MSG_CHANNEL_NOTICE", "YOU_LEFT", "", "", "", "", "", "", 5, CHANNEL)
      game.fire("ADDON_RESTRICTION_STATE_CHANGED", 1, 0)
      game.fire("CHAT_MSG_CHANNEL_LIST", list("Bob", "7. Friends", 7, "Friends"))
      assert.equal(2, #listLines(lines))
    end)
  end)
end)
