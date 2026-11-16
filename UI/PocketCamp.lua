-- PocketCamp: the small on-screen Camp you can keep up while playing. It
-- draws Core's pocketCamp() with a CampScene band of its own: the fire and
-- the online Members, each doing what Core says they're doing, over a
-- soft-edged backdrop of the opacity Core gives, and for a while those who
-- just went offline, asleep in a bedroll. It shows no names: the mouse over a figure
-- shows that Member's Roster tooltip, and over the fire who is doing what.
-- A crate by the fire says Spare notices wait unseen, and a gold cup
-- over it that a Trophy was reached this session, as Core says. A click toggles
-- the panel, or on the crate opens the Spares tab and on the cup the
-- Trophies tab, and a right-click on another Member's figure opens its
-- menu (neither in combat), a drag moves it unless Core
-- says it's locked, and where it's dropped is saved through Core. It's as
-- wide as Core says, growing out from the fire as more of the Crew comes
-- online. Unlocked, a grip shows in its bottom right corner while the mouse
-- is over it: dragging it up or down scales it, sideways sets how wide it
-- can grow (shown at that width while dragged), and a double-click puts
-- both back. Core's pocketCampAnimation
-- events play on it, and a
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
-- The Member whose tooltip is up, "crate" or "cup" for theirs, false
-- for the Pocket Camp's own, nil while none is.
local tooltipFor

-- Its usual width (Core.CAMP_LAYOUT.pocketColumns) in UI units, at the
-- scale it's fitted to. Core's position is the bottom left corner it would
-- have at that width, so it stays put on the fire whatever width it is.
local function usualWidth()
  return ns.Core.CAMP_LAYOUT.pocketColumns * frame.band:Unit()
end

-- Saves where it is, as the bottom left of its usual width round the fire.
local function savePosition()
  local centre = (frame:GetLeft() + frame:GetRight()) / 2
  core:setPocketCampPosition(centre - usualWidth() / 2, frame:GetBottom())
end

-- Puts the frame where Core says: centred where it was dropped, or where
-- it starts.
local function place()
  if frame.moving or frame.scaling then return end
  frame:ClearAllPoints()
  if view.position then
    frame:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", view.position.x + usualWidth() / 2, view.position.y)
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
  savePosition()
  if view then place() end
end

