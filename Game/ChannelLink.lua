-- Channel link: the production link adapter. Joins the Crew's hidden
-- channel, keeps it and its system notices out of chat, carries messages
-- over it with AceComm, and tells Core when the link is up or down.
-- See docs/design/code-structure.md (the link port), docs/design/joining-a-crew.md
-- and docs/research/channel-spike.md.

local _, ns = ...

local ChannelLink = {}
ns.ChannelLink = ChannelLink
LibStub("AceComm-3.0"):Embed(ChannelLink)

local PREFIX = "BFF"
-- The channel list settles a while after login; join once it has been quiet
-- this long, or after the fallback.
local SETTLE_QUIET = 2
local SETTLE_FALLBACK = 10
local JOIN_POLL = 0.5
local JOIN_TIMEOUT = 10
-- Leave a channel only once ChatThrottleLib has drained, or after the
-- longest wait.
local LEAVE_DELAY = 3
local LEAVE_MAX = 15
-- After a refused send, how long the link stays down before coming back up.
local REFUSED_PAUSE = 5

-- Channel events whose system notices for our channels don't print.
local FILTERED_EVENTS = {
  "CHAT_MSG_CHANNEL",
  "CHAT_MSG_CHANNEL_NOTICE",
  "CHAT_MSG_CHANNEL_NOTICE_USER",
  "CHAT_MSG_CHANNEL_JOIN",
  "CHAT_MSG_CHANNEL_LEAVE",
}

local core
local onNotice
local target          -- the Crew's channel and password, from Core
local joining = false
local joined = false
local failed = false
local settled = false
local isUp = false
local refused = false
local lastChannelUpdate
-- Upper-cased names of channels BFF is in or leaving, for the chat filter.
local ours = {}

local function lockdown()
  return C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()
end

local function channelIndex(name)
  local index = GetChannelName(name)
  return index and index > 0 and index or nil
end

-- Tells Core whenever the link goes up or down. isUp is set first, since
-- Core may react by changing the Crew, which comes back here.
local function update()
  local up = target ~= nil and joined and not lockdown() and not refused
  if up == isUp then return end
  isUp = up
  if up then core:up() else core:down() end
end

local function hide(name)
  for i = 1, NUM_CHAT_WINDOWS do
    local frame = _G["ChatFrame" .. i]
    if frame and frame.RemoveChannel then
      frame:RemoveChannel(name)
    else
      RemoveChatWindowChannel(i, name)
    end
  end
end

local function onJoined()
  joining = false
  joined = true
  hide(target.channel)
  update()
end

local function fail(kind)
  joining = false
  failed = true
  onNotice(kind)
  update()
end

local function tryJoin()
  if not target or joined or joining or failed or lockdown() then return end
  if channelIndex(target.channel) then
    -- Still in it after a /reload.
    onJoined()
    return
  end
  if not settled then return end

  joining = true
  local name = target.channel
  JoinTemporaryChannel(name, target.password)
  local waited = 0
  C_Timer.NewTicker(JOIN_POLL, function(ticker)
    waited = waited + JOIN_POLL
    if not joining or not target or target.channel ~= name then
      ticker:Cancel()
    elseif channelIndex(name) then
      ticker:Cancel()
      onJoined()
    elseif waited >= JOIN_TIMEOUT then
      -- No notice explained it; too many channels is the likely cause.
      ticker:Cancel()
      fail("tooManyChannels")
    end
  end)
end

local function leave(name)
  local waited = 0
  C_Timer.NewTicker(1, function(ticker)
    waited = waited + 1
    if target and target.channel == name then
      -- Rejoined before it was left.
      ticker:Cancel()
    elseif waited >= LEAVE_DELAY and not lockdown()
        and (not ChatThrottleLib.bQueueing or waited >= LEAVE_MAX) then
      ticker:Cancel()
      LeaveChannelByName(name)
    end
  end)
end

-- Chat event arguments can be secret under Midnight restrictions.
local function readable(text)
  return type(text) == "string" and not (issecretvalue and issecretvalue(text))
end

-- The shape of every Crew channel name (CrewCode.channel).
local CREW_CHANNEL = "^BFF" .. ("[0-9A-Z]"):rep(7) .. "$"

-- A /reload during leave()'s wait forgets which channel was being left, so
-- after settling, leave any Crew channel that isn't the current one.
local function leaveStale()
  local list = { GetChannelList() }
  for i = 2, #list, 3 do
    local name = list[i]
    if readable(name) and name:upper():find(CREW_CHANNEL)
        and not (target and target.channel:upper() == name:upper()) then
      ours[name:upper()] = true
      leave(name)
    end
  end
