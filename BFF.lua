local addonName, ns = ...

local version = C_AddOns.GetAddOnMetadata(addonName, "Version")
if not version or version:find("@", 1, true) then version = "dev" end
ns.VERSION = version

local function say(text)
  print("|cff33ff99BFF|r: " .. text)
end
ns.say = say

local MESSAGES = {
  invalidCode = "That code doesn't look right.",
  inCrew = "Leave your Crew first (/bff leave).",
  invalidName = "A display name is 2 to 16 characters (/bff name <name>).",
  noCrew = "You're not in a Crew. Type /bff to start or join one.",
  tooManyChannels = "BFF couldn't join its channel: leave a chat channel and /reload.",
  wrongPassword = "BFF couldn't join its channel: start a new Crew.",
  leftCrew = "You left the Crew.",
  minimapHidden = "Minimap button hidden. Type /bff minimap to show it again.",
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

local function chatLine(entry)
  local text = entry.text
  if not text:find("[.!?]$") then text = text .. "." end
  say(text)
end

local pendingAway
local pendingTip
local eventFrame = CreateFrame("Frame")

local function showTip(tip)
  if InCombatLockdown() then
    pendingTip = tip
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
  else
    ns.TipDialog.show(tip)
  end
end

local function showAway(summary)
  if InCombatLockdown() then
    pendingAway = summary
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
  else
    ns.Away.show(summary)
  end
end

local goneAsks = {}

local function askNextGone()
  local ask = goneAsks[1]
  if not ask then return end
  -- WoW: StaticPopup_Show returns nil when no popup frame is free, and no OnHide follows.
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
    ns.TipDialog.refresh()
    ns.Minimap.refresh()
    ns.MapPins.refresh()
  elseif event == "settingChanged" then
    ns.Panel.settingChanged(arg, more)
    ns.PocketCamp.settingChanged(arg, more)
    ns.TipDialog.refresh()
    ns.Minimap.settingChanged(arg, more)
    ns.Toasts.settingChanged(arg, more)
    ns.MapPins.settingChanged(arg, more)
  elseif event == "moved" then
    ns.MapPins.moved()
  elseif event == "crewChanged" then
    ns.ChannelLink.setCrew(ns.core:crew())
    ns.Panel.refresh()
    ns.PocketCamp.refresh()
    ns.Minimap.refresh()
    ns.MapPins.refresh()
  elseif event == "notice" then
    say(MESSAGES[arg])
  elseif event == "newerBff" then
    say(arg.text)
  elseif event == "feedEntry" or event == "reaction" or event == "spare" then
    if more.chat then chatLine(arg) end
    if more.toast then ns.Toasts.show(arg) end
  elseif event == "tip" then
    showTip(arg)
  elseif event == "pocketCampAnimation" then
    ns.PocketCamp.animate(arg)
  elseif event == "campReaction" then
    ns.Panel.campReaction(arg)
    ns.Away.campReaction(arg)
    ns.PocketCamp.campReaction(arg)
  elseif event == "awaySummary" then
    showAway(arg)
  elseif event == "spareGone" then
    spareGone(arg)
  end
end

local function utcOffset()
  local now = time()
  return time(date("*t", now)) - time(date("!*t", now))
end

local itemRefreshDue = false
local function itemInfoReceived()
  if itemRefreshDue then return end
  itemRefreshDue = true
  C_Timer.After(0.2, function()
    itemRefreshDue = false
    ns.Panel.refresh()
  end)
end

local syncLog = ns.SyncLog.new()
ns.syncLog = syncLog
local syncTrace = false
local function traceLine(text)
  local stamp = ("%s %.3f"):format(date("%H:%M:%S"), GetTime())
  syncLog:add(stamp .. "  " .. text)
  if not syncTrace then return end
  if ns.traceSink and ns.traceSink(stamp, text) then return end
  print(("|cff33ff99BFF|r |cff888888%s|r %s"):format(stamp, text))
end

function ns.setSyncTrace(on)
  syncTrace = on and true or false
end

function ns.isSyncTraceOn()
  return syncTrace
end

local function start(isInitialLogin)
  BFF_DB = BFF_DB or {}
  BFF_CharacterDB = BFF_CharacterDB or {}
  syncLog:restore(BFF_CharacterDB.syncLog,
    ("-- earlier sessions above · this one began %s --"):format(date("%Y-%m-%d %H:%M:%S")))
  ns.core = ns.Core.new({
    db = BFF_DB,
    now = GetServerTime,
    random = math.random,
    link = ns.ChannelLink,
    listener = onCoreEvent,
    initialLogin = isInitialLogin,
    maxLevel = GetMaxLevelForPlayerExpansion(),
    utcOffset = utcOffset(),
    daylight = ns.Snapshot.daylight,
    locate = ns.Snapshot.locate,
    itemLink = ns.Snapshot.itemLink,
    itemLook = ns.Skin.itemLook,
    findItem = ns.Bags.findItem,
    version = version,
    changelog = ns.CHANGELOG_TEXT,
  })
  ns.core:setTrace(traceLine)
  ns.ChannelLink.setTrace(traceLine)
  ns.ChannelLink.start(ns.core, function(kind) say(MESSAGES[kind]) end)
  ns.ChannelLink.setCrew(ns.core:crew())
  ns.Panel.start(ns.core)
  ns.PocketCamp.start(ns.core)
  ns.TipDialog.start(ns.core)
  ns.Minimap.start(ns.core)
  ns.MapPins.start(ns.core)
  ns.Toasts.start(ns.core)
  ns.Snapshot.start(ns.core)
  C_Timer.NewTicker(1, function()
    ns.core:doing(ns.Snapshot.doing())
    ns.core:tick()
  end)
  if isInitialLogin and not ns.core:crew() then
    say("type /bff to start or join a Crew.")
  end
end

eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
eventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
-- WoW: after a real login the bags read as empty until the first BAG_UPDATE_DELAYED.
eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
eventFrame:RegisterEvent("ENCOUNTER_END")
-- WoW: with auto-loot the slots are still filled when LOOT_READY fires, and it can
-- fire more than once for one loot window, before LOOT_CLOSED.
eventFrame:RegisterEvent("LOOT_READY")
eventFrame:RegisterEvent("LOOT_CLOSED")
local lootRead = false
eventFrame:RegisterEvent("UI_SCALE_CHANGED")
eventFrame:RegisterEvent("DISPLAY_SIZE_CHANGED")
eventFrame:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_ENTERING_WORLD" and not ns.core then
    start((...))
  elseif event == "PLAYER_LOGOUT" then
    if ns.core then BFF_CharacterDB.syncLog = syncLog:save() end
  elseif event == "GET_ITEM_INFO_RECEIVED" then
    if ns.core then itemInfoReceived() end
  elseif event == "BAG_UPDATE_DELAYED" then
    if ns.core then ns.core:bagsUpdated() end
  elseif event == "ENCOUNTER_END" then
    if ns.core then ns.core:encounterEnded(ns.Snapshot.encounter(...)) end
  elseif event == "LOOT_READY" then
    -- WoW: IsFishingLoot() may not be true yet at the first LOOT_READY.
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
    local summary, tip = pendingAway, pendingTip
    pendingAway, pendingTip = nil, nil
    if summary then ns.Away.show(summary) end
    if tip and ns.core:tip() then ns.TipDialog.show(tip) end
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

function ns.confirmLeave()
  StaticPopup_Show("BFF_LEAVE_CREW")
end

-- WoW: a Forever Character's name can be "First Last".
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

function commands.roster()
  ns.Panel.show("roster")
end

function commands.trophies()
  ns.Panel.show("trophies")
end

function ns.sayPosted(id, result)
  if id then
    say(result .. " is up for your Crew. See /bff spares.")
  else
    say(MESSAGES[result])
  end
end

function commands.spares(rest)
  local sub, link = rest:match("^(%S*)%s*(.-)$")
  if sub:lower() ~= "add" then return ns.Panel.show("spares") end
  ns.sayPosted(ns.Bags.postLink(ns.core, link))
end

function commands.playtimes()
  ns.Panel.showPlayTimes(nil)
end

function commands.professions()
  ns.Panel.show("professions")
end

function commands.catches()
  ns.Panel.show("catches")
end

function commands.dungeons()
  ns.Panel.show("dungeons")
end

function commands.whatsnew()
  ns.Panel.show("whatsnew")
end

function commands.settings()
  ns.Panel.show("settings")
end

function commands.minimap()
  ns.core:setMinimapShown(true)
  say("minimap button shown.")
end

function commands.leave()
  if ns.core:crew() then ns.confirmLeave() else say(MESSAGES.noCrew) end
end

function commands.sim(rest)
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

function commands.report()
  ns.Report.show()
end

function commands.debug(rest)
  if rest:lower() ~= "sync" then return say("/bff debug sync turns the sync trace on or off.") end
  ns.setSyncTrace(not syncTrace)
  say(syncTrace and "sync trace on. /bff debug sync turns it off." or "sync trace off.")
end

local function isDev()
  return ns.Sim ~= nil
end

local function sayLines(lines)
  say(lines[1])
  for i = 2, #lines do print(lines[i]) end
end

function commands.help(rest)
  local word = rest:match("^%S*")
  if word == "" then return sayLines(ns.Commands.help(isDev())) end
  local lines = ns.Commands.helpFor(word, isDev())
  if lines then sayLines(lines) else say(ns.Commands.unknown(word, isDev())) end
end

SLASH_BFF1 = "/bff"
SlashCmdList.BFF = function(input)
  if not ns.core then return end
  local command, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
  command = command:lower()
  if command == "" then
    return ns.Panel.toggle()
  end
  local name = ns.Commands.resolve(command, isDev())
  if name then
    commands[name](rest)
  else
    say(ns.Commands.unknown(command, isDev()))
  end
end

-- WoW: Key Bindings labels Bindings.xml entries from BINDING_HEADER_ and BINDING_NAME_ globals.
BINDING_HEADER_BFF = "BFF"
BINDING_NAME_BFF_TOGGLE = "Open or close the BFF panel"

function BFF_TogglePanel()
  if ns.core then ns.Panel.toggle() end
end
