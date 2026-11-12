-- Gossip: when to talk. Two messages: a DIGEST lists the Member ids and
-- versions you hold, and DATA carries full records. Whoever holds something
-- newer than a DIGEST shows replies with DATA, whoever lacks something
-- replies with their own DIGEST, and a reply someone else already made is
-- dropped. Gossip talks only while the link is up (and in a Crew) and
-- not paused; a change made meanwhile goes out once it talks again.
-- Messages can be lost on the way without anyone knowing, so DIGESTs also
-- go out on their own: one 20-30 s after own DATA (a friend who missed it
-- asks for it), one about every minute, and one to a single friend shortly
-- after a send to them failed. A DIGEST lists up to ten records, taking
-- turns, so a record it leaves out isn't owed.
-- See the sync resolution on #8, docs/design/code-structure.md and
-- docs/adr/0006-a-confirming-digest-instead-of-acks.md.

local _, ns = ...

local Gossip = {}
Gossip.__index = Gossip
ns.Gossip = Gossip

local REPLY_MIN, REPLY_MAX = 1, 4
local ZONE_DELAY = 10
-- A change that can wait (XP, gold) goes out within this long.
local LATER_DELAY = 60
local HEARTBEAT = 5 * 60
-- The DIGEST that follows own DATA, so a friend who missed it asks again.
local CONFIRM_MIN, CONFIRM_MAX = 20, 30
-- A DIGEST goes out this often while the link is up.
local EVERY_MIN, EVERY_MAX = 55, 65
-- After a failed send to a friend, they get a DIGEST of their own this
-- long after, and at most one in each RESYNC_GAP (an account that can't
-- send at all fails every time).
local RESYNC_DELAY = 5
local RESYNC_GAP = 60
-- A record that went out to everyone this recently may still be on its
-- way to whoever sent a DIGEST showing an older version, so it isn't owed
-- to them again (a later DIGEST catches a loss).
local IN_FLIGHT = 2
-- An older BFF owes every record a DIGEST leaves out, so while one was
-- heard this recently and the Crew has more records than a DIGEST holds,
-- the every-minute DIGEST is skipped.
local OLDER_MEMORY = 15 * 60
-- Ten entries of id and version always fit one chunk (247 bytes of a
-- 255-byte whisper, Link/Framing.lua).
local DIGEST_SIZE = 10

-- ledger; now() and random() from Core; send(message, to) encodes and
-- hands a message to the link, for everyone or only the Character named
-- `to`; beforeOwnSend() runs just before own DATA goes out, so whatever
-- only rides a send (where you stand) can be written first.
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
    -- id -> when the version held went out to everyone (sent or heard).
    onWire = {},
    -- A DIGEST to send, and the ids it is meant to fetch; nil wanted means
    -- it goes out whatever others send.
    digestDue = nil,
    wanted = nil,
    -- DATA owed in reply: id -> true, and when it's due.
    owed = {},
    owedDue = nil,
    -- The DIGEST confirming own DATA, and the next one every minute.
    confirmDue = nil,
    everyDue = nil,
    -- The last id a DIGEST listed in turn.
    turn = nil,
    -- When a DIGEST from an older BFF (no turns flag) last came.
    olderHeard = nil,
    -- DIGESTs to single friends after a failed send: name -> when due, and
    -- name -> when the last one went out.
    resync = {},
    resynced = {},
  }, Gossip)
end

-- A whole number of seconds from min to max.
local function between(self, min, max)
  return min + math.floor(self.random() * (max - min + 1))
end

local function replyDelay(self)
  return between(self, REPLY_MIN, REPLY_MAX)
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

-- A DIGEST: own version, the ids a reply DIGEST is meant to fetch, then
-- the other records in turn. partial says some were left out, so the
-- receiver doesn't owe those (older clients ignore it, and owe them).
local function digest(self)
  local versions, partial, turn = self.ledger:digest(DIGEST_SIZE, self.turn, self.wanted)
  self.turn = turn
  -- turns marks a DIGEST from a BFF that knows partial.
  return { type = "DIGEST", versions = versions, partial = partial or nil, turns = true }
end

local function sendDigest(self)
  local message = digest(self)
  cancelDigest(self)
  self.confirmDue = nil
  self.everyDue = self.now() + between(self, EVERY_MIN, EVERY_MAX)
  self.send(message)
end

