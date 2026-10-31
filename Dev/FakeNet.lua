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

-- options: clock (the starting server time, default 1000) and maxLevel.
function FakeNet.new(options)
  options = options or {}
  return setmetatable({
    clock = options.clock or 1000,
    maxLevel = options.maxLevel or 60,
    clients = {},
    queue = {},
    -- Every message put on the wire: { from = name, message = string, time }.
    wire = {},
    -- drop(message, from, to) returns true to lose a message on its way.
    drop = nil,
  }, FakeNet)
end

function FakeNet:now()
  return self.clock
end

-- Puts a message on the wire; it reaches every client whose link is up at
-- the next step, the sender included, as on the real channel.
function FakeNet:broadcast(from, message)
  self.wire[#self.wire + 1] = { from = from.name, message = message, time = self.clock }
  self.queue[#self.queue + 1] = { from = from, message = message }
end

local function isListening(client)
  return client.core ~= nil and client.linkUp
end

local function deliver(self, item)
  for _, client in ipairs(self.clients) do
    if isListening(client) then
      if item.gone then
        if client ~= item.from then client.core:gone(item.gone) end
      elseif not (self.drop and self.drop(item.message, item.from.name, client.name)) then
        client.core:received(item.message)
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
    if client.core and client.ticks then client.core:tick() end
  end
end

-- Runs for the given number of seconds.
function FakeNet:run(seconds)
  for _ = 1, seconds do self:step() end
end

-- A simulated Member's account. options: receiveOnly, random (default a
-- generator seeded by name), db (default empty) and character (the one it
-- plays: guid, name, classFilename, level, xp, maxXp, zone, deaths).
function FakeNet:add(name, options)
  options = options or {}
  local client = setmetatable({
    net = self,
    name = name,
    db = options.db or {},
    random = options.random or seeded(seedFor(name)),
    receiveOnly = options.receiveOnly == true,
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
  self.clients[#self.clients + 1] = client
  return client
end

-- The Member records and events a client's Core produced.
function Client:count(event, kind)
  local n = 0
  for _, e in ipairs(self.events) do
    if e[1] == event and (kind == nil or e[2] == kind) then n = n + 1 end
  end
  return n
end

local function newCore(client, initialLogin)
  local net = client.net
  client.core = ns.Core.new({
    db = client.db,
    now = function() return net.clock end,
    random = client.random,
    link = {
      send = function(message)
        if client.core and client.linkUp then net:broadcast(client, message) end
      end,
    },
    listener = function(...) client.events[#client.events + 1] = { ... } end,
    receiveOnly = client.receiveOnly,
    initialLogin = initialLogin,
    maxLevel = net.maxLevel,
  })
  client.core:updateOwn(copy(client.character))
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

-- A send the game refused: the link goes down and straight back up.
function Client:refused()
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

-- The row the client's Core shows for another client, or nil.
function Client:rowFor(other)
  local id = other.db.memberId
  for _, row in ipairs(self.core:rows()) do
    if row.memberId == id then return row end
  end
  return nil
end
