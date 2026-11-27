-- WoW: Forever accepts addon messages sent to a custom channel and never
-- delivers them, so the channel only says who is online.

local _, ns = ...

local ChannelLink = {}
ns.ChannelLink = ChannelLink
LibStub("AceComm-3.0"):Embed(ChannelLink)

local PREFIX = "BFF"
-- WoW: the channel list keeps changing for a while after login.
local SETTLE_QUIET = 2
local SETTLE_FALLBACK = 10
local JOIN_POLL = 0.5
local JOIN_TIMEOUT = 10
local LEAVE_DELAY = 3
local LEAVE_MAX = 15
local LIST_REFRESH = 60
local LIST_HIDE = 5
-- WoW: ADDON_RESTRICTION_STATE_CHANGED fires as a restriction is activating,
-- before it is active, and again once it is inactive.
local RESTRICTION_INACTIVE = 0
local RESTRICTION_ACTIVATING = 1

local FILTERED_EVENTS = {
  "CHAT_MSG_CHANNEL",
  "CHAT_MSG_CHANNEL_NOTICE",
  "CHAT_MSG_CHANNEL_NOTICE_USER",
  "CHAT_MSG_CHANNEL_JOIN",
  "CHAT_MSG_CHANNEL_LEAVE",
}

local core
local trace
local target
local joining = false
local joined = false
local failure
local settled = false
local afterLogin = false
local isUp = false
local listAsked
-- WoW: a member list asked for while a restriction is activating comes back
-- with its names secret and is printed in chat.
local restrictionStarting
local listsTraced = {}
local lastChannelUpdate
local presence
local framing
local strangerFraming
local outbox = {}
local instanceType
local ours = {}

local function lockdown()
  return C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()
end

local function channelIndex(name)
  local index = GetChannelName(name)
  return index and index > 0 and index or nil
end

-- WoW: chat event arguments can be secret under Midnight restrictions.
local function readable(text)
  return type(text) == "string" and not (issecretvalue and issecretvalue(text))
end

local function isTarget(name)
  return target ~= nil and readable(name) and name:upper() == target.channel:upper()
end

-- WoW: a chat event's arg 9 can be empty; arg 4 is the numbered name ("6. BFF1Z30B0G").
local function baseName(arg4, arg9)
  if readable(arg9) and arg9 ~= "" then return arg9 end
  return readable(arg4) and arg4:gsub("^%d+%.%s*", "") or nil
end

local function shown(value)
  if issecretvalue and issecretvalue(value) then return "secret" end
  if type(value) == "string" then return ('"%s"'):format(value) end
  return tostring(value)
end

local function channelArgs(arg4, arg8, arg9)
  return ("arg 4 %s · arg 8 %s · arg 9 %s"):format(shown(arg4), shown(arg8), shown(arg9))
end

local function traceNotice(kind, sender, arg4, arg8, arg9, isCrew)
  if not trace then return end
  local who = readable(sender) and sender or shown(sender)
  trace(("channel %s: %s · %s (%s)"):format(
    kind, who, channelArgs(arg4, arg8, arg9), isCrew and "Crew channel" or "other channel"))
end

-- WoW: names may be "First Last" on Forever, and "Name-Realm" in chat events.
local function peerKey(name)
  return Ambiguate(name, "none"):lower()
end

-- WoW: on Forever UnitName returns a Character's last name second (retail returns
-- the realm), and the member list and whispers use "First Last".
local function isSelf(name)
  local first, last = UnitName("player")
  if not readable(first) then return false end
  local key = peerKey(name)
  if key == first:lower() then return true end
  return readable(last) and last ~= "" and key == (first .. " " .. last):lower()
end

-- WoW: a chunk already handed to ChatThrottleLib can't be taken back.
local function dropUnsent(key, why)
  local box = outbox[key]
  if not box then return end
  local unsent = 0
  for _, message in ipairs(box.messages) do unsent = unsent + #message.chunks - message.next + 1 end
  if box.busy and box.busy == box.messages[1] then unsent = unsent - 1 end
  box.messages = {}
  if box.flying == 0 then outbox[key] = nil end
  if trace and unsent > 0 then trace(("  dropped %d unsent chunks to %s (%s)"):format(unsent, box.name, why)) end
end

