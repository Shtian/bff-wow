local _, ns = ...

local Gossip = {}
Gossip.__index = Gossip
ns.Gossip = Gossip

local REPLY_MIN, REPLY_MAX = 1, 4
local ZONE_DELAY = 10
local HEARTBEAT = 5 * 60
local DIGEST_SIZE = 10

local function legacyDigest(ledger, limit)
  local own = ledger:own()
  local others = {}
  for _, record in ledger:records() do
    if record ~= own then others[#others + 1] = record end
  end
  table.sort(others, function(a, b)
    if a.version ~= b.version then return a.version > b.version end
    return a.id < b.id
  end)
  local versions = {}
  if own then
    versions[own.id] = own.version
    limit = limit - 1
  end
  for i = 1, math.min(limit, #others) do versions[others[i].id] = others[i].version end
  return versions
end

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
    digestDue = nil,
    wanted = nil,
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
  self.send({ type = "DIGEST", versions = legacyDigest(self.ledger, DIGEST_SIZE) })
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

function Gossip:digestReceived(versions)
  local ledger = self.ledger
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

function Gossip:forget(id)
  self.owed[id] = nil
  if isEmpty(self.owed) then self.owedDue = nil end
  if self.wanted and self.wanted[id] then
    self.wanted[id] = nil
    if isEmpty(self.wanted) then cancelDigest(self) end
  end
end

function Gossip:askAround()
  if self.open then sendDigest(self) end
end

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

function Gossip.sendFailed() end
function Gossip.peerGone() end
