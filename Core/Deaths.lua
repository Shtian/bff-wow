local _, ns = ...

local Deaths = {}
ns.Deaths = Deaths

local UNCOUNTED = { pvp = true, arena = true }

function Deaths.counts(instanceType)
  return not UNCOUNTED[instanceType]
end
