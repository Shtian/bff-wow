-- Sim: /bff sim attaches a few simulated Members to your real Core through
-- FakeNet, so the panel can be tried without another Member online. Their
-- records are kept and relayed like real ones, so it only runs in a Crew
-- where no one else is known yet: start a test Crew for it. Left out of
-- releases.

local _, ns = ...

local Sim = {}
ns.Sim = Sim

local MEMBERS = {
  { name = "Simone", classFilename = "MAGE", level = 12, zone = "Westfall" },
  { name = "Simbad", classFilename = "ROGUE", level = 17, zone = "Redridge Mountains" },
  { name = "Simba", classFilename = "DRUID", level = 9, zone = "Teldrassil" },
}

local net
local ticker
local members

-- Starts the simulated Members. Returns true, or nil and "running" or
-- "notAlone".
function Sim.start(core)
  if net then return nil, "running" end
  local crew = core:crew()
  if not crew or crew.leaving or not crew.alone then return nil, "notAlone" end

  net = ns.FakeNet.new({ clock = GetServerTime() })
  local you = net:attach(core)
  ns.ChannelLink.onSend = function(message) net:broadcast(you, message) end
  members = {}
  for i, member in ipairs(MEMBERS) do
    local client = net:add(member.name, {
      character = {
        guid = "Player-0-Sim" .. i, name = member.name, classFilename = member.classFilename,
        level = member.level, xp = 300 * i, maxXp = 1000 + 200 * i, zone = member.zone, deaths = i,
      },
    })
    client:login()
    client:join(crew.code)
    members[i] = client
  end
  ticker = C_Timer.NewTicker(1, function() net:step(GetServerTime()) end)
  return true
end

-- One simulated Member dings. Returns their Character's name, or nil.
function Sim.ding()
  if not net then return nil end
  local client = members[math.random(#members)]
  client:play({ level = client.character.level + 1, xp = 0 })
  return client.character.name
end

-- Logs the simulated Members out; you see them go offline.
function Sim.stop()
  if not net then return end
  for _, client in ipairs(members) do client:logout() end
  net:step(GetServerTime())
  ticker:Cancel()
  ns.ChannelLink.onSend = nil
  net, ticker, members = nil, nil, nil
end
