-- Core: everything BFF knows and decides, in pure Lua. It never touches the
-- game; App hands it the clock, randomness, the link and saved data.
-- See docs/design/code-structure.md.

local _, ns = ...

local Core = {}
Core.__index = Core
ns.Core = Core

local required = {
  db = "table",
  now = "function",
  random = "function",
  link = "table",
  listener = "function",
  maxLevel = "number",
}

-- deps: db, now(), random(), link (with send(string)), listener(event, ...),
-- receiveOnly, initialLogin and maxLevel.
function Core.new(deps)
  for name, kind in pairs(required) do
    if type(deps[name]) ~= kind then
      error(("Core.new: %s must be a %s"):format(name, kind), 2)
    end
  end
  if type(deps.link.send) ~= "function" then
    error("Core.new: link.send must be a function", 2)
  end

  return setmetatable({
    db = deps.db,
    now = deps.now,
    random = deps.random,
    link = deps.link,
    listener = deps.listener,
    receiveOnly = deps.receiveOnly == true,
    initialLogin = deps.initialLogin == true,
    maxLevel = deps.maxLevel,
    ledger = ns.Ledger.new(deps.db, deps.now, deps.random),
  }, Core)
end

-- The current state of the Character being played, from Snapshot: guid,
-- name, classFilename, level, xp, maxXp, zone and deaths.
function Core:updateOwn(character)
  if self.ledger:updateOwn(character) then
    self.listener("changed")
  end
end

-- The panel's rows, ready to render. Each row is a Member: memberId, and the
-- shown Character's name, classFilename, level, xp, maxXp and zone, plus
-- alts (name, classFilename, level).
function Core:rows()
  return ns.Roster.rows(self.ledger)
end

-- Called once a second. Core decides what is due.
function Core:tick()
end