local FAILURE_REASONS = {
  wrongPassword = "wrong password",
  tooManyChannels = "too many channels",
  brokenChannel = "the game broke the channel",
}
ChannelLink.FAILURE_REASONS = FAILURE_REASONS

local function downReason()
  if not target then return "no Crew" end
  if failure then return FAILURE_REASONS[failure] end
  if not joined then return "not in the channel" end
  if not presence:ready() then return "waiting for the member list" end
  if lockdown() then return "lockdown" end
  return nil
end

local function update(cause)
  local reason = downReason()
  local up = reason == nil
  if up == isUp then return end
  isUp = up
  presence:listening(up)
  if trace then trace(up and ("link up (%s)"):format(cause or "ready") or ("link down (%s)"):format(reason)) end
  if not up then
    for key in pairs(outbox) do dropUnsent(key, "link down") end
    framing:clear()
    strangerFraming:clear()
  end
  if up then core:up() else core:down() end
end

local function noticeLockdown()
  if isUp and lockdown() then update() end
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

-- WoW: the reply arrives as CHAT_MSG_CHANNEL_LIST, the same as /chatlist prints.
local function askList()
  if not target or not joined or lockdown() or restrictionStarting then return end
  listAsked = GetTime()
  ListChannelByName(target.channel)
end

local function onJoined(how, listed)
  if trace then trace(how) end
  joining = false
  joined = true
  listsTraced = {}
  hide(target.channel)
  presence:start()
  if not listed then askList() end
  update("joined the channel")
end

local function fail(kind, outcome)
  if trace then trace("join failed: " .. (outcome or FAILURE_REASONS[kind])) end
  joining = false
  failure = kind
  update()
  core:joinFailed(kind)
end

-- WoW: the client hands out a channel number even when the server refused
-- the join, so only YOU_CHANGED or the member list says BFF got in.
local function awaitConfirmation(name)
  local waited, numbered = 0, false
  C_Timer.NewTicker(JOIN_POLL, function(ticker)
    waited = waited + JOIN_POLL
    if not joining or not target or target.channel ~= name then
      ticker:Cancel()
    elseif not numbered and channelIndex(name) then
      numbered = true
      if trace then trace("got a channel number, waiting for the game to confirm the join") end
      listAsked = GetTime()
      ListChannelByName(name)
    elseif waited >= JOIN_TIMEOUT then
      ticker:Cancel()
      if not numbered then
        fail("tooManyChannels", ("timed out after %d s"):format(JOIN_TIMEOUT))
      elseif trace then
        trace(("join not confirmed after %d s"):format(JOIN_TIMEOUT))
      end
    end
  end)
end

local function tryJoin()
  if not target or joined or joining or failure or lockdown() then return end
  if not target.asked and not afterLogin and channelIndex(target.channel) then
    -- WoW: channel membership survives a /reload. A channel number at login
    -- isn't proof the server let BFF back in.
    onJoined("already in the Crew channel")
    return
  end
  if not settled then return end

  joining = true
  target.asked = true
  if trace then trace("joining the Crew channel") end
  JoinTemporaryChannel(target.channel, target.password)
  awaitConfirmation(target.channel)
end

local function broken()
  if trace then trace("the game broke the Crew channel") end
  joining = false
  joined = false
  failure = "brokenChannel"
  update()
  core:channelBroken()
end

local function leave(name)
  local waited = 0
  C_Timer.NewTicker(1, function(ticker)
    waited = waited + 1
    if target and target.channel == name then
      ticker:Cancel()
    elseif waited >= LEAVE_DELAY and not lockdown()
        and (not ChatThrottleLib.bQueueing or waited >= LEAVE_MAX) then
      ticker:Cancel()
      LeaveChannelByName(name)
    end
  end)
end

local CREW_CHANNEL = "^BFF" .. ("[0-9A-Z]"):rep(7) .. "$"

-- WoW: a /reload drops Lua state, so a leave still waiting is forgotten.
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

local function listFilter(_, _, _, _, _, arg4, _, _, _, _, arg9)
  return listAsked ~= nil and GetTime() - listAsked < LIST_HIDE and isOurs(baseName(arg4, arg9))
end

