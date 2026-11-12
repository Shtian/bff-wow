-- Gossip: when to talk. Two messages: a DIGEST lists the Member ids and
-- versions you hold, and DATA carries full records. Whoever holds something
-- newer than a DIGEST shows replies with DATA, whoever lacks something
-- replies with their own DIGEST, and both replies go only to the Character
-- who sent the DIGEST (to everyone if the link didn't say who). So a friend
-- who is behind can get the same record from several friends, and nobody
-- else is sent anything. Gossip talks only while the link is up (and in a
-- Crew) and not paused; a change made meanwhile goes out once it talks
-- again.
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
-- Stands for everyone where replies are kept by the Character they go to
-- (a number, so never a name).
local EVERYONE = 0

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
    -- The version of the own record everyone was last sent (or held when
    -- Gossip started talking with nothing to send).
    ownSent = nil,
    -- id -> when the version held went out to everyone (sent or heard).
    onWire = {},
    -- DIGESTs to send in reply, by the Character each goes to (or
    -- EVERYONE): { wanted = id -> the version it is meant to fetch, due =
    -- when }.
    asks = {},
    -- DATA owed in reply, by the Character it goes to (or EVERYONE):
    -- { ids = id -> true, due = when }.
    owed = {},
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

-- Takes an id out of what one Character (or EVERYONE) is owed or asked
-- for: pending is owed or asks, and field the set in each entry.
local function strike(pending, to, field, id)
  local entry = pending[to]
  if not entry then return end
  entry[field][id] = nil
  if isEmpty(entry[field]) then pending[to] = nil end
end

-- No longer asks anyone for the record of this id.
local function cancelAsk(self, id)
  for to in pairs(self.asks) do strike(self.asks, to, "wanted", id) end
end

-- No longer owes anyone the record of this id.
local function cancelOwed(self, id)
  for to in pairs(self.owed) do strike(self.owed, to, "ids", id) end
end

-- A DIGEST: own version, the ids a reply DIGEST is meant to fetch (wanted,
-- if any), then the other records in turn. partial says some were left
-- out, so the receiver doesn't owe those (older clients ignore it, and owe
-- them).
local function digest(self, wanted)
  local versions, partial, turn = self.ledger:digest(DIGEST_SIZE, self.turn, wanted)
  self.turn = turn
  -- An own change that hasn't gone out yet isn't shown: it goes to
  -- everyone when it's due, so nobody needs to ask for it.
  local own = self.ledger:memberId()
  if self.dirty and self.ownSent and versions[own] then versions[own] = self.ownSent end
  -- turns marks a DIGEST from a BFF that knows partial.
  return { type = "DIGEST", versions = versions, partial = partial or nil, turns = true }
end

-- A DIGEST to everyone.
local function sendDigest(self)
  local ask = self.asks[EVERYONE]
  local message = digest(self, ask and ask.wanted)
  self.asks[EVERYONE] = nil
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
    self.ownSent = own.version
    self.onWire[own.id] = self.now()
    self.confirmDue = self.now() + between(self, CONFIRM_MIN, CONFIRM_MAX)
    self.send({ type = "DATA", records = { own } })
  end
end

