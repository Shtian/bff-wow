local _, ns = ...

local Deaths = {}
ns.Deaths = Deaths

local UNCOUNTED = { pvp = true, arena = true }
local BACK_TO_LIFE = { PLAYER_ALIVE = true, PLAYER_UNGHOST = true }

function Deaths.counts(instanceType)
  return not UNCOUNTED[instanceType]
end

function Deaths.record(record, event, deadOrGhost, instanceType)
  if event == "PLAYER_DEAD" then
    if not record.deathCounted and Deaths.counts(instanceType) then
      record.deaths = (record.deaths or 0) + 1
      record.deathCounted = true
    end
  elseif BACK_TO_LIFE[event] and not deadOrGhost then
    record.deathCounted = nil
  end
end
