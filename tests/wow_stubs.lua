-- WoW stand-ins for the game-facing files that are tested offline (the
-- channel link). wow() returns a fresh game: env, the globals a file is
-- loaded with (Lua's own come from _G), plus helpers to drive it. Only what
-- those files call is here.

return function()
  local game = {
    time = 100,
    timers = {},
    -- Every SendCommMessage: { prefix, text, distribution, target, priority,
    -- callback, arg }.
    whispers = {},
    frames = {},
    lockdown = false,
    channels = {},
  }

  local function schedule(delay, fn, interval)
    local timer = { due = game.time + delay, fn = fn, interval = interval }
    function timer.Cancel() timer.cancelled = true end
    game.timers[#game.timers + 1] = timer
    return timer
  end

  -- Moves the clock on, running every timer that comes due on the way.
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

  -- Fires a game event at every frame registered for it.
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
          function target.SendCommMessage(_, prefix, text, distribution, to, priority, callback, arg)
            game.whispers[#game.whispers + 1] = {
              prefix = prefix, text = text, distribution = distribution, target = to,
              priority = priority, callback = callback, arg = arg,
            }
          end
        end,
      }
    end,
    C_ChatInfo = { InChatMessagingLockdown = function() return game.lockdown end },
    C_Timer = {
      After = function(delay, fn) schedule(delay, fn) end,
      NewTicker = function(interval, fn) return schedule(interval, fn, interval) end,
    },
    ChatThrottleLib = { bQueueing = false },
    GetTime = function() return game.time end,
    GetChannelName = function(name) return game.channels[name:upper()] or 0 end,
    GetChannelList = function() return end,
    JoinTemporaryChannel = function(name) game.channels[name:upper()] = 5 end,
    LeaveChannelByName = function(name) game.channels[name:upper()] = nil end,
    ListChannelByName = function() end,
    RemoveChatWindowChannel = function() end,
    NUM_CHAT_WINDOWS = 0,
    Ambiguate = function(name) return (name:gsub("%-.*$", "")) end,
    UnitName = function() return "Me" end,
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

  -- Loads a game-facing file into this game, with the addon's namespace.
  function game.load(path, ns)
    local chunk = assert(loadfile(path))
    setfenv(chunk, env)
    chunk("BFF", ns)
    return ns
  end

  return game
end
