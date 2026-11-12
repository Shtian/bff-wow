-- Presence: who is in the Crew channel and can be whispered. Pure: the
-- channel link reads the game (events, names, notices) and tells Presence in
-- plain names; Presence answers who to whisper, whether the first member
-- list is in, and whether a chat notice is about one of ours. It decodes no
-- messages and knows nothing about Members.
-- See docs/design/code-structure.md (the link port).

local _, ns = ...

local Presence = {}
Presence.__index = Presence
ns.Presence = Presence

-- How long to wait for the first member list before being ready anyway (a
-- channel of one may send none).
local LIST_WAIT = 5
-- Messages whispered by someone not (yet) known to be in the channel wait
-- this long for a member list that shows them, and at most this many.
local STRANGER_WAIT = 10
local STRANGER_MAX = 20
-- After "No player named ...", how long more of them for that name (queued
-- whispers, later chunks) stay out of chat.
local NOT_FOUND_HIDE = 30
-- A "Player is offline." within this long after a failed send to one peer
-- is about them.
local OFFLINE_WINDOW = 3
-- An unreadable notice within this long after a whisper may be about it.
local UNREADABLE_WINDOW = 5

local OFFLINE_TEXT = "Player is offline."

local function nothing() end

-- deps: now() in seconds, and optionally:
--   key(name): what makes two spellings the same Character ("Name-Realm"
--     and "name"); lower case if left out
--   trace(line): the sync trace
--   deliver(message): a held message whose sender turned out to be a peer,
--     or a message from a peer
--   ready(why): the first member list since start() is in, or the wait ran out
--   arrived(): a member list showed a new peer while ready
--   gone(name): a peer is gone
--   askList(): a fresh member list would help
function Presence.new(deps)
  return setmetatable({
    now = deps.now,
    key = deps.key or string.lower,
    trace = deps.trace or nothing,
    on = {
      deliver = deps.deliver or nothing,
      ready = deps.ready or nothing,
      arrived = deps.arrived or nothing,
      gone = deps.gone or nothing,
      askList = deps.askList or nothing,
    },
    -- The other Characters in the channel: key -> the name to whisper.
    peers = {},
    -- Senders not yet in peers: key -> { name, since, messages }.
    strangers = {},
    -- Peers whispered after they logged out: key -> when the first
    -- "No player named ..." for them came.
    missed = {},
    -- Peers a send failed to: key -> when the last chunk failed. And when a
    -- "Player is offline." was last put down to one of them, so the chat
    -- filter hides it whether it runs before or after the event.
    failedAt = {},
    offlineMatched = nil,
    -- Names with a whisper still in the send queue, and key -> when the
    -- last chunk left. A peer's leaving cancels neither, so a "No player
    -- named ..." for them can still come (#160). Never cleared with the
    -- peers: the queue outlives them.
    queued = {},
    lastChunk = {},
    lastWhisper = nil,
    -- When start() was called, while the first member list is awaited.
    waitingSince = nil,
    isReady = false,
  }, Presence)
end

local function clear(self, why)
  if next(self.peers) then self.trace(("peers cleared (%s)"):format(why)) end
  self.peers, self.strangers, self.missed, self.failedAt = {}, {}, {}, {}
  self.isReady = false
  self.waitingSince = nil
end

-- The player joined the channel: everyone known is forgotten, and the wait
-- for the first member list starts.
function Presence:start()
  clear(self, "joined the channel")
  self.waitingSince = self.now()
end

-- The Crew changed: everyone known is forgotten, and nothing is awaited.
function Presence:stop()
  clear(self, "Crew changed")
end

-- Whether the first member list since start() is in, or the wait ran out.
function Presence:ready()
  return self.isReady
end

