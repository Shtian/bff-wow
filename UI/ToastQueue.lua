-- ToastQueue: which toasts are on screen, from the toasts decision. Pure
-- Lua, so it's tested offline: Toasts feeds it live Feed entries and the
-- time, and draws visible() after each update. At most MAX toasts show,
-- each for DURATION seconds (the clock stops while hovered); a burst that
-- doesn't fit ends in one "+N more" toast; nothing new shows in combat;
-- and the sound plays at most once per SOUND_GAP. A Reaction to an entry
-- whose Reaction toast is showing or waiting merges into it, and a shown
-- one gets its full time again. See docs/design/toasts.md and
-- docs/design/reactions.md.

local _, ns = ...

local ToastQueue = {}
ToastQueue.__index = ToastQueue
ns.ToastQueue = ToastQueue

ToastQueue.MAX = 3
ToastQueue.DURATION = 6
ToastQueue.SOUND_GAP = 2

function ToastQueue.new()
  return setmetatable({ pending = {}, shown = {} }, ToastQueue)
end

-- The Reaction toast showing or waiting for this entry, and whether it's
-- showing.
local function reactionFor(self, entryKey)
  for _, toast in ipairs(self.shown) do
    if toast.entry and toast.entry.entryKey == entryKey then return toast.entry, toast end
  end
  for _, entry in ipairs(self.pending) do
    if entry.entryKey == entryKey then return entry end
  end
end

-- Adds a Member's name to a Reaction toast: "Bob and Cleo cheered your
-- ding to 30".
local function merge(target, news)
  for _, name in ipairs(target.names) do
    if name == news.name then return false end
  end
  target.names[#target.names + 1] = news.name
  target.text = ns.Reactions.text(target.names, target.phrase)
  return true
end

-- A live Feed entry, or a Reaction from Core's reaction event, to show.
function ToastQueue:push(entry)
  if entry.entryKey then
    local target, toast = reactionFor(self, entry.entryKey)
    if target then
      if merge(target, entry) and toast then toast.renew = true end
      return
    end
    local copy = {}
    for k, v in pairs(entry) do copy[k] = v end
    copy.names = { entry.name }
    entry = copy
  end
  self.pending[#self.pending + 1] = entry
end

-- The toasts on screen, oldest first. A toast is { entry, expiresAt,
-- hovered, left }, or the overflow toast { more = n, ... }; left is the
-- time it had when hovered.
function ToastQueue:visible()
  return self.shown
end

-- Takes every toast off screen and drops those waiting, as turning toasts
-- off does.
function ToastQueue:clear()
  self.pending = {}
  self.shown = {}
end

-- Whether there's nothing to show or wait for.
function ToastQueue:isIdle()
  return #self.shown == 0 and #self.pending == 0
end

local function remove(list, item)
  for i, other in ipairs(list) do
    if other == item then
      table.remove(list, i)
      return true
    end
  end
  return false
end

-- Takes a toast off screen, as a click does.
function ToastQueue:dismiss(toast)
  remove(self.shown, toast)
end

-- Hovering stops a toast's clock; leaving starts it again from where it
-- stopped.
function ToastQueue:hover(toast, hovered, now)
  if (toast.hovered == true) == hovered then return end
  toast.hovered = hovered
  if hovered then
    toast.left = toast.expiresAt - now
  else
    toast.expiresAt = now + toast.left
  end
end

-- Seconds until the toast goes, not counting down while hovered.
function ToastQueue:remaining(toast, now)
  if toast.hovered then return toast.left end
  return toast.expiresAt - now
end

-- Gives a toast its full time.
local function restart(toast, now)
  toast.expiresAt = now + ToastQueue.DURATION
  toast.left = ToastQueue.DURATION
  toast.renew = nil
end

-- Restarts the toasts a merged Reaction renewed. Returns whether any.
local function renew(self, now)
  local any = false
  for _, toast in ipairs(self.shown) do
    if toast.renew then
      restart(toast, now)
      any = true
    end
  end
  return any
end

local function expire(self, now)
  local changed = false
  for i = #self.shown, 1, -1 do
    if self:remaining(self.shown[i], now) <= 0 then
      table.remove(self.shown, i)
      changed = true
    end
  end
  return changed
end

local function overflow(self)
  for _, toast in ipairs(self.shown) do
    if toast.more then return toast end
  end
end

-- Puts waiting entries on screen. What doesn't fit goes into the overflow
-- toast, which takes the last free slot; with no slot free and no overflow
-- toast showing, entries wait. Returns whether anything showed.
local function fill(self, now)
  local pending = self.pending
  if #pending == 0 then return false end
  local free = ToastQueue.MAX - #self.shown
  local more = overflow(self)
  local count
  if #pending <= free then
    count = #pending
  elseif more then
    count = free
  elseif free > 0 then
    count = free - 1
  else
    return false
  end
  for i = 1, count do
    local toast = { entry = pending[i] }
    restart(toast, now)
    self.shown[#self.shown + 1] = toast
  end
  local rest = #pending - count
  if rest > 0 then
    if not more then
      more = { more = 0 }
      self.shown[#self.shown + 1] = more
    end
    more.more = more.more + rest
    restart(more, now)
  end
  self.pending = {}
  return true
end

-- Called every frame with the time in seconds and whether you're in
-- combat. Returns whether the toasts on screen changed, and whether to
-- play the sound.
function ToastQueue:update(now, inCombat)
  local renewed = renew(self, now)
  local changed = expire(self, now) or renewed
  local showed = not inCombat and fill(self, now)
  local sound = false
  if showed and (not self.lastSound or now - self.lastSound >= ToastQueue.SOUND_GAP) then
    self.lastSound = now
    sound = true
  end
  return changed or showed, sound
end
