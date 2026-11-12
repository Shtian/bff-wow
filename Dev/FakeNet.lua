-- FakeNet: real Cores talking through a fake link, on one shared virtual
-- clock, so a whole Crew plays out the same way every run. Used by the
-- offline tests and by /bff sim (Dev/Sim.lua). Pure Lua, like Core.
-- See docs/design/code-structure.md (Tests).

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

-- A small seeded generator, so a run doesn't depend on math.random.
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

-- options: clock (the starting server time, default 1000), maxLevel,
-- items (the link each item string resolves to, as the game's cache
-- would; one not there isn't cached) and finalBosses (encounter ID to
-- instance name, for every client's Core; default the real table).
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
    -- Every message put on the wire: { from = name, message = string, time,
    -- to = the Character name it was sent to, nil for everyone }.
    wire = {},
    -- drop(message, from, to) returns true to lose a message on its way,
    -- with no one told.
    drop = nil,
    -- fail(message, from, to) returns true for a send the game fails: it
    -- doesn't arrive, and the sender's Core hears sendFailed(to's
    -- Character name), as from the channel link.
    fail = nil,
    -- chunked(chunks, from, to) returns the chunks of a message that reach
    -- one client, in the order they arrive: leave one out to lose it, or
    -- hand them back in another order. A message left incomplete is
    -- reported lost by the receiver's Framing, and its Core hears
    -- sendFailed(from's Character name), as from the channel link.
    chunked = nil,
  }, FakeNet)
end

function FakeNet:now()
  return self.clock
end