local function sendOwn(self)
  if self.beforeOwnSend then self.beforeOwnSend() end
  local own = self.ledger:own()
  self.dirty, self.dataDue = false, nil
  self.lastOwnSent = self.now()
  if own then
    self.onWire[own.id] = self.now()
    self.confirmDue = self.now() + between(self, CONFIRM_MIN, CONFIRM_MAX)
    self.send({ type = "DATA", records = { own } })
  end
end

local function sendOwed(self)
  local records = {}
  for id in pairs(self.owed) do
    local record = self.ledger:record(id)
    if record then
      records[#records + 1] = record
      self.onWire[id] = self.now()
    end
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
  self.confirmDue, self.everyDue, self.resync = nil, nil, {}
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
-- display name, Main, and any change that makes a Feed entry, such as a
-- profession milestone), "soon" (zone, debounced) or "later" (XP, gold,
-- other profession changes, Play times: rides the next send, at most a
-- minute away).
-- Where you stand never calls this: it is written just before own DATA
-- goes out (beforeOwnSend).
function Gossip:ownChanged(urgency)
  self.dirty = true
  local due
  if urgency == "now" then
    due = self.now()
  elseif urgency == "soon" then
    due = self.now() + ZONE_DELAY
  else
    due = self.now() + LATER_DELAY
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
-- of our own if they hold something newer or unknown to us. partial says
-- their DIGEST left records out, so one it doesn't list isn't owed; turns
-- says it came from a BFF that knows that (an older one never sends it).
function Gossip:digestReceived(versions, partial, turns)
  local ledger = self.ledger
  if not turns then self.olderHeard = self.now() end
  -- Their DIGEST fetches whatever ours was going to.
  if self.wanted then
    local covered = true
    for id in pairs(self.wanted) do
      local theirs = versions[id]
      if (theirs == nil and partial) or (theirs or 0) > ledger:version(id) then covered = false end
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

  local now = self.now()
  for id, record in ledger:records() do
    local theirs = versions[id]
    local behind = (type(theirs) ~= "number" and not partial) or (type(theirs) == "number" and theirs < record.version)
    local inFlight = self.onWire[id] ~= nil and now - self.onWire[id] < IN_FLIGHT
    if behind and not inFlight then
      self.owed[id] = true
      self.owedDue = self.owedDue or self.now() + replyDelay(self)
    end
  end
end

-- A record that went out on the wire, after the Ledger has merged it.
function Gossip:recordSeen(id, version)
  local held = self.ledger:version(id)
  if version == held then self.onWire[id] = self.now() end
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

-- A send to the Character of this name failed: they may have missed it, so
-- they get a DIGEST of their own shortly after. Nothing else changes.
function Gossip:sendFailed(name)
  if not self.open or type(name) ~= "string" or self.resync[name] then return end
  local due = self.now() + RESYNC_DELAY
  local last = self.resynced[name]
  if last and last + RESYNC_GAP > due then due = last + RESYNC_GAP end
  self.resync[name] = due
end

-- The Character of this name logged out: no DIGEST for them.
function Gossip:peerGone(name)
  if type(name) == "string" then self.resync[name] = nil end
end

-- Whether an older BFF is around and a DIGEST would leave records out,
-- which it would answer with DATA for all of them.
local function olderWouldFlood(self)
  if not self.olderHeard or self.now() - self.olderHeard >= OLDER_MEMORY then return false end
  local count = 0
  for _ in self.ledger:records() do count = count + 1 end
  return count > DIGEST_SIZE
end

-- Called once a second: sends whatever is due.
function Gossip:tick()
  if not self.open then return end
  local now = self.now()
  for name, due in pairs(self.resync) do
    if now >= due then
      self.resync[name] = nil
      self.resynced[name] = now
      self.send(digest(self), name)
    end
  end
  if self.everyDue and now >= self.everyDue and olderWouldFlood(self) then
    self.everyDue = now + between(self, EVERY_MIN, EVERY_MAX)
  end
  if (self.digestDue and now >= self.digestDue) or (self.confirmDue and now >= self.confirmDue)
      or (self.everyDue and now >= self.everyDue) then
    sendDigest(self)
  end
  if self.owedDue and now >= self.owedDue then sendOwed(self) end
  if self.dataDue and now >= self.dataDue then
    sendOwn(self)
  elseif now - self.lastOwnSent >= HEARTBEAT then
    self.ledger:touch()
    sendOwn(self)
  end
end
