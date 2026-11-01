local load = require("tests.load")

local HOUR, DAY = 3600, 86400
local WEEK = 7 * DAY
-- Monday 2026-10-26 00:00 UTC.
local MONDAY = 1792972800

-- A PlayTimes over a fresh table, on a clock the test moves.
local function tracker(start)
  local PlayTimes = load().PlayTimes
  local clock = { t = start or MONDAY }
  local db = {}
  local times = PlayTimes.new(db, function() return clock.t end)
  return times, clock, PlayTimes, db
end

-- Plays from `from` for `seconds`, ticking once a second.
local function play(times, clock, from, seconds)
  clock.t = from
  times:tick()
  for _ = 1, seconds do
    clock.t = clock.t + 1
    times:tick()
  end
end

-- The weeks played (0–4) in a UTC slot of a shared summary, as seen at `now`.
local function weeks(PlayTimes, summary, now, day, hour)
  return PlayTimes.weeksPlayed(summary, now)[(day - 1) * 24 + hour + 1]
end

describe("Play times", function()
  it("start Mondays at 00:00 UTC", function()
    local PlayTimes = load().PlayTimes
    assert.equal(0, PlayTimes.slot(MONDAY))
    assert.equal(1, PlayTimes.slot(MONDAY + HOUR + 59 * 60))
    assert.equal(167, PlayTimes.slot(MONDAY + WEEK - 1))
    assert.equal(PlayTimes.week(MONDAY) + 1, PlayTimes.week(MONDAY + WEEK))
    assert.equal(PlayTimes.week(MONDAY), PlayTimes.week(MONDAY + WEEK - 1))
  end)

  it("count minutes played in the UTC hour of the week they fall in", function()
    local times, clock, PlayTimes = tracker()
    -- Tuesday 20:00–20:10.
    play(times, clock, MONDAY + DAY + 20 * HOUR, 600)
    local summary = times:summary()
    assert.equal(1, weeks(PlayTimes, summary, clock.t, 2, 20))
    assert.equal(0, weeks(PlayTimes, summary, clock.t, 2, 21))
    assert.equal(0, weeks(PlayTimes, summary, clock.t, 2, 19))
  end)

  it("need at least 10 minutes in an hour for it to count", function()
    local times, clock, PlayTimes = tracker()
    play(times, clock, MONDAY + 20 * HOUR, 599)
    assert.equal(0, weeks(PlayTimes, times:summary(), clock.t, 1, 20))
    play(times, clock, clock.t, 1)
    assert.equal(1, weeks(PlayTimes, times:summary(), clock.t, 1, 20))
  end)

  it("split a session that crosses the hour", function()
    local times, clock, PlayTimes = tracker()
    -- 20:50 to 21:10: ten minutes in each hour.
    play(times, clock, MONDAY + 20 * HOUR + 50 * 60, 1200)
    local summary = times:summary()
    assert.equal(1, weeks(PlayTimes, summary, clock.t, 1, 20))
    assert.equal(1, weeks(PlayTimes, summary, clock.t, 1, 21))
  end)

  it("split a session that crosses midnight, and the end of the week", function()
    local times, clock, PlayTimes = tracker()
    -- Sunday 23:50 to Monday 00:10, into the next week.
    play(times, clock, MONDAY + WEEK - 600, 1200)
    local summary = times:summary()
    -- Sunday 23:00 was last week, Monday 00:00 this one.
    assert.equal(1, weeks(PlayTimes, summary, clock.t, 7, 23))
    assert.equal(1, weeks(PlayTimes, summary, clock.t, 1, 0))
  end)

  it("count a slot once per week it was played", function()
    local times, clock, PlayTimes = tracker()
    for week = 0, 2 do
      play(times, clock, MONDAY + week * WEEK + 20 * HOUR, 600)
    end
    assert.equal(3, weeks(PlayTimes, times:summary(), clock.t, 1, 20))
  end)

  it("drop weeks older than the last 4", function()
    local times, clock, PlayTimes = tracker()
    for week = 0, 3 do
      play(times, clock, MONDAY + week * WEEK + 20 * HOUR, 600)
    end
    assert.equal(4, weeks(PlayTimes, times:summary(), clock.t, 1, 20))
    play(times, clock, MONDAY + 4 * WEEK + 3 * HOUR, 60)
    assert.equal(3, weeks(PlayTimes, times:summary(), clock.t, 1, 20))
    play(times, clock, MONDAY + 7 * WEEK + 3 * HOUR, 60)
    assert.equal(0, weeks(PlayTimes, times:summary(), clock.t, 1, 20))
  end)

  it("age a summary by the viewer's clock, so a Member who stopped playing fades out", function()
    local times, clock, PlayTimes = tracker()
    for week = 0, 1 do
      play(times, clock, MONDAY + week * WEEK + 20 * HOUR, 600)
    end
    local summary = times:summary()
    assert.equal(2, weeks(PlayTimes, summary, clock.t, 1, 20))
    assert.equal(2, weeks(PlayTimes, summary, clock.t + 2 * WEEK, 1, 20))
    assert.equal(1, weeks(PlayTimes, summary, clock.t + 3 * WEEK, 1, 20))
    assert.equal(0, weeks(PlayTimes, summary, clock.t + 4 * WEEK, 1, 20))
  end)

  it("don't count a gap such as a loading screen, logout or crash", function()
    local times, clock, PlayTimes = tracker()
    play(times, clock, MONDAY + 20 * HOUR, 300)
    -- Back after twenty minutes away: the gap isn't played time.
    play(times, clock, clock.t + 20 * 60, 299)
    assert.equal(0, weeks(PlayTimes, times:summary(), clock.t, 1, 20))
  end)

  it("pick up where a reload left off without counting twice", function()
    local times, clock, PlayTimes, db = tracker()
    play(times, clock, MONDAY + 20 * HOUR, 300)
    -- A reload: a new PlayTimes over the same saved table, a few seconds on.
    local reloaded = PlayTimes.new(db, function() return clock.t end)
    clock.t = clock.t + 5
    reloaded:tick()
    play(reloaded, clock, clock.t, 290)
    assert.equal(0, weeks(PlayTimes, reloaded:summary(), clock.t, 1, 20))
    play(reloaded, clock, clock.t, 5)
    assert.equal(1, weeks(PlayTimes, reloaded:summary(), clock.t, 1, 20))
  end)

  it("ignore the clock going backwards", function()
    local times, clock, PlayTimes = tracker()
    play(times, clock, MONDAY + 20 * HOUR, 300)
    clock.t = clock.t - 1000
    times:tick()
    play(times, clock, MONDAY + 20 * HOUR + 300, 299)
    assert.equal(0, weeks(PlayTimes, times:summary(), clock.t, 1, 20))
  end)

  it("remember when collecting started", function()
    local times, clock = tracker(MONDAY + 5 * HOUR)
    play(times, clock, MONDAY + 6 * HOUR, 2)
    assert.equal(MONDAY + 5 * HOUR, times:summary().since)
  end)

  it("tell when the shared summary may have changed", function()
    local times, clock = tracker()
    clock.t = MONDAY
    assert.is_false(times:tick())
    for _ = 1, 599 do
      clock.t = clock.t + 1
      assert.is_false(times:tick())
    end
    clock.t = clock.t + 1
    assert.is_true(times:tick())
  end)

  it("share 168 characters, one per hour of the week", function()
    local times, clock, PlayTimes = tracker()
    play(times, clock, MONDAY + 20 * HOUR, 600)
    local summary = times:summary()
    assert.equal(168, #summary.slots)
    assert.is_true(PlayTimes.valid(summary))
    assert.is_false(PlayTimes.valid({ since = 1, week = 1, slots = ("0"):rep(167) }))
    assert.is_false(PlayTimes.valid({ since = 1, week = 1, slots = ("g"):rep(168) }))
    assert.is_false(PlayTimes.valid({ since = 1, slots = ("0"):rep(168) }))
    assert.is_false(PlayTimes.valid("0000"))
  end)

  describe("grid", function()
    it("is 7 days of 24 hours from Monday, shifted to local time", function()
      local PlayTimes = load().PlayTimes
      local values = {}
      for i = 1, 168 do values[i] = 0 end
      -- Monday 20:00 UTC and Sunday 23:00 UTC.
      values[21] = 3
      values[168] = 2
      local utc = PlayTimes.grid(values, 0)
      assert.equal(7, #utc)
      assert.equal(24, #utc[1])
      assert.equal(3, utc[1][21])

      -- Two hours ahead of UTC: Monday 22:00, and Sunday 23:00 becomes
      -- Monday 01:00.
      local ahead = PlayTimes.grid(values, 2 * HOUR)
      assert.equal(3, ahead[1][23])
      assert.equal(2, ahead[1][2])
      assert.equal(0, ahead[7][24])

      -- Five hours behind: Monday 15:00.
      local behind = PlayTimes.grid(values, -5 * HOUR)
      assert.equal(3, behind[1][16])
    end)
  end)
end)
