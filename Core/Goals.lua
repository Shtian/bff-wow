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

local NEXT = {
  crewLevels = function(after)
    return (math.floor(after / CREW_LEVELS_STEP) + 1) * CREW_LEVELS_STEP
  end,
  -- Every 10, and the last rung is max level itself.
  everyone = function(after, maxLevel)
    if after >= maxLevel then return nil end
    return math.min((math.floor(after / EVERYONE_STEP) + 1) * EVERYONE_STEP, maxLevel)
  end,
  deaths = function(after)
    local scale = 1
    while true do
      for _, step in ipairs(DEATHS_STEPS) do
        if step * scale > after then return step * scale end
      end
      scale = scale * 10
    end
  end,
}

-- The first rung of a track above `after`, or nil past the last one.
function Goals.nextRung(track, after, maxLevel)
  return NEXT[track](after, maxLevel)
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

-- The number a track's rungs are measured against.
local function valueOf(progress, track)
  if track == "everyone" then return progress.lowest end
  return progress[track]
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
-- per track, as { track, rung, top } (top: the track's last rung), unless
-- silent.
local function record(self, silent)
  local progress = Goals.progress(counted(self))
  local reached = {}
  for _, track in ipairs(Goals.TRACKS) do
    local saved = self.db.goals.reached[track]
    local newest
    for _, rung in ipairs(Goals.rungs(track, valueOf(progress, track), self.maxLevel)) do
      if not saved[rung] then
        saved[rung] = self.now()
        newest = rung
      end
    end
    if newest and not silent then
      local top = Goals.nextRung(track, newest, self.maxLevel) == nil
      reached[#reached + 1] = { track = track, rung = newest, top = top }
    end
  end
  return reached
end

-- Records progress, after a record changed. Returns the rungs newly reached
-- (see record()). Does nothing until the baseline is taken: while sync
-- settles, the records held may be only part of the Crew, so Everyone at
-- level N could look reached when it isn't.
function Goals:check()
  if not self.settle:isSettled() then return {} end
  return record(self, false)
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

local TITLES = { crewLevels = "Crew levels", deaths = "Crew deaths" }

-- The Goals tab: a row per track, in Goals.TRACKS order: { track, title,
-- rung (the next one, nil when complete), value and goal (the progress bar:
-- value out of goal), complete, last ({ rung, time }, the highest reached,
-- or nil) }. For Everyone at level N, value counts the Members with a
-- Character at the next rung, out of every Member.
function Goals:rows()
  local progress = Goals.progress(counted(self))
  local rows = {}
  for _, track in ipairs(Goals.TRACKS) do
    local top = highestReached(self, track)
    local rung = Goals.nextRung(track, top or 0, self.maxLevel)
    local row = {
      track = track,
      title = TITLES[track],
      rung = rung,
      complete = rung == nil,
      last = top and { rung = top, time = self.db.goals.reached[track][top] } or nil,
    }
    if track == "everyone" then
      if rung then
        local at = 0
        for _, level in ipairs(progress.highest) do
          if level >= rung then at = at + 1 end
        end
        row.title = ("Everyone at level %d"):format(rung)
        row.value, row.goal = at, progress.members
      else
        row.title = "Everyone at max level"
      end
    else
      row.value, row.goal = valueOf(progress, track), rung
    end
    rows[#rows + 1] = row
  end
  return rows
end
