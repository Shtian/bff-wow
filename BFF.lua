-- App: wiring only. Creates Core, routes WoW events to it and ticks it once a
-- second. See docs/design/code-structure.md.

local addonName, ns = ...

-- The .toc's Version, which the packager fills in from the release tag
-- ("v0.2.1"). A checkout that wasn't packaged still has the token.
local version = C_AddOns.GetAddOnMetadata(addonName, "Version")
if not version or version:find("@", 1, true) then version = "dev" end
ns.VERSION = version

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
  invalidItem = "That isn't an item. Drop one on the Spares tab (/bff spares), or type /bff spares add and shift-click it into the chat box.",
  bound = "That item is bound to you, so it can't be passed on.",
  questItem = "That's a quest item, so it can't be passed on.",
  accountBound = "That item is bound to your account, so only your own characters can have it.",
  notInBags = "That item isn't in your bags. BFF can only offer what you're carrying.",
  tooMany = "You have 20 Spares up already. Withdraw one first (/bff spares).",
  tooManyClaims = "You have 20 open Claims already. Withdraw one first.",
  claimed = "You've claimed that one already.",
  own = "That's your own Spare.",
  unknown = "That Spare isn't up any more.",
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

-- Spares whose item left the bags and that have a Claim, asked
-- about one at a time: Give to the winner, withdraw, or not now (the
-- question comes back next login). Escape is "not now".
local goneAsks = {}

local function askNextGone()
  local ask = goneAsks[1]
  if not ask then return end
  -- No free popup: drop the rest rather than wait for an OnHide that
  -- won't come. They're asked again next login.
  if not StaticPopup_Show("BFF_SPARE_GONE", ask.link or "Your Spare",
    ask.winner and ask.winner.character or "?", ask) then
    goneAsks = {}
  end
end

StaticPopupDialogs.BFF_SPARE_GONE = {
  text = "%s is no longer in your bags or bank. %s claimed it.\n\nWhat happened to it?",
  button1 = "Sent it",
  button2 = "Ask me later",
  button3 = "Got rid of it",
  OnAccept = function(_, ask)
    local ok, reason = ns.core:giveSpare(ask.id, ask.winner and ask.winner.memberId)
    if not ok then say(MESSAGES[reason]) end
  end,
  OnAlt = function(_, ask)
    local ok, reason = ns.core:withdrawSpare(ask.id)
    if not ok then say(MESSAGES[reason]) end
  end,
  OnHide = function()
    table.remove(goneAsks, 1)
    C_Timer.After(0, askNextGone)
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
}

-- Core found a Spare's item gone at login: it withdrew it, or asks.
local function spareGone(gone)
  if gone.action == "withdrawn" then
    say(("%s has left your bags, so your Spare is withdrawn."):format(gone.link or "An item"))
  elseif gone.action == "ask" then
    goneAsks[#goneAsks + 1] = gone
    if #goneAsks == 1 then askNextGone() end
  end
end

local function onCoreEvent(event, arg, more)
  if event == "changed" then
    ns.Panel.refresh()
    ns.PocketCamp.refresh()
    ns.Minimap.refresh()
    ns.MapPins.refresh()
    ns.Settings.refresh()
  elseif event == "settingChanged" then
    -- arg is the key, more the new value; each module ignores keys it
    -- doesn't use.
    ns.Panel.settingChanged(arg, more)
    ns.PocketCamp.settingChanged(arg, more)
    ns.Minimap.settingChanged(arg, more)
    ns.Toasts.settingChanged(arg, more)
    ns.Settings.settingChanged(arg, more)
  elseif event == "crewChanged" then
    ns.ChannelLink.setCrew(ns.core:crew())
    ns.Panel.refresh()
    ns.PocketCamp.refresh()
    ns.Minimap.refresh()
    ns.MapPins.refresh()
    ns.Settings.refresh()
  elseif event == "notice" then
    say(MESSAGES[arg])
  elseif event == "feedEntry" or event == "reaction" or event == "spare" then
    -- Core says where each Live event goes: more is its outlets.
    if more.chat then chatLine(arg) end
    if more.toast then ns.Toasts.show(arg) end
  elseif event == "pocketCampAnimation" then
    ns.PocketCamp.animate(arg)
  elseif event == "awaySummary" then
    showAway(arg)
  elseif event == "spareGone" then
    spareGone(arg)
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
    itemLook = ns.Skin.itemLook,
    findItem = ns.Bags.findItem,
  })
  ns.ChannelLink.start(ns.core, function(kind) say(MESSAGES[kind]) end)
  ns.ChannelLink.setCrew(ns.core:crew())
  ns.Panel.start(ns.core)
  ns.PocketCamp.start(ns.core)
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
-- After a real login the bags read as empty until the first of these, so
-- Core checks Spare items only on it.
eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
-- A boss died: Core decides whether it's a clear.
eventFrame:RegisterEvent("ENCOUNTER_END")
-- The loot window filled: Core keeps it if it was fished. With auto-loot
-- the slots are still filled when LOOT_READY fires. It can fire more than
-- once for one window, so a window's catch is kept once, until LOOT_CLOSED.
eventFrame:RegisterEvent("LOOT_READY")
eventFrame:RegisterEvent("LOOT_CLOSED")
local lootRead = false
-- The Camp's art pixel is a whole number of screen pixels: worked out
-- again when the UI scale or the window changes.
eventFrame:RegisterEvent("UI_SCALE_CHANGED")
eventFrame:RegisterEvent("DISPLAY_SIZE_CHANGED")
eventFrame:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_ENTERING_WORLD" and not ns.core then
    start((...))
  elseif event == "GET_ITEM_INFO_RECEIVED" then
    if ns.core then itemInfoReceived() end
  elseif event == "BAG_UPDATE_DELAYED" then
    if ns.core then ns.core:bagsUpdated() end
  elseif event == "ENCOUNTER_END" then
    if ns.core then ns.core:encounterEnded(ns.Snapshot.encounter(...)) end
  elseif event == "LOOT_READY" then
    -- Marked read only once something fished is found, in case
    -- IsFishingLoot() isn't true yet at the first LOOT_READY.
    if ns.core and not lootRead then
      local loot = ns.Snapshot.catch()
      if loot then
        lootRead = true
        ns.core:caught(loot)
      end
    end
  elseif event == "LOOT_CLOSED" then
    lootRead = false
  elseif event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
    if ns.core then
      ns.Panel.refresh()
      ns.PocketCamp.refresh()
    end
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