local function patternFor(format)
  if not format then return nil end
  local escaped = format:gsub("[%^%$%(%)%.%[%]%*%+%-%?%%]", "%%%0")
  local pattern = escaped:gsub("%%%%([sd])", function(kind)
    return kind == "s" and "(.+)" or "%d+"
  end)
  return "^" .. pattern .. "$"
end

-- WoW: after a whisper to a Character who logged out, the game prints
-- "No player named '%s' is currently playing."
local notFoundPattern = patternFor(ERR_CHAT_PLAYER_NOT_FOUND_S)

local function notFoundName(text)
  if not notFoundPattern or not readable(text) then return nil end
  return text:match(notFoundPattern)
end

-- WoW: the wiki gives this text for a whisper to an offline Character; which text
-- Forever prints is unverified.
local OFFLINE_TEXT = "Player is offline."

local function isOffline(text)
  return readable(text) and text == OFFLINE_TEXT
end

local function systemFilter(_, _, text)
  local name = notFoundName(text)
  if name then return presence:hidesNotFound(name) end
  return isOffline(text) and presence:hidesOffline()
end

local tooManyPattern = patternFor(ERR_TOO_MANY_CHAT_CHANNELS)

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

-- WoW: a channel notice carries its kind, then arg 2 and arg 5 names (who
-- did it or who it is about, which differs by kind), arg 4 channel name,
-- arg 8 channel index and arg 9 base name.
local function traceChannelNotice(kind, arg2, arg4, arg5, arg8, arg9)
  if not trace then return end
  trace(("channel notice %s: arg 2 %s · arg 5 %s · %s"):format(
    readable(kind) and kind or shown(kind), shown(arg2), shown(arg5), channelArgs(arg4, arg8, arg9)))
end

function events.CHAT_MSG_CHANNEL_NOTICE(kind, arg2, _, arg4, arg5, _, _, arg8, arg9)
  if not isTarget(baseName(arg4, arg9)) then return end
  traceChannelNotice(kind, arg2, arg4, arg5, arg8, arg9)
  if not readable(kind) then return end
  if kind == "WRONG_PASSWORD" then
    if not joined then fail("wrongPassword") end
  elseif kind == "INVALID_NAME" then
    if not failure then broken() end
  elseif kind == "YOU_CHANGED" then
    if not joined and not failure then onJoined("joined the Crew channel") end
  elseif kind == "YOU_LEFT" or kind == "SUSPENDED" then
    joined = false
    update()
  end
end

function events.CHAT_MSG_CHANNEL_NOTICE_USER(kind, arg2, _, arg4, arg5, _, _, arg8, arg9)
  if isTarget(arg9) then traceChannelNotice(kind, arg2, arg4, arg5, arg8, arg9) end
end

local function currentInstance()
  local inInstance, kind = IsInInstance()
  if not inInstance then return nil end
  return readable(kind) and kind ~= "" and kind or "unknown"
end

-- WoW: some system messages after a whisper are secret to addons.
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

local function traceList(text, where, verdict)
  local key = where .. " (" .. verdict .. ")"
  if not trace or listsTraced[key] then return end
  listsTraced[key] = true
  local names = "text unreadable"
  if readable(text) then
    local count = select(2, text:gsub("[^,]+", ""))
    names = count == 1 and "1 name" or ("%d names"):format(count)
  end
  trace(("member list: %s · %s"):format(names, key))
end

-- WoW: a member list reads "*Owner, @Moderator, First Last, Name-Realm".
function events.CHAT_MSG_CHANNEL_LIST(text, _, _, arg4, _, _, _, arg8, arg9)
  local where = channelArgs(arg4, arg8, arg9)
  local isCrew = isTarget(baseName(arg4, arg9))
  if not joined and not (joining and isCrew) then
    traceList(text, where, "ignored: not in the Crew channel yet")
    return
  elseif not isCrew then
    traceList(text, where, "other channel")
    return
  end
  if not joined then onJoined("joined the Crew channel (member list)", true) end
  if not readable(text) then
    traceList(text, where, "Crew channel, ignored: text unreadable")
    return
  end
  traceList(text, where, "Crew channel")
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

-- WoW: a logout leaves the channel before any goodbye could be sent.
function events.CHAT_MSG_CHANNEL_LEAVE(_, sender, _, arg4, _, _, _, arg8, arg9)
  local isCrew = isTarget(arg9)
  traceNotice("leave", sender, arg4, arg8, arg9, isCrew)
  if not isCrew or not readable(sender) then return end
  presence:left(sender)
