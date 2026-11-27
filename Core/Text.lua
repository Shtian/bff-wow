local _, ns = ...

local Text = {}
ns.Text = Text

local HOUR, DAY = 60 * 60, 24 * 60 * 60

local WEEKDAYS = { "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" }
local MONTHS = {
  "January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December",
}

function Text.list(words)
  if #words < 2 then return words[1] or "" end
  return table.concat(words, ", ", 1, #words - 1) .. " and " .. words[#words]
end

function Text.ago(seconds)
  seconds = math.max(0, seconds)
  if seconds < HOUR then return ("%dm"):format(math.floor(seconds / 60)) end
  if seconds < DAY then return ("%dh"):format(math.floor(seconds / HOUR + 0.5)) end
  return ("%dd"):format(math.floor(seconds / DAY + 0.5))
end

function Text.since(seconds)
  return Text.ago(seconds) .. " ago"
end

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

function Text.dayTitle(daysAgo, time, utcOffset)
  if daysAgo == 0 then return "TODAY" end
  if daysAgo == 1 then return "YESTERDAY" end
  local weekday, day, month = localDate(time, utcOffset)
  return ("%s %02d %s"):format(WEEKDAYS[weekday], day, MONTHS[month]):upper()
end

function Text.monthDay(time, utcOffset)
  local _, day, month = localDate(time, utcOffset)
  return month, day
end

function Text.shortDate(time, utcOffset)
  local _, day, month = localDate(time, utcOffset)
  return ("%d %s"):format(day, MONTHS[month]:sub(1, 3))
end

function Text.grouped(count)
  return (tostring(count):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end
