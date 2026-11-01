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
  noCrew = "You're not in a Crew. Type /bff to start or join one.",
  tooManyChannels = "BFF couldn't join its channel: leave a chat channel and /reload.",
  wrongPassword = "BFF couldn't join its channel: start a new Crew.",
  leftCrew = "You left the Crew.",
  minimapHidden = "Minimap button hidden. Type /bff minimap to show it again.",
  settingsInCombat = "BFF's settings open once you're out of combat.",
  outOfDate = "BFF is out of date: someone in your Crew has a newer version. Update to keep seeing them.",
  invalidItem = "That isn't an item. Type /bff hmd add, then shift-click the item into the chat box.",
  tooMany = "You have 20 Hand-me-downs up already. Withdraw one first (/bff hmd).",
  tooManyClaims = "You have 20 open Claims already. Withdraw one first.",
  claimed = "You've claimed that one already.",
  own = "That's your own Hand-me-down.",
  unknown = "That Hand-me-down isn't up any more.",
  unknownCharacter = "That isn't one of your Characters.",
  noClaim = "Nobody has claimed that one yet.",
  given = "That one has been given already.",
  notClaimed = "You haven't claimed that one.",
  winnerChanged = "Someone claimed it earlier in the meantime. Have another look before you Give it.",
}
ns.MESSAGES = MESSAGES

-- A live Feed entry or Reaction as a chat line: "BFF: Ana dinged 24."
local function chatLine(entry)
  local text = entry.text
  if not text:find("[.!?]$") then text = text .. "." end
  say(text)
end

-- While you were away waits for combat to end.
local pendingAway
local eventFrame = CreateFrame("Frame")

local function showAway(summary)
  if InCombatLockdown() then
    pendingAway = summary
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
  else
    ns.Away.show(summary)
  end
end

local function onCoreEvent(event, kind)
  if event == "changed" then
    ns.Panel.refresh()
    ns.Minimap.refresh()
    ns.MapPins.refresh()
    ns.Settings.refresh()
  elseif event == "crewChanged" then
    ns.ChannelLink.setCrew(ns.core:crew())
    ns.Panel.refresh()
    ns.Minimap.refresh()
    ns.MapPins.refresh()
    ns.Settings.refresh()
  elseif event == "notice" then
    say(MESSAGES[kind])
  elseif event == "feedEntry" or event == "reaction" or event == "handMeDown" then
    if ns.core:isChatLinesOn() then chatLine(kind) end
    if ns.core:isToastsOn() then ns.Toasts.show(kind) end
  elseif event == "awaySummary" then
    showAway(kind)
  end
end

-- How far local time is ahead of server time, so the Feed's days start at
-- local midnight.
local function utcOffset()
  local now = time()
  return time(date("*t", now)) - time(date("!*t", now))
end

-- Redraws the panel once a burst of item info has arrived.
local itemRefreshDue = false
local function itemInfoReceived()
  if itemRefreshDue then return end
  itemRefreshDue = true
  C_Timer.After(0.2, function()
    itemRefreshDue = false
    ns.Panel.refresh()
  end)
end

local function start(isInitialLogin)
  BFF_DB = BFF_DB or {}
  ns.core = ns.Core.new({
    db = BFF_DB,
    now = GetServerTime,
    random = math.random,
    link = ns.ChannelLink,
    listener = onCoreEvent,
    initialLogin = isInitialLogin,
    maxLevel = GetMaxLevelForPlayerExpansion(),
    utcOffset = utcOffset(),
    locate = ns.Snapshot.locate,
    itemLink = ns.Snapshot.itemLink,
  })
  ns.ChannelLink.start(ns.core, function(kind) say(MESSAGES[kind]) end)
  ns.ChannelLink.setCrew(ns.core:crew())
  ns.Panel.start(ns.core)
  ns.Minimap.start(ns.core)
  ns.MapPins.start(ns.core)
  ns.Toasts.start(ns.core)
  ns.Settings.start(ns.core)
  ns.Snapshot.start(ns.core)
  C_Timer.NewTicker(1, function() ns.core:tick() end)
  if isInitialLogin and not ns.core:crew() then
    say("type /bff to start or join a Crew.")
  end
end

eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
eventFrame:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_ENTERING_WORLD" and not ns.core then
    start((...))
  elseif event == "GET_ITEM_INFO_RECEIVED" then
    if ns.core then itemInfoReceived() end
  elseif event == "PLAYER_REGEN_ENABLED" then
    eventFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    local summary = pendingAway
    pendingAway = nil
    if summary then ns.Away.show(summary) end
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

function commands.feed()
  ns.Panel.show("feed")
end

function commands.goals()
  ns.Panel.show("goals")
end

-- /bff hmd opens the Hand-me-downs tab; /bff hmd add <item link> offers
-- the item to the Crew, with the level it needs. BFF can't check yet that
-- it can be traded (#67), so that's up to you.
function commands.hmd(rest)
  local sub, link = rest:match("^(%S*)%s*(.-)$")
  if sub:lower() ~= "add" then return ns.Panel.show("handMeDowns") end
  if link == "" then return say(MESSAGES.invalidItem) end
  local id, reason = ns.core:postHandMeDown(link, ns.Snapshot.requiredLevel(link))
  if id then
    say(link .. " is up for your Crew. See /bff hmd.")
  else
    say(MESSAGES[reason])
  end
end

function commands.when()
  ns.Panel.showWhen(nil)
end

function commands.settings()
  ns.Settings.open()
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
    say("/bff, /bff feed, /bff goals, /bff when, /bff hmd, /bff hmd add <item>, /bff start, /bff join <code>, /bff code, /bff name <name>, /bff settings, /bff minimap, /bff leave")
  end
end

-- The key binding in Bindings.xml, under a "BFF" header in Key Bindings.
BINDING_HEADER_BFF = "BFF"
BINDING_NAME_BFF_TOGGLE = "Open or close the BFF panel"

function BFF_TogglePanel()
  if ns.core then ns.Panel.toggle() end
end
