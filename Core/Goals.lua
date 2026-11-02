-- Goals: the built-in Crew goals. Six tracks: Crew levels (each Member's
-- highest Character, summed), Everyone at level N (every Member has a
-- Character at N), Crew deaths (every Character's deaths, summed), Every
-- profession in the Crew (the twelve, each had by some Character), Crew
-- skill (every profession's base skill, summed) and Everyone a Journeyman
-- (every Member has a profession at a rank's skill on some Character).
-- All but Every profession are a ladder of rungs; its rungs are the
-- professions. Progress is worked out from the Ledger's records of the
-- Members your Roster shows (not Left; Removed ones aren't held), so it is
-- per client. Reached rungs are kept with when they were reached and stay
-- reached if progress drops. Rungs passed when the first sync in a Crew
-- has settled are a silent baseline. Nothing here names a Member.
-- See docs/design/goals.md.

local _, ns = ...

local Goals = {}
Goals.__index = Goals
ns.Goals = Goals

Goals.TRACKS = { "crewLevels", "everyone", "deaths", "professions", "crewSkill", "everyoneRank" }

local CREW_LEVELS_STEP = 50
local EVERYONE_STEP = 10
-- Crew deaths: 25, 50, 100, then the same steps ten times bigger.
local DEATHS_STEPS = { 25, 50, 100 }
-- Crew skill: 500, 1000, 2500, and on the same way.
local SKILL_STEPS = { 500, 1000, 2500 }
local RANK_STEP = 75

-- The twelve, as Every profession in the Crew counts them.
local PROFESSIONS = ns.Professions.ALL

-- A ladder of steps repeated ten times bigger for ever: the first one
-- above after.
local function scaled(steps, after)
  local scale = 1
  while true do
    for _, step in ipairs(steps) do
      if step * scale > after then return step * scale end
    end
    scale = scale * 10
  end
end

-- A count with thousands separators: 2,500.
local function grouped(count)
  return (tostring(count):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

-- "a Journeyman" for the rank a skill stands for.
local function aRank(skill)
  local rank = ns.Professions.rank(skill)
  return (rank:find("^[AEIOU]") and "an " or "a ") .. rank
end

-- "a Cook", "a Cook and an Angler", "a Miner, a Cook and an Angler".
local function listed(nouns)
  if #nouns == 1 then return nouns[1] end
  return table.concat(nouns, ", ", 1, #nouns - 1) .. " and " .. nouns[#nouns]
end

-- Members whose value (highest level or best skill) is at the rung, out of
-- every Member: a count, so no Member's own value shows.
local function membersAt(values)
  return function(progress, rung)
    local at = 0
    for _, value in ipairs(progress[values]) do
      if value >= rung then at = at + 1 end
    end
    return at, progress.members, "Members"
  end
end

-- What makes each track: its next rung after a value (nil past the last),
-- the progress its rungs are measured against, its title on the Goals
-- tab, the Feed entry's text for a rung, and what the progress bar counts
-- when that isn't the measure itself.
local TRACK = {
  crewLevels = {
    next = function(after)
      return (math.floor(after / CREW_LEVELS_STEP) + 1) * CREW_LEVELS_STEP
    end,
    value = function(progress) return progress.crewLevels end,
    title = function() return "Crew levels" end,
    text = function(rung) return ("The Crew reached %d Crew levels!"):format(rung) end,
  },
  everyone = {
    -- Every 10, and the last rung is max level itself.
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
    next = function(after) return scaled(DEATHS_STEPS, after) end,
    value = function(progress) return progress.deaths end,
    title = function() return "Crew deaths" end,
    text = function(rung) return ("The Crew has died %d times together!"):format(rung) end,
  },
  -- Not a ladder: its rungs are the professions. record and row are below.
  professions = {
    title = function() return "Every profession in the Crew" end,
  },
  crewSkill = {
    next = function(after) return scaled(SKILL_STEPS, after) end,
    value = function(progress) return progress.skill end,
    title = function() return "Crew skill" end,
    text = function(rung) return ("The Crew has %s profession skill together!"):format(grouped(rung)) end,
  },
  everyoneRank = {
    -- 75 Apprentice, 150 Journeyman, 225 Expert and 300 Artisan, the last.
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
}

-- The first rung of a track above `after`, or nil past the last one.
function Goals.nextRung(track, after, maxLevel)
  return TRACK[track].next(after, maxLevel)
end

-- Every rung of a track up to and including value, lowest first.
function Goals.rungs(track, value, maxLevel)
  local list = {}
  local rung = Goals.nextRung(track, 0, maxLevel)
  while rung and rung <= value do
    list[#list + 1] = rung
    rung = Goals.nextRung(track, rung, maxLevel)
  end
  return list
end

-- Progress over the given records: crewLevels, deaths, members (those with
-- a Character), lowest (the lowest of their highest levels, 0 with none),
-- highest (each Member's highest level, unordered), and from professions:
-- covered (skill line to { name, icon } for each one some Character has),
-- skill (base skill over every profession of every Character), lowestBest
-- (the lowest of the Members' best skills, 0 with none) and best (each
-- Member's best skill, in highest's order). A Character whose professions
-- are unknown adds nothing, so a Member none of whose are known has a best
-- of 0: Everyone a Journeyman waits for everyone.
function Goals.progress(records)
  local progress = {
    crewLevels = 0, deaths = 0, members = 0, lowest = 0, highest = {},
    covered = {}, skill = 0, lowestBest = 0, best = {},
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

-- Whether a Character's professions are first known, from the Character as
-- it was (nil when new) to as it is: a first share, or a new Character.
function Goals.professionsFirstKnown(before, character)
  return ns.Professions.describe(character.professions) ~= nil
    and not (before and ns.Professions.describe(before.professions))
end

-- Whether a record changing from before (nil when first seen) changes who
-- counts rather than their progress: a Member first seen, Leaving or
-- coming back, or a Character's professions first known. Rungs reached by
-- it are recorded quietly.
function Goals.countedChanged(before, record)
  if before == nil or (before.left == true) ~= (record.left == true) then return true end
  local had = before.characters or {}
  for guid, character in pairs(record.characters or {}) do
    if Goals.professionsFirstKnown(had[guid], character) then return true end
  end
  return false
end

-- db is the whole saved table; Goals keeps `goals`: reached (per track,
-- rung to when it was reached) and baselined (the silent baseline is done).
function Goals.new(db, ledger, now, maxLevel)
  local self = setmetatable({ db = db, ledger = ledger, now = now, maxLevel = maxLevel }, Goals)
  self:load()
  return self
end

function Goals:load()
  local saved = self.db.goals or {}
  saved.reached = saved.reached or {}
  for _, track in ipairs(Goals.TRACKS) do saved.reached[track] = saved.reached[track] or {} end
  self.db.goals = saved
  self.settle = ns.Settle.new(self.now, saved.baselined)
end

-- Leaving or joining a Crew: a new Crew starts with its own baseline.
function Goals:clear()
  self.db.goals = nil
  self:load()
end

-- The records counted: every Member held who hasn't left, you included.
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

local function count(set)
  local n = 0
  for _ in pairs(set) do n = n + 1 end
  return n
end

-- Every profession: reached per skill line. Records the ones had now and
-- returns the Feed entry's { track, rung (how many are reached), text }
-- for any newly had, or nil.
local function recordProfessions(self, _, progress)
  local saved = self.db.goals.reached.professions
  local nouns = {}
  for _, p in ipairs(PROFESSIONS) do
    if progress.covered[p.skillLine] and not saved[p.skillLine] then
      saved[p.skillLine] = self.now()
      nouns[#nouns + 1] = p.noun
    end
  end
  if #nouns == 0 then return nil end
  local reached = count(saved)
  local text = reached >= #PROFESSIONS and "The Crew has every profession!"
    or ("The Crew has %s now!"):format(listed(nouns))
  return { track = "professions", rung = reached, text = text }
end

-- Every profession's row: the twelve, lit once reached (or had now, before
-- the baseline), with the name and icon of whoever has it.
local function professionsRow(self, _, progress)
  local saved = self.db.goals.reached.professions
  local row = { track = "professions", title = TRACK.professions.title(), professions = {}, value = 0 }
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

-- A ladder's rungs passed now: records them, and returns the highest
-- newly reached as { track, rung, text }, or nil.
local function recordLadder(self, track, progress)
  local saved = self.db.goals.reached[track]
  local newest
  for _, rung in ipairs(Goals.rungs(track, TRACK[track].value(progress), self.maxLevel)) do
    if not saved[rung] then
      saved[rung] = self.now()
      newest = rung
    end
  end
  if not newest then return nil end
  local top = Goals.nextRung(track, newest, self.maxLevel) == nil
  return { track = track, rung = newest, text = TRACK[track].text(newest, top) }
end

-- Records every rung progress has passed. Returns the newest per track, as
-- { track, rung, text } (text: the Feed entry's), unless quiet.
local function record(self, quiet)
  local progress = Goals.progress(counted(self))
  local reached = {}
  for _, track in ipairs(Goals.TRACKS) do
    local entry = (TRACK[track].record or recordLadder)(self, track, progress)
    if entry and not quiet then reached[#reached + 1] = entry end
  end
  return reached
end

-- Records progress, after a record changed. Returns the rungs newly reached
-- (see record()), none when quiet: the Members counted changed (one was
-- first seen, left, came back or was Removed), so it isn't progress, as
-- the Feed's first sight of a Member is a silent baseline. Does nothing
-- until the baseline is taken: while sync settles, the records held may be
-- only part of the Crew, so Everyone at level N could look reached when it
-- isn't.
function Goals:check(quiet)
  if not self.settle:isSettled() then return {} end
  return record(self, quiet)
end

function Goals:linkUp()
  self.settle:up()
end

function Goals:linkDown()
  self.settle:down()
end

function Goals:dataMerged()
  self.settle:data()
end

-- Called once a second, in a Crew. Returns true on the tick the baseline
-- is taken.
function Goals:tick()
  if not self.settle:tick() then return false end
  record(self, true)
  self.db.goals.baselined = true
  return true
end

-- A ladder's row on the Goals tab (see rows()).
local function ladderRow(self, track, progress)
  local spec = TRACK[track]
  local top = highestReached(self, track)
  local rung = Goals.nextRung(track, top or 0, self.maxLevel)
  local row = {
    track = track,
    title = spec.title(rung),
    rung = rung,
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

-- The Goals tab: a row per track, in Goals.TRACKS order: { track, title,
-- rung (the next one, nil when complete), value and goal (the progress bar:
-- value out of goal), unit (what value counts, when not the measure
-- itself), complete, last ({ rung, time, label }, the highest reached, or
-- nil; label is how the tab words it: "2,500", "Journeyman") }. Every
-- profession's rung counts professions; its last is the latest reached,
-- labelled with its name; and it has professions, the twelve as { skillLine,
-- name, icon (a file ID or texture path), lit }.
function Goals:rows()
  local progress = Goals.progress(counted(self))
  local rows = {}
  for _, track in ipairs(Goals.TRACKS) do
    rows[#rows + 1] = (TRACK[track].row or ladderRow)(self, track, progress)
  end
  return rows
end
