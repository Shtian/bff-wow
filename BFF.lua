-- App: wiring only. Creates Core, routes WoW events to it and ticks it once a
-- second. See docs/design/code-structure.md.

local _, ns = ...

-- Stands in for the channel link until it exists: sends go nowhere.
local noLink = { send = function() end }

local function onCoreEvent(event)
  if event == "changed" then
    ns.Panel.refresh()
  end
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
  ns.Panel.start(ns.core)
  ns.Snapshot.start(ns.core)
  C_Timer.NewTicker(1, function() ns.core:tick() end)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_ENTERING_WORLD" and not ns.core then
    start((...))
  end
end)

SLASH_BFF1 = "/bff"
SlashCmdList.BFF = function()
  if ns.core then ns.Panel.toggle() end
end