-- Says how posting a bag item went, from Bags' returns: the
-- Spare's id and the item's link, or nil and a reason.
function ns.sayPosted(id, result)
  if id then
    say(result .. " is up for your Crew. See /bff spares.")
  else
    say(MESSAGES[result])
  end
end

-- /bff spares opens the Spares tab; /bff spares add <item link> offers
-- the first matching item in your bags to the Crew, if it can be traded.
function commands.spares(rest)
  local sub, link = rest:match("^(%S*)%s*(.-)$")
  if sub:lower() ~= "add" then return ns.Panel.show("spares") end
  ns.sayPosted(ns.Bags.postLink(ns.core, link))
end

function commands.when()
  ns.Panel.showWhen(nil)
end

function commands.professions()
  ns.Panel.show("professions")
end

function commands.catches()
  ns.Panel.show("catches")
end

function commands.together()
  ns.Panel.show("together")
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

-- /bff sim, /bff sim ding, /bff sim fish and /bff sim stop, only in a dev checkout
-- (Dev/ is left out of releases).
function commands.sim(rest)
  if not ns.Sim then return say("/bff sim is only in a dev checkout.") end
  if rest == "stop" then
    ns.Sim.stop()
    say("simulated Members logged out.")
  elseif rest == "ding" then
    local name = ns.Sim.ding()
    say(name and name .. " dinged." or "/bff sim isn't running.")
  elseif rest == "fish" then
    local name, itemId = ns.Sim.fish()
    say(name and ("%s caught item %d. See /bff catches."):format(name, itemId) or "/bff sim isn't running.")
  else
    local ok, reason = ns.Sim.start(ns.core)
    if ok then
      say("simulated Members joined. /bff sim ding, /bff sim fish, /bff sim stop.")
    elseif reason == "running" then
      say("/bff sim is already running.")
    else
      say("/bff sim needs a Crew no one else is in yet: /bff leave, then /bff start.")
    end
  end
end

-- The sync trace (/bff debug sync): off at every login and reload. Each
-- line from Core and the channel link gets the time of day and GetTime().
-- In a dev checkout the /bffdev console sets ns.traceSink(stamp, text): it
-- shows the line in its log and returns true, else the line goes to chat.
local syncTrace = false
local function traceLine(text)
  local stamp = ("%s %.3f"):format(date("%H:%M:%S"), GetTime())
  if ns.traceSink and ns.traceSink(stamp, text) then return end
  print(("|cff33ff99BFF|r |cff888888%s|r %s"):format(stamp, text))
end

function ns.setSyncTrace(on)
  syncTrace = on and true or false
  local trace = syncTrace and traceLine or nil
  ns.core:setTrace(trace)
  ns.ChannelLink.setTrace(trace)
end

function ns.isSyncTraceOn()
  return syncTrace
end

function commands.debug(rest)
  if rest:lower() ~= "sync" then return say("/bff debug sync turns the sync trace on or off.") end
  ns.setSyncTrace(not syncTrace)
  say(syncTrace and "sync trace on. /bff debug sync turns it off." or "sync trace off.")
end

local HELP = "/bff, /bff feed, /bff goals, /bff when, /bff spares, /bff spares add <item>, /bff professions, "
  .. "/bff together, /bff catches, /bff start, /bff join <code>, /bff code, /bff name <name>, /bff settings, "
  .. "/bff minimap, /bff leave, /bff debug sync, /bff help"

function commands.help()
  say(HELP)
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
    commands.help()
  end
end

-- The key binding in Bindings.xml, under a "BFF" header in Key Bindings.
BINDING_HEADER_BFF = "BFF"
BINDING_NAME_BFF_TOGGLE = "Open or close the BFF panel"

function BFF_TogglePanel()
  if ns.core then ns.Panel.toggle() end
end
