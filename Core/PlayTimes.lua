-- PlayTimes: when in the week the own Member plays, and the compact summary
-- of it their record shares. Counts seconds played per UTC hour of the week
-- (168 slots, weeks starting Monday 00:00 UTC) for the last 4 weeks, in
-- account-wide saved data, so every Character adds to one set. Only the
-- summary leaves the client. See docs/design/play-times.md.

local _, ns = ...

local PlayTimes = {}
PlayTimes.__index = PlayTimes
ns.PlayTimes = PlayTimes

local HOUR = 60 * 60
local DAY = 24 * HOUR
local WEEK = 7 * DAY
local SLOTS = 7 * 24
-- The Unix epoch was a Thursday; this moves week boundaries to Mondays.
local MONDAY_SHIFT = 3 * DAY
-- How many weeks are kept and shared.
local WEEKS = 4
-- A slot counts as played in a week at this many seconds.
local PLAYED = 10 * 60
-- A Member usually plays an hour they played in at least this many of the
-- last WEEKS weeks.
local USUALLY = 2
-- Ticks further apart than this are a loading screen, logout or crash,
-- not play.
local MAX_GAP = 60
local HEX = "0123456789abcdef"

PlayTimes.WEEK = WEEK
PlayTimes.WEEKS = WEEKS
PlayTimes.USUALLY = USUALLY
PlayTimes.PLAYED_MINUTES = PLAYED / 60

-- The UTC hour of the week a server time falls in, 0 (Monday 00:00) to 167.
function PlayTimes.slot(t)
  return math.floor(((t + MONDAY_SHIFT) % WEEK) / HOUR)
end

-- Which week a server time falls in, counting from the epoch.
function PlayTimes.week(t)
  return math.floor((t + MONDAY_SHIFT) / WEEK)
end

-- db is the whole saved table; PlayTimes keeps `playTimes` in it: since
-- (when collecting started), last (the last time counted up to) and weeks
-- (week -> slot + 1 -> seconds played).
-- Collecting starts when the first one is made.
function PlayTimes.new(db, now)
  db.playTimes = db.playTimes or { since = now(), weeks = {} }
  return setmetatable({ saved = db.playTimes, now = now }, PlayTimes)
end

-- Adds seconds played in one slot, and returns whether that made it reach
-- PLAYED.
local function add(self, t, seconds)
  local week = PlayTimes.week(t)
  local slots = self.saved.weeks[week]
  if not slots then
    slots = {}
    self.saved.weeks[week] = slots
  end
  local slot = PlayTimes.slot(t) + 1
  local before = slots[slot] or 0
  slots[slot] = before + seconds
  return before < PLAYED and before + seconds >= PLAYED
end

-- Drops weeks older than the last WEEKS, and returns whether it did.
local function prune(self, t)
  local oldest = PlayTimes.week(t) - WEEKS + 1
  local dropped = false
  for week in pairs(self.saved.weeks) do
    if week < oldest then
      self.saved.weeks[week] = nil
      dropped = true
    end
  end
  return dropped
end

-- Called once a second while the game runs: counts the time since the last
-- tick as played, split at hour boundaries, unless it's a gap. Returns true
-- if the shared summary may have changed.
function PlayTimes:tick()
  local now = self.now()
  local saved = self.saved
  local changed = false
  local last = saved.last
  saved.last = now
  if prune(self, now) then changed = true end
  if not last or now <= last or now - last > MAX_GAP then return changed end

  local t = last
  while t < now do
    local hourEnd = (math.floor(t / HOUR) + 1) * HOUR
    local upTo = math.min(hourEnd, now)
    if add(self, t, upTo - t) then changed = true end
    t = upTo
  end
  -- A new week drops the oldest from the summary.
  if PlayTimes.week(last) ~= PlayTimes.week(now) then changed = true end
  return changed
end

-- The summary shared in the Member record: { since, week (the week it was
-- made in), slots }. slots has a hex digit
-- per UTC slot, a bit per week the slot was played in: 1 for `week`, 2 for
-- the one before, 4 and 8 for the two before that.
function PlayTimes:summary()
  local saved = self.saved
  local week = PlayTimes.week(self.now())
  local digits = {}
  for slot = 1, SLOTS do
    local mask = 0
    for age = 0, WEEKS - 1 do
      local slots = saved.weeks[week - age]
      if slots and (slots[slot] or 0) >= PLAYED then mask = mask + 2 ^ age end
    end
    digits[slot] = HEX:sub(mask + 1, mask + 1)
  end
  return { since = saved.since, week = week, slots = table.concat(digits) }
end

-- Whether a summary from the wire has the expected shape.
function PlayTimes.valid(summary)
  return type(summary) == "table" and type(summary.since) == "number"
    and type(summary.week) == "number" and type(summary.slots) == "string"
    and #summary.slots == SLOTS and not summary.slots:find("[^0-9a-f]")
end

-- Whether two summaries say the same.
function PlayTimes.same(a, b)
  if a == nil or b == nil then return a == b end
  return a.since == b.since and a.week == b.week and a.slots == b.slots
end

local function zeros()
  local values = {}
  for slot = 1, SLOTS do values[slot] = 0 end
  return values
end

-- How many of the last WEEKS weeks, as of `now`, a summary's Member played
-- each UTC slot in: 168 numbers, 0 to 4 (all 0 without a summary). A
-- summary made weeks ago has fewer of them left, so a Member who stopped
-- playing fades out.
function PlayTimes.weeksPlayed(summary, now)
  if not summary then return zeros() end
  local age = PlayTimes.week(now) - summary.week
  local keep = WEEKS - math.max(age, 0)
  local counts = {}
  for slot = 1, SLOTS do
    local mask = (HEX:find(summary.slots:sub(slot, slot), 1, true) or 1) - 1
    local count = 0
    for bit = 0, keep - 1 do
      if math.floor(mask / 2 ^ bit) % 2 == 1 then count = count + 1 end
    end
    counts[slot] = count
  end
  return counts
end

-- How many of the given summaries' Members usually play each UTC slot, as
-- of `now`: 168 numbers.
function PlayTimes.usuallyPlaying(summaries, now)
  local counts = zeros()
  for _, summary in ipairs(summaries) do
    for slot, weeks in ipairs(PlayTimes.weeksPlayed(summary, now)) do
      if weeks >= USUALLY then counts[slot] = counts[slot] + 1 end
    end
  end
  return counts
end

-- Whether every value is 0.
function PlayTimes.isEmpty(values)
  for _, value in ipairs(values) do
    if value > 0 then return false end
  end
  return true
end

-- 168 values by UTC slot as a grid in local time: 7 days from Monday, each
-- 24 hours from 00:00. utcOffset is how many seconds local time is ahead,
-- rounded to the hour.
function PlayTimes.grid(values, utcOffset)
  local shift = math.floor((utcOffset or 0) / HOUR + 0.5)
  local grid = {}
  for day = 1, 7 do
    local hours = {}
    for hour = 1, 24 do
      local localSlot = (day - 1) * 24 + (hour - 1)
      hours[hour] = values[(localSlot - shift) % SLOTS + 1]
    end
    grid[day] = hours
  end
  return grid
end
