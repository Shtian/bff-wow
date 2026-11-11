-- Channel link: the production link adapter. Joins the Crew's hidden
-- channel, keeps it and its system notices out of chat, and tells Core when
-- the link is up or down. The channel only says who is online: on WoW:
-- Forever addon messages sent to a custom channel are accepted and never
-- delivered, so every message goes out with AceComm as an addon whisper to
-- each other Character in the channel.
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
-- A "Player is offline." within this long after a failed send to one
-- Character is about them.
local OFFLINE_WINDOW = 3
-- The channel's member list: how long to wait for the first reply before
-- coming up anyway, how often to ask again, and how long a reply we asked
-- for stays out of chat.
local LIST_WAIT = 5
local LIST_REFRESH = 60
local LIST_HIDE = 5
-- Messages whispered by someone not (yet) known to be in the channel wait
-- this long for a member list that shows them, and at most this many.
local STRANGER_WAIT = 10
local STRANGER_MAX = 20
-- After "No player named ...", how long more of them for that name (queued
-- whispers, later chunks) stay out of chat.
local NOT_FOUND_HIDE = 30
-- An unreadable system message within this long after a whisper goes in
-- the trace (#160: what the game says after a whisper in an instance).
local SECRET_WINDOW = 5

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
-- The sync trace: trace(line). App sets it at start and keeps it set (the
-- sync log keeps every line); nil only before that, and in tests.
local trace
local target          -- the Crew's channel and password, from Core
local joining = false
local joined = false
local failed = false
local settled = false
local isUp = false
-- Whether the first member list since joining is in (or LIST_WAIT passed).
local listed = false
local listAsked
-- Bumped on every join and Crew change, so stale timers do nothing.
local generation = 0
local lastChannelUpdate
-- The other Characters in the channel: Ambiguate(name, "none"):lower() ->
-- the name to whisper.
local peers = {}
-- Messages from senders not yet in peers: key -> { messages }.
local strangers = {}
-- Characters whispered after they logged out: key -> GetTime() of the first
-- "No player named ..." for them.
local missed = {}
-- Peers a send to failed: key -> GetTime() of the last failed chunk. And
-- when a "Player is offline." was last put down to one of them, so the
-- chat filter hides it whether it runs before or after the event.
local failedAt = {}
local offlineMatched
-- GetTime() of the last whisper sent, and whether (and which type of)
-- instance the player was last seen in, for the trace.
local lastWhisper
local instanceType
-- Upper-cased names of channels BFF is in or leaving, for the chat filter.
local ours = {}

local function lockdown()
  return C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()
end

local function channelIndex(name)
  local index = GetChannelName(name)
  return index and index > 0 and index or nil
end

-- Chat event arguments can be secret under Midnight restrictions.
local function readable(text)
  return type(text) == "string" and not (issecretvalue and issecretvalue(text))
end

-- Whether a chat event's channel (its base name, arg 9) is the Crew's.
local function isTarget(name)
  return target ~= nil and readable(name) and name:upper() == target.channel:upper()
end

-- A chat event's channel base name: arg 9, or arg 4 ("6. BFF1Z30B0G")
-- without its number, in case arg 9 is empty.
local function baseName(arg4, arg9)
  if readable(arg9) and arg9 ~= "" then return arg9 end
  return readable(arg4) and arg4:gsub("^%d+%.%s*", "") or nil
end

-- Names may be "First Last" on Forever, and "Name-Realm" in chat events.
local function peerKey(name)
  return Ambiguate(name, "none"):lower()
end

-- On Forever UnitName gives a Character's last name second (where retail
-- gives the realm), and the member list and whispers use "First Last".
local function isSelf(name)
  local first, last = UnitName("player")
  if not readable(first) then return false end
  local key = peerKey(name)
  if key == first:lower() then return true end
  return readable(last) and last ~= "" and key == (first .. " " .. last):lower()
end

