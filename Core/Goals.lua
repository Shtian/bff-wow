local _, ns = ...

local Goals = {}
Goals.__index = Goals
ns.Goals = Goals

Goals.TRACKS = { "crewLevels", "everyone", "deaths", "professions", "crewSkill", "everyoneRank", "catches", "rares" }

local CREW_LEVELS_STEP = 50
local EVERYONE_STEP = 10
local DEATHS_STEPS = { 25, 50, 100 }
local SKILL_STEPS = { 500, 1000, 2500 }
local RANK_STEP = 75
local FRESH = 3 * 24 * 60 * 60
local QUALITIES = { "uncommon", "uncommon", "rare", "rare", "epic", "epic" }
local TOP_QUALITY = "legendary"
local PROFESSIONS_QUALITY = "rare"
local CLEAR_QUALITIES = { dungeon = "epic", raid = "legendary" }
local CLEAR_TITLES = { dungeon = "Dungeons cleared", raid = "Raids cleared" }
local RARE_QUALITY, RARE_ELITE_QUALITY = "rare", "epic"

local Clears = ns.Clears
local Rares = ns.Rares

local PROFESSIONS = ns.Professions.ALL

local function scaled(steps, after)
  local scale = 1
  while true do
    for _, step in ipairs(steps) do
      if step * scale > after then return step * scale end
    end
    scale = scale * 10
  end
end

local grouped = ns.Text.grouped

local function aRank(skill)
  local rank = ns.Professions.rank(skill)
  return (rank:find("^[AEIOU]") and "an " or "a ") .. rank
end

