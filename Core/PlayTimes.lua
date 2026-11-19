local _, ns = ...

local PlayTimes = {}
PlayTimes.__index = PlayTimes
ns.PlayTimes = PlayTimes

local HOUR = 60 * 60
local DAY = 24 * HOUR
local WEEK = 7 * DAY
local SLOTS = 7 * 24
local MONDAY_SHIFT = 3 * DAY
local WEEKS = 4
local PLAYED = 10 * 60
local USUALLY = 2
local MAX_GAP = 60
local HEX = "0123456789abcdef"

PlayTimes.WEEK = WEEK
PlayTimes.WEEKS = WEEKS
PlayTimes.USUALLY = USUALLY
PlayTimes.PLAYED_MINUTES = PLAYED / 60

function PlayTimes.slot(t)
  return math.floor(((t + MONDAY_SHIFT) % WEEK) / HOUR)
end

function PlayTimes.week(t)
  return math.floor((t + MONDAY_SHIFT) / WEEK)
end

function PlayTimes.new(db, now)
  db.playTimes = db.playTimes or { since = now(), weeks = {} }
  return setmetatable({ saved = db.playTimes, now = now }, PlayTimes)
end

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
  if PlayTimes.week(last) ~= PlayTimes.week(now) then changed = true end
  return changed
end

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

function PlayTimes.valid(summary)
  return type(summary) == "table" and type(summary.since) == "number"
    and type(summary.week) == "number" and type(summary.slots) == "string"
    and #summary.slots == SLOTS and not summary.slots:find("[^0-9a-f]")
end

function PlayTimes.same(a, b)
  if a == nil or b == nil then return a == b end
  return a.since == b.since and a.week == b.week and a.slots == b.slots
end

local function zeros()
  local values = {}
  for slot = 1, SLOTS do values[slot] = 0 end
  return values
end

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

function PlayTimes.usuallyPlaying(summaries, now)
  local counts = zeros()
  for _, summary in ipairs(summaries) do
    for slot, weeks in ipairs(PlayTimes.weeksPlayed(summary, now)) do
      if weeks >= USUALLY then counts[slot] = counts[slot] + 1 end
    end
  end
  return counts
end

function PlayTimes.isEmpty(values)
  for _, value in ipairs(values) do
    if value > 0 then return false end
  end
  return true
end

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