-- Why the link is down, or nil while it can be up.
local function downReason()
  if not target then return "no Crew" end
  if not joined then return "not in the channel" end
  if not listed then return "waiting for the member list" end
  if lockdown() then return "lockdown" end
  return nil
end

-- Tells Core whenever the link goes up or down. isUp is set first, since
-- Core may react by changing the Crew, which comes back here. cause says
-- what brought it up, for the trace.
local function update(cause)
  local reason = downReason()
  local up = reason == nil
  if up == isUp then return end
  isUp = up
  if trace then trace(up and ("link up (%s)"):format(cause or "ready") or ("link down (%s)"):format(reason)) end
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

-- Asks the game for the channel's member list (CHAT_MSG_CHANNEL_LIST, as
-- /chatlist prints it).
local function askList()
  if not target or not joined or lockdown() then return end
  listAsked = GetTime()
  ListChannelByName(target.channel)
end

local function deliver(key)
  local waiting = strangers[key]
  strangers[key] = nil
  if not waiting then return end
  if trace then trace(("  delivering %d held whispers from %s"):format(#waiting.messages, peers[key])) end
  for _, message in ipairs(waiting.messages) do core:received(message) end
end

-- Returns true if the name is new. why is for the trace.
local function addPeer(name, why)
  if not readable(name) or name == "" or isSelf(name) then return false end
  local key = peerKey(name)
  if peers[key] then return false end
  peers[key] = name
  if trace then trace(("peer added: %s (%s)"):format(name, why)) end
  deliver(key)
  return true
end

local function removePeer(name, why)
  if not readable(name) or name == "" then return end
  local key = peerKey(name)
  if trace and peers[key] then trace(("peer removed: %s (%s)"):format(peers[key], why)) end
  peers[key] = nil
end

local function forgetPeers(why)
  if trace and next(peers) then trace(("peers cleared (%s)"):format(why)) end
  generation = generation + 1
  peers, strangers, missed, failedAt = {}, {}, {}, {}
  listed = false
end

local function onJoined()
  joining = false
  joined = true
  hide(target.channel)
  forgetPeers("joined the channel")
  askList()
  -- No reply (a channel of one may send none): come up anyway.
  local current = generation
  C_Timer.After(LIST_WAIT, function()
    if generation == current and joined and not listed then
      listed = true
      update("no member list after " .. LIST_WAIT .. " s")
    end
  end)
  update("joined the channel")
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

-- A member list BFF asked for, not one from /chatlist.
local function listFilter(_, _, _, _, _, arg4, _, _, _, _, arg9)
  return listAsked ~= nil and GetTime() - listAsked < LIST_HIDE and isOurs(baseName(arg4, arg9))
end

-- A Lua pattern matching a game message format: %s captures, %d matches
-- a number.
local function patternFor(format)
  if not format then return nil end
  local escaped = format:gsub("[%^%$%(%)%.%[%]%*%+%-%?%%]", "%%%0")
  local pattern = escaped:gsub("%%%%([sd])", function(kind)
    return kind == "s" and "(.+)" or "%d+"
  end)
  return "^" .. pattern .. "$"
end

-- "No player named '%s' is currently playing.": a whisper to a Character
-- that logged out before its leave notice arrived.
local notFoundPattern = patternFor(ERR_CHAT_PLAYER_NOT_FOUND_S)

-- The name in a "No player named ..." notice, whoever it is about.
local function notFoundName(text)
  if not notFoundPattern or not readable(text) then return nil end
  return text:match(notFoundPattern)
end

-- The name in a "No player named ..." for a Character BFF whispered.
local function notFound(text)
  local name = notFoundName(text)
  if not name then return nil end
  local key = peerKey(name)
  local since = missed[key]
  if peers[key] or (since and GetTime() - since < NOT_FOUND_HIDE) then return name end
  return nil
end

-- What the game says after a whisper to a Character who is offline,
-- according to the wiki. Which text Forever prints is unverified (see
-- docs/research/addon-message-reliability.md).
local OFFLINE_TEXT = "Player is offline."

local function isOffline(text)
  return readable(text) and text == OFFLINE_TEXT
end

-- The peer a "Player is offline." is about: it names no one, so only the
-- one peer a send failed to just before, or nil if none or several (an
-- account that can't send fails to everyone).
local function offlinePeer()
  local found
  for key, time in pairs(failedAt) do
    if GetTime() - time < OFFLINE_WINDOW and peers[key] then
      if found then return nil end
      found = key
    end
  end
  return found
end

local function systemFilter(_, _, text)
  if notFound(text) ~= nil then return true end
  return isOffline(text) and (offlinePeer() ~= nil
    or (offlineMatched ~= nil and GetTime() - offlineMatched < OFFLINE_WINDOW))
end

-- "You can only be in %d channels at a time."
local tooManyPattern = patternFor(ERR_TOO_MANY_CHAT_CHANNELS)

-- Too many channels, during a join.
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
  if not isTarget((select(8, ...))) then return end
  if kind == "WRONG_PASSWORD" then
    fail("wrongPassword")
  elseif kind == "YOU_LEFT" or kind == "SUSPENDED" then
    if trace then trace("channel notice: " .. kind) end
    joined = false
    update()
  end
end

-- A peer who logged out before their leave notice came: off the peers
-- list, and offline for Core.
local function dropGone(key, why)
  local name = peers[key]
  if not name then return end
  removePeer(name, why)
  core:gone(Ambiguate(name, "none"))
end

-- The peers' keys, sorted, for the trace.
local function peerKeys()
  local keys = {}
  for key in pairs(peers) do keys[#keys + 1] = key end
  table.sort(keys)
  return table.concat(keys, ", ")
end

-- The instance type the player is in ("party", "raid"), or nil outside one.
local function currentInstance()
  local inInstance, kind = IsInInstance()
  if not inInstance then return nil end
  return readable(kind) and kind ~= "" and kind or "unknown"
end

-- A system message the game won't let addons read, shortly after a
-- whisper: when and where, never its text.
local function traceSecret()
  if not lastWhisper or GetTime() - lastWhisper >= SECRET_WINDOW then return end
  trace(("notice: unreadable system message %.1f s after a whisper · in instance: %s · lockdown: %s"):format(
    GetTime() - lastWhisper, currentInstance() or "no", lockdown() and "yes" or "no"))
end

function events.CHAT_MSG_SYSTEM(text)
  if issecretvalue and issecretvalue(text) then
    if trace then traceSecret() end
    return
  end
  onError(text)
  if isOffline(text) then
    local key = offlinePeer()
    if trace then trace(("notice: %s (%s)"):format(OFFLINE_TEXT, key and peers[key] or "not ours, or not clear whose")) end
    if key then
      offlineMatched = GetTime()
      dropGone(key, OFFLINE_TEXT)
    end
    return
  end
  -- Logged out, and the leave notice hasn't come (or won't).
  local name = notFound(text)
  local key = name and peerKey(name)
  if trace and name then
    trace(("notice: No player named %s%s"):format(name, key and peers[key] and "" or " (already gone)"))
  elseif trace then
    local unmatched = notFoundName(text)
    if unmatched then
      trace(("notice: No player named %s · not a peer (peers: %s)"):format(unmatched, peerKeys()))
    end
  end
  if key and peers[key] then
    missed[key] = GetTime()
    dropGone(key, "No player named")
  end
end

-- The member list: "*Owner, @Moderator, First Last, Name-Realm". Long
-- lists may come in several parts, so it only ever adds. The first one
-- since joining brings the link up; a Character found later while up
-- makes the link go down and straight back up, so Core sends them a fresh
-- DIGEST.
function events.CHAT_MSG_CHANNEL_LIST(text, _, _, arg4, _, _, _, _, arg9)
  if not joined or not isTarget(baseName(arg4, arg9)) or not readable(text) then return end
  local found = false
  for entry in text:gmatch("[^,]+") do
    local name = entry:gsub("^%s*[%*@%+]*", ""):gsub("%s+$", "")
    if addPeer(name, "member list") then found = true end
  end
  if not listed then
    listed = true
    update("member list")
  elseif found and isUp then
    -- Straight to Core, leaving isUp as it is: the link itself never went
    -- down. Neither call changes the Crew, so nothing comes back here.
    if trace then trace("link down and up (new in member list)") end
    core:down()
    core:up()
  end
end

function events.CHAT_MSG_CHANNEL_JOIN(_, sender, ...)
  if joined and isTarget((select(7, ...))) then addPeer(sender, "joined the channel") end
end

function events.UI_ERROR_MESSAGE(_, text)
  onError(text)
end

-- Someone left the Crew channel, i.e. logged out: a real logout leaves it
-- before any goodbye could be sent.
function events.CHAT_MSG_CHANNEL_LEAVE(_, sender, ...)
  if not isTarget((select(7, ...))) or not readable(sender) then return end
  removePeer(sender, "left the channel")
  core:gone(Ambiguate(sender, "none"))
end

-- Entering or leaving an instance, for the trace's timeline around a
-- dungeon. Every loading screen fires this, so it only notes a change.
function events.PLAYER_ENTERING_WORLD()
  local now = currentInstance()
  if now == instanceType then return end
  if trace then
    trace(now and ("entered an instance (%s)"):format(now) or ("left an instance (%s)"):format(instanceType))
  end
  instanceType = now
end

-- The player left the group, or it disbanded (#160 happens after one).
function events.GROUP_LEFT()
  if trace then trace("left the group, or it disbanded") end
end

-- Whoever joined or left during lockdown: ask again once it lifts.
function events.ADDON_RESTRICTION_STATE_CHANGED(kind, state)
  if trace then trace(("chat restriction: type %s, state %s"):format(tostring(kind), tostring(state))) end
  update("chat restriction changed")
  tryJoin()
  askList()
end

-- A send to one peer failed (a general error, a logout, lockdown, or an
-- account that can't send addon messages): only they may have missed it,
-- so the link stays up and Core sends them a DIGEST of their own soon.
local function onFailed(name)
  if peers[peerKey(name)] then core:sendFailed(Ambiguate(name, "none")) end
end

-- AceComm's callback, once per chunk, with the name whispered to, the
-- bytes sent so far and in all. Through AceComm, ChatThrottleLib's didSend
-- arrives fourth: false for any failure but a throttle, which
-- ChatThrottleLib queues again itself, so that one never gets here.
-- Handled on the next frame, since it can run inside Core's own send.
local function onSent(name, sent, total, didSend)
  if trace then
    trace(("  chunk to %s: %s/%s B %s"):format(tostring(name), tostring(sent), tostring(total),
      didSend == false and "failed" or "sent"))
  end
  if didSend == false then
    failedAt[peerKey(name)] = GetTime()
    C_Timer.After(0, function() onFailed(name) end)
  end
end

-- A message only counts from someone in the Crew channel: over the channel
-- itself (password-protected), or whispered by a Character in it. Any other
-- way (party, guild) it is dropped. A whisper from someone not known to be
-- in the channel yet, usually a Character who just joined, waits for a
-- member list that shows them.
local function onComm(_, message, distribution, sender)
  if trace then trace(("%s from %s · %d B"):format(distribution, tostring(sender), #message)) end
  if distribution == "CHANNEL" then
    core:received(message)
    return
  end
  if distribution ~= "WHISPER" or not target or not readable(sender) or isSelf(sender) then return end
  local key = peerKey(sender)
  if peers[key] then
    core:received(message)
    return
  end
  local waiting = strangers[key]
  if not waiting then
    waiting = { messages = {} }
    strangers[key] = waiting
    if trace then trace(("holding whispers from %s: not in the member list yet"):format(sender)) end
    local current = generation
    C_Timer.After(STRANGER_WAIT, function()
      if generation == current and strangers[key] == waiting then
        strangers[key] = nil
        if trace then
          trace(("dropped %d whispers from %s: not in the member list after %d s"):format(
            #waiting.messages, sender, STRANGER_WAIT))
        end
      end
    end)
    askList()
  end
  if #waiting.messages < STRANGER_MAX then
    waiting.messages[#waiting.messages + 1] = message
  elseif trace then
    trace(("dropped a whisper from %s: %d already held"):format(sender, STRANGER_MAX))
  end
end

-- Starts the link. core gets up(), down(), gone(name) and received(message); notice
-- gets "tooManyChannels" or "wrongPassword" when the channel can't be joined.
function ChannelLink.start(theCore, notice)
  core = theCore
  onNotice = notice

  ChannelLink:RegisterComm(PREFIX, onComm)
  -- App starts the link on the first PLAYER_ENTERING_WORLD, which this
  -- frame is too late for.
  instanceType = currentInstance()

  local addFilter = ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter or ChatFrame_AddMessageEventFilter
  for _, event in ipairs(FILTERED_EVENTS) do addFilter(event, filter) end
  addFilter("CHAT_MSG_CHANNEL_LIST", listFilter)
  addFilter("CHAT_MSG_SYSTEM", systemFilter)

  local frame = CreateFrame("Frame")
  for event in pairs(events) do frame:RegisterEvent(event) end
  frame:SetScript("OnEvent", function(_, event, ...) events[event](...) end)
  C_Timer.After(SETTLE_FALLBACK, settle)
  C_Timer.NewTicker(LIST_REFRESH, askList)
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
  forgetPeers("Crew changed")
  failed = false
  if name then ours[name:upper()] = true end
  update()
  tryJoin()
end

-- How many chunks AceComm splits a message into: one up to 255 bytes,
-- else 254 bytes each (one goes to the part marker).
local function chunks(size)
  if size <= 255 then return 1 end
  return math.ceil(size / 254)
end

-- Sets the sync trace: trace(line), lines without a timestamp, or nil for
-- none.
function ChannelLink.setTrace(fn)
  trace = fn
end

-- For /bff report: whether the link is up, why not if it isn't, how many
-- other Characters are in the channel, the instance type the player is in
-- (nil outside one) and whether chat messaging lockdown is on.
function ChannelLink.state()
  local count = 0
  for _ in pairs(peers) do count = count + 1 end
  return {
    up = isUp, reason = not isUp and downReason() or nil, peers = count,
    instance = currentInstance(), lockdown = lockdown() and true or false,
  }
end

local function whisper(name, message)
  -- A one-chunk message (every DIGEST) can jump the queue: it bypasses
  -- AceComm's reassembly. Longer ones all keep one priority, so chunks of
  -- two messages to the same peer never interleave.
  local priority = chunks(#message) == 1 and "ALERT" or "NORMAL"
  if trace then trace(("  to %s · %d B · %d chunks"):format(name, #message, chunks(#message))) end
  lastWhisper = GetTime()
  ChannelLink:SendCommMessage(PREFIX, message, "WHISPER", name, priority, onSent, name)
end

-- Best-effort: dropped while the link is down, and reaches only the
-- Characters known to be in the channel: all of them, or only the one
-- named `to`. ChannelLink.onSend, if set, also gets every message sent
-- (for /bff sim).
function ChannelLink.send(message, to)
  if not isUp then
    if trace then trace(("  not sent: link down (%s)"):format(downReason())) end
    return
  end
  if ChannelLink.onSend then ChannelLink.onSend(message, to) end
  if to then
    local name = peers[peerKey(to)]
    if name then
      whisper(name, message)
    elseif trace then
      trace(("  not sent: %s is not in the channel"):format(to))
    end
    return
  end
  if trace and not next(peers) then trace("  not sent: no one else in the channel") end
  for _, name in pairs(peers) do whisper(name, message) end
end