-- The messages on the wire since `mark` (an index into wire), decoded, each
-- with sender (the client's name), to and size (bytes encoded). Only those
-- sent by the client named `name` and of type `kind`, if given.
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

-- Puts a message on the wire; it reaches every client whose link is up at
-- the next step, the sender included, as on the real channel. With `to` (a
-- Character name) it reaches only that client, as a whisper. It travels as
-- the chunks the channel link would whisper (Link/Framing.lua).
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

-- A client's Framing: it splits what the client sends and puts together
-- what it receives, per sender's Character name.
local function newFraming(client)
  local net = client.net
  return ns.Framing.new({
    now = function() return net.clock end,
    lost = function(sender)
      if client.core then client.core:sendFailed(sender) end
    end,
  })
end

-- The chunks of a message reach a client, which hears the message once
-- they are all in.
local function receive(self, item, client)
  local chunks = item.chunks
  if self.chunked then chunks = self.chunked(chunks, item.from.name, client.name) end
  for _, chunk in ipairs(chunks) do
    local sender = characterName(item.from)
    local message = client.framing:receive(sender, chunk)
    if message then client.core:received(message, sender) end
  end
end

local function deliver(self, item)
  for _, client in ipairs(self.clients) do
    if isListening(client) then
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

-- Advances the clock to `time` (default one second on): delivers what was
-- sent before, then ticks every online Core.
function FakeNet:step(time)
  self.clock = time or self.clock + 1
  local queue = self.queue
  self.queue = {}
  for _, item in ipairs(queue) do deliver(self, item) end
  for _, client in ipairs(self.clients) do
    if client.core then client.framing:tick() end
    if client.core and client.ticks then client.core:tick() end
  end
end

-- Runs for the given number of seconds.
function FakeNet:run(seconds)
  for _ = 1, seconds do self:step() end
end

-- A simulated Member's account. options: random (default a
-- generator seeded by name), db (default empty), character (the one it
-- plays: guid, name, classFilename, level, xp, maxXp, zone, deaths, money),
-- location (where it stands, as Snapshot.locate reports it: mapId, x and y,
-- or instance; default nowhere known) and utcOffset (seconds its local time
-- is ahead of server time, default 0) and bags (where each item GUID is,
-- as Bags.findItem reads it: "bags" for the bags or bank, "equipped", or
-- nil when it has left; default empty) and gossip (the Gossip module its
-- Core uses, for a client that syncs like an older BFF; default Core's).
function FakeNet:add(name, options)
  options = options or {}
  local client = setmetatable({
    net = self,
    name = name,
    db = options.db or {},
    random = options.random or seeded(seedFor(name)),
    utcOffset = options.utcOffset,
    location = copy(options.location),
    bags = copy(options.bags) or {},
    gossip = options.gossip,
    bagReads = 0,
    character = copy(options.character) or {
      guid = "Player-0-" .. name, name = name, classFilename = "WARRIOR",
      level = 10, xp = 0, maxXp = 1000, zone = "Elwynn Forest", deaths = 0,
    },
    events = {},
    linkUp = false,
    ticks = true,
  }, Client)
  client.saved = copy(client.db)
  self.clients[#self.clients + 1] = client
  return client
end

-- Attaches a Core the net doesn't run, such as the real one in game: it
-- hears every simulated client, and broadcast(client, message) is how its
-- own sends reach them.
function FakeNet:attach(core, name)
  local client = setmetatable({ net = self, name = name or "you", core = core, linkUp = true }, Client)
  client.framing = newFraming(client)
  self.clients[#self.clients + 1] = client
  return client
end

-- How many times the client's Core fired this event (and notice kind).
function Client:count(event, kind)
  local n = 0
  for _, e in ipairs(self.events) do
    if e[1] == event and (kind == nil or e[2] == kind) then n = n + 1 end
  end
  return n
end

local function newCore(client, initialLogin)
  local net = client.net
  -- A new session: whatever was half received is gone.
  client.framing = newFraming(client)
  client.core = ns.Core.new({
    db = client.db,
    now = function() return net.clock end,
    random = client.random,
    link = {
      send = function(message, to)
        if client.core and client.linkUp then net:broadcast(client, message, to) end
      end,
    },
    gossip = client.gossip,
    listener = function(...) client.events[#client.events + 1] = { ... } end,
    initialLogin = initialLogin,
    maxLevel = net.maxLevel,
    utcOffset = client.utcOffset,
    locate = function() return copy(client.location) end,
    itemLink = function(itemString) return net.items[itemString] end,
    itemLook = function(itemId) return net.looks[itemId] end,
    finalBosses = net.finalBosses,
    findItem = function(itemGuid)
      client.bagReads = client.bagReads + 1
      local where = client.bags[itemGuid]
      return where ~= nil, where == "equipped"
    end,
  })
  client.core:updateOwn(copy(client.character))
  client.memberId = client.core:rows()[1].memberId
end

local function bringUp(client)
  if client.locked or not client.core or not client.core:crew() then return end
  client.linkUp = true
  client.core:up()
end

-- Logs in: a new Core over the saved data, then the link comes up once the
-- client is in a Crew.
function Client:login()
  assert(not self.core, self.name .. " is already online")
  newCore(self, true)
  bringUp(self)
  return self
end

-- Logs out: the saved data is written, and the others see this Character
-- leave the channel. skipGone leaves that notice out.
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

-- A /reload: a new Core over the same data, still in the channel.
function Client:reload()
  assert(self.core, self.name .. " is not online")
  self.saved = copy(self.db)
  self.linkUp = false
  newCore(self, false)
  bringUp(self)
  return self
end

-- A client crash: whatever changed since the last logout or reload is
-- lost, and nobody sees the Character leave the channel.
function Client:crash()
  self.core = nil
  self.linkUp = false
  self.db = copy(self.saved)
  return self
end

-- Lockdown: the link goes down while the client stays online, and what is
-- sent to it meanwhile is lost.
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

-- The link goes down and straight back up, as when the channel link finds
-- a new Character in the member list: a fresh DIGEST goes out.
function Client:relink()
  self.linkUp = false
  self.core:down()
  bringUp(self)
  return self
end

-- Joins (or starts, without a code) a Crew, and lets the link come up.
function Client:join(code)
  if code then
    assert(self.core:joinCrew(code, self.name))
  else
    code = assert(self.core:startCrew(self.name)).code
  end
  bringUp(self)
  return code
end

-- Changes the Character being played and tells Core, as Snapshot would.
function Client:play(changes)
  for k, v in pairs(changes or {}) do self.character[k] = v end
  if self.core then self.core:updateOwn(copy(self.character)) end
  return self
end

-- Puts an item GUID somewhere ("bags", "equipped", or nil for gone).
-- Core hears of it on the next bagsUpdated.
function Client:putItem(itemGuid, where)
  self.bags[itemGuid] = where
  return self
end

-- The bags have settled, as on BAG_UPDATE_DELAYED.
function Client:bagsUpdated()
  self.core:bagsUpdated()
  return self
end

-- Moves the client: where Core's next locate() finds it, as
-- Snapshot.locate would report it (nil when it can't be read).
function Client:move(location)
  self.location = copy(location)
  return self
end

-- The row the client's Core shows for another client, or nil.
function Client:rowFor(other)
  local id = other.memberId
  for _, row in ipairs(self.core:rows()) do
    if row.memberId == id then return row end
  end
  return nil
end
