-- App: wiring only. Creates Core, routes WoW events to it and ticks it once a
-- second. See docs/design/code-structure.md.

local _, ns = ...

-- Stands in for the channel link until it exists: sends go nowhere.
local noLink = { send = function() end }

local function onCoreEvent()
end

local function start(isInitialLogin)
  BFF_DB = BFF_DB or {}
  ns.core = ns.Core.new({
    db = BFF_DB,
    now = GetServerTime,
    random = math.random,
    link = noLink,
    listener = onCoreEvent,
    receiveOnly = IsTrialAccount() or IsVeteranTrialAccount(),
    initialLogin = isInitialLogin,
    maxLevel = GetMaxLevelForPlayerExpansion(),
  })
  C_Timer.NewTicker(1, function() ns.core:tick() end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_ENTERING_WORLD" and not ns.core then
    start((...))
  end
end)
