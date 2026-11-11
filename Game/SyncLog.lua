-- Sync log: the sync trace's recent lines, kept whether or not /bff debug
-- sync prints them, so /bff report can hand them over after something went
-- wrong. A ring buffer of at most `cap` lines, oldest dropped first. App
-- saves it per Character (BFF_CharacterDB.syncLog) at logout and reload and
-- restores it at login, after which a separator marks where this session
-- began. See docs/design/code-structure.md.

local _, ns = ...

local SyncLog = {}
SyncLog.__index = SyncLog
ns.SyncLog = SyncLog

-- About an evening's sync activity around a dungeon, and small enough to
-- save per Character.
SyncLog.CAP = 300

function SyncLog.new(cap)
  -- Lines live at buffer[first .. first + count - 1], wrapping at cap.
  return setmetatable({ cap = cap or SyncLog.CAP, buffer = {}, first = 1, count = 0 }, SyncLog)
end

function SyncLog:add(line)
  local cap = self.cap
  if self.count < cap then
    self.buffer[(self.first + self.count - 1) % cap + 1] = line
    self.count = self.count + 1
  else
    self.buffer[self.first] = line
    self.first = self.first % cap + 1
  end
end

-- The lines, oldest first, as a new array.
function SyncLog:lines()
  local lines = {}
  for i = 0, self.count - 1 do
    lines[i + 1] = self.buffer[(self.first + i - 1) % self.cap + 1]
  end
  return lines
end

-- What to keep in saved variables: never more than the cap.
SyncLog.save = SyncLog.lines

-- Adds a saved log's lines (only its newest, if it's longer than the cap,
-- and only strings), then `separator` if there were any.
function SyncLog:restore(saved, separator)
  if type(saved) ~= "table" then return end
  local lines = {}
  for _, line in ipairs(saved) do
    if type(line) == "string" then lines[#lines + 1] = line end
  end
  if #lines == 0 then return end
  for i = math.max(1, #lines - self.cap + 1), #lines do self:add(lines[i]) end
  self:add(separator)
end
