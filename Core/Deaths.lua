local _, ns = ...

local Deaths = {}
ns.Deaths = Deaths

local UNCOUNTED = { pvp = true, arena = true }

function Deaths.counts(instanceType)
  return not UNCOUNTED[instanceType]
end

function Deaths.died(characterDB, instanceType)
  if characterDB.deathCounted or not Deaths.counts(instanceType) then return end
  characterDB.deaths = characterDB.deaths + 1
  characterDB.deathCounted = true
end

function Deaths.checkAlive(characterDB, deadOrGhost)
  if not deadOrGhost then characterDB.deathCounted = nil end
end
