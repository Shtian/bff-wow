return function()
  local game = {
    time = 100,
    timers = {},
    whispers = {},
    frames = {},
    lockdown = false,
    channels = {},
    listed = {},
    -- WoW: on Forever, UnitName("player") returns the last name second,
    -- where retail puts the realm.
    player = { "Me" },
    -- WoW: ChatThrottleLib sends at once while it has bandwidth to spare,
    -- calling back inside SendAddonMessage.
    instant = false,
    instance = { false, "none" },
  }

  -- WoW: Midnight hands addons secret values for chat text they may not
  -- read; indexing, concatenating, tostring or # on one errors.
  local secrets = setmetatable({}, { __mode = "k" })
  function game.secret()
    local function refuse() error("read a secret value", 2) end
    local value = setmetatable({}, {
      __index = refuse, __newindex = refuse, __concat = refuse, __tostring = refuse,
      __len = refuse, __eq = refuse, __lt = refuse, __le = refuse, __call = refuse,
    })
    secrets[value] = true
    return value
  end

  local function schedule(delay, fn, interval)
    local timer = { due = game.time + delay, fn = fn, interval = interval }
    function timer.Cancel() timer.cancelled = true end
    game.timers[#game.timers + 1] = timer
    return timer
  end

  function game.advance(seconds)
    local stop = game.time + (seconds or 0)
    while true do
      local next
      for _, timer in ipairs(game.timers) do
        if not timer.cancelled and timer.due <= stop and (next == nil or timer.due < next.due) then next = timer end
      end
      if not next then break end
      game.time = math.max(game.time, next.due)
      if next.interval then
        next.due = next.due + next.interval
        next.fn(next)
      else
        next.cancelled = true
        next.fn()
      end
    end
    game.time = stop
  end

  -- WoW: ChatThrottleLib calls back with whether the chunk went out and an
  -- Enum.SendAddonMessageResult code.
  function game.sent(whisper) whisper.callback(whisper.arg, true, 0) end
  function game.failed(whisper, result) whisper.callback(whisper.arg, false, result or 9) end

  function game.fire(event, ...)
    for _, frame in ipairs(game.frames) do
      if frame.events[event] and frame.onEvent then frame.onEvent(frame, event, ...) end
    end
  end

  local env = setmetatable({
    LibStub = function()
      return {
        Embed = function(_, target)
          function target.RegisterComm(_, _, fn) game.onComm = fn end
        end,
      }
    end,
    C_ChatInfo = { InChatMessagingLockdown = function() return game.lockdown end },
    C_Timer = {
      After = function(delay, fn) schedule(delay, fn) end,
      NewTicker = function(interval, fn) return schedule(interval, fn, interval) end,
    },
    ChatThrottleLib = {
      bQueueing = false,
      SendAddonMessage = function(_, priority, prefix, text, distribution, to, queue, callback, arg)
        game.whispers[#game.whispers + 1] = {
          prefix = prefix, text = text, distribution = distribution, target = to,
          priority = priority, queue = queue, callback = callback, arg = arg,
        }
        if game.instant then callback(arg, true, 0) end
      end,
    },
    GetTime = function() return game.time end,
    GetChannelName = function(name) return game.channels[name:upper()] or 0 end,
    GetChannelList = function() return end,
    JoinTemporaryChannel = function(name)
      game.joins = (game.joins or 0) + 1
      if not game.refuseJoin then game.channels[name:upper()] = 5 end
    end,
    LeaveChannelByName = function(name) game.channels[name:upper()] = nil end,
    ListChannelByName = function(name) game.listed[#game.listed + 1] = name end,
    RemoveChatWindowChannel = function() end,
    NUM_CHAT_WINDOWS = 0,
    Ambiguate = function(name) return (name:gsub("%-.*$", "")) end,
    UnitName = function() return unpack(game.player) end,
    IsInInstance = function() return unpack(game.instance) end,
    issecretvalue = function(value) return secrets[value] == true end,
    ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing.",
    ERR_TOO_MANY_CHAT_CHANNELS = "You can only be in %d channels at a time.",
    ChatFrame_AddMessageEventFilter = function(event, fn)
      game.filters = game.filters or {}
      game.filters[event] = fn
    end,
    CreateFrame = function()
      local frame = { events = {} }
      function frame.RegisterEvent(self, event) self.events[event] = true end
      function frame.SetScript(self, _, fn) self.onEvent = fn end
      game.frames[#game.frames + 1] = frame
      return frame
    end,
  }, { __index = _G })
  env._G = env
  game.env = env

  function game.load(path, ns)
    for line in io.lines("BFF.toc") do
      local pure = line:match("^%s*(Link/[^%s]+%.lua)%s*$")
      if pure then assert(loadfile(pure))("BFF", ns) end
    end
    local chunk = assert(loadfile(path))
    setfenv(chunk, env)
    chunk("BFF", ns)
    return ns
  end

  return game
end