-- Sends the DATA owed to one Character, or to everyone.
local function sendOwed(self, to)
  local records = {}
  for id in pairs(self.owed[to].ids) do
    local record = self.ledger:record(id)
    if record then
      records[#records + 1] = record
      if to == EVERYONE then self.onWire[id] = self.now() end
    end
  end
  self.owed[to] = nil
  if #records > 0 then self.send({ type = "DATA", records = records }, to ~= EVERYONE and to or nil) end
end

-- Starts or stops talking. Starting sends a fresh DIGEST, plus own DATA if
-- the own record changed meanwhile. Stopping drops replies owed, since the
-- DIGEST on starting again asks for whatever is still missing.
local function update(self)
  local open = self.linkUp and not self.paused
  if open == self.open then return end
  self.open = open
  self.owed, self.asks = {}, {}
  self.confirmDue, self.everyDue, self.resync = nil, nil, {}
  if not open then return end
  sendDigest(self)
  if self.dirty then
    sendOwn(self)
  else
    self.lastOwnSent = self.now()
    local own = self.ledger:own()
    self.ownSent = own and own.version
  end
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

-- A DIGEST from someone else: owe them DATA for what we hold newer, and a
-- DIGEST of our own if they hold something newer or unknown to us. partial
-- says their DIGEST left records out, so one it doesn't list isn't owed;
-- turns says it came from a BFF that knows that (an older one never sends
-- it). from is the name of the Character who sent it, where the replies
-- go; without one they go to everyone.
function Gossip:digestReceived(versions, partial, turns, from)
  local ledger = self.ledger
  local to = type(from) == "string" and from or EVERYONE
  if not turns then self.olderHeard = self.now() end
  local now = self.now()
  -- Their DIGEST, answered to everyone, fetches whatever ours to everyone
  -- was going to.
  local everyone = self.asks[EVERYONE]
  if everyone and to == EVERYONE then
    local covered = true
    for id in pairs(everyone.wanted) do
      local theirs = versions[id]
      if (theirs == nil and partial) or (theirs or 0) > ledger:version(id) then covered = false end
    end
    if covered then self.asks[EVERYONE] = nil end
  end
  if not self.open then return end

  for id, version in pairs(versions) do
    if type(id) == "string" and type(version) == "number" and id ~= ledger:memberId()
        and not ledger:isRemoved(id) and version > ledger:version(id) then
      local ask = self.asks[to]
      if not ask then
        ask = { wanted = {}, due = now + replyDelay(self) }
        self.asks[to] = ask
      end
      ask.wanted[id] = version
    end
  end

  for id, record in ledger:records() do
    local theirs = versions[id]
    -- An own change that hasn't gone out yet goes to everyone when it's
    -- due: they are only behind if they lack what did go out.
    local unsent = self.dirty and id == ledger:memberId()
    local held = unsent and self.ownSent or record.version
    local behind = (type(theirs) ~= "number" and not partial) or (type(theirs) == "number" and theirs < held)
    local inFlight = self.onWire[id] ~= nil and now - self.onWire[id] < IN_FLIGHT
    if behind and not inFlight and unsent then
      -- The reply would carry the change, which is news to everyone: sent
      -- to this Character alone, they would hold a version the others
      -- lack and hand it on, one reply after another. So own DATA goes
      -- out early instead.
      self.dataDue = math.min(self.dataDue or math.huge, now + replyDelay(self))
    elseif behind and not inFlight then
      local reply = self.owed[to]
      if not reply then
        reply = { ids = {}, due = now + replyDelay(self) }
        self.owed[to] = reply
      end
      reply.ids[id] = true
    end
  end
end

-- A record that came in DATA, after the Ledger has merged it. toEveryone
-- says the DATA most likely went to everyone (Core can't see who else was
-- sent it), so nobody is owed the record any more; a reply to one
-- Character is seen by nobody else, so what is owed to the others stays.
function Gossip:recordSeen(id, version, toEveryone)
  local held = self.ledger:version(id)
  if toEveryone then
    if version == held then self.onWire[id] = self.now() end
    if version >= held then cancelOwed(self, id) end
  elseif version >= held then
    strike(self.owed, EVERYONE, "ids", id)
  end
  -- Whoever it came from, a record now held isn't asked for.
  for to, ask in pairs(self.asks) do
    if ask.wanted[id] and held >= ask.wanted[id] then strike(self.asks, to, "wanted", id) end
  end
end

-- A removed Member: no reply is owed for them, nor a DIGEST to fetch them.
function Gossip:forget(id)
  cancelOwed(self, id)
  cancelAsk(self, id)
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

-- The Character of this name logged out: no reply is owed to them, nor a
-- DIGEST of their own.
function Gossip:peerGone(name)
  if type(name) ~= "string" then return end
  self.resync[name], self.owed[name], self.asks[name] = nil, nil, nil
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
  local everyone = self.asks[EVERYONE]
  if (everyone and now >= everyone.due) or (self.confirmDue and now >= self.confirmDue)
      or (self.everyDue and now >= self.everyDue) then
    sendDigest(self)
  end
  for to, ask in pairs(self.asks) do
    if now >= ask.due then
      self.asks[to] = nil
      self.send(digest(self, ask.wanted), to)
    end
  end
  for to, reply in pairs(self.owed) do
    if now >= reply.due then sendOwed(self, to) end
  end
  if self.dataDue and now >= self.dataDue then
    sendOwn(self)
  elseif now - self.lastOwnSent >= HEARTBEAT then
    self.ledger:touch()
    sendOwn(self)
  end
end
