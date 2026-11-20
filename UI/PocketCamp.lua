local _, ns = ...

local PocketCamp = {}
ns.PocketCamp = PocketCamp

local START_Y = -220
local REDRAW_EVERY = 30
local MUTED = ns.Skin.MUTED
local GRIP = 12

local core
local frame
local view
local fighting = false
local tooltipFor

local function usualWidth()
  return ns.Core.CAMP_LAYOUT.pocketColumns * frame.band:Unit()
end

local function savePosition()
  local centre = (frame:GetLeft() + frame:GetRight()) / 2
  core:setPocketCampPosition(centre - usualWidth() / 2, frame:GetBottom())
end

local function place()
  if frame.moving or frame.scaling then return end
  frame:ClearAllPoints()
  if view.position then
    frame:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", view.position.x + usualWidth() / 2, view.position.y)
  else
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, START_Y)
  end
end

local function dropped()
  if not frame.moving then return end
  frame.moving = nil
  frame:StopMovingOrSizing()
  frame:SetUserPlaced(false)
  savePosition()
  if view then place() end
end

local function fit(scale, columns)
  frame.band:SetTarget(ns.CampScene.FIGURE_TARGET * scale)
  frame:SetSize(frame.band:Fit(columns or view.columns, view.rows))
end

local function cursor()
  local x, y = GetCursorPosition()
  local scale = frame:GetEffectiveScale()
  return x / scale, y / scale
end

local function pinTopCentre(centre, top)
  frame:ClearAllPoints()
  frame:SetPoint("TOP", UIParent, "BOTTOMLEFT", centre, top)
end

local function draggedSize(drag)
  local x, y = cursor()
  local percent = math.floor(drag.start.scale * (drag.height + drag.y - y) / drag.height * 100 + 0.5)
  local scale = math.max(ns.Core.POCKET_CAMP_MIN_SCALE, math.min(ns.Core.POCKET_CAMP_MAX_SCALE, percent)) / 100
  local step = ns.Core.CAMP_LAYOUT.pocketStep
  local unit = ns.CampScene.FIGURE_TARGET * scale
  local steps = math.floor(2 * (x - drag.x) / unit / step + 0.5)
  return { scale = scale, columns = ns.Core.pocketCampWidth(drag.start.columns + steps * step) }
end

-- WoW: a frame clamped to the screen is moved when it grows past an edge,
-- so the fire's spot is read once, at the press.
local function drawDragged()
  local size = frame.scaling.size
  fit(size.scale, size.columns)
  pinTopCentre(frame.scaling.centre, frame.scaling.top)
  frame.band:Draw(setmetatable({ columns = size.columns }, { __index = view }))
end

local function gripTooltip(owner)
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  local drag = frame.scaling
  if drag then
    GameTooltip:AddLine(("Room for %d"):format(ns.Core.pocketCampSeats(drag.size.columns)))
    GameTooltip:AddLine(("%d%% size"):format(math.floor(drag.size.scale * 100 + 0.5)), 1, 1, 1)
  else
    GameTooltip:AddLine("Drag sideways for room for more")
    GameTooltip:AddLine("Drag up or down to scale", 1, 1, 1)
    GameTooltip:AddLine("Double-click: usual size", MUTED[1], MUTED[2], MUTED[3])
  end
  GameTooltip:Show()
end

local function startScaling()
  local x, y = cursor()
  local start = { scale = view.scale, columns = view.maxColumns }
  frame.scaling = {
    centre = (frame:GetLeft() + frame:GetRight()) / 2, top = frame:GetTop(), height = frame:GetHeight(),
    x = x, y = y, start = start, size = start,
  }
  drawDragged()
  gripTooltip(frame.grip)
end

local function endScaling()
  local drag = frame.scaling
  if not drag then return end
  frame.scaling = nil
  if GameTooltip:IsOwned(frame.grip) then GameTooltip:Hide() end
  local start, size = drag.start, drag.size
  if size.scale == start.scale and size.columns == start.columns then
    if view then PocketCamp.refresh() end
    return
  end
  savePosition()
  if size.scale ~= start.scale then core:setPocketCampScale(size.scale) end
  if size.columns ~= start.columns then core:setPocketCampColumns(size.columns) end
end

local function updateGrip()
  local drag = frame.scaling
  frame.grip:SetShown(drag or (view and not view.locked and not frame.moving and frame:IsMouseOver()) or false)
  if not (drag and view) then return end
  local size = draggedSize(drag)
  if size.scale == drag.size.scale and size.columns == drag.size.columns then return end
  drag.size = size
  drawDragged()
  gripTooltip(frame.grip)
end

local function usualSize()
  if not view or (view.scale == 1 and view.maxColumns == ns.Core.CAMP_LAYOUT.pocketColumns) then return end
  local centre, top = (frame:GetLeft() + frame:GetRight()) / 2, frame:GetTop()
  fit(1)
  core:setPocketCampPosition(centre - usualWidth() / 2, top - frame:GetHeight())
  core:setPocketCampScale(nil)
  core:setPocketCampColumns(nil)
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
    if button == "LeftButton" and view and not view.locked then startScaling() end
  end)
  grip:SetScript("OnMouseUp", endScaling)
  grip:SetScript("OnDoubleClick", function()
    if view and not view.locked then usualSize() end
  end)
  grip:SetScript("OnEnter", gripTooltip)
  grip:SetScript("OnLeave", function()
    if not frame.scaling then GameTooltip:Hide() end
  end)
  grip:Hide()
  frame.grip = grip
