local load = require("tests.load")

local Framing = load().Framing

-- A Framing with its own clock, recording every sender a message was
-- reported lost from, and how many of its chunks came ("2 of 3").
local function newFraming(random)
  local world = { time = 100, lost = {}, got = {} }
  world.framing = Framing.new({
    now = function() return world.time end,
    random = random,
    lost = function(sender, got, total)
      world.lost[#world.lost + 1] = sender
      world.got[#world.got + 1] = got .. " of " .. total
    end,
  })
  -- Moves the clock on, ticking once a second as the links do.
  function world.advance(seconds)
    for _ = 1, seconds do
      world.time = world.time + 1
      world.framing:tick()
    end
  end
  return world, world.framing
end

-- A message of `size` bytes that says where each byte belongs.
local function text(size)
  local parts = {}
  for i = 1, math.ceil(size / 10) do parts[i] = ("%09d."):format(i) end
  return table.concat(parts):sub(1, size)
end

-- Hands chunks to a Framing in the order given: every message completed.
local function receive(framing, sender, chunks, order)
  local done = {}
  for _, index in ipairs(order) do
    done[#done + 1] = framing:receive(sender, chunks[index])
  end
  return done
end

describe("Framing", function()
  describe("splitting", function()
    it("sends a message that fits as one chunk", function()
      local _, framing = newFraming()
      assert.equal(1, #framing:split(text(Framing.ROOM)))
      assert.equal(1, Framing.count(Framing.ROOM))
    end)

    it("splits a longer message into chunks of at most 255 bytes", function()
      local _, framing = newFraming()
      local chunks = framing:split(text(Framing.ROOM * 2 + 1))
      assert.equal(3, #chunks)
      assert.equal(3, Framing.count(Framing.ROOM * 2 + 1))
      assert.equal(255, #chunks[1])
      assert.equal(255, #chunks[2])
      for _, chunk in ipairs(chunks) do assert.is_true(#chunk <= 255) end
    end)

    it("starts every chunk with a marker an older BFF reads as a newer protocol", function()
      local ns = load()
      local chunks = ns.Framing.new({ now = function() return 0 end }):split(text(600))
      for _, chunk in ipairs(chunks) do
        assert.equal("2|", chunk:sub(1, 2))
        assert.is_true(ns.Framing.isChunk(chunk))
      end
      -- An older BFF's Codec read "<protocol>|" and compared it with its own, 1.
      assert.is_true(tonumber(chunks[1]:match("^(%d+)|")) > 1)
    end)

    it("never starts a chunk with a byte AceComm treats as multipart control", function()
      -- Whatever the message holds, and for every message id.
      local _, framing = newFraming()
      local message = ("\001\002\003\004"):rep(200)
      for _ = 1, 4000 do
        for _, chunk in ipairs(framing:split(message)) do
          assert.is_nil(chunk:find("^[%z\001-\009]"))
        end
      end
    end)

    it("doesn't take a protocol 1 message for a chunk", function()
      assert.is_false(Framing.isChunk("1|whatever"))
      assert.is_false(Framing.isChunk(""))
    end)
  end)

  describe("reassembling", function()
    it("gives back a one-chunk message at once", function()
      local _, sender = newFraming()
      local _, receiver = newFraming()
      assert.same({ "hello" }, receive(receiver, "Bob", sender:split("hello"), { 1 }))
    end)

    it("delivers only once every chunk is in", function()
      local _, sender = newFraming()
      local _, receiver = newFraming()
      local message = text(700)
      local chunks = sender:split(message)
      assert.equal(3, #chunks)
      assert.is_nil(receiver:receive("Bob", chunks[1]))
      assert.is_nil(receiver:receive("Bob", chunks[2]))
      assert.equal(message, receiver:receive("Bob", chunks[3]))
    end)

    it("puts chunks that arrive out of order back in order", function()
      local _, sender = newFraming()
      local _, receiver = newFraming()
      local message = text(1200)
      local chunks = sender:split(message)
      assert.equal(5, #chunks)
      assert.same({ message }, receive(receiver, "Bob", chunks, { 3, 1, 5, 4, 2 }))
    end)

    it("keeps two interleaved messages from one sender apart", function()
      local _, sender = newFraming()
      local _, receiver = newFraming()
      local first, second = text(600), ("x"):rep(500)
      local a, b = sender:split(first), sender:split(second)
      assert.is_nil(receiver:receive("Bob", a[1]))
      assert.is_nil(receiver:receive("Bob", b[1]))
      assert.is_nil(receiver:receive("Bob", b[3]))
      assert.is_nil(receiver:receive("Bob", a[2]))
      assert.equal(second, receiver:receive("Bob", b[2]))
      assert.equal(first, receiver:receive("Bob", a[3]))
    end)

    it("keeps two senders using the same message id apart", function()
      local _, bob = newFraming()
      local _, cat = newFraming()
      local _, receiver = newFraming()
      local fromBob, fromCat = text(400), ("y"):rep(400)
      local a, b = bob:split(fromBob), cat:split(fromCat)
      assert.is_nil(receiver:receive("Bob", a[1]))
      assert.is_nil(receiver:receive("Cat", b[1]))
      assert.equal(fromBob, receiver:receive("Bob", a[2]))
      assert.equal(fromCat, receiver:receive("Cat", b[2]))
    end)

    it("ignores the same chunk arriving twice", function()
      local _, sender = newFraming()
      local _, receiver = newFraming()
      local message = text(400)
      local chunks = sender:split(message)
      assert.same({ message }, receive(receiver, "Bob", chunks, { 1, 1, 2 }))
    end)

    it("starts over when a message id comes back with another number of chunks", function()
      -- A sender who reloaded can reuse an id while its old message is
      -- still incomplete here.
      local _, before = newFraming()
      local _, after = newFraming()
      local world, receiver = newFraming()
      local old, new = before:split(text(700)), after:split(("z"):rep(400))
      assert.is_nil(receiver:receive("Bob", old[1]))
      assert.is_nil(receiver:receive("Bob", new[1]))
      assert.equal(("z"):rep(400), receiver:receive("Bob", new[2]))
      world.advance(60)
      assert.same({}, world.lost)
    end)

    it("starts over when a message id comes back with other text in a chunk it has", function()
      local _, before = newFraming()
      local _, after = newFraming()
      local _, receiver = newFraming()
      local old, new = before:split(text(700)), after:split(("z"):rep(700))
      assert.is_nil(receiver:receive("Bob", old[1]))
      assert.is_nil(receiver:receive("Bob", old[2]))
      assert.is_nil(receiver:receive("Bob", new[1]))
      assert.is_nil(receiver:receive("Bob", new[2]))
      assert.equal(("z"):rep(700), receiver:receive("Bob", new[3]))
    end)

    it("drops a chunk it can't read", function()
      local world, receiver = newFraming()
      for _, chunk in ipairs({ "2|", "2|00", "2|000201x", "2|00010000x", "2|00000001x", "2|!!010001x" }) do
        assert.is_nil(receiver:receive("Bob", chunk))
      end
      world.advance(60)
      assert.same({}, world.lost)
    end)

    it("starts message ids where random says, and wraps around", function()
      local _, sender = newFraming(function() return 0.9999 end)
      local _, receiver = newFraming()
      for i = 1, 5 do
        local message = text(300 + i)
        assert.same({ message }, receive(receiver, "Bob", sender:split(message), { 1, 2 }))
      end
    end)
  end)

  describe("a lost chunk", function()
    it("is reported once, 30 s after the message's last chunk came in", function()
      local _, sender = newFraming()
      local world, receiver = newFraming()
      local chunks = sender:split(text(700))
      receiver:receive("Bob", chunks[1])
      world.advance(20)
      receiver:receive("Bob", chunks[3])
      world.advance(29)
      assert.same({}, world.lost)
      world.advance(1)
      assert.same({ "Bob" }, world.lost)
      assert.same({ "2 of 3" }, world.got)
      world.advance(120)
      assert.same({ "Bob" }, world.lost)
    end)

    it("makes a chunk that turns up later the start of a message that is lost too", function()
      local _, sender = newFraming()
      local world, receiver = newFraming()
      local chunks = sender:split(text(400))
      receiver:receive("Bob", chunks[1])
      world.advance(30)
      assert.is_nil(receiver:receive("Bob", chunks[2]))
      world.advance(30)
      assert.same({ "Bob", "Bob" }, world.lost)
    end)

    it("doesn't hold up the messages after it", function()
      local _, sender = newFraming()
      local world, receiver = newFraming()
      local lost, fine = sender:split(text(400)), sender:split(text(500))
      receiver:receive("Bob", lost[2])
      assert.same({ text(500) }, receive(receiver, "Bob", fine, { 1, 2, 3 }))
      world.advance(30)
      assert.same({ "Bob" }, world.lost)
    end)

    it("isn't reported for a sender who is forgotten", function()
      local _, sender = newFraming()
      local world, receiver = newFraming()
      receiver:receive("Bob", sender:split(text(400))[1])
      receiver:receive("Cat", sender:split(text(400))[1])
      receiver:forget("Bob")
      world.advance(30)
      assert.same({ "Cat" }, world.lost)
    end)

    it("isn't reported once everyone is forgotten", function()
      local _, sender = newFraming()
      local world, receiver = newFraming()
      receiver:receive("Bob", sender:split(text(400))[1])
      receiver:clear()
      world.advance(30)
      assert.same({}, world.lost)
    end)
  end)
end)
