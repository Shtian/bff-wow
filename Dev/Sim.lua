-- Sim: /bff sim attaches a few simulated Members to your real Core through
-- FakeNet, so the panel can be tried without another Member online. Their
-- records are kept and relayed like real ones, so it only runs in a Crew
-- where no one else is known yet: start a test Crew for it. It fills the
-- Camp: two sit by the fire, two fall asleep, one with a fresh max level,
-- and one by the fire leaves two graves. Also the dev
-- console (/bffdev, opened by /bff sim too): buttons that make each
-- simulated Member ding, die, move, fish (a Catch, or now and then an
-- unlisted one), step through what they're doing (a vendor, the auction
-- house, fighting, resting, flying), hand in a quest, react to your newest
-- entry, offer a
-- test Spare, Claim your newest one or log out,
-- one that plays out a stretch of you being away so While you were away
-- shows (with Reactions to your entries), one that reaches the next Crew
-- deaths goal, one where simulated Members clear the next dungeon, and a
-- live log of what your Core sends, receives and fires (and the sync
-- trace, with its Sync trace box). /bffdev toast [n]
-- shows sample toasts. Also the encounter logger: every ENCOUNTER_END is
-- printed and saved with what the game and BFF made of it, for
-- docs/research/boss-kills.md (/bffdev encounters). Left out of releases;
-- it lives here, not in a file of its own, so the .toc (a shipped file)
-- stays as it is.

local _, ns = ...

local Sim = {}
ns.Sim = Sim

local DAY = 24 * 60 * 60
-- WoW: Forever's level span. Simulated Members keep to it even on a client
-- with a higher cap (testing on retail), so the Together line and the
-- Roster look as they will in game.
local MAX_LEVEL = 60
-- Their levels are around yours, or around this when you're above the
-- span (a retail Character).
local BASE_LEVEL = 24
-- How long after starting the offline Members log out.
local LOGOUT_AFTER = 20
-- How long after starting the Camp gets its news: Simone dies twice (two
-- graves) and Simba reaches max level (a spark) before going to sleep.
local CAMP_NEWS_AFTER = 5

-- Made-up final bosses for every dungeon and raid, since Forever's
-- encounter IDs aren't known yet: the simulated Members' Cores know these,
-- so their clears are recorded through the real encounterEnded().
local SIM_BOSS = 900000
local SIM_FINALS = {}
for _, dungeon in ipairs(ns.Core.DUNGEONS) do
  if dungeon.kind == "dungeon" or dungeon.kind == "raid" then SIM_FINALS[SIM_BOSS + dungeon.index] = dungeon.name end
end

-- Professions as Snapshot reads them: skill line ID, name, icon file ID,
-- then skill and max per Character that has it.
local PROFESSIONS = {
  alchemy = { 171, "Alchemy", 136240 },
  herbalism = { 182, "Herbalism", 136246 },
  mining = { 186, "Mining", 136248 },
  blacksmithing = { 164, "Blacksmithing", 136241 },
  tailoring = { 197, "Tailoring", 136249 },
  skinning = { 393, "Skinning", 134366 },
  firstAid = { 129, "First Aid", 135966, true },
  fishing = { 356, "Fishing", 136245, true },
  cooking = { 185, "Cooking", 133971, true },
}

local function professions(...)
  local list = {}
  for i = 1, select("#", ...), 3 do
    local key, skill, max = select(i, ...)
    local p = PROFESSIONS[key]
    list[#list + 1] = { skillLine = p[1], name = p[2], icon = p[3], skill = skill, max = max, secondary = p[4] }
  end
  return list
end

-- levelOffset is relative to the Character you play, so "can play" shows up.
-- The first Character is the one being played; the others were played
-- `ago` seconds earlier. main picks the Character set as Main, if any.
local MEMBERS = {
  -- Online on their Main, and can play with you.
  { name = "Simone", characters = {
    { name = "Simone", classFilename = "MAGE", levelOffset = 2, zone = "Westfall",
      professions = professions("herbalism", 300, 300, "alchemy", 287, 300, "cooking", 300, 300) },
    { name = "Simonette", classFilename = "PRIEST", levelOffset = -8, zone = "Darkshore", ago = 2 * DAY,
      professions = professions("tailoring", 140, 150, "firstAid", 150, 150) },
  } },
  -- On an Alt, with a Main that can play with you.
  { name = "Simbad", main = 2, characters = {
    { name = "Simbad", classFilename = "ROGUE", levelOffset = 10, zone = "Redridge Mountains",
      professions = professions("skinning", 120, 150, "fishing", 211, 225) },
    { name = "Simbadsson", classFilename = "WARRIOR", levelOffset = -1, zone = "Wetlands", ago = DAY,
      professions = professions("mining", 300, 300, "blacksmithing", 262, 300) },
  } },
  -- Logs out soon after, with an Alt unseen for 40 days (hidden).
  { name = "Simba", offline = true, characters = {
    { name = "Simba", classFilename = "DRUID", levelOffset = 6, zone = "Teldrassil" },
    { name = "Simbalina", classFilename = "HUNTER", levelOffset = -15, zone = "Durotar", ago = 40 * DAY },
  } },
  -- Another sleeper for the Camp.
  { name = "Mirelle", offline = true, characters = {
    { name = "Mirelle", classFilename = "PALADIN", levelOffset = -5, zone = "Darkshore" },
  } },
}

local ZONES = {
  "Elwynn Forest", "Westfall", "Duskwood", "Redridge Mountains", "Stormwind City",
  "Durotar", "The Barrens", "Ashenvale", "Stranglethorn Vale", "Ironforge",
}

-- Each zone's uiMapID as the classic-era clients number them, then as
-- retail does, so the simulated Members get world map pins. Which
-- numbering a client uses isn't known up front (Forever may have its
-- own), so mapIdFor asks C_Map and takes the one whose map has the
-- zone's name, or else looks the name up in the client's map tree.
local MAP_IDS = {
  ["Elwynn Forest"] = { 1429, 37 }, ["Westfall"] = { 1436, 52 }, ["Duskwood"] = { 1431, 47 },
  ["Redridge Mountains"] = { 1433, 49 }, ["Stormwind City"] = { 1453, 84 }, ["Durotar"] = { 1411, 1 },
  -- Retail splits the Barrens; its Northern Barrens is 10.
  ["The Barrens"] = { 1413, 10 }, ["Ashenvale"] = { 1440, 63 }, ["Stranglethorn Vale"] = { 1434, 224 },
  ["Ironforge"] = { 1455, 87 }, ["Teldrassil"] = { 1438, 57 }, ["Darkshore"] = { 1439, 62 },
  ["Wetlands"] = { 1437, 56 },
}
-- Names other than the zone's own that count as a match.
local MAP_ALIASES = { ["The Barrens"] = "Northern Barrens" }
-- zone -> resolved uiMapID. Misses aren't kept: inside an instance the
-- tree can't be read, and it can be once you're back out.
local resolved = {}

