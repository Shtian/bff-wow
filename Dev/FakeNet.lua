local _, ns = ...

local FakeNet = {}
FakeNet.__index = FakeNet
ns.FakeNet = FakeNet

local Client = {}
Client.__index = Client

local function copy(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for k, v in pairs(value) do result[k] = copy(v) end
  return result
end

local function seeded(seed)
  local state = seed
  return function()
    state = (state * 1103515245 + 12345) % 2147483648
    return state / 2147483648
  end
end

local function seedFor(name)
  local seed = 7
  for i = 1, #name do seed = (seed * 31 + name:byte(i)) % 2147483647 end
  return seed
end

function FakeNet.new(options)
  options = options or {}
  return setmetatable({
    clock = options.clock or 1000,
    maxLevel = options.maxLevel or 60,
    items = options.items or {},
    looks = options.looks or {},
    finalBosses = options.finalBosses,
    clients = {},
    queue = {},
    wire = {},
    drop = nil,
    fail = nil,
    chunked = nil,
    channels = options.channels == true,
    sees = nil,
  }, FakeNet)
end

function FakeNet:now()
  return self.clock
end

function FakeNet:sent(mark, name, kind)
  local messages = {}
  for i = mark + 1, #self.wire do
    local item = self.wire[i]
    local decoded = ns.Codec.decode(item.message)
    if type(decoded) == "table" and (name == nil or item.from == name) and (kind == nil or decoded.type == kind) then
      decoded.sender, decoded.to, decoded.size = item.from, item.to, #item.message
      messages[#messages + 1] = decoded
    end
  end
  return messages
end

function FakeNet:broadcast(from, message, to)
  self.wire[#self.wire + 1] = { from = from.name, message = message, time = self.clock, to = to }
  self.queue[#self.queue + 1] = { from = from, message = message, to = to, chunks = from.framing:split(message) }
end

local function isListening(client)
  return client.core ~= nil and client.linkUp
end

local function characterName(client)
  return client.character and client.character.name or client.name
end

local function newFraming(client)
  local net = client.net
  return ns.Framing.new({
    now = function() return net.clock end,
    lost = function(sender)
      if client.core then client.core:sendFailed(sender) end
    end,
  })
end

local function receive(self, item, client)
  local chunks = item.chunks
  if self.chunked then chunks = self.chunked(chunks, item.from.name, client.name) end
  for _, chunk in ipairs(chunks) do
    local sender = characterName(item.from)
    local message = client.framing:receive(sender, chunk)
    if message then client.core:received(message, sender) end
  end
end

local function channelOf(client)
  local crew = client.core and client.core:channel()
  return crew and crew.channel
end

local function inChannel(self, client, name)
  for _, other in ipairs(self.clients) do
    if other ~= client and characterName(other) == name then
      if other.stillListed then return true end
      if channelOf(other) and (not self.channels or channelOf(other) == channelOf(client)) then return true end
    end
  end
  return false
end

local function bounce(self, item)
  for _, client in ipairs(self.clients) do
    if client.stillListed and (item.to == nil or item.to == characterName(client)) then
      client.stillListed = nil
      if item.from.core then item.from.core:gone(characterName(client)) end
    end
  end
end

local function hasPeer(self, client, other)
  if channelOf(client) ~= nil and channelOf(client) == channelOf(other) then return true end
  return client.vouched[other.name] == true or (self.sees ~= nil and self.sees(client.name, other.name))
end

local function reaches(self, item, client)
  if not self.channels or item.gone then return true end
  local from = item.from
  if not hasPeer(self, from, client) then return false end
  if hasPeer(self, client, from) then return true end
  if not client.core:fromKnownMember(item.message) then return false end
  client.vouched[from.name] = true
  return true
end

local function deliver(self, item)
  if not item.gone then bounce(self, item) end
  for _, client in ipairs(self.clients) do
    if isListening(client) and reaches(self, item, client) then
      if item.gone then
        if client ~= item.from then client.core:gone(item.gone) end
      elseif item.to == nil or characterName(client) == item.to then
        if client ~= item.from and self.fail and self.fail(item.message, item.from.name, client.name) then
          if item.from.core then item.from.core:sendFailed(characterName(client)) end
        elseif not (self.drop and self.drop(item.message, item.from.name, client.name)) then
          receive(self, item, client)
        end
      end
    end
  end
end

local relinkMoved, followChannel

function FakeNet:step(time)
  self.clock = time or self.clock + 1
  for _, client in ipairs(self.clients) do
    relinkMoved(client)
    followChannel(client)
  end
  local queue = self.queue
  self.queue = {}
  for _, item in ipairs(queue) do deliver(self, item) end
  for _, client in ipairs(self.clients) do
    if client.core then client.framing:tick() end
    if client.core and client.ticks then client.core:tick() end
  end
end

function FakeNet:run(seconds)
  for _ = 1, seconds do self:step() end
end

function FakeNet:add(name, options)
  options = options or {}
  local client = setmetatable({
    net = self,
    name = name,
    db = options.db or {},
    random = options.random or seeded(seedFor(name)),
    utcOffset = options.utcOffset,
    daylight = copy(options.daylight),
    location = copy(options.location),
    bags = copy(options.bags) or {},
    gossip = options.gossip,
    version = options.version,
    changelog = options.changelog,
    ruleset = copy(options.ruleset),
    bagReads = 0,
    character = copy(options.character) or {
      guid = "Player-0-" .. name, name = name, classFilename = "WARRIOR",
      level = 10, xp = 0, maxXp = 1000, zone = "Elwynn Forest", deaths = 0,
    },
    events = {},
    vouched = {},
    linkUp = false,
    ticks = true,
  }, Client)
  client.saved = copy(client.db)
  self.clients[#self.clients + 1] = client
  return client
end

function FakeNet:attach(core, name)
  local client = setmetatable({
    net = self, name = name or "you", core = core, linkUp = true, vouched = {}, attached = true,
  }, Client)
  client.framing = newFraming(client)
  self.clients[#self.clients + 1] = client
  return client
end

function Client:count(event, kind)
  local n = 0
  for _, e in ipairs(self.events) do
    if e[1] == event and (kind == nil or e[2] == kind) then n = n + 1 end
  end
  return n
end

local function newCore(client, initialLogin)
  local net = client.net
  client.framing = newFraming(client)
  client.core = ns.Core.new({
    db = client.db,
    now = function() return net.clock end,
    random = client.random,
    link = {
      send = function(message, to)
        if client.core and client.linkUp then net:broadcast(client, message, to) end
      end,
      inChannel = function(name) return inChannel(net, client, name) end,
    },
    gossip = client.gossip,
    ruleset = copy(client.ruleset),
    listener = function(event, ...)
      client.events[#client.events + 1] = { event, ... }
      if event == "crewChanged" and net.channels then client.moved = true end
    end,
    initialLogin = initialLogin,
    maxLevel = net.maxLevel,
    utcOffset = client.utcOffset,
    daylight = function()
      local daylight = client.daylight or {}
      return daylight.isDay, daylight.hour, daylight.minute
    end,
    locate = function() return copy(client.location) end,
    itemLink = function(itemString) return net.items[itemString] end,
    itemLook = function(itemId) return net.looks[itemId] end,
    finalBosses = net.finalBosses,
    version = client.version,
    changelog = client.changelog,
    findItem = function(itemGuid)
      client.bagReads = client.bagReads + 1
      local where = client.bags[itemGuid]
      return where ~= nil, where == "equipped"
    end,
  })
  client.core:updateOwn(copy(client.character))
  client:noteMemberId()
end

function Client:noteMemberId()
  for _, row in ipairs(self.core:rows()) do
    if row.own then self.memberId = row.memberId end
  end
end

local function bringUp(client)
  if client.locked or not client.core or not client.core:channel() then return end
  client.linkUp = true
  client.core:up()
end

function relinkMoved(client)
  if not client.moved then return end
  client.moved = nil
  client.vouched = {}
  if not client.core then return end
  if client.linkUp then
    client.linkUp = false
    client.core:down()
  end
  bringUp(client)
end

function followChannel(client)
  if client.attached then return end
  if not client.core then
    client.inCrewChannel = nil
    return
  end
  local wanted = client.core:channel() ~= nil
  local was = client.inCrewChannel
  client.inCrewChannel = wanted
  if was == nil or was == wanted then return end
  if wanted then
    bringUp(client)
  else
    if client.linkUp then
      client.linkUp = false
      client.core:down()
    end
    client.net.queue[#client.net.queue + 1] = { from = client, gone = characterName(client) }
  end
end

function Client:login()
  assert(not self.core, self.name .. " is already online")
  newCore(self, true)
  bringUp(self)
  return self
end

function Client:logout(skipGone)
  assert(self.core, self.name .. " is not online")
  self.saved = copy(self.db)
  self.core = nil
  self.linkUp = false
  if not skipGone then
    self.net.queue[#self.net.queue + 1] = { from = self, gone = self.character.name }
  end
  return self
end

function Client:logoutStillListed()
  self:logout(true)
  self.stillListed = true
  return self
end

function Client:reload()
  assert(self.core, self.name .. " is not online")
  self.saved = copy(self.db)
  self.linkUp = false
  newCore(self, false)
  bringUp(self)
  return self
end

-- WoW: a client crash writes no saved variables.
function Client:crash()
  self.core = nil
  self.linkUp = false
  self.db = copy(self.saved)
  return self
end

function Client:lockdown(on)
  self.locked = on
  if not self.core then return self end
  if on and self.linkUp then
    self.linkUp = false
    self.core:down()
  elseif not on then
    bringUp(self)
  end
  return self
end

function Client:relink()
  self.linkUp = false
  self.core:down()
  bringUp(self)
  return self
end

function Client:join(code)
  if code then
    assert(self.core:joinCrew(code, self.name))
  else
    code = assert(self.core:startCrew(self.name)).code
  end
  self:noteMemberId()
  self.moved = nil
  bringUp(self)
  return code
end

function Client:play(changes)
  for k, v in pairs(changes or {}) do self.character[k] = v end
  if self.core then self.core:updateOwn(copy(self.character)) end
  return self
end

function Client:putItem(itemGuid, where)
  self.bags[itemGuid] = where
  return self
end

function Client:bagsUpdated()
  self.core:bagsUpdated()
  return self
end

function Client:move(location)
  self.location = copy(location)
  return self
end

function Client:slot()
  return ns.Slots.find(self.db, self.ruleset)
end

function Client:rowFor(other)
  local id = other.memberId
  for _, row in ipairs(self.core:rows()) do
    if row.memberId == id then return row end
  end
  return nil
end
