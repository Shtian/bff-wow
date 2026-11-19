local _, ns = ...

local Framing = {}
Framing.__index = Framing
ns.Framing = Framing

-- WoW: an addon message carries at most 255 bytes.
local CHUNK_SIZE = 255
-- WoW: AceComm-3.0 treats a message starting with \001 to \004 as multipart control.
local MARKER = "2|"
local DIGITS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
local BASE = #DIGITS
local LIMIT = BASE * BASE
local HEADER = #MARKER + 6
Framing.LOST_AFTER = 30
local LOST_AFTER = Framing.LOST_AFTER

Framing.ROOM = CHUNK_SIZE - HEADER

local VALUES = {}
for i = 1, BASE do VALUES[DIGITS:byte(i)] = i - 1 end

local function digits(value)
  local high = math.floor(value / BASE)
  return DIGITS:sub(high + 1, high + 1) .. DIGITS:sub(value % BASE + 1, value % BASE + 1)
end

local function number(text, position)
  local high, low = VALUES[text:byte(position)], VALUES[text:byte(position + 1)]
  return high and low and high * BASE + low
end

local function nothing() end

function Framing.new(deps)
  return setmetatable({
    now = deps.now,
    lost = deps.lost or nothing,
    nextId = deps.random and math.floor(deps.random() * LIMIT) % LIMIT or 0,
    partial = {},
  }, Framing)
end

function Framing.count(size)
  return math.max(1, math.ceil(size / Framing.ROOM))
end

function Framing.isChunk(text)
  return text:sub(1, #MARKER) == MARKER
end

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

function Framing:forget(sender)
  self.partial[sender] = nil
end

function Framing:clear()
  self.partial = {}
end
