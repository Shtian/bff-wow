-- Text: pure wording helpers Core's ready-to-render reads share: how long
-- ago as Last seen words it, and dates in the viewer's local time from a
-- server time and utcOffset (seconds local time is ahead), worked out here
-- since Core has no date(). English, as the game's date() writes it.

local _, ns = ...

local Text = {}
ns.Text = Text

local HOUR, DAY = 60 * 60, 24 * 60 * 60

local WEEKDAYS = { "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" }
local MONTHS = {
  "January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December",
}

-- How long ago, as Last seen words it: 5m, 3h, 2d.
function Text.ago(seconds)
  seconds = math.max(0, seconds)
  if seconds < HOUR then return ("%dm"):format(math.floor(seconds / 60)) end
  if seconds < DAY then return ("%dh"):format(math.floor(seconds / HOUR + 0.5)) end
  return ("%dd"):format(math.floor(seconds / DAY + 0.5))
end

-- Last seen in words: "5m ago".
function Text.since(seconds)
  return Text.ago(seconds) .. " ago"
end

-- The local calendar date of a server time: weekday (1 for Sunday), day
-- of the month, month (1–12). Days since 1970 to a civil date, as in
-- Howard Hinnant's days_from_civil inverse.
local function localDate(time, utcOffset)
  local days = math.floor((time + utcOffset) / DAY)
  local weekday = (days + 4) % 7 + 1
  local z = days + 719468
  local era = math.floor(z / 146097)
  local doe = z - era * 146097
  local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
  local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
  local mp = math.floor((5 * doy + 2) / 153)
  local day = doy - math.floor((153 * mp + 2) / 5) + 1
  local month = mp < 10 and mp + 3 or mp - 9
  return weekday, day, month
end

-- A Feed day's title: "TODAY", "YESTERDAY", else "MONDAY 02 NOVEMBER".
function Text.dayTitle(daysAgo, time, utcOffset)
  if daysAgo == 0 then return "TODAY" end
  if daysAgo == 1 then return "YESTERDAY" end
  local weekday, day, month = localDate(time, utcOffset)
  return ("%s %02d %s"):format(WEEKDAYS[weekday], day, MONTHS[month]):upper()
end

-- A short date: "3 Nov".
function Text.shortDate(time, utcOffset)
  local _, day, month = localDate(time, utcOffset)
  return ("%d %s"):format(day, MONTHS[month]:sub(1, 3))
end

-- A count with thousands separators: 2,500.
function Text.grouped(count)
  return (tostring(count):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end
