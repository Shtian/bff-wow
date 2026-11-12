-- Channel link: the production link adapter. Joins the Crew's hidden
-- channel, keeps it and its system notices out of chat, and tells Core when
-- the link is up or down. The channel only says who is online: on WoW:
-- Forever addon messages sent to a custom channel are accepted and never
-- delivered, so every message goes out as addon whispers to each other
-- Character in the channel: in BFF's own chunks (Link/Framing.lua), handed
-- to ChatThrottleLib a chunk at a time. AceComm only receives: it registers
-- the prefix and still puts an older BFF's multipart messages together.
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
-- The channel's member list: how often to ask again, and how long a reply
-- we asked for stays out of chat.
local LIST_REFRESH = 60
local LIST_HIDE = 5

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
local listAsked
local lastChannelUpdate
-- Who is in the channel and can be whispered (Link/Presence.lua). Made
-- below, once what it calls is defined.
local presence
-- Splits messages into chunks and puts the chunks received back together,
-- per sender's peer key. Made below, like presence.
local framing
-- What is still to send, per peer: key -> { name, flying (chunks handed to
-- ChatThrottleLib and not yet out), busy (the long message one of them
-- belongs to, or false), messages (each { chunks, next }, the multi-chunk messages
-- in order) }. ChatThrottleLib gets one chunk of these at a time, so the
-- rest can be dropped when the peer leaves or the link goes down.
local outbox = {}
-- Whether (and which type of) instance the player was last seen in, for
-- the trace.
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

-- A chat event argument for the trace, without reading a secret one.
local function shown(value)
  if issecretvalue and issecretvalue(value) then return "secret" end
  if type(value) == "string" then return ('"%s"'):format(value) end
  return tostring(value)
end

-- Every join and leave notice, ours or not, with the arguments that say
-- which channel it is (#162: whether Forever sends them for the Crew's
-- channel, and how).
local function traceNotice(kind, sender, arg4, arg8, arg9, isCrew)
  if not trace then return end
  local who = readable(sender) and sender or shown(sender)
  trace(("channel %s: %s · arg 4 %s · arg 8 %s · arg 9 %s (%s)"):format(
    kind, who, shown(arg4), shown(arg8), shown(arg9), isCrew and "Crew channel" or "other channel"))
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

-- Drops the chunks not yet handed to ChatThrottleLib for a peer. One
-- already there can't be taken back.
local function dropUnsent(key, why)
  local box = outbox[key]
  if not box then return end
  local unsent = 0
  for _, message in ipairs(box.messages) do unsent = unsent + #message.chunks - message.next + 1 end
  -- The first message's next chunk is the one already handed over.
  if box.busy and box.busy == box.messages[1] then unsent = unsent - 1 end
  box.messages = {}
  if box.flying == 0 then outbox[key] = nil end
  if trace and unsent > 0 then trace(("  dropped %d unsent chunks to %s (%s)"):format(unsent, box.name, why)) end
end

-- Why the link is down, or nil while it can be up.
local function downReason()
  if not target then return "no Crew" end
  if not joined then return "not in the channel" end
  if not presence:ready() then return "waiting for the member list" end
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
  presence:listening(up)
  if trace then trace(up and ("link up (%s)"):format(cause or "ready") or ("link down (%s)"):format(reason)) end
  -- Nothing gets through while it is down, and Core starts over with a
  -- DIGEST when it comes up: half-sent and half-received messages go.
  if not up then
    for key in pairs(outbox) do dropUnsent(key, "link down") end
    framing:clear()
  end
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

local function onJoined()
  joining = false
  joined = true
  hide(target.channel)
  presence:start()
  askList()
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

-- What the game says after a whisper to a Character who is offline,
-- according to the wiki. Which text Forever prints is unverified (see
-- docs/research/addon-message-reliability.md).
local OFFLINE_TEXT = "Player is offline."

local function isOffline(text)
  return readable(text) and text == OFFLINE_TEXT
end

-- Hides the notices about a Character BFF whispered. Presence says whether
-- one is ours; nothing is remembered here.
local function systemFilter(_, _, text)
  local name = notFoundName(text)
  if name then return presence:hidesNotFound(name) end
  return isOffline(text) and presence:hidesOffline()
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

-- The instance type the player is in ("party", "raid"), or nil outside one.
local function currentInstance()
  local inInstance, kind = IsInInstance()
  if not inInstance then return nil end
  return readable(kind) and kind ~= "" and kind or "unknown"
end