end

-- WoW: every loading screen fires PLAYER_ENTERING_WORLD.
function events.PLAYER_ENTERING_WORLD()
  local now = currentInstance()
  if now == instanceType then return end
  if trace then
    trace(now and ("entered an instance (%s)"):format(now) or ("left an instance (%s)"):format(instanceType))
  end
  instanceType = now
end

function events.GROUP_LEFT()
  if trace then trace("left the group, or it disbanded") end
end

-- WoW: while a restriction is activating, InChatMessagingLockdown() doesn't
-- report it yet, and no event fires once it does.
function events.ADDON_RESTRICTION_STATE_CHANGED(kind, state)
  if trace then trace(("chat restriction: type %s, state %s"):format(tostring(kind), tostring(state))) end
  if state == RESTRICTION_ACTIVATING then
    local stamp = {}
    restrictionStarting = stamp
    C_Timer.After(0, function()
      if restrictionStarting == stamp then restrictionStarting = nil end
      noticeLockdown()
    end)
  end
  update("chat restriction changed")
  tryJoin()
  if state == RESTRICTION_INACTIVE then askList() end
end

local function onFailed(name)
  if presence:has(name) then core:sendFailed(Ambiguate(name, "none")) end
end

local function isQueued(key)
  return outbox[key] ~= nil
end

local pump

-- WoW: ChatThrottleLib calls back once per chunk, possibly inside its own send,
-- and never for a throttled chunk, which it queues again itself.
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
    if box.messages[1] == message then
      message.next = flight.index + 1
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
  -- WoW: ChatThrottleLib takes turns between queue names.
  ChatThrottleLib:SendAddonMessage(priority, PREFIX, message.chunks[index], "WHISPER", box.name, PREFIX .. key,
    onSent, { key = key, name = box.name, message = message, index = index })
end

function pump(key)
  local box = outbox[key]
  if not box or box.busy or #box.messages == 0 then return end
  local message = box.messages[1]
  box.busy = message
  sendChunk(box, key, message, message.next, "NORMAL")
end

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

local function vouchIfKnown(name, text)
  local message = text
  if ns.Framing.isChunk(text) then
    message = strangerFraming:receive(peerKey(name), text)
    if not message then return end
  end
  if core:fromKnownMember(message) then
    strangerFraming:forget(peerKey(name))
    presence:vouched(name)
  end
end

local function onComm(_, message, distribution, sender)
  if trace then trace(("%s from %s · %d B"):format(distribution, tostring(sender), #message)) end
  if distribution == "CHANNEL" then
    if readable(sender) then onWhisper(message, sender) end
    return
  end
  if distribution ~= "WHISPER" or not target or not readable(sender) or isSelf(sender) then return end
  presence:heard(sender, message)
  if presence:holds(sender) then vouchIfKnown(sender, message) end
end

presence = ns.Presence.new({
  now = GetTime,
  key = peerKey,
  trace = function(line) if trace then trace(line) end end,
  deliver = onWhisper,
  ready = update,
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
  lost = function(key, got, total)
    local name = presence:peer(key) or key
    if trace then
      trace(("message from %s lost: %d of %d chunks after %d s"):format(name, got, total, ns.Framing.LOST_AFTER))
    end
    onFailed(name)
  end,
})

strangerFraming = ns.Framing.new({ now = GetTime })

function ChannelLink.start(theCore, isInitialLogin)
  core = theCore
  afterLogin = isInitialLogin == true

  ChannelLink:RegisterComm(PREFIX, onComm)
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
    noticeLockdown()
    presence:tick()
    framing:tick()
    strangerFraming:tick()
  end)
end

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
  failure = nil
  if name then ours[name:upper()] = true end
  update()
  tryJoin()
end

function ChannelLink.inChannel(name)
  return presence:has(name)
end

function ChannelLink.setTrace(fn)
  trace = fn
end

local function sendable()
  return isUp and not lockdown()
end

function ChannelLink.state()
  local up = sendable()
  return {
    up = up, reason = not up and downReason() or nil, peers = presence:count(),
    instance = currentInstance(), lockdown = lockdown() and true or false,
  }
end

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

function ChannelLink.send(message, to)
  if not sendable() then
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
