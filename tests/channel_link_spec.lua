local wow = require("tests.wow_stubs")

local CHANNEL = "BFFABCDEFG"

-- A Core that records what the link tells it.
local function fakeCore()
  local core = { calls = {} }
  for _, method in ipairs({ "up", "down", "gone", "sendFailed", "received" }) do
    core[method] = function(_, ...)
      core.calls[#core.calls + 1] = { method, ... }
    end
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

-- A channel link in the Crew's channel with Bob and Cat (on another realm),
-- link up.
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

-- Who each whisper since `mark` went to.
local function targets(game, mark)
  local names = {}
  for i = (mark or 0) + 1, #game.whispers do names[#names + 1] = game.whispers[i].target end
  table.sort(names)
  return names
end

-- The chunks another BFF would whisper for a message.
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
      -- Nothing is left queued for anyone.
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

      -- Cat's go on.
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

      -- The next message starts from its first chunk.
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

  -- The game's AceComm delivery: a BFF whisper from a Character.
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
    -- Silence is no one's logout: the Roster keeps its own rule.
    assert.equal(0, core.count("gone"))
    assert.equal(0, core.count("down"))
    assert.equal(2, link.state().peers)

    whisperFrom(game, "Bob")
    mark = #game.whispers
    link.send("1|digest")
    assert.same({ "Bob", "Cat-Realm" }, targets(game, mark))
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
    -- No down and up, so no DIGEST to everyone each minute.
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
    -- Someone new while up: Core hears down and up, for a fresh DIGEST.
    assert.equal(1, core.count("down"))
    assert.equal(2, core.count("up"))
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

  -- #160: a peer's leaving doesn't cancel the whispers queued for them.
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
      -- The one chunk ChatThrottleLib already had; the rest never go.
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
    -- Starts the trace: the lines it reports.
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
      -- The chat filter doesn't read it either.
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

  -- Channel notice arguments: text, sender, language, arg 4 (channel name),
  -- ..., arg 8 (channel index), arg 9 (base name).
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
end)