-- Sizes the band for a scale (1 is the usual size) and a width in art
-- pixels (default Core's). The art pixel is exactly FIGURE_TARGET × scale
-- UI units, so it scales smoothly.
local function fit(scale, columns)
  frame.band:SetTarget(ns.CampScene.FIGURE_TARGET * scale)
  frame:SetSize(frame.band:Fit(columns or view.columns, view.rows))
end

-- The mouse in UI units from the screen's bottom left.
local function cursor()
  local x, y = GetCursorPosition()
  local scale = frame:GetEffectiveScale()
  return x / scale, y / scale
end

-- Its top and the fire's centre in UI units from the screen's bottom
-- left, so it grows and shrinks both ways from the fire.
local function pinTopCentre(centre, top)
  frame:ClearAllPoints()
  frame:SetPoint("TOP", UIParent, "BOTTOMLEFT", centre, top)
end

-- The scale and max width the grip is dragged to. Down makes it bigger, by
-- as much as the mouse moved against its height at the press, in whole
-- percents within Core's limits. Sideways adds or takes away room from the
-- max width at the press, a step (a seat each side) at a time: it grows
-- both ways from the fire, so the width changes by twice what the mouse
-- moved, keeping its right edge under the mouse.
local function draggedSize(drag)
  local x, y = cursor()
  local percent = math.floor(drag.start.scale * (drag.height + drag.y - y) / drag.height * 100 + 0.5)
  local scale = math.max(ns.Core.POCKET_CAMP_MIN_SCALE, math.min(ns.Core.POCKET_CAMP_MAX_SCALE, percent)) / 100
  local step = ns.Core.CAMP_LAYOUT.pocketStep
  local unit = ns.CampScene.FIGURE_TARGET * scale
  local steps = math.floor(2 * (x - drag.x) / unit / step + 0.5)
  return { scale = scale, columns = ns.Core.pocketCampWidth(drag.start.columns + steps * step) }
end

-- While the grip is dragged it's drawn at the size it's dragged to, round
-- the fire where it was at the press (read once, so the screen's clamp
-- can't feed back into the drag), and as wide as the max width being set,
-- so the room shows. Narrower than Core's view, figures past its edge are
-- cut off until the drag ends.
local function drawDragged()
  local size = frame.scaling.size
  fit(size.scale, size.columns)
  pinTopCentre(frame.scaling.centre, frame.scaling.top)
  frame.band:Draw(setmetatable({ columns = size.columns }, { __index = view }))
end

-- While the grip is dragged its tooltip says how big it is and how many
-- it has room for.
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

-- Starts a drag of the grip at the scale and max width Core has, drawn at
-- that max at once.
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

-- Ends a drag of the grip and saves the scale and how wide it can grow,
-- and where it is. It then fits the Crew online again, round the same
-- fire. A press that changed neither saves nothing.
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

-- The grip follows the mouse: shown over the Pocket Camp while it isn't
-- locked, and while it's being dragged, it redraws at the size it's dragged
-- to.
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

-- Back to the usual size and width, keeping its top and the fire where
-- they are.
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

-- The actor whose figure the mouse is over, or nil.
local function hovered()
  local x = cursor()
  return frame.band:ActorAt(x - frame:GetLeft())
end

-- Whether the mouse is over the crate.
local function overCrate()
  local x, y = cursor()
  return frame.band:CrateAt(x - frame:GetLeft(), y - frame:GetBottom())
end

-- Whether the mouse is over the trophy cup.
local function overCup()
  local x, y = cursor()
  return frame.band:CupAt(x - frame:GetLeft(), y - frame:GetBottom())
end

-- What the tooltip is for where the mouse is: "crate", "cup", a
-- Member's id, or false for the Pocket Camp's own.
local function pointedAt()
  if overCrate() then return "crate" end
  if overCup() then return "cup" end
  local actor = hovered()
  return actor and actor.memberId or false
end

-- Over the crate, how many Spare notices wait and that a click shows them;
-- over the cup, each Trophy reached this session and how long ago;
-- over a figure, that Member's tooltip as the Roster shows it, and "In
-- your group" when they are; over a bedroll, who is asleep and since when;
-- anywhere else, who is doing what.
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

-- Opens the world map on a map, guarded in case Forever lacks the helper.
local function openMap(mapId)
  if OpenWorldMap then
    OpenWorldMap(mapId)
  elseif WorldMapFrame then
    ShowUIPanel(WorldMapFrame)
    WorldMapFrame:SetMapID(mapId)
  end
end

-- A right-click on another Member's figure: Whisper and Invite (the
-- Roster's own), Show on map (greyed out with no known spot) and Open in
-- panel. Nothing on your own figure, a bedroll, the fire or empty space.
local function showMenu()
  local actor = not (overCrate() or overCup()) and hovered()
  local menu = actor and actor.menu
  if not menu then return end
  hideTooltip()
  MenuUtil.CreateContextMenu(frame, function(_, root)
    root:CreateTitle(menu.title)
    root:CreateButton("Whisper", function() ns.Panel.whisper(menu.fullName) end)
    root:CreateButton("Invite", function() ns.Panel.invite(menu.fullName) end)
    root:CreateButton("Show on map", function() openMap(menu.mapId) end):SetEnabled(menu.mapId ~= nil)
    root:CreateButton("Open in panel", function() ns.Panel.show("roster") end)
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
  -- The panel can't open in combat, so a click does nothing there, nor
  -- does a right-click open the menu. On the crate it opens the Spares
  -- tab, which marks the notices seen, and on the cup the Trophies tab.
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
  -- Hidden mid-drag (combat began): the drag still saves where it got to.
  frame:SetScript("OnHide", function()
    dropped()
    endScaling()
  end)
  local sinceRedraw = 0
  frame:SetScript("OnUpdate", function(_, elapsed)
    updateGrip()
    -- The tooltip follows the mouse from figure to figure, the crate and
    -- the cup.
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
    inCombat = event == "PLAYER_REGEN_DISABLED"
    PocketCamp.refresh()
  end)
  inCombat = InCombatLockdown() and true or false

  frame.band = ns.CampScene.new(frame, {
    target = ns.CampScene.FIGURE_TARGET, shadow = true, names = false, backdrop = ns.CampSheet.pocketBackdrop,
    -- Scales smoothly with the grip; whole screen pixels made it step.
    crisp = false,
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
  frame.band:SetBackdropAlpha(view.opacity)
  if frame.scaling then
    -- Mid-drag it keeps the size it's dragged to.
    drawDragged()
  else
    fit(view.scale)
    place()
    frame.band:Draw(view)
  end
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