-- A system message the game won't let addons read, shortly after a
-- whisper: when and where, never its text.
local function traceSecret(since)
  trace(("notice: unreadable system message %.1f s after a whisper · in instance: %s · lockdown: %s"):format(
    since, currentInstance() or "no", lockdown() and "yes" or "no"))
end

function events.CHAT_MSG_SYSTEM(text)
  if issecretvalue and issecretvalue(text) then
    local since = presence:unreadable()
    if trace and since then traceSecret(since) end
    return
  end
  onError(text)
  if isOffline(text) then
    presence:offline()
    return
  end
  local name = notFoundName(text)
  if name then presence:notFound(name) end
end

-- The member list: "*Owner, @Moderator, First Last, Name-Realm".
function events.CHAT_MSG_CHANNEL_LIST(text, _, _, arg4, _, _, _, _, arg9)
  if not joined or not isTarget(baseName(arg4, arg9)) or not readable(text) then return end
  local names = {}
  for entry in text:gmatch("[^,]+") do
    local name = entry:gsub("^%s*[%*@%+]*", ""):gsub("%s+$", "")
    if not isSelf(name) then names[#names + 1] = name end
  end
  presence:listed(names)
end

function events.CHAT_MSG_CHANNEL_JOIN(_, sender, _, arg4, _, _, _, arg8, arg9)
  local isCrew = isTarget(arg9)
  traceNotice("join", sender, arg4, arg8, arg9, isCrew)
  if joined and isCrew and readable(sender) and not isSelf(sender) then presence:joined(sender) end
end

function events.UI_ERROR_MESSAGE(_, text)
  onError(text)
end

-- Someone left the Crew channel, i.e. logged out: a real logout leaves it
-- before any goodbye could be sent.
function events.CHAT_MSG_CHANNEL_LEAVE(_, sender, _, arg4, _, _, _, arg8, arg9)
  local isCrew = isTarget(arg9)
  traceNotice("leave", sender, arg4, arg8, arg9, isCrew)
  if not isCrew or not readable(sender) then return end
  presence:left(sender)
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
  if presence:has(name) then core:sendFailed(Ambiguate(name, "none")) end
end

-- Whether anything for a peer is still to go out.
local function isQueued(key)
  return outbox[key] ~= nil
end

local pump

-- ChatThrottleLib's callback, once per chunk handed to it: whether it went
-- out, and the game's result code (Enum.SendAddonMessageResult). A
-- throttle never gets here: ChatThrottleLib queues that chunk again itself.
-- A failure is handled on the next frame, since this can run inside Core's
-- own send.
local function onSent(flight, didSend, result)
  local key, name, message = flight.key, flight.name, flight.message
  local refused = didSend == false
  if trace then
    trace(("  chunk %d/%d to %s · %d B · %s"):format(flight.index, #message.chunks, name, #message.chunks[flight.index],
      refused and ("failed (result %s)"):format(tostring(result)) or "sent"))
  end
  local box = outbox[key]
  box.flying = box.flying - 1
  if #message.chunks > 1 then
    box.busy = false
    -- Still the first message, unless the peer left meanwhile.
    if box.messages[1] == message then
      message.next = flight.index + 1
      -- The rest of a message is no use without the chunk that failed.
      if refused and message.next <= #message.chunks then
        if trace then
          trace(("  dropped %d unsent chunks to %s (a chunk failed)"):format(#message.chunks - flight.index, name))
        end
        message.next = #message.chunks + 1
      end
      if message.next > #message.chunks then table.remove(box.messages, 1) end
    end
  end
  if box.flying == 0 and #box.messages == 0 then outbox[key] = nil end
  presence:chunk(name, isQueued(key), refused)
  if refused then C_Timer.After(0, function() onFailed(name) end) end
  pump(key)
end

local function sendChunk(box, key, message, index, priority)
  box.flying = box.flying + 1
  -- A queue per peer, so ChatThrottleLib takes turns between them.
  ChatThrottleLib:SendAddonMessage(priority, PREFIX, message.chunks[index], "WHISPER", box.name, PREFIX .. key,
    onSent, { key = key, name = box.name, message = message, index = index })
end

-- Hands ChatThrottleLib the next chunk of a peer's first multi-chunk
-- message, unless one is still there.
function pump(key)
  local box = outbox[key]
  if not box or box.busy or #box.messages == 0 then return end
  local message = box.messages[1]
  box.busy = message
  sendChunk(box, key, message, message.next, "NORMAL")
end

-- A whisper from a peer (Presence held it if they weren't one yet): one of
-- BFF's chunks, delivered once its message is whole, or a whole protocol 1
-- message, which AceComm put together. Core hears who whispered it, so
-- it can reply to them alone.
local function onWhisper(text, name)
  if not ns.Framing.isChunk(text) then
    core:received(text, Ambiguate(name, "none"))
    return
  end
  local message, chunks = framing:receive(peerKey(name), text)
  if not message then return end
  if trace and chunks > 1 then
    trace(("  message from %s whole · %d B · %d chunks"):format(name, #message, chunks))
  end
  core:received(message, Ambiguate(name, "none"))
end

-- A message only counts from someone in the Crew channel: over the channel
-- itself (password-protected), or whispered by a Character in it. Any other
-- way (party, guild) it is dropped. Presence holds a whisper from someone
-- not known to be in the channel yet.
local function onComm(_, message, distribution, sender)
  if trace then trace(("%s from %s · %d B"):format(distribution, tostring(sender), #message)) end
  if distribution == "CHANNEL" then
    if readable(sender) then onWhisper(message, sender) end
    return
  end
  if distribution ~= "WHISPER" or not target or not readable(sender) or isSelf(sender) then return end
  presence:heard(sender, message)
end

presence = ns.Presence.new({
  now = GetTime,
  key = peerKey,
  trace = function(line) if trace then trace(line) end end,
  deliver = onWhisper,
  ready = update,
  -- A Character found in the channel while the link is up: Core hears down
  -- and straight back up, so it sends them a fresh DIGEST. isUp stays as
  -- it is, since the link itself never went down, and neither call changes
  -- the Crew, so nothing comes back here.
  arrived = function()
    if not isUp then return end
    if trace then trace("link down and up (new in member list)") end
    core:down()
    core:up()
  end,
  gone = function(name)
    dropUnsent(peerKey(name), "gone")
    framing:forget(peerKey(name))
    core:gone(Ambiguate(name, "none"))
  end,
  askList = askList,
})

framing = ns.Framing.new({
  now = GetTime,
  random = math.random,
  -- A message from a peer stayed incomplete: Core asks them again, as
  -- after a failed send to them.
  lost = function(key, got, total)
    local name = presence:peer(key) or key
    if trace then
      trace(("message from %s lost: %d of %d chunks after %d s"):format(name, got, total, ns.Framing.LOST_AFTER))
    end
    onFailed(name)
  end,
})

-- Starts the link. core gets up(), down(), gone(name) and received(message, from); notice
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
  C_Timer.NewTicker(1, function()
    presence:tick()
    framing:tick()
  end)
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
  presence:stop()
  failed = false
  if name then ours[name:upper()] = true end
  update()
  tryJoin()
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
  return {
    up = isUp, reason = not isUp and downReason() or nil, peers = presence:count(),
    instance = currentInstance(), lockdown = lockdown() and true or false,
  }
end

-- Queues a message's chunks for a peer. A one-chunk message (every DIGEST)
-- jumps the queue: it goes to ChatThrottleLib at once, at ALERT. A longer
-- one waits its turn behind the peer's other long ones, a chunk at a time.
local function whisper(name, chunks, size)
  if trace then trace(("  to %s · %d B · %d chunks"):format(name, size, #chunks)) end
  local key = peerKey(name)
  local box = outbox[key]
  if not box then
    box = { name = name, flying = 0, busy = false, messages = {} }
    outbox[key] = box
  end
  presence:whispered(name)
  local message = { chunks = chunks, next = 1 }
  if #chunks == 1 then
    sendChunk(box, key, message, 1, "ALERT")
  else
    box.messages[#box.messages + 1] = message
    pump(key)
  end
end

-- Best-effort: dropped while the link is down, and reaches only the
-- Characters known to be in the channel and not silent (Presence): all of
-- them, or only the one named `to`. ChannelLink.onSend, if set, also gets every message sent
-- (for /bff sim).
function ChannelLink.send(message, to)
  if not isUp then
    if trace then trace(("  not sent: link down (%s)"):format(downReason())) end
    return
  end
  if ChannelLink.onSend then ChannelLink.onSend(message, to) end
  local names = presence:targets(to)
  if trace and #names == 0 then
    if to then
      trace(("  not sent: %s is %s"):format(to, presence:has(to) and "silent" or "not in the channel"))
    else
      trace(presence:count() > 0 and "  not sent: everyone in the channel is silent"
        or "  not sent: no one else in the channel")
    end
  end
  if #names == 0 then return end
  local chunks = framing:split(message)
  for _, name in ipairs(names) do whisper(name, chunks, #message) end
end
