local _, ns = ...

local ToastQueue = {}
ToastQueue.__index = ToastQueue
ns.ToastQueue = ToastQueue

ToastQueue.MAX = 3
ToastQueue.DURATION = 10
ToastQueue.SOUND_GAP = 2

function ToastQueue.new(reactionText)
  return setmetatable({ pending = {}, shown = {}, reactionText = reactionText }, ToastQueue)
end

local function reactionFor(self, entryKey)
  for _, toast in ipairs(self.shown) do
    if toast.entry and toast.entry.entryKey == entryKey then return toast.entry, toast end
  end
  for _, entry in ipairs(self.pending) do
    if entry.entryKey == entryKey then return entry end
  end
end

local function merge(self, target, news)
  for _, name in ipairs(target.names) do
    if name == news.name then return false end
  end
  target.names[#target.names + 1] = news.name
  target.text = self.reactionText(target.names, target.phrase)
  return true
end

function ToastQueue:push(entry)
  if entry.entryKey then
    local target, toast = reactionFor(self, entry.entryKey)
    if target then
      if merge(self, target, entry) and toast then toast.renew = true end
      return
    end
    local copy = {}
    for k, v in pairs(entry) do copy[k] = v end
    copy.names = { entry.name }
    entry = copy
  end
  self.pending[#self.pending + 1] = entry
end

function ToastQueue:visible()
  return self.shown
end

function ToastQueue:clear()
  self.pending = {}
  self.shown = {}
end

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

function ToastQueue:dismiss(toast)
  remove(self.shown, toast)
end

function ToastQueue:hover(toast, hovered, now)
  if (toast.hovered == true) == hovered then return end
  toast.hovered = hovered
  if hovered then
    toast.left = toast.expiresAt - now
  else
    toast.expiresAt = now + toast.left
  end
end

function ToastQueue:remaining(toast, now)
  if toast.hovered then return toast.left end
  return toast.expiresAt - now
end

function ToastQueue:share(toast, now)
  return math.max(0, math.min(1, self:remaining(toast, now) / ToastQueue.DURATION))
end

local function restart(toast, now)
  toast.expiresAt = now + ToastQueue.DURATION
  toast.left = ToastQueue.DURATION
  toast.renew = nil
end

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
