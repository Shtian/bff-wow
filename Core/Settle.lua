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
    upSince = nil,
    lastData = nil,
  }, Settle)
end

function Settle:restart()
  self.settled = false
  self.upSince, self.lastData = nil, nil
end

function Settle:up()
  self.upSince = self.upSince or self.now()
end

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
