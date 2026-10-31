-- App: wiring only. Creates Core, routes WoW events to it and ticks it once a
-- second. See docs/design/code-structure.md.

local _, ns = ...

local function say(text)
  print("|cff33ff99BFF|r: " .. text)
end
ns.say = say

-- What Core's and the channel link's refusals and notices say.
local MESSAGES = {
  invalidCode = "That code doesn't look right.",
  inCrew = "Leave your Crew first (/bff leave).",
  invalidName = "A display name is 2 to 16 characters (/bff name <name>).",
  receiveOnly = "Trial accounts can join a Crew but not start one.",
  noCrew = "You're not in a Crew. Type /bff to start or join one.",
  tooManyChannels = "BFF couldn't join its channel: leave a chat channel and /reload.",
  wrongPassword = "BFF couldn't join its channel: start a new Crew.",
  leftCrew = "You left the Crew.",
  outOfDate = "BFF is out of date: someone in your Crew has a newer version. Update to keep seeing them.",
}
ns.MESSAGES = MESSAGES

local function onCoreEvent(event, kind)
  if event == "changed" then
    ns.Panel.refresh()
    ns.Minimap.refresh()
  elseif event == "crewChanged" then
    ns.ChannelLink.setCrew(ns.core:crew())
    ns.Panel.refresh()
    ns.Minimap.refresh()
  elseif event == "notice" then
    say(MESSAGES[kind])
  end
end

local function start(isInitialLogin)
  BFF_DB = BFF_DB or {}
  ns.core = ns.Core.new({
    db = BFF_DB,
    now = GetServerTime,
    random = math.random,
    link = ns.ChannelLink,
    listener = onCoreEvent,
    receiveOnly = IsTrialAccount() or IsVeteranTrialAccount(),
    initialLogin = isInitialLogin,
    maxLevel = GetMaxLevelForPlayerExpansion(),
  })
  ns.ChannelLink.start(ns.core, function(kind) say(MESSAGES[kind]) end)
  ns.ChannelLink.setCrew(ns.core:crew())
  ns.Panel.start(ns.core)
  ns.Minimap.start(ns.core)
  ns.Snapshot.start(ns.core)
  C_Timer.NewTicker(1, function() ns.core:tick() end)
  if isInitialLogin and not ns.core:crew() then
    say("type /bff to start or join a Crew.")
  end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_ENTERING_WORLD" and not ns.core then
    start((...))
  end
end)

StaticPopupDialogs.BFF_LEAVE_CREW = {
  text = "Leave your Crew? The others will see that you left.",
  button1 = YES,
  button2 = NO,
  OnAccept = function() ns.core:leaveCrew() end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
}

-- Asks to confirm, then leaves.
function ns.confirmLeave()
  StaticPopup_Show("BFF_LEAVE_CREW")
end

-- The display name the setup view and slash commands start from: the one
-- already set, or the current Character's first name (Forever Characters
-- may also have a last name, which could push it past 16 characters).
function ns.defaultDisplayName()
  return ns.core:displayName() or (UnitName("player") or ""):match("^%S*")
end
local defaultName = ns.defaultDisplayName

local function printCode(crew)
  say("your Crew code is " .. crew.code .. ". Share it with the others outside the game.")
end

local commands = {}

function commands.start()
  local crew, reason = ns.core:startCrew(defaultName())
  if crew then printCode(crew) else say(MESSAGES[reason]) end
end

function commands.join(code)
  local crew, reason = ns.core:joinCrew(code, defaultName())
  if crew then say("you're in the Crew " .. crew.code .. ".") else say(MESSAGES[reason]) end
end

function commands.code()
  local crew = ns.core:crew()
  if crew then printCode(crew) else say(MESSAGES.noCrew) end
end

function commands.name(name)
  local ok, reason = ns.core:setDisplayName(name)
  if ok then say("your display name is " .. ns.core:displayName() .. ".") else say(MESSAGES[reason]) end
end

function commands.minimap()
  ns.core:setMinimapShown(true)
  say("minimap button shown.")
end

function commands.leave()
  if ns.core:crew() then ns.confirmLeave() else say(MESSAGES.noCrew) end
end

-- /bff sim, /bff sim ding and /bff sim stop, only in a dev checkout
-- (Dev/ is left out of releases).
function commands.sim(rest)
  if not ns.Sim then return say("/bff sim is only in a dev checkout.") end
  if rest == "stop" then
    ns.Sim.stop()
    say("simulated Members logged out.")
  elseif rest == "ding" then
    local name = ns.Sim.ding()
    say(name and name .. " dinged." or "/bff sim isn't running.")
  else
    local ok, reason = ns.Sim.start(ns.core)
    if ok then
      say("three simulated Members joined. /bff sim ding, /bff sim stop.")
    elseif reason == "running" then
      say("/bff sim is already running.")
    else
      say("/bff sim needs a Crew no one else is in yet: /bff leave, then /bff start.")
    end
  end
end

SLASH_BFF1 = "/bff"
SlashCmdList.BFF = function(input)
  if not ns.core then return end
  local command, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
  command = command:lower()
  if command == "" then
    ns.Panel.toggle()
  elseif commands[command] then
    commands[command](rest)
  else
    say("/bff, /bff start, /bff join <code>, /bff code, /bff name <name>, /bff minimap, /bff leave")
  end
end

-- The key binding in Bindings.xml, under a "BFF" header in Key Bindings.
BINDING_HEADER_BFF = "BFF"
BINDING_NAME_BFF_TOGGLE = "Open or close the BFF panel"

function BFF_TogglePanel()
  if ns.core then ns.Panel.toggle() end
end