local function named(info, zone)
  return info and (info.name == zone or info.name == MAP_ALIASES[zone])
end

-- The top of the map tree you stand in (the cosmic or world map).
local function rootMap()
  local id = C_Map.GetBestMapForUnit("player")
  local info = id and C_Map.GetMapInfo(id)
  while info and info.parentMapID and info.parentMapID ~= 0 do
    id = info.parentMapID
    info = C_Map.GetMapInfo(id)
  end
  return id
end

-- A zone or city map under the root with the zone's name, for clients
-- that number maps neither way.
local function searchTree(zone)
  local root = rootMap()
  if not root then return nil end
  local wanted = { [Enum.UIMapType.Zone] = true, [Enum.UIMapType.City] = true }
  for _, info in ipairs(C_Map.GetMapChildrenInfo(root, nil, true) or {}) do
    if wanted[info.mapType] and named(info, zone) then return info.mapID end
  end
  return nil
end

local function mapIdFor(zone)
  if resolved[zone] then return resolved[zone] end
  local found
  for _, id in ipairs(MAP_IDS[zone] or {}) do
    if named(C_Map.GetMapInfo(id), zone) then
      found = id
      break
    end
  end
  found = found or searchTree(zone)
  resolved[zone] = found
  return found
end

-- A made-up spot somewhere in the middle of the zone, for locate().
local function spotIn(zone)
  local mapId = mapIdFor(zone)
  if not mapId then return nil end
  return { mapId = mapId, x = 0.3 + 0.4 * math.random(), y = 0.3 + 0.4 * math.random() }
end

local net
local ticker
local members
-- Your Member id, whose entries the React button reacts to.
local yourId

-- The GUID of member i's Character j.
local function guidFor(i, j)
  return ("Player-0-Sim%d-%d"):format(i, j)
end

