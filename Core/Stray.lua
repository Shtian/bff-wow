local _, ns = ...

local Stray = {}
Stray.__index = Stray
ns.Stray = Stray

Stray.AFTER_LOGIN = 3 * 60
Stray.STAYS_FOR = 10 * 60
Stray.IGNORED_BEFORE_A_BREAK = 3
Stray.BREAK = 7 * 24 * 60 * 60

local KEPT = "The %s stays. Change it in Settings › You › Look."
local TITLE = "A stray %s"
local HINT = "Click to keep it. Right-click: not now."

local function named(key)
  return ns.Look.petLabel(key):lower()
end

function Stray.describe(visit)
  return { key = visit.key, since = visit.since, tooltip = { title = TITLE:format(named(visit.key)), hint = HINT } }
end

function Stray.new(db, now, random)
  return setmetatable({ db = db, now = now, random = random, loggedIn = now(), came = false, stopped = false },
    Stray)
end

local function saved(self)
  local stray = self.db.stray
  if type(stray) ~= "table" then
    stray = {}
    self.db.stray = stray
  end
  return stray
end

local function pick(self, last)
  local keys = {}
  for _, pet in ipairs(ns.Look.PETS) do
    if pet.key ~= "none" and pet.key ~= last then keys[#keys + 1] = pet.key end
  end
  return keys[math.min(#keys, math.floor(self.random() * #keys) + 1)]
end

local function due(self, fighting)
  if self.came or self.stopped or fighting then return false end
  local now = self.now()
  local nextAt = saved(self).nextAt
  return now - self.loggedIn >= Stray.AFTER_LOGIN and not (type(nextAt) == "number" and now < nextAt)
end

function Stray:wanderOff()
  if not self.visit then return false end
  self.visit = nil
  local stray = saved(self)
  stray.ignored = (type(stray.ignored) == "number" and stray.ignored or 0) + 1
  if stray.ignored % Stray.IGNORED_BEFORE_A_BREAK == 0 then stray.nextAt = self.now() + Stray.BREAK end
  return true
end

function Stray:tick(wanted, fighting)
  if self.visit and not wanted then
    self.visit = nil
    return true
  end
  if self.visit then
    return self.now() - self.visit.since >= Stray.STAYS_FOR and self:wanderOff()
  end
  if not (wanted and due(self, fighting)) then return false end
  local stray = saved(self)
  local key = pick(self, stray.last)
  stray.last = key
  self.came = true
  self.visit = { key = key, since = self.now() }
  return true
end

function Stray:visiting()
  return self.visit
end

function Stray:keep()
  local visit = self.visit
  if not visit then return nil end
  self.visit = nil
  return visit.key, KEPT:format(named(visit.key))
end

function Stray:notNow()
  self.stopped = true
  if not self.visit then return false end
  self.visit = nil
  return true
end
