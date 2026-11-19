local _, ns = ...

local Presence = {}
Presence.__index = Presence
ns.Presence = Presence

-- WoW: a channel with only the player in it may send no member list.
local LIST_WAIT = 5
local STRANGER_WAIT = 10
local STRANGER_MAX = 20
local NOT_FOUND_HIDE = 30
-- WoW: the member list can go on showing a Character who logged out.
local READD_WAIT = 300
local OFFLINE_WINDOW = 3
local UNREADABLE_WINDOW = 5

local SILENCE = 180
Presence.SILENCE = SILENCE
local RETRY = 300

local OFFLINE_TEXT = "Player is offline."

local function nothing() end

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
    peers = {},
    strangers = {},
    missed = {},
    -- WoW: a chat filter can run before or after the event handler.
    failedAt = {},
    offlineMatched = nil,
    -- WoW: leaving the channel doesn't empty ChatThrottleLib's queue, so a "No
    -- player named ..." can still come after a peer leaves.
    queued = {},
    lastChunk = {},
    lastWhisper = nil,
    unanswered = {},
    silent = {},
    isListening = false,
    lastTick = deps.now(),
    waitingSince = nil,
    isReady = false,
  }, Presence)
end

local function clear(self, why)
  if next(self.peers) then self.trace(("peers cleared (%s)"):format(why)) end
  self.peers, self.strangers, self.missed, self.failedAt = {}, {}, {}, {}
  self.unanswered, self.silent = {}, {}
  self.isReady = false
  self.waitingSince = nil
end

function Presence:start()
  clear(self, "joined the channel")
  self.waitingSince = self.now()
end

function Presence:stop()
  clear(self, "Crew changed")
end

function Presence:ready()
  return self.isReady
end

local function deliverHeld(self, key)
  local waiting = self.strangers[key]
  self.strangers[key] = nil
  if not waiting then return end
  self.trace(("  delivering %d held whispers from %s"):format(#waiting.messages, self.peers[key]))
  for _, message in ipairs(waiting.messages) do self.on.deliver(message, waiting.name) end
end

local function add(self, name, why)
  if name == "" then return false end
  local key = self.key(name)
  if self.peers[key] then return false end
  self.peers[key] = name
  self.missed[key] = nil
  self.trace(("peer added: %s (%s)"):format(name, why))
  deliverHeld(self, key)
  return true
end

local function remove(self, name, why)
  if name == "" then return end
  local key = self.key(name)
  if self.peers[key] then self.trace(("peer removed: %s (%s)"):format(self.peers[key], why)) end
  self.peers[key] = nil
  self.unanswered[key], self.silent[key] = nil, nil
end

local function drop(self, key, why)
  local name = self.peers[key]
  if not name then return end
  remove(self, name, why)
  self.on.gone(name)
end

local function reportedMissing(self, key)
  local since = self.missed[key]
  return since ~= nil and self.now() - since < READD_WAIT
end

-- WoW: a long member list can come in several parts.
function Presence:listed(names)
  local found = false
  for _, name in ipairs(names) do
    if not reportedMissing(self, self.key(name)) and add(self, name, "member list") then found = true end
  end
  if not self.isReady then
    self.isReady = true
    self.on.ready("member list")
  elseif found then
    self.on.arrived()
  end
end

function Presence:joined(name)
  add(self, name, "joined the channel")
end

function Presence:left(name)
  remove(self, name, "left the channel")
  self.on.gone(name)
end

-- WoW: a Character who just joined can whisper before a member list shows them.
function Presence:heard(name, message)
  local key = self.key(name)
  if reportedMissing(self, key) then add(self, name, "whispered again") end
  if self.peers[key] then
    self.unanswered[key] = nil
    if self.silent[key] then
      self.silent[key] = nil
      self.trace(("peer heard again: %s"):format(self.peers[key]))
    end
    self.on.deliver(message, name)
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

function Presence:holds(name)
  return self.strangers[self.key(name)] ~= nil
end

function Presence:vouched(name)
  add(self, name, "known Member")
end

function Presence:listening(isUp)
  if isUp and not self.isListening then
    for key in pairs(self.silent) do self.silent[key] = RETRY end
  end
  self.isListening = isUp
end

function Presence:tick()
  local now = self.now()
  local elapsed = now - self.lastTick
  self.lastTick = now
  if self.isListening then
    for key, since in pairs(self.silent) do self.silent[key] = since + elapsed end
    for key, waited in pairs(self.unanswered) do
      waited = waited + elapsed
      self.unanswered[key] = waited
      if waited >= SILENCE and not self.silent[key] then
        self.silent[key] = 0
        self.trace(("peer silent: %s (no whisper from them for %d s)"):format(self.peers[key], SILENCE))
      end
    end
  end
  if not self.isReady and self.waitingSince and now - self.waitingSince >= LIST_WAIT then
    self.isReady = true
    self.on.ready("no member list after " .. LIST_WAIT .. " s")
  end
  for key, since in pairs(self.missed) do
    if now - since >= READD_WAIT then self.missed[key] = nil end
  end
  for key, waiting in pairs(self.strangers) do
    if now - waiting.since >= STRANGER_WAIT then
      self.strangers[key] = nil
      self.trace(("dropped %d whispers from %s: not in the member list after %d s"):format(
        #waiting.messages, waiting.name, STRANGER_WAIT))
    end
  end
end

local function muted(self, key)
  local since = self.silent[key]
  return since ~= nil and since < RETRY
end

function Presence:targets(to)
  if to then
    local key = self.key(to)
    return { not muted(self, key) and self.peers[key] or nil }
  end
  local keys = {}
  for key in pairs(self.peers) do
    if not muted(self, key) then keys[#keys + 1] = key end
  end
  table.sort(keys)
  local names = {}
  for i, key in ipairs(keys) do names[i] = self.peers[key] end
  return names
end

function Presence:has(name)
  return self.peers[self.key(name)] ~= nil
end

function Presence:peer(name)
  return self.peers[self.key(name)]
end

function Presence:count()
  local count = 0
  for _ in pairs(self.peers) do count = count + 1 end
  return count
end

function Presence:whispered(name)
  local key = self.key(name)
  self.queued[key] = true
  self.lastWhisper = self.now()
  if self.peers[key] then self.unanswered[key] = self.unanswered[key] or 0 end
  if self.silent[key] then
    self.trace(("  trying silent peer again: %s"):format(self.peers[key]))
    self.silent[key] = 0
  end
end

function Presence:chunk(name, queued, failed)
  local key = self.key(name)
  self.lastChunk[key] = self.now()
  self.queued[key] = queued and true or nil
  if failed then self.failedAt[key] = self.now() end
end

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

-- WoW: the leave notice can come after "No player named ...", or never.
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

-- WoW: "Player is offline." names no one.
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

function Presence:hidesOffline()
  return offlinePeer(self) ~= nil
    or (self.offlineMatched ~= nil and self.now() - self.offlineMatched < OFFLINE_WINDOW)
end

function Presence:offline()
  local key = offlinePeer(self)
  self.trace(("notice: %s (%s)"):format(OFFLINE_TEXT, key and self.peers[key] or "not ours, or not clear whose"))
  if key then
    self.offlineMatched = self.now()
    drop(self, key, OFFLINE_TEXT)
  end
end

function Presence:unreadable()
  local since = self.lastWhisper and self.now() - self.lastWhisper
  return since and since < UNREADABLE_WINDOW and since or nil
end