local function character(i, j, spec, yourLevel)
  return {
    guid = guidFor(i, j), name = spec.name, classFilename = spec.classFilename,
    level = math.max(1, math.min(MAX_LEVEL, yourLevel + spec.levelOffset)), xp = 300 * j, maxXp = 1000 + 200 * i,
    zone = spec.zone, deaths = i + j, professions = spec.professions,
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
    client.characters[j] = character(i, j, spec.characters[j], yourLevel)
    client.current = j
    client.character = client.characters[j]
    client:move(spotIn(client.character.zone))
    if client.core then client:play() else client:login() end
  end
  net.clock = now
  if spec.main then client.core:setMain(guidFor(i, spec.main)) end
end

-- Four weeks of made-up Play times for the When tab: each Member has
-- their own evening hours (UTC) and plays most weeks, plus weekend
-- afternoons now and then.
local function playTimesHistory(i, now)
  local PlayTimes = ns.PlayTimes
  local current = PlayTimes.week(now)
  local weeks = {}
  for age = 0, PlayTimes.WEEKS - 1 do
    local week = current - age
    local slots = {}
    for day = 0, 6 do
      for hour = 0, 23 do
        local evening = day < 5 and hour >= 17 + i and hour <= 20 + i
        local weekend = day >= 5 and hour >= 12 + i and hour <= 15 + i
        if (evening and (week + day + i) % 3 ~= 0) or (weekend and (week + i) % 2 == 0) then
          slots[day * 24 + hour + 1] = 20 * 60
        end
      end
    end
    weeks[week] = slots
  end
  return { since = now - 30 * 24 * 60 * 60, weeks = weeks }
end

-- Fished items that aren't on Catches' list, so unlisted catches show.
local UNLISTED = { 271647, 271648 }

-- The client fishes in the zone it's in, as Snapshot.catch would read it:
-- mostly something on the list, now and then an unlisted find. Returns
-- the item ID.
local function fishUp(client)
  local itemId
  if math.random() < 0.1 then
    itemId = UNLISTED[math.random(#UNLISTED)]
  else
    local types = ns.Catches.TYPES
    local t = types[math.random(#types)]
    itemId = t.items[math.random(#t.items)]
  end
  client.core:caught({
    items = { { itemId = itemId, quantity = 1 } },
    zone = client.character.zone,
    mapId = client.location and client.location.mapId,
  })
  return itemId
end

-- A few days of past catches for the first two Members, so /bff catches
-- has something in it from the start.
local function fishHistory(client, i, now)
  if i > 2 then return end
  for day = 6, 1, -1 do
    net.clock = now - day * DAY + i * 3600
    fishUp(client)
  end
  net.clock = now
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
  if yourLevel > MAX_LEVEL then yourLevel = BASE_LEVEL end
  net = ns.FakeNet.new({
    clock = now, maxLevel = math.min(MAX_LEVEL, GetMaxLevelForPlayerExpansion()), finalBosses = SIM_FINALS,
  })
  local you = net:attach(core)
  yourId = core.ledger:memberId()
  -- The simulated Members only belong to the Crew the sim started in. Once
  -- you leave it (or join another), nothing more passes between them and
  -- you, or your Core would take their records into the new Crew and relay
  -- them to its real Members.
  local code = crew.code
  local function inSimCrew()
    local current = core:crew()
    return current ~= nil and current.code == code
  end
  ns.ChannelLink.onSend = function(message, to)
    if inSimCrew() then net:broadcast(you, message, to) end
  end
  members = {}
  local current = members
  for i, spec in ipairs(MEMBERS) do
    local client = net:add(spec.name, { db = { playTimes = playTimesHistory(i, now) } })
    client.characters = {}
    playHistory(client, i, spec, yourLevel, now)
    fishHistory(client, i, now)
    client:join(crew.code)
    members[i] = client
    if spec.offline then
      C_Timer.After(LOGOUT_AFTER, function()
        if members == current and client.core then client:logout() end
      end)
    end
  end
  C_Timer.After(CAMP_NEWS_AFTER, function()
    if members ~= current then return end
    local simone, simba = members[1], members[3]
    if simone.core then simone:play({ deaths = (simone.character.deaths or 0) + 2 }) end
    if simba.core then simba:play({ level = net.maxLevel, xp = 0 }) end
  end)
  ticker = C_Timer.NewTicker(1, function()
    if not inSimCrew() then return Sim.stop(true) end
    net:step(GetServerTime())
  end)
  ns.Console.open(core)
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

-- One online simulated Member catches something. Returns their
-- Character's name and the item ID, or nil.
function Sim.fish()
  if not net then return nil end
  local online = {}
  for _, client in ipairs(members) do
    if client.core then online[#online + 1] = client end
  end
  if #online == 0 then return nil end
  local client = online[math.random(#online)]
  return client.character.name, fishUp(client)
end

function Sim.isRunning()
  return net ~= nil
end

-- What the console shows per simulated Member: name, online, and the
-- Character being played.
function Sim.members()
  local list = {}
  for i, client in ipairs(members or {}) do
    list[i] = { name = client.name, online = client.core ~= nil, character = client.character }
  end
  return list
end

local function otherZone(current)
  local zone
  repeat zone = ZONES[math.random(#ZONES)] until zone ~= current
  return zone
end

-- Reacts to your newest Feed entry the client can still react to.
local function reactToYou(client, you)
  for _, day in ipairs(client.core:feed().days) do
    for _, entry in ipairs(day.entries) do
      if entry.memberId == you and entry.canReact and not entry.reacted then
        return client.core:react(entry.key)
      end
    end
  end
  return false
end

-- Test Spares, as links the way the game hands them out: one
-- plain, one with an enchant, one with a scaling random suffix.
local TEST_ITEMS = {
  { link = "|cff1eff00|Hitem:5191::::::::18:::::::|h[Cruel Barb]|h|r", level = 19 },
  { link = "|cff1eff00|Hitem:2042:1897:::::::20:::::::|h[Staff of Westfall]|h|r", level = 18 },
  { link = "|cff1eff00|Hitem:15210::::::-19:1238425:30:::::::|h[Raider Shortsword of the Monkey]|h|r", level = 15 },
}

-- Offers a test Spare to the Crew.
local function offer(client, i)
  local item = TEST_ITEMS[(i - 1) % #TEST_ITEMS + 1]
  return client.core:postSpare(item.link, item.level)
end

-- Claims your newest Spare the client hasn't claimed yet.
local function claimYours(client, you)
  for _, row in ipairs(client.core:spares().crew) do
    if row.ownerId == you and row.canClaim then
      return client.core:claimSpare(row.ownerId, row.id)
    end
  end
  return false
end

-- Steps the Character's first profession short of 300 up to its next
-- milestone, or picks up Tailoring if it has none to raise. A Character
-- whose client never shared professions (Simba's) is left alone.
local function skillUp(client)
  local known = client.character.professions
  if not known then return end
  local list = {}
  for i, p in ipairs(known) do
    list[i] = { skillLine = p.skillLine, name = p.name, icon = p.icon, skill = p.skill, max = p.max,
      secondary = p.secondary }
  end
  for _, p in ipairs(list) do
    for _, milestone in ipairs(ns.Professions.MILESTONES) do
      if p.skill < milestone then
        p.skill, p.max = milestone, math.max(p.max, milestone)
        client:play({ professions = list })
        return
      end
    end
  end
  local tailoring = PROFESSIONS.tailoring
  if #list < 2 then
    list[#list + 1] = { skillLine = tailoring[1], name = tailoring[2], icon = tailoring[3], skill = 1, max = 75 }
    client:play({ professions = list })
  end
end

-- What the console's Doing button steps a simulated Member through, as
-- Snapshot.doing would report each.
local DOING = { { vendor = true }, { auction = true }, { combat = true }, { resting = true }, { flying = true } }

-- What each console button does to a simulated Member's client.
local ACTIONS = {
  skill = skillUp,
  ding = function(client) client:play({ level = client.character.level + 1, xp = 0 }) end,
  xp = function(client)
    local c = client.character
    client:play({ xp = math.min(c.maxXp - 1, c.xp + math.floor(c.maxXp / 4)) })
  end,
  die = function(client) client:play({ deaths = (client.character.deaths or 0) + 1 }) end,
  zone = function(client)
    local zone = otherZone(client.character.zone)
    client:move(spotIn(zone))
    client:play({ zone = zone })
  end,
  max = function(client) client:play({ level = net.maxLevel, xp = 0 }) end,
  -- Switches to the Member's next Character, as logging in on an Alt would.
  alt = function(client)
    client.current = client.current % #client.characters + 1
    client.character = client.characters[client.current]
    client:move(spotIn(client.character.zone))
    client:play()
  end,
  react = function(client) reactToYou(client, yourId) end,
  fish = fishUp,
  -- Steps through what a Member can be doing, then back to nothing.
  doing = function(client)
    client.doingStep = (client.doingStep or 0) % (#DOING + 1) + 1
    client.core:doing(DOING[client.doingStep] or {})
  end,
  quest = function(client) client.core:questHandedIn() end,
  offer = function(client, i) offer(client, i) end,
  claim = function(client) claimYours(client, yourId) end,
  online = function(client)
    if client.core then client:logout() else client:login() end
  end,
}

-- Makes simulated Member i do action (a key of ACTIONS). Online-only
-- actions do nothing while they're logged out. Returns true if it did
-- something.
function Sim.act(i, action)
  local client = members and members[i]
  if not client or not ACTIONS[action] then return false end
  if action ~= "online" and not client.core then return false end
  ACTIONS[action](client, i)
  return true
end

-- How long after Sim.away an offline Member who played logs out again.
local AWAY_LOGOUT_AFTER = 5

local function levelUp(client, levels)
  return { level = math.min(net.maxLevel, client.character.level + levels), xp = 0 }
end

local function playCharacter(client, j)
  client.current = j
  client.character = client.characters[j]
  client:play()
end

-- What each simulated Member gets up to while you're away, by index.
local AWAY = {
  -- Rolls a new Character and plays it a little, then dings and dies on
  -- the one they were on.
  function(client, i)
    local was = client.current
    local j
    for k, c in ipairs(client.characters) do
      if c.name == "Simonetta" then j = k end
    end
    if not j then
      j = #client.characters + 1
      client.characters[j] = {
        guid = guidFor(i, j), name = "Simonetta", classFilename = "WARLOCK",
        level = 1, xp = 0, maxXp = 400, zone = "Elwynn Forest", deaths = 0,
      }
    end
    playCharacter(client, j)
    client:play(levelUp(client, 4))
    playCharacter(client, was)
    client:play(levelUp(client, 3))
    client:play({ deaths = (client.character.deaths or 0) + 2 })
  end,
  -- Dings and dies on the one they're on, then dings on the other.
  function(client)
    client:play(levelUp(client, 2))
    client:play({ deaths = (client.character.deaths or 0) + 1 })
    playCharacter(client, client.current % #client.characters + 1)
    client:play(levelUp(client, 1))
  end,
  -- Reaches max level.
  function(client)
    client:play({ level = net.maxLevel, xp = 0 })
  end,
}

-- Plays out a stretch of you being away: core goes back to how it is
-- right after logging in, so what happens next isn't announced, then each
-- simulated Member plays (logging in first if offline, and out again
-- after). Once sync settles, Core sends While you were away as on a real
-- login. Returns true, or nil and "notRunning".
function Sim.away(core)
  if not net then return nil, "notRunning" end
  local log = core.log
  log.settle:restart()
  if core.linkUp then log:linkUp() end
  local current = members
  for i, client in ipairs(members) do
    local wasOffline = not client.core
    if wasOffline then client:login() end
    AWAY[i](client, i)
    reactToYou(client, core.ledger:memberId())
    if wasOffline then
      C_Timer.After(AWAY_LOGOUT_AFTER, function()
        if members == current and client.core then client:logout() end
      end)
    end
  end
  return true
end

-- The first simulated Member online dies as many times as the Crew needs
-- to reach its next Crew deaths goal, so the goal's Feed entry and toast
-- show. Returns the rung, or nil and "notRunning" or "nobodyOnline".
function Sim.goal(core)
  if not net then return nil, "notRunning" end
  local client
  for _, member in ipairs(members) do
    if member.core then client = client or member end
  end
  if not client then return nil, "nobodyOnline" end
  for _, goal in ipairs(core:goals()) do
    if goal.track == "deaths" then
      client:play({ deaths = (client.character.deaths or 0) + goal.goal - goal.value })
      return goal.rung
    end
  end
end

-- The simulated Members online clear the first dungeon (or raid, with
-- kind "raid") the Crew hasn't, in one party, each recording it as their
-- client would. The Crew trophy's Feed entry and toast follow once their
-- records reach you. Returns the instance's name, or nil and
-- "notRunning", "nobodyOnline" or "allCleared".
function Sim.clear(core, kind)
  if not net then return nil, "notRunning" end
  local party = {}
  for _, member in ipairs(members) do
    if member.core then party[#party + 1] = member end
  end
  if #party == 0 then return nil, "nobodyOnline" end
  local trophies = core:trophies()
  local grid = kind == "raid" and trophies.raids or trophies.dungeons
  local target
  for _, slot in ipairs(grid.slots) do
    if not slot.cleared then target = target or slot end
  end
  if not target then return nil, "allCleared" end
  local id
  for boss, name in pairs(SIM_FINALS) do
    if name == target.name then id = boss end
  end
  local group = {}
  for i, member in ipairs(party) do
    group[i] = { guid = member.character.guid, name = member.character.name }
  end
  for _, member in ipairs(party) do
    member.core:encounterEnded({
      encounterId = id, success = true, instanceType = kind == "raid" and "raid" or "party", party = group,
    })
  end
  return target.name
end

-- Logs the simulated Members out; you see them go offline. abandoned (you
-- left the sim's Crew) drops whatever is still on the wire instead, so
-- none of it reaches you.
function Sim.stop(abandoned)
  if not net then return end
  if abandoned then
    net.queue = {}
  else
    for _, client in ipairs(members) do
      if client.core then client:logout() end
    end
    net:step(GetServerTime())
  end
  ticker:Cancel()
  ns.ChannelLink.onSend = nil
  net, ticker, members = nil, nil, nil
end

-- Whether a record is one of the simulated Members': their Characters'
-- GUIDs all come from guidFor.
local function isSimulated(record)
  local any = false
  for _, held in pairs(record.characters or {}) do
    if type(held.guid) ~= "string" or not held.guid:find("^Player%-0%-Sim%d") then
      return false
    end
    any = true
  end
  return any
end

-- Clears simulated Members out of a real Crew they leaked into (the sim
-- once kept running after you left its Crew): each one held gets a newer
-- record saying they left, as if they had sent it themselves, so your Core
-- stops showing them and gossip carries it to the other Members. Returns
-- how many, or nil and "running".
function Sim.purge(core)
  if net then return nil, "running" end
  local count = 0
  for id, record in core.ledger:records() do
    if id ~= core.ledger:memberId() and not record.left and isSimulated(record) then
      local tombstone = {
        id = id, version = math.max(GetServerTime(), record.version + 1),
        displayName = record.displayName, left = true,
      }
      core:received(ns.Codec.encode({ type = "DATA", from = id, records = { tombstone } }))
      count = count + 1
    end
  end
  return count
end

-- Console: the dev window. Watching starts the first time it opens, by
-- wrapping the real Core's link, listener and incoming calls, and goes on
-- until a /reload.

local Console = {}
ns.Console = Console

local Skin = ns.Skin

local WIDTH = 868
local HEIGHT = 480
local INSET = 12
local ROW_HEIGHT = 28
local BUTTON_WIDTH = 50
-- Enough for an evening of the sync trace.
local MAX_LINES = 5000

local SENT = "ffd14a"
local RECEIVED = "70e370"
local EVENT = "8fb6ff"
local LINK = "c0a0ff"
local DIM = "8c8a99"
local TRACE = "e0a070"

-- The console buttons on each simulated Member's row, left to right.
local BUTTONS = {
  { "ding", "Ding" }, { "xp", "XP" }, { "die", "Die" }, { "zone", "Zone" },
  { "alt", "Alt" }, { "max", "Max" }, { "skill", "Skill" }, { "fish", "Fish" }, { "doing", "Doing" }, { "quest", "Quest" },
  { "react", "React" }, { "offer", "Offer" },
  { "claim", "Claim" }, { "online", "Log out" },
}

local frame
local watched
local showChanged = false

local function color(hex, text)
  return "|cff" .. hex .. text .. "|r"
end

local function log(text)
  if not frame then return end
  frame.log:AddMessage(color(DIM, date("%H:%M:%S")) .. "  " .. text)
end

-- The sync trace (/bff debug sync, or the console's Sync trace box) shows
-- here instead of chat once the console has been opened, hidden or not.
ns.traceSink = function(stamp, text)
  if not frame then return false end
  frame.log:AddMessage(color(DIM, stamp) .. "  " .. color(TRACE, "trace  ") .. text)
  return true
end

-- A Member id as a name: you, a simulated Member, or whoever the panel
-- shows for it.
local function nameOf(id)
  if id == watched.ledger:memberId() then return "you" end
  for _, client in ipairs(members or {}) do
    if client.memberId == id then return client.name end
  end
  for _, row in ipairs(watched:rows()) do
    if row.memberId == id then return row.displayName or row.name end
  end
  return id
end

-- A record in one line: who, and the Character they played last.
local function describeRecord(record)
  local latest
  for _, c in pairs(record.characters or {}) do
    if not latest or (c.lastPlayed or 0) > (latest.lastPlayed or 0) then latest = c end
  end
  local who = record.displayName or nameOf(record.id)
  if not latest then return who end
  return ("%s: %s L%s %s, %s deaths"):format(who, latest.name, latest.level, latest.zone or "?", latest.deaths or 0)
end

-- A wire message in one line, and the Member id that sent it.
local function describe(message)
  local decoded, reason = ns.Codec.decode(message)
  if type(decoded) ~= "table" then return color(DIM, "undecodable (" .. tostring(reason) .. ")") end
  if decoded.type == "DIGEST" then
    local n = 0
    for _ in pairs(decoded.versions or {}) do n = n + 1 end
    return ("DIGEST %d version%s"):format(n, n == 1 and "" or "s"), decoded.from
  elseif decoded.type == "DATA" then
    local parts = {}
    for _, record in ipairs(decoded.records or {}) do parts[#parts + 1] = describeRecord(record) end
    return "DATA " .. table.concat(parts, "; "), decoded.from
  end
  return tostring(decoded.type), decoded.from
end

local function onEvent(event, arg)
  if event == "changed" then
    if showChanged then log(color(DIM, "changed")) end
  elseif event == "feedEntry" then
    log(color(EVENT, "feed  ") .. arg.text)
  elseif event == "reaction" then
    log(color(EVENT, "reaction  ") .. arg.text)
  elseif event == "spare" then
    log(color(EVENT, "spare  ") .. arg.text)
  elseif event == "pocketCampAnimation" then
    log(color(EVENT, "pocket camp  ") .. arg.kind .. (arg.memberId and "  " .. nameOf(arg.memberId) or ""))
  elseif event == "awaySummary" then
    log(color(EVENT, "away summary  ") .. tostring(arg.count) .. " entries from " .. #arg.members .. " Members")
  else
    log(color(EVENT, event) .. (arg ~= nil and "  " .. tostring(arg) or ""))
  end
end

-- Wraps the Core's ports on the instance, so every message and event also
-- reaches the log. Your own messages echoed back by the channel are left
-- out: they show once, as sent.
local function watch(core)
  if watched then return end
  watched = core

  local link = core.link
  core.link = {
    send = function(message, to)
      log(color(SENT, "-> sent  ") .. (describe(message)) .. (to and (" to " .. to) or ""))
      return link.send(message, to)
    end,
  }

  local listener = core.listener
  core.listener = function(event, ...)
    onEvent(event, ...)
    return listener(event, ...)
  end

  local received, up, down, gone = core.received, core.up, core.down, core.gone
  function core.received(self, message, sender)
    local text, from = describe(message)
    if from ~= self.ledger:memberId() then
      log(color(RECEIVED, "<- " .. (from and nameOf(from) or "?") .. "  ") .. text)
    end
    return received(self, message, sender)
  end
  function core.up(self)
    log(color(LINK, "link up"))
    return up(self)
  end
  function core.down(self)
    log(color(LINK, "link down"))
    return down(self)
  end
  function core.gone(self, name)
    log(color(LINK, "gone  ") .. tostring(name))
    return gone(self, name)
  end
end

local function refreshMembers()
  local list = Sim.members()
  local running = Sim.isRunning()
  frame.headerRight:SetText(running and "sim running" or "sim off")
  frame.start:SetEnabled(not running)
  frame.start:SetAlpha(running and 0.4 or 1)
  frame.stop:SetEnabled(running)
  frame.stop:SetAlpha(running and 1 or 0.4)
  frame.away:SetEnabled(running)
  frame.away:SetAlpha(running and 1 or 0.4)
  frame.empty:SetShown(not running)
  for i, row in ipairs(frame.rows) do
    local member = list[i]
    row:SetShown(member ~= nil)
    if member then
      local c = member.character
      local state = member.online and color("70e370", "online") or color(DIM, "offline")
      row.label:SetText(("%s  %s\n%s L%d %s, %d xp, %d deaths"):format(
        member.name, state, c.name, c.level, c.zone, c.xp, c.deaths or 0))
      for _, button in ipairs(row.buttons) do
        if button.action == "online" then
          button:SetText(member.online and "Log out" or "Log in")
        else
          button:SetEnabled(member.online)
          button:SetAlpha(member.online and 1 or 0.4)
        end
      end
    end
  end
end

local function memberRow(i)
  local row = CreateFrame("Frame", nil, frame)
  row:SetHeight(ROW_HEIGHT)
  row:SetPoint("TOPLEFT", INSET, -(Skin.HEADER_HEIGHT + 44 + (i - 1) * (ROW_HEIGHT + 4)))
  row:SetPoint("RIGHT", -INSET, 0)
  row.buttons = {}
  local anchor
  for b = #BUTTONS, 1, -1 do
    local action, text = BUTTONS[b][1], BUTTONS[b][2]
    local button = Skin.button(row, text, function()
      if Sim.act(i, action) then
        local member = Sim.members()[i]
        log(color(DIM, ("sim  %s: %s"):format(member.name, action)))
      end
      refreshMembers()
    end)
    button:SetSize(action == "online" and 64 or BUTTON_WIDTH, 22)
    if anchor then button:SetPoint("RIGHT", anchor, "LEFT", -4, 0) else button:SetPoint("RIGHT", 0, 0) end
    button.action = action
    anchor = button
    row.buttons[#row.buttons + 1] = button
  end
  -- Cut short with "..." rather than run under the buttons.
  row.label = Skin.label(row, "small", Skin.TEXT)
  row.label:SetPoint("TOPLEFT", 0, 0)
  row.label:SetPoint("BOTTOMLEFT", 0, 0)
  row.label:SetPoint("RIGHT", anchor, "LEFT", -8, 0)
  return row
end

local function create()
  frame = Skin.window("BFFDevConsole", WIDTH, "BFF dev console")
  frame:SetHeight(HEIGHT)
  frame:SetPoint("CENTER", 200, 0)

  local top = -(Skin.HEADER_HEIGHT + 10)
  frame.start = Skin.button(frame, "Start sim", function()
    local ok, reason = Sim.start(watched)
    if not ok then
      log(color(DIM, reason == "notAlone"
        and "the sim needs a Crew no one else is in yet: /bff leave, then /bff start"
        or "the sim is already running"))
    end
    refreshMembers()
  end, true)
  frame.start:SetPoint("TOPLEFT", INSET, top)
  frame.stop = Skin.button(frame, "Stop sim", function()
    Sim.stop()
    refreshMembers()
  end)
  frame.stop:SetPoint("LEFT", frame.start, "RIGHT", 6, 0)
  local clear = Skin.button(frame, "Clear log", function() frame.log:Clear() end)
  clear:SetPoint("LEFT", frame.stop, "RIGHT", 6, 0)
  frame.away = Skin.button(frame, "Away", function()
    if not Sim.away(watched) then return end
    log(color(DIM, watched:isAwayPopupOn()
      and "sim  you were away: the popup shows once sync settles (about 10 s)"
      or "sim  you were away, but the popup is off in Settings"))
  end)
  frame.away:SetPoint("LEFT", clear, "RIGHT", 6, 0)
  frame.goal = Skin.button(frame, "Goal", function()
    local rung, reason = Sim.goal(watched)
    if rung then
      log(color(DIM, ("sim  the Crew dies its way to %d deaths"):format(rung)))
    elseif reason == "nobodyOnline" then
      log(color(DIM, "sim  log a simulated Member in first"))
    end
  end)
  frame.goal:SetPoint("LEFT", frame.away, "RIGHT", 6, 0)
  frame.dungeon = Skin.button(frame, "Dungeon", function()
    local name, reason = Sim.clear(watched)
    if name then
      log(color(DIM, ("sim  the simulated Members online clear %s"):format(name)))
    elseif reason == "nobodyOnline" then
      log(color(DIM, "sim  log a simulated Member in first"))
    elseif reason == "allCleared" then
      log(color(DIM, "sim  the Crew has cleared every dungeon"))
    end
  end)
  frame.dungeon:SetPoint("LEFT", frame.goal, "RIGHT", 6, 0)
  local changed = Skin.checkbox(frame, "Log every \"changed\"", function(self)
    showChanged = self:GetChecked()
  end)
  changed:SetPoint("LEFT", frame.dungeon, "RIGHT", 12, 0)
  frame.trace = Skin.checkbox(frame, "Sync trace", function(self)
    ns.setSyncTrace(self:GetChecked())
    log(color(DIM, ns.isSyncTraceOn() and "sync trace on" or "sync trace off"))
  end)
  frame.trace:SetPoint("LEFT", changed.label, "RIGHT", 12, 0)

  frame.empty = Skin.label(frame, "small", Skin.MUTED)
  frame.empty:SetPoint("TOPLEFT", INSET, top - 38)
  frame.empty:SetText("The sim is off. The log still shows real traffic on your Crew's channel.")

  frame.rows = {}
  for i = 1, #MEMBERS do frame.rows[i] = memberRow(i) end

  local logTop = Skin.HEADER_HEIGHT + 44 + #MEMBERS * (ROW_HEIGHT + 4) + 8
  local plate = CreateFrame("Frame", nil, frame)
  plate:SetPoint("TOPLEFT", INSET, -logTop)
  plate:SetPoint("BOTTOMRIGHT", -INSET, INSET)
  Skin.fill(plate, { 0, 0, 0, 0.35 })
  Skin.border(plate, Skin.BORDER)

  local messages = CreateFrame("ScrollingMessageFrame", nil, plate)
  messages:SetPoint("TOPLEFT", 6, -6)
  messages:SetPoint("BOTTOMRIGHT", -6, 6)
  messages:SetFontObject(Skin.fonts.small)
  messages:SetJustifyH("LEFT")
  messages:SetFading(false)
  messages:SetMaxLines(MAX_LINES)
  messages:EnableMouseWheel(true)
  messages:SetScript("OnMouseWheel", function(self, delta)
    if delta > 0 then self:ScrollUp() else self:ScrollDown() end
  end)
  frame.log = messages

  -- The simulated Members' rows follow their state, whoever changed it.
  local elapsedSince = 0
  frame:SetScript("OnUpdate", function(_, elapsed)
    elapsedSince = elapsedSince + elapsed
    if elapsedSince >= 0.5 then
      elapsedSince = 0
      refreshMembers()
      frame.trace:SetChecked(ns.isSyncTraceOn())
    end
  end)
end

-- Opens the console, and starts watching core the first time.
function Console.open(core)
  if not frame then create() end
  watch(core)
  refreshMembers()
  frame.trace:SetChecked(ns.isSyncTraceOn())
  frame:Show()
end

function Console.toggle(core)
  if frame and frame:IsShown() then frame:Hide() else Console.open(core) end
end

SLASH_BFFDEV1 = "/bffdev"
-- Sample toasts, one of each kind, for /bffdev toast.
local SAMPLE_TOASTS = {
  { kind = "ding", text = "Simone dinged 24" },
  { kind = "death", text = "Simbad died 2 times" },
  { kind = "maxLevel", text = "Simba reached max level!", highlight = true },
  { kind = "newCharacter", text = "Simone has a new Character: Simonette (Priest)" },
  { kind = "joined", text = "Simbad joined the Crew", highlight = true },
  { kind = "left", text = "Simba left the Crew" },
  { kind = "goal", text = "The Crew reached 300 Crew levels!", highlight = true },
  { kind = "goal", text = "The Crew has an Engineer now!", highlight = true },
  { kind = "goal", text = "The Crew cleared The Deadmines!", highlight = true },
  { kind = "claimed", text = "Simone claimed [Cruel Barb] for Simonette", opens = "spares" },
  { kind = "given", text = "Simbad sent you [Staff of Westfall]. Check Simonette's mailbox.", opens = "spares" },
  { kind = "gave", text = "Simbad gave Simone [Staff of Westfall]" },
  { kind = "newProfession", text = "Simone's Alt Simmy picked up Tailoring", icon = 136249 },
  { kind = "professionSkill", text = "Simbad reached 225 Blacksmithing", icon = 136241 },
  { kind = "professionMaxed", text = "Simone maxed Alchemy", icon = 136240, highlight = true },
}

-- The encounter logger: every ENCOUNTER_END, printed and saved in
-- BFF_DB.devEncounters (the newest ENCOUNTER_LOG_MAX), with whether each
-- value is secret, GetInstanceInfo(), the group, and what BFF made of it.
-- For docs/research/boss-kills.md.
local ENCOUNTER_LOG_MAX = 200
local SECRET = "<secret>"

-- A value as it can be saved and printed, and whether it's secret.
local function plain(value)
  if issecretvalue and issecretvalue(value) then return SECRET, true end
  return value, false
end

local function logEncounter(...)
  local args = { ... }
  local entry = { time = GetServerTime(), secret = {}, instance = {} }
  local fields = { "encounterID", "encounterName", "difficultyID", "groupSize", "success" }
  for i, field in ipairs(fields) do
    entry[field], entry.secret[field] = plain(args[i])
  end
  local info = { GetInstanceInfo() }
  local infoFields = {
    "name", "instanceType", "difficultyID", "difficultyName", "maxPlayers",
    "dynamicDifficulty", "isDynamic", "instanceID", "instanceGroupSize", "LfgDungeonID",
  }
  for i, field in ipairs(infoFields) do
    entry.instance[field] = (plain(info[i]))
    if select(2, plain(info[i])) then entry.secret["instance." .. field] = true end
  end
  -- Read raw here, so a secret GUID or name shows as secret, not missing.
  entry.party = {}
  local units = {}
  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
  else
    units[1] = "player"
    for i = 1, 4 do units[#units + 1] = "party" .. i end
  end
  for _, unit in ipairs(units) do
    if UnitExists(unit) then
      local guid, guidSecret = plain(UnitGUID(unit))
      local name, nameSecret = plain((UnitName(unit)))
      entry.party[#entry.party + 1] = { unit = unit, guid = guid, name = name }
      if guidSecret then entry.secret[unit .. ".guid"] = true end
      if nameSecret then entry.secret[unit .. ".name"] = true end
    end
  end
  local name, reason = ns.Clears.cleared(ns.Snapshot.encounter(...), ns.Core.FINAL_BOSSES)
  entry.bff = name and ("clears " .. name) or reason
  BFF_DB.devEncounters = BFF_DB.devEncounters or {}
  local saved = BFF_DB.devEncounters
  saved[#saved + 1] = entry
  while #saved > ENCOUNTER_LOG_MAX do table.remove(saved, 1) end

  local secrets = {}
  for field in pairs(entry.secret) do
    if entry.secret[field] then secrets[#secrets + 1] = field end
  end
  local names = {}
  for i, unit in ipairs(entry.party) do names[i] = unit.name or "?" end
  print(("BFF dev: ENCOUNTER_END %s %q in %s (%s, instance %s) success %s; party %s; secret: %s; BFF: %s"):format(
    tostring(entry.encounterID), tostring(entry.encounterName), tostring(entry.instance.name),
    tostring(entry.instance.instanceType), tostring(entry.instance.instanceID), tostring(entry.success),
    table.concat(names, ", "), #secrets > 0 and table.concat(secrets, ", ") or "none", entry.bff))
  log(color(EVENT, "encounter  ") .. ("%s %s: %s"):format(tostring(entry.encounterID), tostring(entry.encounterName), entry.bff))
end

local encounterFrame = CreateFrame("Frame")
encounterFrame:RegisterEvent("ENCOUNTER_END")
encounterFrame:SetScript("OnEvent", function(_, _, ...)
  local ok, err = pcall(logEncounter, ...)
  if not ok then print("BFF dev: couldn't log ENCOUNTER_END: " .. tostring(err)) end
end)

-- /bffdev encounters: how many are saved and the last few; with "clear",
-- empties the log.
local function showEncounters(rest)
  if rest == "clear" then
    BFF_DB.devEncounters = nil
    return print("BFF dev: encounter log cleared.")
  end
  local saved = BFF_DB.devEncounters or {}
  print(("BFF dev: %d encounters saved in BFF_DB.devEncounters (written to SavedVariables on /reload or logout)."):format(#saved))
  for i = math.max(1, #saved - 4), #saved do
    local e = saved[i]
    print(("  %s %s %q in %s (instance %s): %s"):format(date("%d %b %H:%M", e.time), tostring(e.encounterID),
      tostring(e.encounterName), tostring(e.instance.name), tostring(e.instance.instanceID), tostring(e.bff)))
  end
end

-- /bffdev toggles the console; /bffdev toast [n] shows n sample toasts
-- (default 1), straight to the toasts and not through Core; /bffdev purge
-- runs Sim.purge; /bffdev clear [raid] makes the simulated Members online
-- clear the next dungeon (or raid); /bffdev encounters [clear] shows (or
-- empties) the encounter log.
SlashCmdList.BFFDEV = function(input)
  if not ns.core then return end
  local command, count = (input or ""):match("^%s*(%S*)%s*(%d*)")
  local rest = (input or ""):match("^%s*%S*%s*(.-)%s*$")
  if command == "encounters" then return showEncounters(rest) end
  if command == "clear" then
    local name, reason = Sim.clear(ns.core, rest == "raid" and "raid" or nil)
    print(name and ("BFF dev: the simulated Members online clear %s."):format(name)
      or ("BFF dev: no clear (%s)."):format(reason))
    return
  end
  if command == "purge" then
    local purged = Sim.purge(ns.core)
    print(purged and ("BFF: %d simulated Members marked as left."):format(purged)
      or "BFF: stop the sim first (/bff sim stop).")
    return
  end
  if command == "toast" then
    for i = 1, tonumber(count) or 1 do
      ns.Toasts.show(SAMPLE_TOASTS[(i - 1) % #SAMPLE_TOASTS + 1])
    end
    return
  end
  Console.toggle(ns.core)
end
