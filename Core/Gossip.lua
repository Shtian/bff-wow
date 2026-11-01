-- Gossip: when to talk. Two messages: a DIGEST lists the Member ids and
-- versions you hold, and DATA carries full records. Whoever holds something
-- newer than a DIGEST shows replies with DATA, whoever lacks something
-- replies with their own DIGEST, and a reply someone else already made is
-- dropped. Gossip talks only while the link is up (and in a Crew) and
-- not paused; a change made meanwhile goes out once it talks again.
-- See the sync resolution on #8 and docs/design/code-structure.md.

local _, ns = ...

local Gossip = {}
Gossip.__index = Gossip
ns.Gossip = Gossip

local REPLY_MIN, REPLY_MAX = 1, 4
local ZONE_DELAY = 10
local HEARTBEAT = 5 * 60
-- Ten entries of id and version always fit one 255-byte message.
local DIGEST_SIZE = 10

-- ledger; now() and random() from Core; send(message) encodes and hands a
-- message to the link; beforeOwnSend() runs just before own DATA goes out,
-- so whatever only rides a send (where you stand) can be written first.
function Gossip.new(ledger, now, random, send, beforeOwnSend)
  return setmetatable({
    ledger = ledger,
    now = now,
    random = random,
    send = send,
    beforeOwnSend = beforeOwnSend,
    linkUp = false,
    paused = false,
    open = false,
    -- Own record changed since own DATA last went out, and when it's due.
    dirty = false,
    dataDue = nil,
    lastOwnSent = 0,
    -- A DIGEST to send, and the ids it is meant to fetch; nil wanted means
    -- it goes out whatever others send.
    digestDue = nil,
    wanted = nil,
    -- DATA owed in reply: id -> true, and when it's due.
    owed = {},
    owedDue = nil,
  }, Gossip)
end

local function replyDelay(self)
  return REPLY_MIN + math.floor(self.random() * (REPLY_MAX - REPLY_MIN + 1))
end

local function isEmpty(set)
  return next(set) == nil
end

local function cancelDigest(self)
  self.digestDue, self.wanted = nil, nil
end

local function cancelOwed(self)
  self.owed, self.owedDue = {}, nil
end

local function sendDigest(self)
  cancelDigest(self)
  self.send({ type = "DIGEST", versions = self.ledger:digest(DIGEST_SIZE) })
end

local function sendOwn(self)
  if self.beforeOwnSend then self.beforeOwnSend() end
  local own = self.ledger:own()
  self.dirty, self.dataDue = false, nil
  self.lastOwnSent = self.now()
  if own then self.send({ type = "DATA", records = { own } }) end
end

local function sendOwed(self)
  local records = {}
  for id in pairs(self.owed) do
    local record = self.ledger:record(id)
    if record then records[#records + 1] = record end
  end
  cancelOwed(self)
  if #records > 0 then self.send({ type = "DATA", records = records }) end
end

-- Starts or stops talking. Starting sends a fresh DIGEST, plus own DATA if
-- the own record changed meanwhile. Stopping drops replies owed, since the
-- DIGEST on starting again asks for whatever is still missing.
local function update(self)
  local open = self.linkUp and not self.paused
  if open == self.open then return end
  self.open = open
  cancelOwed(self)
  cancelDigest(self)
  if not open then return end
  sendDigest(self)
  if self.dirty then sendOwn(self) else self.lastOwnSent = self.now() end
end

-- Whether the link is up and Core is in a Crew. Every change to up sends a
-- fresh DIGEST.
function Gossip:setLink(up)
  self.linkUp = up
  update(self)
end

-- Pause sharing: fully silent, so others see you as offline.
function Gossip:setPaused(paused)
  self.paused = paused
  update(self)
end

-- Sends a message right away whether or not Gossip is talking (leaving the
-- Crew).
function Gossip:sendNow(message)
  self.send(message)
end

-- The own record changed. urgency is "now" (ding, death, new Character,
-- display name, Main), "soon" (zone, debounced) or "later" (XP, gold, Play times:
-- waits for the next send or the heartbeat). Where you stand never calls
-- this: it is written just before own DATA goes out (beforeOwnSend).
function Gossip:ownChanged(urgency)
  self.dirty = true
  local due
  if urgency == "now" then
    due = self.now()
  elseif urgency == "soon" then
    due = self.now() + ZONE_DELAY
  end
  if due and (self.dataDue == nil or due < self.dataDue) then self.dataDue = due end
end

-- How urgent a change to the Character being played is, from the
-- Character before (nil if new) and after.
function Gossip.urgency(before, after)
  if before == nil or before.level ~= after.level or before.deaths ~= after.deaths then
    return "now"
  elseif before.zone ~= after.zone then
    return "soon"
  end
  return "later"
end

-- A DIGEST from someone else: owe DATA for what we hold newer, and a DIGEST
-- of our own if they hold something newer or unknown to us.
function Gossip:digestReceived(versions)
  local ledger = self.ledger
  -- Their DIGEST fetches whatever ours was going to.
  if self.wanted then
    local covered = true
    for id in pairs(self.wanted) do
      local theirs = versions[id] or 0
      if theirs > ledger:version(id) then covered = false end
    end
    if covered then cancelDigest(self) end
  end
  if not self.open then return end

  for id, version in pairs(versions) do
    if type(id) == "string" and type(version) == "number" and id ~= ledger:memberId()
        and not ledger:isRemoved(id) and version > ledger:version(id) then
      if not self.digestDue then
        self.digestDue, self.wanted = self.now() + replyDelay(self), {}
      end
      if self.wanted then self.wanted[id] = version end
    end
  end

  for id, record in ledger:records() do
    local theirs = versions[id]
    if type(theirs) ~= "number" or theirs < record.version then
      self.owed[id] = true
      self.owedDue = self.owedDue or self.now() + replyDelay(self)
    end
  end
end

-- A record that went out on the wire, after the Ledger has merged it.
function Gossip:recordSeen(id, version)
  local held = self.ledger:version(id)
  if self.owed[id] and version >= held then
    self.owed[id] = nil
    if isEmpty(self.owed) then self.owedDue = nil end
  end
  if self.wanted and self.wanted[id] and held >= self.wanted[id] then
    self.wanted[id] = nil
    if isEmpty(self.wanted) then cancelDigest(self) end
  end
end

-- A removed Member: no reply is owed for them, nor a DIGEST to fetch them.
function Gossip:forget(id)
  self.owed[id] = nil
  if isEmpty(self.owed) then self.owedDue = nil end
  if self.wanted and self.wanted[id] then
    self.wanted[id] = nil
    if isEmpty(self.wanted) then cancelDigest(self) end
  end
end

-- Sends a DIGEST now, so whoever holds something we lack replies with it.
function Gossip:askAround()
  if self.open then sendDigest(self) end
end

-- Called once a second: sends whatever is due.
function Gossip:tick()
  if not self.open then return end
  local now = self.now()
  if self.digestDue and now >= self.digestDue then sendDigest(self) end
  if self.owedDue and now >= self.owedDue then sendOwed(self) end
  if self.dataDue and now >= self.dataDue then
    sendOwn(self)
  elseif now - self.lastOwnSent >= HEARTBEAT then
    self.ledger:touch()
    sendOwn(self)
  end
end