local function deliverHeld(self, key)
  local waiting = self.strangers[key]
  self.strangers[key] = nil
  if not waiting then return end
  self.trace(("  delivering %d held whispers from %s"):format(#waiting.messages, self.peers[key]))
  for _, message in ipairs(waiting.messages) do self.on.deliver(message) end
end

-- Returns true if the name is new. why is for the trace.
local function add(self, name, why)
  if name == "" then return false end
  local key = self.key(name)
  if self.peers[key] then return false end
  self.peers[key] = name
  self.trace(("peer added: %s (%s)"):format(name, why))
  deliverHeld(self, key)
  return true
end

local function remove(self, name, why)
  if name == "" then return end
  local key = self.key(name)
  if self.peers[key] then self.trace(("peer removed: %s (%s)"):format(self.peers[key], why)) end
  self.peers[key] = nil
end

-- A peer who logged out before their leave notice came.
local function drop(self, key, why)
  local name = self.peers[key]
  if not name then return end
  remove(self, name, why)
  self.on.gone(name)
end

-- A member list's names, without the player's own. Long lists may come in
-- several parts, so a list only ever adds. The first one since start()
-- brings ready; a new name in a later one is reported as arrived.
function Presence:listed(names)
  local found = false
  for _, name in ipairs(names) do
    if add(self, name, "member list") then found = true end
  end
  if not self.isReady then
    self.isReady = true
    self.on.ready("member list")
  elseif found then
    self.on.arrived()
  end
end

-- A join notice for the channel.
function Presence:joined(name)
  add(self, name, "joined the channel")
end

-- A leave notice for the channel: they logged out.
function Presence:left(name)
  remove(self, name, "left the channel")
  self.on.gone(name)
end

-- A message whispered by a name. Only a peer's counts; one from anyone
-- else, usually a Character who just joined, waits for a member list that
-- shows them.
function Presence:heard(name, message)
  local key = self.key(name)
  if self.peers[key] then
    self.on.deliver(message)
    return
  end
  local waiting = self.strangers[key]
  if not waiting then
    waiting = { name = name, since = self.now(), messages = {} }
    self.strangers[key] = waiting
    self.trace(("holding whispers from %s: not in the member list yet"):format(name))
    self.on.askList()
  end
  if #waiting.messages < STRANGER_MAX then
    waiting.messages[#waiting.messages + 1] = message
  else
    self.trace(("dropped a whisper from %s: %d already held"):format(name, STRANGER_MAX))
  end
end

-- Once a second.
function Presence:tick()
  local now = self.now()
  if not self.isReady and self.waitingSince and now - self.waitingSince >= LIST_WAIT then
    self.isReady = true
    self.on.ready("no member list after " .. LIST_WAIT .. " s")
  end
  for key, waiting in pairs(self.strangers) do
    if now - waiting.since >= STRANGER_WAIT then
      self.strangers[key] = nil
      self.trace(("dropped %d whispers from %s: not in the member list after %d s"):format(
        #waiting.messages, waiting.name, STRANGER_WAIT))
    end
  end
end

-- Who to whisper, sorted: every peer, or only the one named `to` (none if
-- they aren't a peer).
function Presence:targets(to)
  if to then return { self.peers[self.key(to)] } end
  local keys = {}
  for key in pairs(self.peers) do keys[#keys + 1] = key end
  table.sort(keys)
  local names = {}
  for i, key in ipairs(keys) do names[i] = self.peers[key] end
  return names
end

function Presence:has(name)
  return self.peers[self.key(name)] ~= nil
end

function Presence:count()
  local count = 0
  for _ in pairs(self.peers) do count = count + 1 end
  return count
end

-- A whisper to a name entered the send queue.
function Presence:whispered(name)
  self.queued[self.key(name)] = true
  self.lastWhisper = self.now()
end

-- A chunk of a whisper to a name left the queue: whether any whisper to
-- them is still queued, and whether this chunk failed (anything but a
-- throttle).
function Presence:chunk(name, queued, failed)
  local key = self.key(name)
  self.lastChunk[key] = self.now()
  self.queued[key] = queued and true or nil
  if failed then self.failedAt[key] = self.now() end
end

-- Whether a "No player named ..." for a name is about a Character BFF
-- whispered: a peer, one just dropped for it, or one who left with
-- whispers to them still queued or just sent.
function Presence:hidesNotFound(name)
  local key, now = self.key(name), self.now()
  local since, chunk = self.missed[key], self.lastChunk[key]
  if self.peers[key] or (since and now - since < NOT_FOUND_HIDE) then return true end
  return self.queued[key] == true or (chunk ~= nil and now - chunk < NOT_FOUND_HIDE)
end

local function peerKeys(self)
  local keys = {}
  for key in pairs(self.peers) do keys[#keys + 1] = key end
  table.sort(keys)
  return table.concat(keys, ", ")
end

-- "No player named ...": they logged out, and the leave notice hasn't come
-- (or won't).
function Presence:notFound(name)
  local key = self.key(name)
  if not self:hidesNotFound(name) then
    self.trace(("notice: No player named %s · not a peer (peers: %s)"):format(name, peerKeys(self)))
    return
  end
  self.trace(("notice: No player named %s%s"):format(name, self.peers[key] and "" or " (already gone)"))
  if self.peers[key] then
    self.missed[key] = self.now()
    drop(self, key, "No player named")
  end
end

-- The peer a "Player is offline." is about: it names no one, so only the
-- one peer a send failed to just before, or nil if none or several (an
-- account that can't send fails to everyone).
local function offlinePeer(self)
  local found
  for key, time in pairs(self.failedAt) do
    if self.now() - time < OFFLINE_WINDOW and self.peers[key] then
      if found then return nil end
      found = key
    end
  end
  return found
end

-- Whether a "Player is offline." is about a peer.
function Presence:hidesOffline()
  return offlinePeer(self) ~= nil
    or (self.offlineMatched ~= nil and self.now() - self.offlineMatched < OFFLINE_WINDOW)
end

-- "Player is offline."
function Presence:offline()
  local key = offlinePeer(self)
  self.trace(("notice: %s (%s)"):format(OFFLINE_TEXT, key and self.peers[key] or "not ours, or not clear whose"))
  if key then
    self.offlineMatched = self.now()
    drop(self, key, OFFLINE_TEXT)
  end
end

-- A notice the game wouldn't let the channel link read. Returns how many
-- seconds after the last whisper it came if that is soon enough to be
-- about it, else nil.
function Presence:unreadable()
  local since = self.lastWhisper and self.now() - self.lastWhisper
  return since and since < UNREADABLE_WINDOW and since or nil
end
