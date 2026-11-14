-- PocketCamp: the small on-screen Camp you can keep up while playing. It
-- draws Core's pocketCamp() with a CampScene band of its own: the fire and
-- the online Members, each doing what Core says they're doing, over a
-- soft-edged backdrop of the opacity Core gives. It shows no names: the mouse over a figure
-- shows that Member's Roster tooltip, and over the fire who is doing what.
-- A click toggles the panel (not in combat), a drag moves it unless Core
-- says it's locked, and where it's dropped is saved through Core. Unlocked,
-- a grip shows in its bottom right corner while the mouse is over it: a drag
-- there scales it, and a double-click puts it back to its usual size. Core's pocketCampAnimation events play on it, and a
-- Cheer makes a friend hop. No frame is made until Core first has a Pocket
-- Camp; hidden, nothing of it runs. It never reads a setting or a Member
-- record. See docs/design/pocket-camp.md.

local _, ns = ...

local PocketCamp = {}
ns.PocketCamp = PocketCamp

-- Where it starts, until it's dragged: its centre this far under the
-- screen's.
local START_Y = -220
-- Sparks and Last seen go stale, so it redraws this often while shown.
local REDRAW_EVERY = 30
local MUTED = ns.Skin.MUTED
-- The scale grip's size in UI units.
local GRIP = 12

local core
local frame
-- What Core last gave: the Pocket Camp, or nil while there's none.
local view
local inCombat = false
-- The Member whose tooltip is up, false for the Pocket Camp's own, nil
-- while none is.
local tooltipFor

-- Puts the frame where Core says: where it was dropped, or where it starts.
local function place()
  if frame.moving or frame.scaling then return end
  frame:ClearAllPoints()
  if view.position then
    frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", view.position.x, view.position.y)
  else
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, START_Y)
  end
end

-- Ends a drag and saves where it left the frame.
local function dropped()
  if not frame.moving then return end
  frame.moving = nil
  frame:StopMovingOrSizing()
  frame:SetUserPlaced(false)
  core:setPocketCampPosition(frame:GetLeft(), frame:GetBottom())
  if view then place() end
end

-- Sizes the band for a scale (1 is the usual size): its art pixel stays a
-- whole number of screen pixels, so the size steps as the scale changes.
local function fit(scale)
  frame.band:SetTarget(ns.CampScene.FIGURE_TARGET * scale)
  frame:SetSize(frame.band:Fit(view.columns, view.rows))
end

local function cursorX()
  return GetCursorPosition() / frame:GetEffectiveScale()
end

-- Its top left in UI units from the screen's bottom left.
local function pinTopLeft(left, top)
  frame:ClearAllPoints()
  frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
end

-- The scale the grip is dragged to: the width grows or shrinks by as much
-- as the mouse has moved since the press, in whole percents, within Core's
-- limits.
local function draggedScale(drag)
  local width = drag.width + cursorX() - drag.x
  local percent = math.floor(drag.from * width / drag.width * 100 + 0.5)
  return math.max(ns.Core.POCKET_CAMP_MIN_SCALE, math.min(ns.Core.POCKET_CAMP_MAX_SCALE, percent)) / 100
end

-- Ends a drag of the grip and saves the scale, and where its corner is.
-- A press that didn't change the scale saves nothing.
local function endScaling()
  local drag = frame.scaling
  if not drag then return end
  frame.scaling = nil
  if drag.scale == drag.from then return end
  local left, bottom = frame:GetLeft(), frame:GetBottom()
  core:setPocketCampPosition(left, bottom)
  core:setPocketCampScale(drag.scale)
end

-- The grip follows the mouse: shown over the Pocket Camp while it isn't
-- locked, and while it's being dragged, it redraws at the scale it's
-- dragged to, its top left where it was at the press (read once, so the
-- screen's clamp can't feed back into the scale).
local function updateGrip()
  local drag = frame.scaling
  frame.grip:SetShown(drag or (view and not view.locked and not frame.moving and frame:IsMouseOver()) or false)
  if not (drag and view) then return end
  local scale = draggedScale(drag)
  if scale == drag.scale then return end
  drag.scale = scale
  local width = frame:GetWidth()
  fit(scale)
  pinTopLeft(drag.left, drag.top)
  -- The art pixel steps, so many scales draw the same.
  if frame:GetWidth() ~= width then frame.band:Draw(view) end
end

-- Back to the usual size, keeping its top left where it is, as a drag does.
local function usualSize()
  if not view or view.scale == 1 then return end
  local left, top = frame:GetLeft(), frame:GetTop()
  fit(1)
  core:setPocketCampPosition(left, top - frame:GetHeight())
  core:setPocketCampScale(nil)
end

