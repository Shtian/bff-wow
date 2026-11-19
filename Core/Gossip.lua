local _, ns = ...

local Gossip = {}
Gossip.__index = Gossip
ns.Gossip = Gossip

local REPLY_MIN, REPLY_MAX = 1, 4
local ZONE_DELAY = 10
local LATER_DELAY = 60
local HEARTBEAT = 5 * 60
local CONFIRM_MIN, CONFIRM_MAX = 20, 30
local EVERY_MIN, EVERY_MAX = 55, 65
Gossip.EVERY_MAX = EVERY_MAX
local RESYNC_DELAY = 5
local RESYNC_GAP = 60
local IN_FLIGHT = 2
local OLDER_MEMORY = 15 * 60
local DIGEST_SIZE = 10
local EVERYONE = 0

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
    dirty = false,
    dataDue = nil,
    lastOwnSent = 0,
    ownSent = nil,
    onWire = {},
    asks = {},
    owed = {},
    confirmDue = nil,
    everyDue = nil,
    turn = nil,
    olderHeard = nil,
    resync = {},
    resynced = {},
  }, Gossip)
end

local function between(self, min, max)
  return min + math.floor(self.random() * (max - min + 1))
end

local function replyDelay(self)
  return between(self, REPLY_MIN, REPLY_MAX)
end

local function isEmpty(set)
  return next(set) == nil
end

local function strike(pending, to, field, id)
  local entry = pending[to]
  if not entry then return end
  entry[field][id] = nil
  if isEmpty(entry[field]) then pending[to] = nil end
end

local function cancelAsk(self, id)
  for to in pairs(self.asks) do strike(self.asks, to, "wanted", id) end
end

local function cancelOwed(self, id)
  for to in pairs(self.owed) do strike(self.owed, to, "ids", id) end
end

local function digest(self, wanted)
  local versions, partial, turn = self.ledger:digest(DIGEST_SIZE, self.turn, wanted)
  self.turn = turn
  local own = self.ledger:memberId()
  if self.dirty and self.ownSent and versions[own] then versions[own] = self.ownSent end
  return { type = "DIGEST", versions = versions, partial = partial or nil, turns = true }
end

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

function Gossip:setLink(up)
  self.linkUp = up
  update(self)
end

function Gossip:setPaused(paused)
  self.paused = paused
  update(self)
end

function Gossip:sendNow(message)
  self.send(message)
end

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

function Gossip.urgency(before, after)
  if before == nil or before.level ~= after.level or before.deaths ~= after.deaths then
    return "now"
  elseif before.zone ~= after.zone then
    return "soon"
  end
  return "later"
end

function Gossip:digestReceived(versions, partial, turns, from)
  local ledger = self.ledger
  local to = type(from) == "string" and from or EVERYONE
  if not turns then self.olderHeard = self.now() end
  local now = self.now()
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
    local unsent = self.dirty and id == ledger:memberId()
    local held = unsent and self.ownSent or record.version
    local behind = (type(theirs) ~= "number" and not partial) or (type(theirs) == "number" and theirs < held)
    local inFlight = self.onWire[id] ~= nil and now - self.onWire[id] < IN_FLIGHT
    if behind and not inFlight and unsent then
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

function Gossip:recordSeen(id, version, toEveryone)
  local held = self.ledger:version(id)
  if toEveryone then
    if version == held then self.onWire[id] = self.now() end
    if version >= held then cancelOwed(self, id) end
  elseif version >= held then
    strike(self.owed, EVERYONE, "ids", id)
  end
  for to, ask in pairs(self.asks) do
    if ask.wanted[id] and held >= ask.wanted[id] then strike(self.asks, to, "wanted", id) end
  end
end

function Gossip:forget(id)
  cancelOwed(self, id)
  cancelAsk(self, id)
end

function Gossip:askAround()
  if self.open then sendDigest(self) end
end

function Gossip:sendFailed(name)
  if not self.open or type(name) ~= "string" or self.resync[name] then return end
  local due = self.now() + RESYNC_DELAY
  local last = self.resynced[name]
  if last and last + RESYNC_GAP > due then due = last + RESYNC_GAP end
  self.resync[name] = due
end

function Gossip:peerGone(name)
  if type(name) ~= "string" then return end
  self.resync[name], self.owed[name], self.asks[name] = nil, nil, nil
end

local function olderWouldFlood(self)
  if not self.olderHeard or self.now() - self.olderHeard >= OLDER_MEMORY then return false end
  local count = 0
  for _ in self.ledger:records() do count = count + 1 end
  return count > DIGEST_SIZE
end

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
