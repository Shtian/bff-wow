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
  local link = game.load("Game/ChannelLink.lua", {}).ChannelLink
  local core = fakeCore()
  link.start(core, function() end)
  link.setCrew({ channel = CHANNEL, password = "pw" })
  game.advance(11)
  game.fire("CHAT_MSG_CHANNEL_LIST", "*Bob, Cat-Realm", nil, nil, "5. " .. CHANNEL, nil, nil, nil, nil, CHANNEL)
  assert.equal(1, core.count("up"))
  return game, link, core
end

-- Who each whisper since `mark` went to.
local function targets(game, mark)
  local names = {}
  for i = (mark or 0) + 1, #game.whispers do names[#names + 1] = game.whispers[i].target end
  table.sort(names)
  return names
end

-- The game's AceComm callback for a whisper: one chunk failed.
local function fail(whisper)
  whisper.callback(whisper.arg, #whisper.text, #whisper.text, false)
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

  it("keeps the link up after a failed send, and tells Core who it failed to", function()
    local game, link, core = linked()
    link.send("1|data")
    for _, whisper in ipairs(game.whispers) do
      if whisper.target == "Cat-Realm" then fail(whisper) end
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
      if whisper.target == "Bob" then fail(whisper) end
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
    for _, whisper in ipairs(game.whispers) do fail(whisper) end
    game.advance(0)
    game.fire("CHAT_MSG_SYSTEM", "Player is offline.")
    assert.equal(0, core.count("gone"))
    assert.is_false(game.filters.CHAT_MSG_SYSTEM(nil, "CHAT_MSG_SYSTEM", "Player is offline."))
  end)

  it("keeps everyone after a Player is offline with no failed send near it", function()
    local game, link, core = linked()
    link.send("1|data")
    fail(game.whispers[1])
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
    fail(game.whispers[1])
    game.advance(0)
    assert.equal(1, core.count("gone", "Bob"))
    assert.equal(0, core.count("sendFailed"))
  end)
end)
