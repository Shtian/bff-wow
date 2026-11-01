-- Settle: when sync has gone quiet. Settles 10 s after the last DATA that
-- changed something, or at most 30 s after the link came up; a link that
-- goes down first starts it over. Feed uses it for While you were away
-- after a login, and Goals for its silent baseline (docs/design/feed.md,
-- docs/design/goals.md).

local _, ns = ...

local Settle = {}
Settle.__index = Settle
ns.Settle = Settle

local QUIET_FOR = 10
local SETTLE_WITHIN = 30

function Settle.new(now, settled)
  return setmetatable({
    now = now,
    settled = settled == true,
    -- When the link came up, and when DATA last changed something.
    upSince = nil,
    lastData = nil,
  }, Settle)
end

-- Starts waiting again, as if never settled.
function Settle:restart()
  self.settled = false
  self.upSince, self.lastData = nil, nil
end

-- The link came up: settling starts, if it hasn't.
function Settle:up()
  self.upSince = self.upSince or self.now()
end

-- The link went down before settling: it starts over at the next up().
function Settle:down()
  if self.settled then return end
  self.upSince, self.lastData = nil, nil
end

function Settle:data()
  self.lastData = self.now()
end

function Settle:isSettled()
  return self.settled
end

-- Called once a second. Returns true on the tick it settles.
function Settle:tick()
  if self.settled or not self.upSince then return false end
  local now = self.now()
  local quietSince = math.max(self.upSince, self.lastData or self.upSince)
  if now - quietSince >= QUIET_FOR or now - self.upSince >= SETTLE_WITHIN then
    self.settled = true
    return true
  end
  return false
end
