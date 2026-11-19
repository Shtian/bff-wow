local _, ns = ...

local Toasts = {}
ns.Toasts = Toasts

local Skin = ns.Skin

local WIDTH = 300
local HEIGHT = 40
local GAP = 6
local ICON = 18
local PICTURE = 24
local REACT = 20
local FADE = 0.6
local TIMER = 2
local TIMER_COLOR = { 1, 1, 1, 0.18 }
local DEFAULT_FROM_TOP = 160
local MORE_ICON = "Interface\\FriendsFrame\\UI-Toast-ChatInviteIcon"

local SOUNDS = {
  { "UI_BNET_TOAST", "Friend online" },
  { "TELL_MESSAGE", "Whisper" },
  { "IG_PLAYER_INVITE", "Invite" },
  { "IG_QUEST_LIST_COMPLETE", "Quest complete" },
  { "READY_CHECK", "Ready check" },
  { "RAID_WARNING", "Raid warning" },
  { "MAP_PING", "Map ping" },
  { "ALARM_CLOCK_WARNING_3", "Alarm" },
}

local core
local queue
local driver
local toastFrames = {}
local mover

function Toasts.sounds()
  local list = { { key = "none", label = "None" } }
  for _, sound in ipairs(SOUNDS) do
    if SOUNDKIT and SOUNDKIT[sound[1]] then
      list[#list + 1] = { key = sound[1], label = sound[2] }
    end
  end
  return list
end

function Toasts.soundLabel(key)
  for _, sound in ipairs(Toasts.sounds()) do
    if sound.key == key then return sound.label end
  end
  return "None"
end

-- WoW: PlaySound on the "Master" channel is heard with game sounds off.
function Toasts.play(key)
  local id = SOUNDKIT and SOUNDKIT[key]
  if id then PlaySound(id, "Master") end
end

local function position()
  local x, y = core:toastPosition()
  local height = UIParent:GetHeight()
  if not x then
    x, y = UIParent:GetWidth() / 2, height - DEFAULT_FROM_TOP
  end
  return x, y, y > height / 2
end

local function openFeed(toast)
  queue:dismiss(toast)
  ns.Panel.show(toast.entry and toast.entry.opens or "feed")
end

local function onClick(self, button)
  if button == "LeftButton" then openFeed(self.toast) else queue:dismiss(self.toast) end
  Toasts.draw()
end

local function onReact(self)
  local entry = self:GetParent().toast.entry
  if not (entry and entry.key) or entry.reacted then return end
  local ok, reason = core:react(entry.key)
  entry.reacted = ok or reason == "reacted"
  self:SetReaction(entry.reaction, entry.reacted)
  if ok and entry.reaction == "cheer" then ns.Panel.cheered(entry.memberId) end
end

local function createToast()
  local toast = CreateFrame("Button", nil, UIParent)
  toast:SetSize(WIDTH, HEIGHT)
  toast:SetFrameStrata("HIGH")
  toast:SetClampedToScreen(true)
  Skin.fill(toast, { Skin.WINDOW[1], Skin.WINDOW[2], Skin.WINDOW[3], 0.88 })
  toast.timer = toast:CreateTexture(nil, "ARTWORK")
  toast.timer:SetColorTexture(1, 1, 1, 1)
  Skin.color(toast.timer, TIMER_COLOR)
  toast.timer:SetPoint("BOTTOMLEFT")
  toast.timer:SetHeight(TIMER)
  Skin.fill(toast, Skin.HOVER, "HIGHLIGHT")

  toast.picture = Skin.feedPicture(toast, PICTURE)
  toast.picture:SetPoint("LEFT", 10, 0)
  toast.figure = ns.CampScene.figure(toast)
  toast.figure:SetPoint("CENTER", toast.picture)
  toast.icon = toast:CreateTexture(nil, "ARTWORK")
  toast.icon:SetSize(ICON, ICON)
  toast.icon:SetPoint("LEFT", 10 + (PICTURE - ICON) / 2, 0)
  toast.icon:SetTexture(MORE_ICON)
  toast.icon:SetDesaturated(true)
  Skin.color(toast.icon, Skin.FEED_ICON_COLOR)
  toast.text = Skin.label(toast, "body")
  toast.text:SetPoint("LEFT", toast.picture, "RIGHT", 10, 0)
  toast.text:SetWordWrap(false)
  toast.react = Skin.reactionButton(toast, REACT, onReact)
  toast.react:SetPoint("RIGHT", -10, 0)

  toast:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  toast:SetScript("OnClick", onClick)
  toast:Hide()
  return toast
end

local function drawPicture(frame, entry)
  if entry.entryKey then
    frame.picture:SetPicture(Skin.REACTION_ICONS[entry.reaction], Skin.GOLD)
  else
    frame.picture:SetKind(entry.kind, entry.icon, entry.edge)
  end
end

local function drawToast(frame, toast)
  local entry = toast.entry
  local highlight = entry ~= nil and entry.highlight == true
  local canReact = entry ~= nil and not entry.entryKey and entry.canReact == true
  frame.react:SetShown(canReact)
  if canReact then frame.react:SetReaction(entry.reaction, entry.reacted) end
  frame.text:SetPoint("RIGHT", canReact and -(REACT + 16) or -10, 0)
  local figure = entry ~= nil and entry.figure
  frame.picture:SetShown(entry ~= nil)
  frame.picture:SetAlpha(figure and 0 or 1)
  frame.icon:SetShown(entry == nil)
  if figure then frame.figure:SetClass(figure) else frame.figure:Hide() end
  if entry then
    drawPicture(frame, entry)
    frame.text:SetText(entry.text)
    Skin.color(frame.text, highlight and Skin.GOLD or Skin.TEXT)
  else
    frame.text:SetText(("+%d more in the Feed"):format(toast.more))
    Skin.color(frame.text, Skin.MUTED)
  end
end

function Toasts.draw()
  local visible = queue:visible()
  local x, y, down = position()
  local step = (HEIGHT + GAP) * (down and -1 or 1)
  local count = #visible
  for i = 1, count do
    local toast = visible[count - i + 1]
    local frame = toastFrames[i] or createToast()
    toastFrames[i] = frame
    frame.toast = toast
    drawToast(frame, toast)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y + (i - 1) * step)
    frame:Show()
  end
  for i = count + 1, #toastFrames do toastFrames[i]:Hide() end
