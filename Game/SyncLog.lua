local _, ns = ...

local SyncLog = {}
SyncLog.__index = SyncLog
ns.SyncLog = SyncLog

SyncLog.CAP = 300

function SyncLog.new(cap)
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

function SyncLog:lines()
  local lines = {}
  for i = 0, self.count - 1 do
    lines[i + 1] = self.buffer[(self.first + i - 1) % self.cap + 1]
  end
  return lines
end

SyncLog.save = SyncLog.lines

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