end

local function hovered()
  local x = cursor()
  return frame.band:ActorAt(x - frame:GetLeft())
end

local function overCrate()
  local x, y = cursor()
  return frame.band:CrateAt(x - frame:GetLeft(), y - frame:GetBottom())
end

local function overCup()
  local x, y = cursor()
  return frame.band:CupAt(x - frame:GetLeft(), y - frame:GetBottom())
end

local function pointedAt()
  if overCrate() then return "crate" end
  if overCup() then return "cup" end
  local actor = hovered()
  return actor and actor.memberId or false
end

local function showTooltip()
  if not view then return end
  tooltipFor = pointedAt()
  GameTooltip:SetOwner(frame, "ANCHOR_TOP")
  if tooltipFor == "crate" then
    GameTooltip:AddLine(view.sparesTooltip.title)
    GameTooltip:AddLine(view.sparesTooltip.hint, MUTED[1], MUTED[2], MUTED[3])
    GameTooltip:Show()
    return
  end
  if tooltipFor == "cup" then
    local tip = view.trophiesTooltip
    GameTooltip:AddLine(tip.title)
    for _, line in ipairs(tip.lines) do GameTooltip:AddLine(line, 1, 1, 1) end
    GameTooltip:AddLine(tip.hint, MUTED[1], MUTED[2], MUTED[3])
    GameTooltip:Show()
    return
  end
  local actor = tooltipFor and hovered()
  if actor and actor.pose == "asleep" then
    GameTooltip:AddLine(("%s: %s"):format(actor.label, actor.status), 1, 1, 1)
  elseif actor then
    if actor.since then GameTooltip:AddLine(actor.status, 1, 1, 1) end
    ns.Panel.characterTooltip(actor.row, actor.row)
    if actor.group then GameTooltip:AddLine("In your group", 1, 1, 1) end
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

local function outOfCombat(action)
  return function()
    if not InCombatLockdown() then action() end
  end
end

local function showMenu()
  local actor = not (overCrate() or overCup()) and hovered()
  local menu = actor and actor.menu
  if not menu then return end
  hideTooltip()
  MenuUtil.CreateContextMenu(frame, function(_, root)
    root:CreateTitle(menu.fullName)
    root:CreateButton("Whisper", function() ns.Actions.whisper(menu.fullName) end)
    root:CreateButton("Invite", function() ns.Actions.invite(menu.fullName) end)
    root:CreateButton("Show on map", outOfCombat(function() ns.Actions.openMap(menu.mapId) end)):SetEnabled(menu.mapId ~= nil)
    root:CreateButton("Open in panel", outOfCombat(function() ns.Panel.show("roster") end))
  end)
end

local function create()
  frame = CreateFrame("Button", "BFFPocketCamp", UIParent)
  frame:SetFrameStrata("LOW")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function()
    if view and not view.locked then
      frame.moving = true
      frame:StartMoving()
    end
  end)
  frame:SetScript("OnDragStop", dropped)
  frame:SetScript("OnClick", function(_, button)
    if InCombatLockdown() then return end
    if button == "RightButton" then
      showMenu()
    elseif overCrate() then
      ns.Panel.show("spares")
    elseif overCup() then
      ns.Panel.show("goals")
    else
      ns.Panel.toggle()
    end
  end)
  frame:SetScript("OnEnter", showTooltip)
  frame:SetScript("OnLeave", hideTooltip)
  frame:SetScript("OnHide", function()
    dropped()
    endScaling()
  end)
  local sinceRedraw = 0
  frame:SetScript("OnUpdate", function(_, elapsed)
    updateGrip()
    if tooltipFor ~= nil and GameTooltip:IsOwned(frame) then
      if pointedAt() ~= tooltipFor then showTooltip() end
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
    fighting = event == "PLAYER_REGEN_DISABLED"
    PocketCamp.refresh()
  end)
  fighting = InCombatLockdown() and true or false

  frame.band = ns.CampScene.new(frame, {
    target = ns.CampScene.FIGURE_TARGET, shadow = true, names = false, backdrop = ns.CampSheet.pocketBackdrop,
    crisp = false,
  })
  frame.band:SetAllPoints()
  createGrip()
end

function PocketCamp.refresh()
  if not core then return end
  view = core:pocketCamp()
  if not view then
    if frame then frame:Hide() end
    return
  end
  if not frame then create() end
  if view.inCombat == "hide" and fighting then
    frame:Hide()
    return
  end
  frame:SetAlpha(view.inCombat == "fade" and fighting and view.combatFade or 1)
  frame.band:SetBackdropAlpha(view.opacity)
  if frame.scaling then
    drawDragged()
  else
    fit(view.scale)
    place()
    frame.band:Draw(view)
  end
  frame:Show()
  if GameTooltip:IsOwned(frame) then showTooltip() end
end

function PocketCamp.settingChanged(key)
  if key == "camp" or key == "seasons" or key:find("^pocketCamp") then PocketCamp.refresh() end
end

function PocketCamp.animate(animation)
  if frame and frame:IsShown() then frame.band:Animate(animation.kind, animation.memberId) end
end

function PocketCamp.cheered(memberId)
  if frame and frame:IsShown() then frame.band:Hop(memberId) end
end

function PocketCamp.campReaction(reaction)
  if frame and frame:IsShown() then frame.band:React(reaction) end
end

function PocketCamp.start(theCore)
  core = theCore
  PocketCamp.refresh()
end