end

local function settle()
  if settled then return end
  settled = true
  leaveStale()
  tryJoin()
end

local function isOurs(name)
  return readable(name) and ours[name:upper()] == true
end

local function filter(_, _, ...)
  return isOurs((select(9, ...)))
end

local tooManyPattern = ERR_TOO_MANY_CHAT_CHANNELS
  and "^" .. ERR_TOO_MANY_CHAT_CHANNELS:gsub("%%d", "%%d+") .. "$"

-- The game's "You can only be in %d channels at a time.", during a join.
local function onError(text)
  if joining and tooManyPattern and readable(text) and text:find(tooManyPattern) then
    fail("tooManyChannels")
  end
end

local events = {}

function events.CHANNEL_UI_UPDATE()
  if settled then return end
  local stamp = {}
  lastChannelUpdate = stamp
  C_Timer.After(SETTLE_QUIET, function()
    if lastChannelUpdate == stamp then settle() end
  end)
end

function events.CHAT_MSG_CHANNEL_NOTICE(kind, ...)
  local name = select(8, ...)
  if not target or not isOurs(name) or name:upper() ~= target.channel:upper() then return end
  if kind == "WRONG_PASSWORD" then
    fail("wrongPassword")
  elseif kind == "YOU_LEFT" or kind == "SUSPENDED" then
    joined = false
    update()
  end
end

function events.CHAT_MSG_SYSTEM(text)
  onError(text)
end

function events.UI_ERROR_MESSAGE(_, text)
  onError(text)
end

-- Someone left the Crew channel, i.e. logged out: a real logout leaves it
-- before any goodbye could be sent.
function events.CHAT_MSG_CHANNEL_LEAVE(_, sender, ...)
  local name = select(7, ...)
  if not target or not isOurs(name) or name:upper() ~= target.channel:upper() then return end
  if readable(sender) then core:gone(Ambiguate(sender, "none")) end
end

function events.ADDON_RESTRICTION_STATE_CHANGED()
  update()
  tryJoin()
end

-- A send the game refused (throttled, or a general error): the link goes
-- down, and back up a few seconds later, so Core's next up() sends a fresh
-- DIGEST. The pause keeps a refusal that repeats from becoming a loop.
local function onRefused()
  if refused then return end
  refused = true
  update()
  C_Timer.After(REFUSED_PAUSE, function()
    refused = false
    update()
  end)
end

local SUCCESS = Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.Success or 0

-- AceComm's callback, once per chunk. Handled on the next frame, since it
-- can run inside Core's own send.
local function onSent(_, _, _, result)
  if result ~= nil and result ~= SUCCESS then C_Timer.After(0, onRefused) end
end

-- Starts the link. core gets up(), down(), gone(name) and received(message); notice
-- gets "tooManyChannels" or "wrongPassword" when the channel can't be joined.
function ChannelLink.start(theCore, notice)
  core = theCore
  onNotice = notice

  ChannelLink:RegisterComm(PREFIX, function(_, message)
    core:received(message)
  end)

  local addFilter = ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter or ChatFrame_AddMessageEventFilter
  for _, event in ipairs(FILTERED_EVENTS) do addFilter(event, filter) end

  local frame = CreateFrame("Frame")
  for event in pairs(events) do frame:RegisterEvent(event) end
  frame:SetScript("OnEvent", function(_, event, ...) events[event](...) end)
  C_Timer.After(SETTLE_FALLBACK, settle)
end

-- Follows Core's crew(): joins its channel, or leaves the old one.
function ChannelLink.setCrew(crew)
  local name = crew and crew.channel
  if target and target.channel == name then return end

  if target then
    joined = false
    joining = false
    leave(target.channel)
  end
  target = crew and { channel = crew.channel, password = crew.password }
  failed = false
  if name then ours[name:upper()] = true end
  update()
  tryJoin()
end

-- Best-effort: dropped while the link is down. ChannelLink.onSend, if set,
-- also gets every message sent (for /bff sim).
function ChannelLink.send(message)
  local index = isUp and channelIndex(target.channel)
  if not index then return end
  if ChannelLink.onSend then ChannelLink.onSend(message) end
  ChannelLink:SendCommMessage(PREFIX, message, "CHANNEL", index, nil, onSent)
end