local function createGrip()
  local grip = CreateFrame("Button", nil, frame)
  grip:SetSize(GRIP, GRIP)
  grip:SetPoint("BOTTOMRIGHT")
  grip:SetFrameLevel(frame:GetFrameLevel() + 10)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:SetScript("OnMouseDown", function(_, button)
    if button == "LeftButton" and view and not view.locked then
      GameTooltip:Hide()
      frame.scaling = {
        left = frame:GetLeft(), top = frame:GetTop(), width = frame:GetWidth(), x = cursorX(),
        from = view.scale, scale = view.scale,
      }
    end
  end)
  grip:SetScript("OnMouseUp", endScaling)
  grip:SetScript("OnDoubleClick", function()
    if view and not view.locked then usualSize() end
  end)
  grip:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Drag to scale")
    GameTooltip:AddLine("Double-click: usual size", MUTED[1], MUTED[2], MUTED[3])
    GameTooltip:Show()
  end)
  grip:SetScript("OnLeave", function() GameTooltip:Hide() end)
  grip:Hide()
  frame.grip = grip
end

-- The actor whose figure the mouse is over, or nil.
local function hovered()
  local x = GetCursorPosition()
  return frame.band:ActorAt(x / frame:GetEffectiveScale() - frame:GetLeft())
end

-- Over a figure, that Member's tooltip as the Roster shows it; anywhere
-- else, who is doing what.
local function showTooltip()
  if not view then return end
  local actor = hovered()
  tooltipFor = actor and actor.memberId or false
  GameTooltip:SetOwner(frame, "ANCHOR_TOP")
  if actor then
    ns.Panel.characterTooltip(actor.row, actor.row)
  else
    GameTooltip:AddLine(view.tooltip.title)
    for _, line in ipairs(view.tooltip.lines) do GameTooltip:AddLine(line, 1, 1, 1) end
    if view.moreText then GameTooltip:AddLine(view.moreText, MUTED[1], MUTED[2], MUTED[3]) end
  end
  GameTooltip:AddLine(view.tooltip.hint, MUTED[1], MUTED[2], MUTED[3])
  GameTooltip:Show()
end

local function hideTooltip()
  tooltipFor = nil
  GameTooltip:Hide()
end

local function create()
  frame = CreateFrame("Button", "BFFPocketCamp", UIParent)
  frame:SetFrameStrata("LOW")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:RegisterForClicks("LeftButtonUp")
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function()
    if view and not view.locked then
      frame.moving = true
      frame:StartMoving()
    end
  end)
  frame:SetScript("OnDragStop", dropped)
  -- The panel can't open in combat, so a click does nothing there.
  frame:SetScript("OnClick", function()
    if not InCombatLockdown() then ns.Panel.toggle() end
  end)
  frame:SetScript("OnEnter", showTooltip)
  frame:SetScript("OnLeave", hideTooltip)
  -- Hidden mid-drag (combat began): the drag still saves where it got to.
  frame:SetScript("OnHide", function()
    dropped()
    endScaling()
  end)
  local sinceRedraw = 0
  frame:SetScript("OnUpdate", function(_, elapsed)
    updateGrip()
    -- The tooltip follows the mouse from figure to figure.
    if tooltipFor ~= nil and GameTooltip:IsOwned(frame) then
      local actor = hovered()
      if (actor and actor.memberId or false) ~= tooltipFor then showTooltip() end
    end
    sinceRedraw = sinceRedraw + elapsed
    if sinceRedraw >= REDRAW_EVERY then
      sinceRedraw = 0
      PocketCamp.refresh()
    end
  end)
  frame:RegisterEvent("PLAYER_REGEN_DISABLED")
  frame:RegisterEvent("PLAYER_REGEN_ENABLED")
  frame:SetScript("OnEvent", function(_, event)
    inCombat = event == "PLAYER_REGEN_DISABLED"
    PocketCamp.refresh()
  end)
  inCombat = InCombatLockdown() and true or false

  frame.band = ns.CampScene.new(frame, {
    target = ns.CampScene.FIGURE_TARGET, shadow = true, names = false, backdrop = ns.CampSheet.pocketBackdrop,
  })
  frame.band:SetAllPoints()
  createGrip()
end

-- Redraws from Core: shown while Core has a Pocket Camp, unless it hides
-- in combat and you're in it.
function PocketCamp.refresh()
  if not core then return end
  view = core:pocketCamp()
  if not view then
    if frame then frame:Hide() end
    return
  end
  if not frame then create() end
  -- Hidden in combat, nothing is drawn until it's over.
  if view.hideInCombat and inCombat then
    frame:Hide()
    return
  end
  if not frame.scaling then fit(view.scale) end
  place()
  frame.band:SetBackdropAlpha(view.opacity)
  frame.band:Draw(view)
  frame:Show()
  if GameTooltip:IsOwned(frame) then showTooltip() end
end

-- The Camp's setting and the Pocket Camp's own all change what it shows.
function PocketCamp.settingChanged(key)
  if key == "camp" or key:find("^pocketCamp") then PocketCamp.refresh() end
end

-- Core's pocketCampAnimation: { kind, memberId }, played once.
function PocketCamp.animate(animation)
  if frame and frame:IsShown() then frame.band:Animate(animation.kind, animation.memberId) end
end

-- You Cheered a Member: they hop, if they're by this fire.
function PocketCamp.cheered(memberId)
  if frame and frame:IsShown() then frame.band:Hop(memberId) end
end

function PocketCamp.start(theCore)
  core = theCore
  PocketCamp.refresh()
end
