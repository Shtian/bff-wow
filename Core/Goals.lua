-- Goals: the built-in Crew goals. Three tracks, each a ladder of rungs:
-- Crew levels (each Member's highest Character, summed), Everyone at level
-- N (every Member has a Character at N) and Crew deaths (every Character's
-- deaths, summed). Progress is worked out from the Ledger's records of the
-- Members your Roster shows (not Left; Removed ones aren't held), so it is
-- per client. Reached rungs are kept with when they were reached and stay
-- reached if progress drops. Rungs passed when the first sync in a Crew
-- has settled are a silent baseline. Nothing here names a Member.
-- See docs/design/goals.md.

local _, ns = ...

local Goals = {}
Goals.__index = Goals
ns.Goals = Goals

Goals.TRACKS = { "crewLevels", "everyone", "deaths" }

local CREW_LEVELS_STEP = 50
local EVERYONE_STEP = 10
-- Crew deaths: 25, 50, 100, then the same steps ten times bigger.
local DEATHS_STEPS = { 25, 50, 100 }

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
    -- Members with a Character at the next rung, out of every Member: a
    -- count, so no Member's own level shows.
    bar = function(progress, rung)
      local at = 0
      for _, level in ipairs(progress.highest) do
        if level >= rung then at = at + 1 end
      end
      return at, progress.members, "Members"
    end,
  },
  deaths = {
    next = function(after)
      local scale = 1
      while true do
        for _, step in ipairs(DEATHS_STEPS) do
          if step * scale > after then return step * scale end
        end
        scale = scale * 10
      end
    end,
    value = function(progress) return progress.deaths end,
    title = function() return "Crew deaths" end,
    text = function(rung) return ("The Crew has died %d times together!"):format(rung) end,
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
-- a Character), lowest (the lowest of their highest levels, 0 with none)
-- and highest (each Member's highest level, unordered).
function Goals.progress(records)
  local progress = { crewLevels = 0, deaths = 0, members = 0, lowest = 0, highest = {} }
  for _, record in ipairs(records) do
    local top
    for _, character in pairs(record.characters or {}) do
      top = math.max(top or 0, character.level or 0)
      progress.deaths = progress.deaths + (character.deaths or 0)
    end
    if top then
      progress.members = progress.members + 1
      progress.highest[progress.members] = top
      progress.crewLevels = progress.crewLevels + top
      progress.lowest = progress.members == 1 and top or math.min(progress.lowest, top)
    end
  end
  return progress
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

-- Records every rung progress has passed. Returns the highest newly reached
-- per track, as { track, rung, text } (text: the Feed entry's), unless
-- quiet.
local function record(self, quiet)
  local progress = Goals.progress(counted(self))
  local reached = {}
  for _, track in ipairs(Goals.TRACKS) do
    local saved = self.db.goals.reached[track]
    local newest
    for _, rung in ipairs(Goals.rungs(track, TRACK[track].value(progress), self.maxLevel)) do
      if not saved[rung] then
        saved[rung] = self.now()
        newest = rung
      end
    end
    if newest and not quiet then
      local top = Goals.nextRung(track, newest, self.maxLevel) == nil
      reached[#reached + 1] = { track = track, rung = newest, text = TRACK[track].text(newest, top) }
    end
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

-- The Goals tab: a row per track, in Goals.TRACKS order: { track, title,
-- rung (the next one, nil when complete), value and goal (the progress bar:
-- value out of goal), unit (what value counts, when not the measure
-- itself), complete, last ({ rung, time }, the highest reached, or nil) }.
function Goals:rows()
  local progress = Goals.progress(counted(self))
  local rows = {}
  for _, track in ipairs(Goals.TRACKS) do
    local spec = TRACK[track]
    local top = highestReached(self, track)
    local rung = Goals.nextRung(track, top or 0, self.maxLevel)
    local row = {
      track = track,
      title = spec.title(rung),
      rung = rung,
      complete = rung == nil,
      last = top and { rung = top, time = self.db.goals.reached[track][top] } or nil,
    }
    if rung and spec.bar then
      row.value, row.goal, row.unit = spec.bar(progress, rung)
    elseif rung then
      row.value, row.goal = spec.value(progress), rung
    end
    rows[#rows + 1] = row
  end
  return rows
end
