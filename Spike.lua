-- Throwaway spike for "Spike: do two clients see each other over the Crew channel?" (#6).
-- Everything is logged to chat and to BFFSpikeLog (WTF\Account\<ACCOUNT>\SavedVariables\BFF.lua).

local PREFIX = "BFFSPIKE"
local channelName, channelPass = "BFFSpike6", "spike6"
local MAX_LOG = 3000

local log
local seq = 0
local autoTicker
local recv = { count = 0 }
local t0 = GetTimePreciseSec()

local function str(v)
  if issecretvalue and issecretvalue(v) then return "<secret>" end
  local ok, s = pcall(tostring, v)
  return ok and s or "<?>"
end

local function args(...)
  local out = {}
  for i = 1, select("#", ...) do out[#out + 1] = str((select(i, ...))) end
  return table.concat(out, " | ")
end

local function write(kind, text)
  local line = ("%s +%.3f [%s] %s"):format(date("%H:%M:%S"), GetTimePreciseSec() - t0, kind, text)
  print("|cff33ff99BFF spike|r " .. line)
  if log then
    log[#log + 1] = line
    if #log > MAX_LOG then table.remove(log, 1) end
  end
end

local function lockdown()
  if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
    return str(C_ChatInfo.InChatMessagingLockdown())
  end
  return "n/a"
end

local function resultName(r)
  if Enum and Enum.SendAddonMessageResult then
    for k, v in pairs(Enum.SendAddonMessageResult) do
      if v == r then return k end
    end
  end
  return str(r)
end

local function channelId()
  local id = GetChannelName(channelName)
  return id or 0
end

local function env()
  local restricted = "n/a"
  if C_ChatInfo and C_ChatInfo.AreOutgoingAddonChatMessagesRestricted then
    restricted = str(C_ChatInfo.AreOutgoingAddonChatMessagesRestricted())
  end
  local version, build, _, interface = GetBuildInfo()
  write("env", ("%s-%s (normalized %s) %s guid=%s"):format(
    str(UnitName("player")), str(GetRealmName()), str(GetNormalizedRealmName()),
    str(UnitFactionGroup("player")), str(UnitGUID("player"))))
  write("env", ("project=%s build=%s.%s interface=%s trial=%s veteran=%s outgoingRestricted=%s lockdown=%s"):format(
    str(WOW_PROJECT_ID), str(version), str(build), str(interface),
    str(IsTrialAccount and IsTrialAccount()), str(IsVeteranTrialAccount and IsVeteranTrialAccount()),
    restricted, lockdown()))
end

local function hide()
  for i = 1, NUM_CHAT_WINDOWS or 10 do
    if RemoveChatWindowChannel then
      local ok, err = pcall(RemoveChatWindowChannel, i, channelName)
      if not ok then write("hide", "RemoveChatWindowChannel(" .. i .. ") failed: " .. str(err)) end
    end
    local frame = _G["ChatFrame" .. i]
    if frame and ChatFrame_RemoveChannel then pcall(ChatFrame_RemoveChannel, frame, channelName) end
  end
  write("hide", "removed " .. channelName .. " from chat frames")
end

local function join()
  write("join", ("JoinTemporaryChannel(%s, ***) lockdown=%s"):format(channelName, lockdown()))
  local ok, a, b = pcall(JoinTemporaryChannel, channelName, channelPass)
  write("join", "returned ok=" .. str(ok) .. " " .. args(a, b))
  local tries = 0
  C_Timer.NewTicker(0.5, function(t)
    tries = tries + 1
    local id = channelId()
    if id > 0 then
      t:Cancel()
      write("join", ("in channel, index %d after %.1f s"):format(id, tries * 0.5))
      hide()
    elseif tries >= 20 then
      t:Cancel()
      write("join", "NOT in channel after 10 s")
    end
  end)
end

local function send(text)
  local id = channelId()
  if id == 0 then
    write("send", "not in channel, dropped: " .. text)
    return
  end
  local ok, r = pcall(C_ChatInfo.SendAddonMessage, PREFIX, text, "CHANNEL", id)
  write("send", ("%s -> ok=%s result=%s lockdown=%s"):format(text, str(ok), ok and resultName(r) or str(r), lockdown()))
end

local function ping(kind)
  seq = seq + 1
  send(("%s %d %d"):format(kind, seq, GetServerTime()))
end

local function onAddonMessage(prefix, text, channel, sender, target, zoneChannelID, localID, name, instanceID)
  if prefix ~= PREFIX then return end
  recv.count = recv.count + 1
  local now = GetTimePreciseSec()
  recv.first = recv.first or now
  recv.last = now
  local sentAt = tonumber(str(text):match("%s(%d+)$") or "")
  local latency = sentAt and (GetServerTime() - sentAt) or "?"
  write("recv", ("%q from sender=%q channel=%s target=%s zoneChannelID=%s localID=%s name=%s instanceID=%s latency=%ss lockdown=%s"):format(
    str(text), str(sender), str(channel), str(target), str(zoneChannelID), str(localID), str(name), str(instanceID),
    str(latency), lockdown()))
  if Ambiguate then write("recv", "Ambiguate(sender, 'none') = " .. str(Ambiguate(sender, "none"))) end
end

local f = CreateFrame("Frame")
local events = {
  "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD", "PLAYER_LOGOUT",
  "CHAT_MSG_ADDON", "CHAT_MSG_CHANNEL_NOTICE", "CHAT_MSG_CHANNEL_NOTICE_USER",
  "ADDON_RESTRICTION_STATE_CHANGED", "ENCOUNTER_START", "ENCOUNTER_END",
  "CHALLENGE_MODE_START", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
}
for _, ev in ipairs(events) do
  local ok = pcall(f.RegisterEvent, f, ev)
  if not ok then print("|cff33ff99BFF spike|r event not available: " .. ev) end
end

f:SetScript("OnEvent", function(_, ev, ...)
  if ev == "ADDON_LOADED" then
    if ... ~= "BFF" then return end
    BFFSpikeLog = BFFSpikeLog or {}
    log = BFFSpikeLog
    write("session", "---- loaded ----")
  elseif ev == "PLAYER_ENTERING_WORLD" then
    local initial, reload = ...
    write("event", ("PLAYER_ENTERING_WORLD initial=%s reload=%s"):format(str(initial), str(reload)))
    if initial or reload then
      env()
      local ok = pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
      write("prefix", "registered " .. PREFIX .. " ok=" .. str(ok))
      C_Timer.After(10, join)
    end
  elseif ev == "PLAYER_LEAVING_WORLD" or ev == "PLAYER_LOGOUT" then
    ping("BYE-" .. ev)
  elseif ev == "CHAT_MSG_ADDON" then
    onAddonMessage(...)
  elseif ev == "CHAT_MSG_CHANNEL_NOTICE" or ev == "CHAT_MSG_CHANNEL_NOTICE_USER" then
    local all = args(...)
    if all:lower():find(channelName:lower(), 1, true) then write("notice", ev .. ": " .. all) end
  elseif ev == "ADDON_RESTRICTION_STATE_CHANGED" then
    write("lockdown", ("ADDON_RESTRICTION_STATE_CHANGED %s -> InChatMessagingLockdown=%s"):format(args(...), lockdown()))
  else
    write("event", ev .. " " .. args(...) .. " lockdown=" .. lockdown())
  end
end)

local help = {
  "/bffspike status - environment, channel index, lockdown, receive count",
  "/bffspike join [name pass] - (re)join the channel (auto-joins 10 s after login)",
  "/bffspike leave - leave the channel",
  "/bffspike ping - send one PING",
  "/bffspike auto [seconds] - toggle a PING every N seconds (default 5)",
  "/bffspike burst [n] - send n messages at once (default 30)",
  "/bffspike stats - received count and spread since the last reset",
  "/bffspike reset - reset receive stats",
  "/bffspike clear - clear the saved log",
}

SLASH_BFFSPIKE1 = "/bffspike"
SlashCmdList.BFFSPIKE = function(input)
  local cmd, a, b = strsplit(" ", strtrim(input or ""))
  cmd = (cmd or ""):lower()
  if cmd == "status" then
    env()
    write("status", ("channel %s index=%d received=%d"):format(channelName, channelId(), recv.count))
  elseif cmd == "join" then
    if a and a ~= "" then channelName, channelPass = a, b or "" end
    join()
  elseif cmd == "leave" then
    LeaveChannelByName(channelName)
    write("leave", channelName)
  elseif cmd == "ping" then
    ping("PING")
  elseif cmd == "auto" then
    if autoTicker then
      autoTicker:Cancel()
      autoTicker = nil
      write("auto", "off")
    else
      local every = tonumber(a) or 5
      autoTicker = C_Timer.NewTicker(every, function() ping("AUTO") end)
      write("auto", "every " .. every .. " s")
    end
  elseif cmd == "burst" then
    local n = tonumber(a) or 30
    for i = 1, n do send(("BURST %d/%d %d"):format(i, n, GetServerTime())) end
  elseif cmd == "stats" then
    local spread = recv.first and (recv.last - recv.first) or 0
    write("stats", ("received %d, first-to-last %.2f s"):format(recv.count, spread))
  elseif cmd == "reset" then
    recv = { count = 0 }
    write("stats", "reset")
  elseif cmd == "clear" then
    wipe(BFFSpikeLog)
    write("session", "log cleared")
  else
    for _, line in ipairs(help) do print("|cff33ff99BFF spike|r " .. line) end
  end
end
