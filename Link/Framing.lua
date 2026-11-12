-- Framing: splits a message into chunks an addon whisper can carry, and puts
-- the chunks received back together. Pure: the links hand it strings and a
-- sender's name. Every chunk says which message it belongs to, where in it
-- and of how many, so chunks may arrive in any order and two messages from
-- one sender may interleave; a message is given back only once every chunk
-- is in, and one that stays incomplete is reported lost.
-- See docs/design/code-structure.md (the link port) and docs/adr/0007.

local _, ns = ...

local Framing = {}
Framing.__index = Framing
ns.Framing = Framing

-- The most the game carries in one addon message.
local CHUNK_SIZE = 255
-- What every chunk starts with. An older BFF, which got whole messages from
-- AceComm, reads it as protocol 2 (Codec's header) and shows its
-- out-of-date notice. It also keeps a chunk from starting with a byte
-- AceComm treats as multipart control (\001 to \004): BFF still registers
-- with AceComm to read protocol 1.
local MARKER = "2|"
-- After the marker: the message id, the chunk's index and the total, two
-- digits each in base 62.
local DIGITS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
local BASE = #DIGITS
local LIMIT = BASE * BASE
local HEADER = #MARKER + 6
-- A message with no new chunk for this many seconds is lost.
Framing.LOST_AFTER = 30
local LOST_AFTER = Framing.LOST_AFTER

-- How many bytes of a message fit in one chunk.
Framing.ROOM = CHUNK_SIZE - HEADER

local VALUES = {}
for i = 1, BASE do VALUES[DIGITS:byte(i)] = i - 1 end

local function digits(value)
  local high = math.floor(value / BASE)
  return DIGITS:sub(high + 1, high + 1) .. DIGITS:sub(value % BASE + 1, value % BASE + 1)
end

-- The number two digits at `position` stand for, or nil.
local function number(text, position)
  local high, low = VALUES[text:byte(position)], VALUES[text:byte(position + 1)]
  return high and low and high * BASE + low
end

local function nothing() end

-- deps: now() in seconds, and optionally:
--   random(): 0 up to 1, for the first message id, so a sender who reloads
--     rarely reuses the id of a message still incomplete at a receiver
--   lost(sender, got, total): a message from this sender stayed
--     incomplete, with how many of its chunks came
function Framing.new(deps)
  return setmetatable({
    now = deps.now,
    lost = deps.lost or nothing,
    nextId = deps.random and math.floor(deps.random() * LIMIT) % LIMIT or 0,
    -- Incomplete messages: sender -> id -> { total, count, at (when the
    -- last new chunk came), parts (index -> text) }.
    partial = {},
  }, Framing)
end

-- How many chunks a message of this many bytes takes.
function Framing.count(size)
  return math.max(1, math.ceil(size / Framing.ROOM))
end

-- Whether a string received is a chunk, and not a whole protocol 1 message.
function Framing.isChunk(text)
  return text:sub(1, #MARKER) == MARKER
end

-- The message as chunks, in order, each at most 255 bytes.
function Framing:split(message)
  local total = Framing.count(#message)
  assert(total < LIMIT, "message too long to frame")
  local id = digits(self.nextId)
  self.nextId = (self.nextId + 1) % LIMIT
  local chunks = {}
  for index = 1, total do
    local from = (index - 1) * Framing.ROOM + 1
    chunks[index] = MARKER .. id .. digits(index) .. digits(total) .. message:sub(from, from + Framing.ROOM - 1)
  end
  return chunks
end

-- A chunk from a sender (whatever names them: two spellings are two
-- senders). Returns the whole message once its last missing
-- chunk is in, with how many chunks it came in; nil until then, and for a
-- chunk that can't be read.
function Framing:receive(sender, chunk)
  if not Framing.isChunk(chunk) or #chunk < HEADER then return nil end
  local id = chunk:sub(#MARKER + 1, #MARKER + 2)
  local index, total = number(chunk, #MARKER + 3), number(chunk, #MARKER + 5)
  if not number(id, 1) or not index or not total or index < 1 or index > total then return nil end
  local part = chunk:sub(HEADER + 1)
  if total == 1 then return part, 1 end

  local messages = self.partial[sender]
  if not messages then
    messages = {}
    self.partial[sender] = messages
  end
  local message = messages[id]
  if message and message.parts[index] == part then return nil end
  -- The same id with another total, or other text where a chunk already
  -- is, is a new message: the sender reloaded and reused the id.
  if not message or message.total ~= total or message.parts[index] then
    message = { total = total, count = 0, parts = {} }
    messages[id] = message
  end
  message.parts[index] = part
  message.count = message.count + 1
  message.at = self.now()
  if message.count < total then return nil end

  messages[id] = nil
  if next(messages) == nil then self.partial[sender] = nil end
  return table.concat(message.parts), total
end

-- Once a second: reports each message that has waited too long. Reported
-- after the pass, since whoever hears of it may hand in a chunk.
function Framing:tick()
  local now = self.now()
  local lost = {}
  for sender, messages in pairs(self.partial) do
    for id, message in pairs(messages) do
      if now - message.at >= LOST_AFTER then
        messages[id] = nil
        lost[#lost + 1] = { sender = sender, message = message }
      end
    end
    if next(messages) == nil then self.partial[sender] = nil end
  end
  for _, item in ipairs(lost) do self.lost(item.sender, item.message.count, item.message.total) end
end

-- A sender is gone: their incomplete messages are dropped, unreported.
function Framing:forget(sender)
  self.partial[sender] = nil
end

-- Everyone's incomplete messages are dropped, unreported.
function Framing:clear()
  self.partial = {}
end