end

local function hover(now)
  for _, frame in ipairs(toastFrames) do
    if frame:IsShown() then queue:hover(frame.toast, frame:IsMouseOver(), now) end
  end
end

local function fade(now)
  for _, frame in ipairs(toastFrames) do
    if frame:IsShown() then
      local left = frame.toast.hovered and FADE or queue:remaining(frame.toast, now)
      frame:SetAlpha(math.max(0, math.min(1, left / FADE)))
      frame.timer:SetWidth(math.max(1, WIDTH * queue:share(frame.toast, now)))
    end
  end
end

local function onUpdate()
  local now = GetTime()
  hover(now)
  local changed, sound = queue:update(now, InCombatLockdown())
  if sound then Toasts.play(core:toastSound()) end
  if changed then Toasts.draw() end
  fade(now)
  if queue:isIdle() then driver:Hide() end
end

function Toasts.settingChanged(key, on)
  if key ~= "toasts" or on or not queue then return end
  queue:clear()
  Toasts.draw()
end

function Toasts.show(entry)
  queue:push(entry)
  driver:Show()
end

local function placeMover()
  local x, y, down = position()
  mover:ClearAllPoints()
  mover:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
  mover.hint:SetText(down and "Toasts stack downward from here." or "Toasts stack upward from here.")
  mover.hint:ClearAllPoints()
  mover.done:ClearAllPoints()
  mover.reset:ClearAllPoints()
  if down then
    mover.hint:SetPoint("TOP", mover, "BOTTOM", 0, -6)
    mover.done:SetPoint("TOPRIGHT", mover, "BOTTOM", -4, -24)
    mover.reset:SetPoint("TOPLEFT", mover, "BOTTOM", 4, -24)
  else
    mover.hint:SetPoint("BOTTOM", mover, "TOP", 0, 6)
    mover.done:SetPoint("BOTTOMRIGHT", mover, "TOP", -4, 24)
    mover.reset:SetPoint("BOTTOMLEFT", mover, "TOP", 4, 24)
  end
end

local function moverDropped(self)
  self:StopMovingOrSizing()
  local x, y = self:GetCenter()
  core:setToastPosition(x, y)
  placeMover()
end

local function createMover()
  mover = CreateFrame("Frame", "BFFToastMover", UIParent)
  mover:SetSize(WIDTH, HEIGHT)
  mover:SetFrameStrata("DIALOG")
  mover:SetClampedToScreen(true)
  mover:SetMovable(true)
  mover:EnableMouse(true)
  mover:RegisterForDrag("LeftButton")
  mover:SetScript("OnDragStart", mover.StartMoving)
  mover:SetScript("OnDragStop", moverDropped)
  mover:Hide()
  mover:SetScript("OnHide", function(self)
    local onDone = self.onDone
    self.onDone = nil
    if onDone then onDone() end
  end)
  table.insert(UISpecialFrames, "BFFToastMover")
  Skin.fill(mover, Skin.WINDOW)
  Skin.border(mover, Skin.GOLD)
  local text = Skin.label(mover, "body", Skin.GOLD)
  text:SetPoint("CENTER")
  text:SetText("BFF toasts appear here. Drag to move.")

  mover.hint = Skin.label(mover, "small", Skin.MUTED)
  mover.done = Skin.button(mover, "Done", function() mover:Hide() end, true)
  mover.reset = Skin.button(mover, "Reset", function()
    core:setToastPosition(nil)
    placeMover()
  end)
end

function Toasts.move(onDone)
  if not mover then createMover() end
  mover.onDone = onDone
  placeMover()
  mover:Show()
end

function Toasts.start(theCore)
  core = theCore
  queue = ns.ToastQueue.new(ns.Core.reactionText)
  driver = CreateFrame("Frame")
  driver:Hide()
  driver:SetScript("OnUpdate", onUpdate)
end
