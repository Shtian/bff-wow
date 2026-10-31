-- Sim: /bff sim attaches a few simulated Members to your real Core through
-- FakeNet, so the panel can be tried without another Member online. Their
-- records are kept and relayed like real ones, so it only runs in a Crew
-- where no one else is known yet: start a test Crew for it. Left out of
-- releases.

local _, ns = ...

local Sim = {}
ns.Sim = Sim

local DAY = 24 * 60 * 60
-- How long after starting the offline Member logs out.
local LOGOUT_AFTER = 20

-- Levels are relative to the Character you play, so "can play" shows up.
-- The first Character is the one being played; the others were played
-- `ago` seconds earlier. main picks the Character set as Main, if any.
local MEMBERS = {
  -- Online on their Main, and can play with you.
  { name = "Simone", characters = {
    { name = "Simone", classFilename = "MAGE", level = 2, zone = "Westfall" },
    { name = "Simonette", classFilename = "PRIEST", level = -8, zone = "Darkshore", ago = 2 * DAY },
  } },
  -- On an Alt, with a Main that can play with you.
  { name = "Simbad", main = 2, characters = {
    { name = "Simbad", classFilename = "ROGUE", level = 10, zone = "Redridge Mountains" },
    { name = "Simbadsson", classFilename = "WARRIOR", level = -1, zone = "Wetlands", ago = DAY },
  } },
  -- Logs out soon after, with an Alt unseen for 40 days (hidden).
  { name = "Simba", offline = true, characters = {
    { name = "Simba", classFilename = "DRUID", level = 6, zone = "Teldrassil" },
    { name = "Simbalina", classFilename = "HUNTER", level = -15, zone = "Durotar", ago = 40 * DAY },
  } },
}

local net
local ticker
local members

local function character(i, j, spec, yourLevel)
  return {
    guid = ("Player-0-Sim%d-%d"):format(i, j), name = spec.name, classFilename = spec.classFilename,
    level = math.max(1, yourLevel + spec.level), xp = 300 * j, maxXp = 1000 + 200 * i,
    zone = spec.zone, deaths = i + j,
  }
end

-- Plays each Character at its time, oldest first, ending on the one being
-- played now.
local function playHistory(client, i, spec, yourLevel, now)
  local order = {}
  for j = #spec.characters, 1, -1 do order[#order + 1] = j end
  table.sort(order, function(a, b)
    return (spec.characters[a].ago or 0) > (spec.characters[b].ago or 0)
  end)
  for _, j in ipairs(order) do
    net.clock = now - (spec.characters[j].ago or 0)
    client.character = character(i, j, spec.characters[j], yourLevel)
    if client.core then client:play() else client:login() end
  end
  net.clock = now
  if spec.main then client.core:setMain(character(i, spec.main, spec.characters[spec.main], yourLevel).guid) end
end

-- Starts the simulated Members. Returns true, or nil and "running" or
-- "notAlone".
function Sim.start(core)
  if net then return nil, "running" end
  local crew = core:crew()
  if not crew or crew.leaving or not crew.alone then return nil, "notAlone" end

  local now = GetServerTime()
  local own = core:rows()[1]
  local yourLevel = own and own.level or 10
  net = ns.FakeNet.new({ clock = now })
  local you = net:attach(core)
  ns.ChannelLink.onSend = function(message) net:broadcast(you, message) end
  members = {}
  local current = members
  for i, spec in ipairs(MEMBERS) do
    local client = net:add(spec.name)
    playHistory(client, i, spec, yourLevel, now)
    client:join(crew.code)
    members[i] = client
    if spec.offline then
      C_Timer.After(LOGOUT_AFTER, function()
        if members == current and client.core then client:logout() end
      end)
    end
  end
  ticker = C_Timer.NewTicker(1, function() net:step(GetServerTime()) end)
  return true
end

-- One online simulated Member dings. Returns their Character's name, or nil.
function Sim.ding()
  if not net then return nil end
  local online = {}
  for _, client in ipairs(members) do
    if client.core then online[#online + 1] = client end
  end
  if #online == 0 then return nil end
  local client = online[math.random(#online)]
  client:play({ level = client.character.level + 1, xp = 0 })
  return client.character.name
end

-- Logs the simulated Members out; you see them go offline.
function Sim.stop()
  if not net then return end
  for _, client in ipairs(members) do
    if client.core then client:logout() end
  end
  net:step(GetServerTime())
  ticker:Cancel()
  ns.ChannelLink.onSend = nil
  net, ticker, members = nil, nil, nil
end