local function listed(nouns)
  if #nouns == 1 then return nouns[1] end
  return table.concat(nouns, ", ", 1, #nouns - 1) .. " and " .. nouns[#nouns]
end

local function membersAt(values)
  return function(progress, rung)
    local at = 0
    for _, value in ipairs(progress[values]) do
      if value >= rung then at = at + 1 end
    end
    return at, progress.members, "Members"
  end
end

local TRACK = {
  crewLevels = {
    name = "Crew levels",
    next = function(after)
      return (math.floor(after / CREW_LEVELS_STEP) + 1) * CREW_LEVELS_STEP
    end,
    value = function(progress) return progress.crewLevels end,
    title = function() return "Crew levels" end,
    text = function(rung) return ("The Crew reached %d Crew levels!"):format(rung) end,
  },
  everyone = {
    name = "Everyone at a level",
    next = function(after, maxLevel)
      if after >= maxLevel then return nil end
      return math.min((math.floor(after / EVERYONE_STEP) + 1) * EVERYONE_STEP, maxLevel)
    end,
    value = function(progress) return progress.lowest end,
    title = function(rung)
      return rung and ("Everyone at level %d"):format(rung) or "Everyone at max level"
    end,
    text = function(rung, top)
      if top then return "Everyone in the Crew has a Character at max level!" end
      return ("Everyone in the Crew has a Character at %d!"):format(rung)
    end,
    bar = membersAt("highest"),
  },
  deaths = {
    name = "Crew deaths",
    next = function(after) return scaled(DEATHS_STEPS, after) end,
    value = function(progress) return progress.deaths end,
    title = function() return "Crew deaths" end,
    text = function(rung) return ("The Crew has died %d times together!"):format(rung) end,
  },
  professions = {
    name = "Every profession in the Crew",
    title = function() return "Every profession in the Crew" end,
  },
  crewSkill = {
    name = "Crew skill",
    next = function(after) return scaled(SKILL_STEPS, after) end,
    value = function(progress) return progress.skill end,
    title = function() return "Crew skill" end,
    text = function(rung) return ("The Crew has %s profession skill together!"):format(grouped(rung)) end,
  },
  everyoneRank = {
    name = "Everyone at a rank",
    next = function(after)
      if after >= ns.Professions.CAP then return nil end
      return (math.floor(after / RANK_STEP) + 1) * RANK_STEP
    end,
    value = function(progress) return progress.lowestBest end,
    title = function(rung) return "Everyone " .. aRank(rung or ns.Professions.CAP) end,
    text = function(rung) return ("Everyone in the Crew is %s at something!"):format(aRank(rung)) end,
    label = function(rung) return ns.Professions.rank(rung) end,
    bar = membersAt("best"),
  },
  catches = {
    name = "Types caught",
    next = function(after)
      for _, step in ipairs(ns.Catches.STEPS) do
        if step > after then return step end
      end
      return nil
    end,
    value = function(progress) return progress.catches end,
    title = function() return "Types of fish caught" end,
    text = function(rung, top)
      if top then return "The Crew has caught every type of fish" end
      return ("The Crew has caught %d types of fish"):format(rung)
    end,
    label = function(rung)
      return rung >= ns.Catches.TOTAL and "Every type" or ("%d types"):format(rung)
    end,
  },
  rares = {
    name = "Rares slain",
    next = function(after)
      for _, step in ipairs(Rares.STEPS) do
        if step > after then return step end
      end
      return nil
    end,
    value = function(progress) return progress.rares end,
    title = function() return "Rares slain" end,
    text = function(rung, top)
      if top then return "The Crew has slain every Rare!" end
      return ("The Crew has slain %d Rares!"):format(rung)
    end,
    label = function(rung)
      return rung >= Rares.TOTAL and "Every Rare" or ("%d Rares"):format(rung)
    end,
  },
}

function Goals.nextRung(track, after, maxLevel)
  return TRACK[track].next(after, maxLevel)
end

function Goals.rungs(track, value, maxLevel)
  local list = {}
  local rung = Goals.nextRung(track, 0, maxLevel)
  while rung and rung <= value do
    list[#list + 1] = rung
    rung = Goals.nextRung(track, rung, maxLevel)
  end
  return list
end

function Goals.progress(records)
  local progress = {
    crewLevels = 0, deaths = 0, members = 0, lowest = 0, highest = {},
    covered = {}, skill = 0, lowestBest = 0, best = {},
    catches = ns.Catches.typesCaught(records),
    rares = Rares.slain(records),
  }
  for _, record in ipairs(records) do
    local top, best = nil, 0
    for _, character in pairs(record.characters or {}) do
      top = math.max(top or 0, character.level or 0)
      progress.deaths = progress.deaths + (character.deaths or 0)
      local professions = ns.Professions.describe(character.professions)
      for _, p in ipairs(professions or {}) do
        best = math.max(best, p.skill)
        progress.skill = progress.skill + p.skill
        progress.covered[p.skillLine] = progress.covered[p.skillLine] or { name = p.name, icon = p.icon }
      end
    end
    if top then
      progress.members = progress.members + 1
      progress.highest[progress.members] = top
      progress.crewLevels = progress.crewLevels + top
      progress.lowest = progress.members == 1 and top or math.min(progress.lowest, top)
      progress.best[progress.members] = best
      progress.lowestBest = progress.members == 1 and best or math.min(progress.lowestBest, best)
    end
  end
  return progress
end

function Goals.professionsFirstKnown(before, character)
  return ns.Professions.describe(character.professions) ~= nil
    and not (before and ns.Professions.describe(before.professions))
end

function Goals.countedChanged(before, record)
  if before == nil or (before.left == true) ~= (record.left == true) then return true end
  local had = before.characters or {}
  for guid, character in pairs(record.characters or {}) do
    if Goals.professionsFirstKnown(had[guid], character) then return true end
  end
  return false
end

function Goals.new(db, ledger, now, maxLevel)
  local self = setmetatable({ db = db, ledger = ledger, now = now, maxLevel = maxLevel }, Goals)
  self:load()
  return self
end

function Goals:load()
  self.visiting = false
  local saved = self.db.goals or {}
  saved.reached = saved.reached or {}
  saved.quiet = saved.quiet or {}
  saved.clears = saved.clears or {}
  saved.rareKills = saved.rareKills or {}
  for _, track in ipairs(Goals.TRACKS) do
    if saved.baselined and not saved.reached[track] then
      saved.late = saved.late or {}
      saved.late[track] = true
    end
    saved.reached[track] = saved.reached[track] or {}
    saved.quiet[track] = saved.quiet[track] or {}
  end
  self.db.goals = saved
  self.settle = ns.Settle.new(self.now, saved.baselined)
  self.lateSettle = ns.Settle.new(self.now, saved.late == nil)
end

function Goals:clear()
  self.db.goals = nil
  self:load()
end

local function counted(self)
  local records = {}
  for _, record in self.ledger:records() do
    if not record.left then records[#records + 1] = record end
  end
  return records
end

local function highestReached(self, track)
  local top
  for rung in pairs(self.db.goals.reached[track]) do top = math.max(top or rung, rung) end
  return top
end

local function reach(self, track, rung, quiet)
  self.db.goals.reached[track][rung] = self.now()
  if quiet then self.db.goals.quiet[track][rung] = true end
end

local function count(set)
  local n = 0
  for _ in pairs(set) do n = n + 1 end
  return n
end

local function recordProfessions(self, _, progress, quiet)
  local saved = self.db.goals.reached.professions
  local nouns = {}
  for _, p in ipairs(PROFESSIONS) do
    if progress.covered[p.skillLine] and not saved[p.skillLine] then
      reach(self, "professions", p.skillLine, quiet)
      nouns[#nouns + 1] = p.noun
    end
  end
  if #nouns == 0 then return nil end
  local reached = count(saved)
  local text = reached >= #PROFESSIONS and "The Crew has every profession!"
    or ("The Crew has %s now!"):format(listed(nouns))
  return { track = "professions", rung = reached, text = text }
end

local function professionsRow(self, _, progress)
  local saved = self.db.goals.reached.professions
  local row = {
    track = "professions", title = TRACK.professions.title(), professions = {}, value = 0, reached = count(saved),
  }
  local lastTime
  for i, p in ipairs(PROFESSIONS) do
    local had = progress.covered[p.skillLine]
    local lit = saved[p.skillLine] ~= nil or had ~= nil
    row.professions[i] = {
      skillLine = p.skillLine,
      name = had and had.name or p.name,
      icon = had and had.icon or p.icon,
      lit = lit,
    }
    if lit then row.value = row.value + 1 end
    local time = saved[p.skillLine]
    if time and (not lastTime or time >= lastTime) then
      lastTime = time
      row.last = { rung = count(saved), time = time, label = row.professions[i].name }
    end
  end
  row.goal = #PROFESSIONS
  row.complete = count(saved) >= #PROFESSIONS
  row.rung = not row.complete and count(saved) + 1 or nil
  if row.complete then row.value, row.goal = nil, nil end
  return row
end
TRACK.professions.record = recordProfessions
TRACK.professions.row = professionsRow

local function recordLadder(self, track, progress, quiet)
  local saved = self.db.goals.reached[track]
  local newest
  for _, rung in ipairs(Goals.rungs(track, TRACK[track].value(progress), self.maxLevel)) do
    if not saved[rung] then
      reach(self, track, rung, quiet)
      newest = rung
    end
  end
  if not newest then return nil end
  local top = Goals.nextRung(track, newest, self.maxLevel) == nil
  return { track = track, rung = newest, text = TRACK[track].text(newest, top) }
end

local function recordClears(self, records, quiet)
  local saved = self.db.goals.clears
  local new = {}
  for name, clear in pairs(Clears.collect(records)) do
    local had = saved[name]
    if had then
      had.time = math.min(had.time, clear.time)
      for id in pairs(clear.members) do had.members[id] = true end
    else
      saved[name] = { time = clear.time, members = clear.members, quiet = quiet or nil, seen = self.now() }
      if not quiet then new[#new + 1] = Clears.instance(name) end
    end
  end
  table.sort(new, function(x, y) return x.index < y.index end)
  local entries = {}
  for i, dungeon in ipairs(new) do
    entries[i] = { track = "clears", rung = dungeon.index, text = Clears.text(dungeon.name) }
  end
  return entries
end

local function killer(self, memberId)
  if memberId == self.ledger:memberId() then return "You" end
  local held = self.ledger:record(memberId)
  return held and ns.Roster.memberName(held, self.now()) or "Someone"
end

local function recordRareKills(self, records, quiet)
  local saved = self.db.goals.rareKills
  local new = {}
  for id, kill in pairs(Rares.collect(records)) do
    local had = saved[id]
    if had then
      if kill.time < had.time then
        had.time, had.memberId, had.character = kill.time, kill.memberId, kill.character
      end
    else
      saved[id] = {
        time = kill.time, memberId = kill.memberId, character = kill.character, quiet = quiet or nil, seen = self.now(),
      }
      if not quiet then new[#new + 1] = Rares.byId(id) end
    end
  end
  table.sort(new, function(x, y) return x.index < y.index end)
  local entries = {}
  for i, r in ipairs(new) do
    entries[i] = { track = "rareKills", rung = r.id, text = Rares.text(r.name, killer(self, saved[r.id].memberId)) }
  end
  return entries
end

local function record(self, quiet)
  local records = counted(self)
  local progress = Goals.progress(records)
  local late = self.db.goals.late or {}
  local reached = {}
  for _, track in ipairs(Goals.TRACKS) do
    if not late[track] then
      local entry = (TRACK[track].record or recordLadder)(self, track, progress, quiet)
      if entry and not quiet then reached[#reached + 1] = entry end
    end
  end
  for _, entry in ipairs(recordClears(self, records, quiet)) do reached[#reached + 1] = entry end
  for _, entry in ipairs(recordRareKills(self, records, quiet)) do reached[#reached + 1] = entry end
  return reached
end

function Goals:check(quiet)
  if not self.settle:isSettled() then return {} end
  return record(self, quiet)
end

function Goals:linkUp()
  self.settle:up()
  self.lateSettle:up()
end

function Goals:linkDown()
  self.settle:down()
  self.lateSettle:down()
end

function Goals:dataMerged()
  self.settle:data()
  self.lateSettle:data()
end

local function baselineLate(self)
  local progress = Goals.progress(counted(self))
  for track in pairs(self.db.goals.late) do
    (TRACK[track].record or recordLadder)(self, track, progress, true)
  end
  self.db.goals.late = nil
end

function Goals:tick()
  if self.lateSettle:tick() then baselineLate(self) end
  if not self.settle:tick() then return false end
  record(self, true)
  self.db.goals.baselined = true
  return true
end

local function ladderRow(self, track, progress)
  local spec = TRACK[track]
  local top = highestReached(self, track)
  local rung = Goals.nextRung(track, top or 0, self.maxLevel)
  local row = {
    track = track,
    title = spec.title(rung),
    rung = rung,
    reached = count(self.db.goals.reached[track]),
    complete = rung == nil,
    last = top and {
      rung = top,
      time = self.db.goals.reached[track][top],
      label = spec.label and spec.label(top) or grouped(top),
    } or nil,
  }
  if rung and spec.bar then
    row.value, row.goal, row.unit = spec.bar(progress, rung)
  elseif rung then
    row.value, row.goal = spec.value(progress), rung
  end
  return row
end

function Goals:rows()
  local progress = Goals.progress(counted(self))
  local rows = {}
  for _, track in ipairs(Goals.TRACKS) do
    rows[#rows + 1] = (TRACK[track].row or ladderRow)(self, track, progress)
  end
  return rows
end

local function quality(nth)
  return QUALITIES[nth] or TOP_QUALITY
end

local function trophy(self, track, key, fields)
  fields.track = track
  fields.title = TRACK[track].name
  fields.quiet = self.db.goals.quiet[track][key] == true
  fields.arrived = fields.time
  fields.fresh = not fields.quiet and self.now() - fields.time < FRESH
  return fields
end

local function ladderTrophies(self, track)
  local spec = TRACK[track]
  local saved = self.db.goals.reached[track]
  local rungs = {}
  for rung in pairs(saved) do rungs[#rungs + 1] = rung end
  table.sort(rungs)
  local list = {}
  for nth, rung in ipairs(rungs) do
    list[nth] = trophy(self, track, rung, {
      rung = rung,
      time = saved[rung],
      label = spec.label and spec.label(rung) or grouped(rung),
      text = spec.text(rung, Goals.nextRung(track, rung, self.maxLevel) == nil),
      quality = quality(nth),
    })
  end
  return list
end

local function professionTrophies(self, _, progress)
  local saved = self.db.goals.reached.professions
  local reached = {}
  for i, p in ipairs(PROFESSIONS) do
    if saved[p.skillLine] then reached[#reached + 1] = { p = p, order = i, time = saved[p.skillLine] } end
  end
  table.sort(reached, function(x, y)
    if x.time ~= y.time then return x.time < y.time end
    return x.order < y.order
  end)
  local list = {}
  for nth, item in ipairs(reached) do
    local had = progress.covered[item.p.skillLine]
    list[nth] = trophy(self, "professions", item.p.skillLine, {
      rung = nth,
      time = item.time,
      label = had and had.name or item.p.name,
      icon = had and had.icon or item.p.icon,
      text = nth >= #PROFESSIONS and "The Crew has every profession!"
        or ("The Crew has %s now!"):format(item.p.noun),
      quality = PROFESSIONS_QUALITY,
    })
  end
  return list
end
TRACK.professions.trophies = professionTrophies

local function partyNames(self, members)
  local you = self.ledger:memberId()
  local names = {}
  for id in pairs(members) do
    local held = self.ledger:record(id)
    if held and id ~= you then names[#names + 1] = ns.Roster.memberName(held, self.now()) end
  end
  table.sort(names, function(x, y) return x:lower() < y:lower() end)
  if members[you] then table.insert(names, 1, "You") end
  return names
end

local function clearTrophies(self)
  local list = {}
  for name, saved in pairs(self.db.goals.clears) do
    local dungeon = Clears.instance(name)
    if dungeon then
      local quiet = saved.quiet == true
      local arrived = saved.seen or saved.time
      list[name] = {
        track = "clears",
        kind = dungeon.kind,
        instance = name,
        title = CLEAR_TITLES[dungeon.kind],
        rung = dungeon.index,
        label = Clears.label(name),
        text = Clears.text(name),
        time = saved.time,
        quality = CLEAR_QUALITIES[dungeon.kind],
        quiet = quiet,
        arrived = arrived,
        fresh = not quiet and self.now() - arrived < FRESH,
        party = partyNames(self, saved.members),
      }
    end
  end
  return list
end

local function rareKillTrophies(self)
  local list = {}
  for id, saved in pairs(self.db.goals.rareKills) do
    local r = Rares.byId(id)
    if r then
      local quiet = saved.quiet == true
      local arrived = saved.seen or saved.time
      local held = self.ledger:record(saved.memberId)
      local character = held and saved.character and type(held.characters) == "table" and held.characters[saved.character]
      list[id] = {
        track = "rareKills",
        npcId = id,
        title = TRACK.rares.name,
        rung = r.index,
        label = r.name,
        zone = r.zone,
        level = r.level,
        elite = r.elite == true,
        text = Rares.text(r.name, killer(self, saved.memberId)),
        time = saved.time,
        quality = r.elite and RARE_ELITE_QUALITY or RARE_QUALITY,
        quiet = quiet,
        arrived = arrived,
        fresh = not quiet and self.now() - arrived < FRESH,
        by = killer(self, saved.memberId),
        character = character and character.name or nil,
      }
    end
  end
  return list
end

local function rareGrid(trophies)
  local result = { slain = 0, slots = {} }
  for i, r in ipairs(Rares.LIST) do
    local won = trophies[r.id]
    result.slots[i] = {
      npcId = r.id, name = r.name, label = r.name, kind = "rare", zone = r.zone, level = r.level,
      levels = tostring(r.level),
      elite = r.elite == true, slain = won ~= nil, trophy = won,
    }
    if won then result.slain = result.slain + 1 end
  end
  result.total = #result.slots
  return result
end

local function grid(kind, trophies)
  local result = { cleared = 0, slots = {} }
  for i, dungeon in ipairs(Clears.instances(kind)) do
    local won = trophies[dungeon.name]
    result.slots[i] = {
      name = dungeon.name,
      label = Clears.label(dungeon.name),
      kind = kind,
      levels = Clears.levels(dungeon),
      cleared = won ~= nil,
      trophy = won,
    }
    if won then result.cleared = result.cleared + 1 end
  end
  result.total = #result.slots
  return result
end

function Goals:open()
  if self.visiting then return end
  self.visiting = true
  self.since = self.db.goals.seen
  self.db.goals.seen = self.now()
end

function Goals:leave()
  self.visiting = false
end

function Goals:trophies()
  local result = { settled = self.db.goals.baselined == true, count = 0, shelf = {}, cabinet = {}, sinceSeen = 0 }
  local progress = Goals.progress(counted(self))
  local order = {}
  for i, track in ipairs(Goals.TRACKS) do
    order[track] = i
    local list = (TRACK[track].trophies or ladderTrophies)(self, track, progress)
    if #list > 0 then
      result.cabinet[#result.cabinet + 1] = { track = track, title = TRACK[track].name, trophies = list }
      for _, item in ipairs(list) do result.shelf[#result.shelf + 1] = item end
    end
  end
  result.goalsReached = #result.shelf
  order.clears = #Goals.TRACKS + 1
  local clears = clearTrophies(self)
  for _, item in pairs(clears) do result.shelf[#result.shelf + 1] = item end
  result.dungeons = grid("dungeon", clears)
  result.raids = grid("raid", clears)
  order.rareKills = #Goals.TRACKS + 2
  local rareKills = rareKillTrophies(self)
  for _, item in pairs(rareKills) do result.shelf[#result.shelf + 1] = item end
  result.rares = rareGrid(rareKills)
  table.sort(result.shelf, function(x, y)
    if x.time ~= y.time then return x.time > y.time end
    if x.track ~= y.track then return order[x.track] < order[y.track] end
    return x.rung > y.rung
  end)
  result.count = #result.shelf
  result.latest = result.shelf[1]
  local since = self.db.goals.seen
  if self.visiting then since = self.since end
  for i, item in ipairs(result.shelf) do
    item.unseen = since ~= nil and not item.quiet and item.arrived > since
    if i > 1 and item.unseen then result.sinceSeen = result.sinceSeen + 1 end
  end
  return result
end
