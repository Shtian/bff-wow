-- TogetherTab: the panel's Together tab, laid out from Core's together().
-- A toolbar ("As Gahzuria 24", what's hidden, Clear and Show), then a
-- 1–60 level line that scrolls sideways: friends' dots and labels above the
-- axis, a lane per dungeon bar that needs one below it, and an overview
-- strip under it to jump along. In type a step larger than the rest of the
-- panel, since it's read at a glance. Clicking friends picks them to see the dungeons you share,
-- and the Show menu filters the line. With the Camp on, friends are their
-- Camp heads on the line rather than dots. Core places and words everything;
-- this only draws it and keeps what's picked. See docs/design/together.md.

local _, ns = ...

local TogetherTab = {}
ns.TogetherTab = TogetherTab

local Skin = ns.Skin

local GOLD = Skin.GOLD
local TEXT = Skin.TEXT
local MUTED = Skin.MUTED
local DIM = Skin.DIM
local ONLINE = Skin.ONLINE
local OFFLINE = Skin.OFFLINE

-- The tab's two fonts, Skin's a step up from what the rest of the panel
-- uses: Core measures its "small" and "tiny" texts in these.
local SMALL = "text"
local TINY = "small"
local FONT_FOR = { small = SMALL, tiny = TINY }

local INSET = 12
local TOOLBAR = 32
local OVERVIEW = 22
-- Inside the line, from its top: the band's label, the label rows, the dot
-- rail, the axis and the dungeon lanes.
local ROW = 21
local ROWS_TOP = 20
local LABEL_HEIGHT = 20
local AXIS = 20
local LANE = 23
local BAR = 20
-- The online dot before an online friend's name, as the header's.
local ONLINE_DOT = 6
local DOT = 7
local RING = 2
local KEYLINE = 1
local WHEEL_STEP = 48
local DASH = 3
-- A press that moves the cursor less than this is a click, not a drag.
local CLICK_SLOP = 4
-- What a selection fades: unpicked friends and dungeons not shared.
local FADED = 0.3
local SHARED = { 1, 1, 1, 0.6 }
local MENU_WIDTH = 240
local MENU_PAD = 10
-- Every other ten levels' wash, your level's line down through the lanes,
-- and the hover guide.
local DECADE = Skin.warm(0.022)
local YOU_LINE = Skin.warm(0.28)
local GUIDE = Skin.warm(0.16)
-- A bar's plate: its fill and 2px end caps, by whether you fit it, have
-- outlevelled it or neither. What's outlevelled sinks back.
local PLATE = { fits = 0.12, past = 0.025, other = 0.05 }
local CAP = { fits = 0.45, past = 0.07, other = 0.14 }
local CAP_WIDTH = 2
-- A bar's name starts this far in, clear of its cap.
local NAME_INSET = 6
local PAST_ALPHA = 0.7
-- A hovered bar's range, marked on the axis.
local RANGE_SHADE = { 1, 1, 1, 0.1 }
local RANGE_EDGE = { 1, 1, 1, 0.55 }
-- With the Camp on: a head stands on the rail, a 2px ground line under it.
local HEAD_GAP = 4
local GROUND = 2
-- The overview's minimap: decade marks and how far down the lanes go.
local OVERVIEW_MARK = Skin.warm(0.12)
local OVERVIEW_NUMBER = Skin.warm(0.3)
local OVERVIEW_LANES = 9

local view
local core
-- Whether the Camp is on: friends show as its heads (the Lit Camp Rule).
local lit = false
-- The Members picked on the line, as memberIds; Core drops any it doesn't
-- know.
local selected = {}
-- Bars by frame, for the sticky names while scrolling.
local barFrames = {}
local labelFrames, dotFrames, stemTextures = {}, {}, {}
local tickTextures, numberLabels, overviewTicks = {}, {}, {}
local headFrames, decadeTextures, overviewLines = {}, {}, {}
local overviewMarks, overviewNumbers = {}, {}

local function classHex(classFilename)
  local r, g, b = Skin.classColor(classFilename)
  return Skin.hex({ r, g, b })
end

local function colored(text, color)
  return Skin.hex(color) .. text .. "|r"
end

local function hideFrom(list, from)
  for i = from, #list do list[i]:Hide() end
end

-- A text's width in Skin's font, for Core's placement.
local measurers = {}
local function measure(text, font)
  local label = measurers[font]
  if not label then
    label = Skin.label(view, FONT_FOR[font])
    label:Hide()
    measurers[font] = label
  end
  label:SetText(text)
  return math.ceil(label:GetStringWidth())
end

local function layout()
  return ns.Core.TOGETHER_LAYOUT
end

-- Only the label rows in use take room; the rest goes to the lanes.
local function rows()
  return view.data and view.data.rows or layout().rows
end

-- Rows count up from the axis; y is from the line's top.
local function rowY(row)
  return ROWS_TOP + (rows() - row) * ROW
end

-- The rail: dots' centres, or the ground heads stand on.
local function headHeight()
  return lit and math.ceil(ns.CampScene.HEAD_ROWS * ns.CampScene.artUnit(view, ns.CampScene.FIGURE_TARGET)) or 0
end

local function railY()
  if lit then return ROWS_TOP + rows() * ROW + HEAD_GAP + headHeight() end
  return ROWS_TOP + rows() * ROW + 6
end

local function axisY()
  return railY() + (lit and 8 or 14)
end

local function laneY(lane)
  return axisY() + AXIS + 6 + (lane - 1) * LANE
end

-- Tooltips anchor to the right of what's hovered, as small controls' do.
local function showTooltip(owner)
  if not owner.tooltip then return end
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  owner.tooltip(owner)
  GameTooltip:Show()
end

local function hideTooltip()
  GameTooltip:Hide()
end

local function line(text, color)
  color = color or TEXT
  GameTooltip:AddLine(text, color[1], color[2], color[3])
end

-- A Character's line: the Character (full name, level and the extra
-- parts) on the left, whose they are on the right, so the two names never
-- run together.
local function characterLine(character, extra)
  local parts = {
    classHex(character.classFilename) .. character.fullName .. "|r",
    colored(tostring(character.level), MUTED),
  }
  for _, part in ipairs(extra) do parts[#parts + 1] = part end
  GameTooltip:AddDoubleLine(table.concat(parts, " "), character.member, 1, 1, 1, DIM[1], DIM[2], DIM[3])
end

local function groupTooltip(owner)
  for _, character in ipairs(owner.group.characters) do
    local parts = {}
    if character.alt then parts[#parts + 1] = colored("alt", DIM) end
    if character.online and not character.own then parts[#parts + 1] = colored("online", ONLINE) end
    if character.canPlay then
      parts[#parts + 1] = colored(character.apart, GOLD)
    elseif character.apart then
      parts[#parts + 1] = colored(character.apart, DIM)
    end
    characterLine(character, parts)
  end
end

local function dungeonTooltip(owner)
  local tooltip = owner.bar.tooltip
  GameTooltip:AddLine(tooltip.title, 1, 1, 1)
  if tooltip.detail then line(tooltip.detail, DIM) end
  if tooltip.forever then line(tooltip.forever, MUTED) end
  for _, raid in ipairs(tooltip.raids or {}) do
    line(colored(raid.name, TEXT) .. " " .. colored(raid.detail, DIM)
      .. (raid.forever and " " .. Skin.foreverGlyph(MUTED) or ""))
  end
  line(tooltip.you, tooltip.fits and TEXT or DIM)
  for _, fitter in ipairs(tooltip.fitters) do
    local parts = {}
    if fitter.online then parts[#parts + 1] = colored("online", ONLINE) end
    if fitter.far then parts[#parts + 1] = colored("· " .. fitter.far, DIM) end
    characterLine(fitter, parts)
  end
  if tooltip.none then line(tooltip.none, DIM) end
  if tooltip.almost then line(tooltip.almost, DIM) end
end

local function redraw()
  if view then TogetherTab.draw(view:GetParent(), core, lit) end
end

local function pick(memberIds, add)
  selected = ns.Core.selectTogether(selected, memberIds, add)
  redraw()
end

local function clearSelection()
  if #selected == 0 then return end
  selected = {}
  redraw()
end

-- Dragging the line moves along the levels; anything on it passes its
-- mouse-down on, so a drag can start on a bar or a label. A press that
-- doesn't move is a click: on a friend it picks them, on the line's empty
-- space it clears what's picked.
local function scrollTo(x)
  local scroller = view.scroller
  local range = math.max(0, view.track:GetWidth() - scroller:GetWidth())
  scroller:SetHorizontalScroll(math.min(range, math.max(0, x)))
  TogetherTab.scrolled()
end

local function cursorX()
  return GetCursorPosition() / view.scroller:GetEffectiveScale()
end

local function cursorY()
  local _, y = GetCursorPosition()
  return y / view.scroller:GetEffectiveScale()
end

-- Up and down, when the lanes are taller than the window.
local function scrollDownTo(y)
  local range = math.max(0, view.track:GetHeight() - view.scroller:GetHeight())
  view.scroller:SetVerticalScroll(math.min(range, math.max(0, y)))
end

local function startDrag()
  view.dragFrom = cursorX()
  view.dragFromY = cursorY()
  view.pressFrom = view.dragFrom
  view.dragScroll = view.scroller:GetHorizontalScroll()
  view.dragScrollY = view.scroller:GetVerticalScroll()
end

local function stopDrag()
  view.dragFrom = nil
end

local function endPress(frame, button)
  local pressFrom = view.pressFrom
  view.pressFrom = nil
  stopDrag()
  if button ~= "LeftButton" or not pressFrom or not frame.onClick then return end
  if math.abs(cursorX() - pressFrom) < CLICK_SLOP then frame.onClick(frame) end
end

local function passDrag(frame)
  frame:SetScript("OnMouseDown", startDrag)
  frame:SetScript("OnMouseUp", endPress)
end

local function centreOnYou()
  if not view.data then return end
  scrollTo(view.data.you - view.scroller:GetWidth() / 2)
end

local function hoverable(parent, tooltip)
  local frame = CreateFrame("Frame", nil, parent)
  frame:EnableMouse(true)
  frame.tooltip = tooltip
  frame:SetScript("OnEnter", showTooltip)
  frame:SetScript("OnLeave", hideTooltip)
  passDrag(frame)
  return frame
end

-- A dashed 1px edge round a frame, for the attunement.
local function dashes(frame, width, height)
  frame.dashes = frame.dashes or {}
  local count = 0
  local function dash(x, y, w, h)
    count = count + 1
    local texture = frame.dashes[count]
    if not texture then
      texture = frame:CreateTexture(nil, "BORDER")
      frame.dashes[count] = texture
    end
    texture:SetColorTexture(1, 1, 1, frame.bar and frame.bar.fits and 0.5 or 0.25)
    texture:ClearAllPoints()
    texture:SetPoint("TOPLEFT", x, -y)
    texture:SetSize(w, h)
    texture:Show()
  end
  for x = 0, width - 1, 2 * DASH do
    local w = math.min(DASH, width - x)
    dash(x, 0, w, 1)
    dash(x, height - 1, w, 1)
  end
  for y = 0, height - 1, 2 * DASH do
    local h = math.min(DASH, height - y)
    dash(0, y, 1, h)
    dash(width - 1, y, 1, h)
  end
  hideFrom(frame.dashes, count + 1)
end

-- Hovering a friend lights up their Members' other labels on the line.
local function lightOtherLabels(group)
  local ids = {}
  for _, id in ipairs(group and group.memberIds or {}) do ids[id] = true end
  for _, label in ipairs(labelFrames) do
    local kin = false
    if group and label:IsShown() and label.group ~= group then
      for _, id in ipairs(label.group.memberIds) do
        if ids[id] then kin = true end
      end
    end
    label.kin:SetShown(kin)
  end
end

-- A group's dot or label: a tooltip, lights up their other labels, and
-- picks them on click (shift adds).
local function memberFrame()
  local frame = hoverable(view.track, groupTooltip)
  frame:SetScript("OnEnter", function(self)
    showTooltip(self)
    lightOtherLabels(self.group)
  end)
  frame:SetScript("OnLeave", function()
    hideTooltip()
    lightOtherLabels(nil)
  end)
  frame.onClick = function(self) pick(self.group.memberIds, IsShiftKeyDown()) end
  return frame
end

-- The Show menu: Core's options as checkboxes, the key and the help line.
-- Built once from the first together().show; draws its values each time.
local function keySwatch(parent, kind)
  local swatch = CreateFrame("Frame", nil, parent)
  swatch:SetSize(22, 9)
  if kind == "fits" then
    Skin.fill(swatch, { 1, 1, 1, 0.12 })
    local underline = Skin.fill(swatch, Skin.BAR, "BORDER")
    underline:ClearAllPoints()
    underline:SetPoint("BOTTOMLEFT")
    underline:SetPoint("BOTTOMRIGHT")
    underline:SetHeight(2)
  elseif kind == "attunement" then
    swatch.dashed = true
  elseif kind == "forever" then
    Skin.foreverMark(swatch):SetPoint("LEFT")
  elseif kind == "fitters" then
    for i, classFilename in ipairs({ "DRUID", "ROGUE" }) do
      local dot = swatch:CreateTexture(nil, "ARTWORK")
      dot:SetSize(6, 6)
      dot:SetColorTexture(1, 1, 1, 1)
      dot:SetVertexColor(Skin.classColor(classFilename))
      dot:SetPoint("LEFT", (i - 1) * 8, 0)
      Skin.round(swatch, dot)
    end
  end
  return swatch
end

local function createMenu(show)
  local menu = CreateFrame("Frame", nil, view)
  menu:SetWidth(MENU_WIDTH)
  menu:SetPoint("TOPRIGHT", view.showButton, "BOTTOMRIGHT", 0, -2)
  menu:SetFrameLevel(view:GetFrameLevel() + 30)
  menu:EnableMouse(true)
  Skin.fill(menu, { Skin.WINDOW[1], Skin.WINDOW[2], Skin.WINDOW[3], 1 })
  Skin.border(menu, { 1, 1, 1, 0.18 })
  menu.checks = {}
  local y = 6
  local function heading(text)
    local label = Skin.label(menu, "label", MUTED)
    label:SetPoint("TOPLEFT", MENU_PAD, -(y + 6))
    label:SetText(text)
    local rule = Skin.fill(menu, Skin.LINE, "BORDER")
    rule:ClearAllPoints()
    rule:SetHeight(1)
    rule:SetPoint("LEFT", label, "RIGHT", 6, 0)
    rule:SetPoint("RIGHT", menu, "RIGHT", -MENU_PAD, 0)
    y = y + 22
  end
  for _, section in ipairs(show.sections) do
    heading(section.title)
    for _, option in ipairs(section.options) do
      local key = option.key
      local check = Skin.checkbox(menu, option.label, function(self)
        core:setSetting(key, self:GetChecked() and true or false)
        redraw()
      end)
      check.label:SetFontObject(Skin.fonts[SMALL])
      check:SetHitRectInsets(0, -(check.label:GetStringWidth() + 6), 0, 0)
      check:SetPoint("TOPLEFT", MENU_PAD, -(y + 4))
      menu.checks[key] = check
      y = y + 24
    end
  end
  heading(show.key.title)
  for _, item in ipairs(show.key.items) do
    local swatch = keySwatch(menu, item.kind)
    swatch:SetPoint("TOPLEFT", MENU_PAD, -(y + 4))
    if swatch.dashed then dashes(swatch, 22, 9) end
    local label = Skin.label(menu, SMALL, MUTED)
    label:SetPoint("LEFT", swatch, "RIGHT", 7, 0)
    label:SetText(item.text)
    y = y + 20
  end
  local help = Skin.label(menu, SMALL, DIM)
  help:SetPoint("TOPLEFT", MENU_PAD, -(y + 6))
  help:SetWidth(MENU_WIDTH - 2 * MENU_PAD)
  help:SetText(show.help)
  menu:SetHeight(y + 6 + help:GetStringHeight() + 10)

  -- A click anywhere outside it, but on the Show button, closes it.
  menu:SetScript("OnShow", function(self) self:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
  menu:SetScript("OnHide", function(self)
    self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
    TogetherTab.escapeKeys()
  end)
  menu:SetScript("OnEvent", function(self)
    if not self:IsMouseOver() and not view.showButton:IsMouseOver() then self:Hide() end
  end)
  menu:Hide()
  return menu
end

local function drawMenu(show)
  if not view.menu then view.menu = createMenu(show) end
  for _, section in ipairs(show.sections) do
    for _, option in ipairs(section.options) do view.menu.checks[option.key]:SetChecked(option.value) end
  end
end

local function toggleMenu()
  if not view.menu then return end
  view.menu:SetShown(not view.menu:IsShown())
  TogetherTab.escapeKeys()
end

-- Escape closes the menu, else clears what's picked. The tab only takes
-- the keyboard while there's one of those to undo, and never in combat,
-- where it can't let other keys through.
local function createEscapeKeys()
  local keys = CreateFrame("Frame", nil, view)
  keys:SetScript("OnKeyDown", function(self, key)
    if InCombatLockdown() then return end
    if key ~= "ESCAPE" then
      self:SetPropagateKeyboardInput(true)
      return
    end
    self:SetPropagateKeyboardInput(false)
    if view.menu and view.menu:IsShown() then
      view.menu:Hide()
    else
      clearSelection()
    end
    TogetherTab.escapeKeys()
  end)
  -- Let go before combat locks it in; take it back after.
  keys:RegisterEvent("PLAYER_REGEN_DISABLED")
  keys:RegisterEvent("PLAYER_REGEN_ENABLED")
  keys:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_REGEN_DISABLED" then
      self:SetPropagateKeyboardInput(true)
      self:EnableKeyboard(false)
    else
      TogetherTab.escapeKeys()
    end
  end)
  return keys
end

function TogetherTab.escapeKeys()
  if not view or InCombatLockdown() then return end
  local active = view:IsVisible() and ((view.menu and view.menu:IsShown()) or #selected > 0)
  view.escapeKeys:SetPropagateKeyboardInput(true)
  view.escapeKeys:EnableKeyboard(active and true or false)
end

local function createView(parent)
  view = CreateFrame("Frame", nil, parent)
  view:SetAllPoints()

  -- Toolbar: who you play as, and what's hidden.
  view.toolbar = CreateFrame("Frame", nil, view)
  view.toolbar:SetPoint("TOPLEFT")
  view.toolbar:SetPoint("TOPRIGHT")
  view.toolbar:SetHeight(TOOLBAR)
  Skin.edge(view.toolbar, "BOTTOM", Skin.LINE)
  view.as = Skin.label(view.toolbar, SMALL, MUTED)
  view.as:SetPoint("LEFT", INSET, 0)
  view.asAlt = Skin.badge(view.toolbar, TINY, MUTED)
  view.asAlt:SetPoint("LEFT", view.as, "RIGHT", 4, 0)
  view.asAlt:SetText("alt")
  view.showButton = Skin.button(view.toolbar, "Show", toggleMenu)
  view.showButton:SetHeight(22)
  view.showButton.label:SetFontObject(Skin.fonts[SMALL])
  view.showButton.iconRoom = Skin.leadIcon(view.showButton, "filter", TEXT)
  view.showButton:SetPoint("RIGHT", -8, 0)
  -- Clear, while friends are picked, left of Show.
  view.clear = Skin.button(view.toolbar, "Clear", clearSelection)
  view.clear:SetHeight(22)
  view.clear.label:SetFontObject(Skin.fonts[SMALL])
  view.clear:SetPoint("RIGHT", view.showButton, "LEFT", -6, 0)
  view.hidden = Skin.label(view.toolbar, SMALL, DIM)
  view.hidden:SetJustifyH("RIGHT")

  -- The overview strip.
  view.overview = CreateFrame("Frame", nil, view)
  view.overview:SetPoint("BOTTOMLEFT")
  view.overview:SetPoint("BOTTOMRIGHT")
  view.overview:SetHeight(OVERVIEW)
  Skin.edge(view.overview, "TOP", Skin.LINE)
  view.strip = CreateFrame("Frame", nil, view.overview)
  view.strip:SetPoint("LEFT", INSET, 0)
  view.strip:SetPoint("RIGHT", -INSET, 0)
  view.strip:SetHeight(OVERVIEW - 4)
  view.strip:EnableMouse(true)
  -- The can-play band, as on the line.
  view.stripBand = Skin.fill(view.strip, Skin.alpha(GOLD, 0.12), "BACKGROUND", 1)
  view.stripBand:ClearAllPoints()
  view.stripBandEdges = {}
  for i = 1, 2 do
    local edge = Skin.fill(view.strip, Skin.alpha(GOLD, 0.5), "BORDER")
    edge:ClearAllPoints()
    edge:SetWidth(1)
    view.stripBandEdges[i] = edge
  end
  view.stripYou = Skin.fill(view.strip, GOLD, "OVERLAY")
  view.stripYou:ClearAllPoints()
  view.stripYou:SetSize(2, OVERVIEW - 8)
  view.stripWindow = CreateFrame("Frame", nil, view.strip)
  view.stripWindow:SetHeight(OVERVIEW - 6)
  Skin.fill(view.stripWindow, Skin.warm(0.04))
  Skin.border(view.stripWindow, Skin.warm(0.35))
  local function jump()
    local scale = view.strip:GetEffectiveScale()
    local x = GetCursorPosition() / scale - view.strip:GetLeft()
    local share = math.min(1, math.max(0, x / view.strip:GetWidth()))
    scrollTo(share * view.track:GetWidth() - view.scroller:GetWidth() / 2)
  end
  view.strip:SetScript("OnMouseDown", function(self)
    self.dragging = true
    jump()
  end)
  view.strip:SetScript("OnMouseUp", function(self) self.dragging = false end)
  view.strip:SetScript("OnUpdate", function(self)
    if self.dragging then
      if IsMouseButtonDown("LeftButton") then jump() else self.dragging = false end
    end
  end)

  -- The line itself.
  view.scroller = CreateFrame("ScrollFrame", nil, view)
  view.scroller:SetPoint("TOPLEFT", 0, -TOOLBAR)
  view.scroller:SetPoint("BOTTOMRIGHT", 0, OVERVIEW)
  view.scroller:SetClipsChildren(true)
  view.scroller:EnableMouse(true)
  view.scroller:EnableMouseWheel(true)
  view.track = CreateFrame("Frame", nil, view.scroller)
  view.track:SetSize(1, 1)
  view.scroller:SetScrollChild(view.track)
  view.scroller:SetScript("OnMouseWheel", function(self, delta)
    scrollTo(self:GetHorizontalScroll() - delta * WHEEL_STEP)
  end)
  passDrag(view.scroller)
  view.scroller.onClick = clearSelection
  view.scroller:SetScript("OnUpdate", function()
    TogetherTab.hovered()
    if not view.dragFrom then return end
    if not IsMouseButtonDown("LeftButton") then
      stopDrag()
      return
    end
    scrollTo(view.dragScroll - (cursorX() - view.dragFrom))
    scrollDownTo(view.dragScrollY + (cursorY() - view.dragFromY))
  end)

  -- The can-play band: a faint gold fill with 1px edges.
  view.band = view.track:CreateTexture(nil, "BACKGROUND")
  view.band:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.04)
  view.bandLeft = view.track:CreateTexture(nil, "BORDER")
  view.bandLeft:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.45)
  view.bandLeft:SetWidth(1)
  view.bandRight = view.track:CreateTexture(nil, "BORDER")
  view.bandRight:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.45)
  view.bandRight:SetWidth(1)
  view.bandLabel = Skin.label(view.track, TINY, GOLD)

  -- Your level, down from the axis through the lanes: a bar it crosses is
  -- one you fit.
  view.youLine = view.track:CreateTexture(nil, "BORDER", nil, 1)
  view.youLine:SetColorTexture(unpack(YOU_LINE))
  view.youLine:SetWidth(1)

  -- The hover guide: a line at the level under the cursor, and what it
  -- says on the axis.
  view.guide = view.track:CreateTexture(nil, "BORDER", nil, 2)
  view.guide:SetColorTexture(unpack(GUIDE))
  view.guide:SetWidth(1)
  view.guide:Hide()
  view.guideTag = Skin.badge(view.track, TINY, TEXT, Skin.RAISED)
  view.guideTag:SetHeight(16)
  Skin.border(view.guideTag, Skin.BORDER)
  view.guideTag:SetFrameLevel(view.track:GetFrameLevel() + 20)
  view.guideTag:Hide()

  -- The axis.
  view.axis = view.track:CreateTexture(nil, "BACKGROUND", nil, 1)
  view.axis:SetColorTexture(unpack(Skin.SIDEBAR))
  view.axisTop = view.track:CreateTexture(nil, "BORDER")
  view.axisTop:SetColorTexture(Skin.BORDER[1], Skin.BORDER[2], Skin.BORDER[3], Skin.BORDER[4])
  view.axisTop:SetHeight(1)
  view.axisBottom = view.track:CreateTexture(nil, "BORDER")
  view.axisBottom:SetColorTexture(Skin.BORDER[1], Skin.BORDER[2], Skin.BORDER[3], Skin.BORDER[4])
  view.axisBottom:SetHeight(1)
  -- Your level on the axis: a light flag with the number on it.
  view.youFlag = Skin.badge(view.track, TINY, Skin.WINDOW, Skin.TEXT)
  view.youFlag:SetHeight(15)
  view.youFlag:SetFrameLevel(view.track:GetFrameLevel() + 15)
  -- A hovered bar's range on the axis.
  view.rangeShade = CreateFrame("Frame", nil, view.track)
  view.rangeShade:SetHeight(AXIS)
  view.rangeShade:SetFrameLevel(view.track:GetFrameLevel() + 14)
  Skin.fill(view.rangeShade, RANGE_SHADE)
  for _, side in ipairs({ "LEFT", "RIGHT" }) do Skin.edge(view.rangeShade, side, RANGE_EDGE) end
  view.rangeShade:Hide()

  -- Back to you, when you've scrolled away.
  view.backLeft = Skin.button(view, "‹ You", centreOnYou)
  view.backLeft:SetHeight(22)
  view.backLeft.label:SetFontObject(Skin.fonts[SMALL])
  view.backLeft:SetPoint("TOPLEFT", view.scroller, "TOPLEFT", 6, -4)
  view.backLeft:SetFrameLevel(view.scroller:GetFrameLevel() + 10)
  view.backRight = Skin.button(view, "You ›", centreOnYou)
  view.backRight:SetHeight(22)
  view.backRight.label:SetFontObject(Skin.fonts[SMALL])
  view.backRight:SetPoint("TOPRIGHT", view.scroller, "TOPRIGHT", -6, -4)
  view.backRight:SetFrameLevel(view.scroller:GetFrameLevel() + 10)

  -- With only near your level on: what's said over a stretch of the line
  -- with no dungeons, and the link that turns the filter off.
  view.empty = CreateFrame("Frame", nil, view)
  view.empty:SetSize(1, 16)
  view.empty:SetFrameLevel(view.scroller:GetFrameLevel() + 10)
  view.emptyText = Skin.label(view.empty, SMALL, DIM)
  view.emptyText:SetPoint("LEFT")
  view.emptyAction = CreateFrame("Button", nil, view.empty)
  view.emptyAction:SetHeight(16)
  view.emptyAction:SetPoint("LEFT", view.emptyText, "RIGHT", 0, 0)
  view.emptyAction.label = Skin.label(view.emptyAction, SMALL, MUTED)
  view.emptyAction.label:SetPoint("LEFT")
  view.emptyAction:SetScript("OnEnter", function(self) Skin.color(self.label, TEXT) end)
  view.emptyAction:SetScript("OnLeave", function(self) Skin.color(self.label, MUTED) end)
  view.emptyAction:SetScript("OnClick", function()
    if not view.data or not view.data.empty then return end
    core:setSetting(view.data.empty.setting, false)
    redraw()
    centreOnYou()
  end)
  view.empty:Hide()

  view.escapeKeys = createEscapeKeys()
  view:SetScript("OnHide", function()
    if view.menu then view.menu:Hide() end
    TogetherTab.escapeKeys()
  end)
end

local function at(region, x, y, width, height)
  region:ClearAllPoints()
  region:SetPoint("TOPLEFT", view.track, "TOPLEFT", x, -y)
  if width then region:SetWidth(width) end
  if height then region:SetHeight(height) end
end

local function drawAxis(data)
  -- Tall enough for every lane; taller than the window, it pans up and
  -- down too.
  local trackHeight = math.max(view.scroller:GetHeight(), laneY(data.lanes) + BAR + 8)
  view.track:SetSize(data.width, trackHeight)
  scrollDownTo(view.scroller:GetVerticalScroll())

  at(view.band, data.band.left, 0, data.band.right - data.band.left, trackHeight)
  at(view.bandLeft, data.band.left, 0, nil, trackHeight)
  at(view.bandRight, data.band.right - 1, 0, nil, trackHeight)
  at(view.bandLabel, data.band.left + 5, 3)
  view.bandLabel:SetText(data.band.text)

  for i, decade in ipairs(data.decades) do
    local texture = decadeTextures[i]
    if not texture then
      texture = view.track:CreateTexture(nil, "BACKGROUND", nil, -1)
      texture:SetColorTexture(unpack(DECADE))
      decadeTextures[i] = texture
    end
    at(texture, decade.left, 0, decade.right - decade.left, trackHeight)
    texture:Show()
  end
  hideFrom(decadeTextures, #data.decades + 1)

  local y = axisY()
  at(view.axis, 0, y, data.width, AXIS)
  at(view.axisTop, 0, y, data.width)
  at(view.axisBottom, 0, y + AXIS - 1, data.width)
  at(view.youLine, data.you, y + AXIS, 1, trackHeight - y - AXIS)
  at(view.guide, 0, 0, 1, trackHeight)
  view.youFlag:SetText(data.as.level)
  view.youFlag:ClearAllPoints()
  view.youFlag:SetPoint("TOP", view.track, "TOPLEFT", data.you, -(y + 2))

  local numbers = 0
  for i, tick in ipairs(data.ticks) do
    local texture = tickTextures[i]
    if not texture then
      texture = view.track:CreateTexture(nil, "ARTWORK")
      texture:SetWidth(1)
      tickTextures[i] = texture
    end
    texture:SetColorTexture(1, 1, 1, tick.big and 0.4 or 0.16)
    at(texture, tick.x, y, 1, tick.big and 5 or 3)
    texture:Show()
    -- Your level's number is on its flag.
    if tick.number and not tick.you then
      numbers = numbers + 1
      local label = numberLabels[numbers]
      if not label then
        label = Skin.label(view.track, TINY)
        numberLabels[numbers] = label
      end
      label:SetText(tick.level)
      Skin.color(label, MUTED)
      label:ClearAllPoints()
      label:SetPoint("TOP", view.track, "TOPLEFT", tick.x, -(y + 4))
      label:Show()
    end
  end
  hideFrom(tickTextures, #data.ticks + 1)
  hideFrom(numberLabels, numbers + 1)
end

local function createDotFrame()
  local frame = memberFrame()
  local size = DOT + 2 * (RING + KEYLINE)
  frame:SetSize(size + 4, size + 4)
  frame.outline = frame:CreateTexture(nil, "ARTWORK", nil, 0)
  frame.outline:SetSize(size + 2, size + 2)
  frame.outline:SetPoint("CENTER")
  frame.outline:SetColorTexture(1, 1, 1, 0.7)
  Skin.round(frame, frame.outline)
  frame.keyline = frame:CreateTexture(nil, "ARTWORK", nil, 1)
  frame.keyline:SetSize(size, size)
  frame.keyline:SetPoint("CENTER")
  frame.keyline:SetColorTexture(Skin.WINDOW[1], Skin.WINDOW[2], Skin.WINDOW[3], 1)
  Skin.round(frame, frame.keyline)
  frame.ring = frame:CreateTexture(nil, "ARTWORK", nil, 2)
  frame.ring:SetSize(DOT + 2 * RING, DOT + 2 * RING)
  frame.ring:SetPoint("CENTER")
  frame.ring:SetColorTexture(1, 1, 1, 1)
  Skin.round(frame, frame.ring)
  frame.dot = frame:CreateTexture(nil, "ARTWORK", nil, 3)
  frame.dot:SetSize(DOT, DOT)
  frame.dot:SetPoint("CENTER")
  frame.dot:SetColorTexture(1, 1, 1, 1)
  Skin.round(frame, frame.dot)
  frame.count = Skin.badge(frame, TINY, TEXT, Skin.RAISED)
  frame.count:SetPoint("BOTTOMLEFT", frame, "CENTER", 4, 3)
  return frame
end

-- With the Camp on, a friend's Camp head on the rail, a ground line under
-- it: green while someone there is played, light for yours, else grey.
local function createHeadFrame()
  local frame = memberFrame()
  frame.head = ns.CampScene.head(frame)
  frame.head:SetPoint("BOTTOM", 0, GROUND + 1)
  frame.ground = frame:CreateTexture(nil, "ARTWORK")
  frame.ground:SetHeight(GROUND)
  frame.ground:SetColorTexture(1, 1, 1, 1)
  frame.count = Skin.badge(frame, TINY, TEXT, Skin.RAISED)
  frame.count:SetPoint("BOTTOMLEFT", frame.head, "TOPRIGHT", -2, -4)
  return frame
end

local function createLabelFrame()
  local frame = memberFrame()
  frame:SetHeight(LABEL_HEIGHT)
  frame.hover = Skin.fill(frame, Skin.LINE, "HIGHLIGHT")
  frame.kin = Skin.fill(frame, Skin.LINE)
  frame.kin:Hide()
  frame.online = frame:CreateTexture(nil, "ARTWORK")
  frame.online:SetSize(ONLINE_DOT, ONLINE_DOT)
  frame.online:SetColorTexture(1, 1, 1, 1)
  Skin.color(frame.online, ONLINE)
  Skin.round(frame, frame.online)
  frame.online:SetPoint("LEFT", 4, 0)
  frame.name = Skin.label(frame, SMALL, TEXT)
  frame.name:SetWordWrap(false)
  frame.alt = Skin.badge(frame, TINY, MUTED)
  frame.alt:SetText("alt")
  frame.level = Skin.label(frame, TINY, MUTED)
  frame.more = Skin.label(frame, SMALL, MUTED)
  return frame
end

local function drawGroups(data)
  local rail = railY()
  local stems = 0
  for i, group in ipairs(data.groups) do
    local pin
    if lit then
      pin = headFrames[i] or createHeadFrame()
      headFrames[i] = pin
      pin.head:SetClass(group.classFilename)
      local width = pin.head:GetWidth()
      pin:SetSize(width, pin.head:GetHeight() + GROUND + 1)
      pin:ClearAllPoints()
      pin:SetPoint("BOTTOM", view.track, "TOPLEFT", group.x, -(rail + GROUND + 1))
      pin.ground:ClearAllPoints()
      pin.ground:SetPoint("BOTTOMLEFT", 3, 0)
      pin.ground:SetPoint("BOTTOMRIGHT", -3, 0)
      Skin.color(pin.ground, group.own and TEXT or (group.online and ONLINE or OFFLINE))
      if dotFrames[i] then dotFrames[i]:Hide() end
    else
      pin = dotFrames[i] or createDotFrame()
      dotFrames[i] = pin
      pin:ClearAllPoints()
      pin:SetPoint("CENTER", view.track, "TOPLEFT", group.x, -rail)
      pin.dot:SetVertexColor(Skin.classColor(group.classFilename))
      Skin.color(pin.ring, group.online and ONLINE or OFFLINE)
      pin.outline:SetShown(group.own)
      if headFrames[i] then headFrames[i]:Hide() end
    end
    pin.group = group
    pin.count:SetShown(group.row == nil and group.count > 1)
    pin.count:SetText(group.count)
    pin:SetAlpha(group.faded and FADED or 1)
    pin:Show()

    local label = labelFrames[i] or createLabelFrame()
    labelFrames[i] = label
    label.group = group
    if group.row then
      local y = rowY(group.row)
      at(label, group.labelX, y, group.labelWidth)
      local online = group.online and not group.own
      label.online:SetShown(online)
      label.name:ClearAllPoints()
      label.name:SetPoint("LEFT", online and layout().online + 3 or 3, 0)
      label.name:SetText(group.label)
      label.name:SetWidth(math.min(label.name:GetUnboundedStringWidth(), layout().nameWidth))
      local anchor = label.name
      label.alt:SetShown(group.alt)
      if group.alt then
        label.alt:ClearAllPoints()
        label.alt:SetPoint("LEFT", anchor, "RIGHT", 4, 0)
        anchor = label.alt
      end
      label.level:ClearAllPoints()
      label.level:SetPoint("LEFT", anchor, "RIGHT", 4, 0)
      label.level:SetText(group.level)
      label.more:ClearAllPoints()
      label.more:SetPoint("LEFT", label.level, "RIGHT", 3, 0)
      label.more:SetText(group.more > 0 and "+" .. group.more or "")
      label.kin:Hide()
      label:SetAlpha(group.faded and FADED or 1)
      label:Show()

      stems = stems + 1
      local stem = stemTextures[stems]
      if not stem then
        stem = view.track:CreateTexture(nil, "BORDER")
        stem:SetColorTexture(1, 1, 1, 0.14)
        stemTextures[stems] = stem
      end
      local top = lit and rail - headHeight() - 2 or rail - 3
      at(stem, group.x, y + LABEL_HEIGHT - 2, 1, math.max(1, top - y - LABEL_HEIGHT))
      stem:SetAlpha(group.faded and FADED or 1)
      stem:Show()
    else
      label:Hide()
    end
  end
  hideFrom(dotFrames, lit and 1 or #data.groups + 1)
  hideFrom(headFrames, lit and #data.groups + 1 or 1)
  hideFrom(labelFrames, #data.groups + 1)
  hideFrom(stemTextures, stems + 1)
end

-- A hovered bar marks its range on the axis.
local function showRange(frame)
  local bar = frame.bar
  view.rangeShade:ClearAllPoints()
  view.rangeShade:SetPoint("TOPLEFT", view.track, "TOPLEFT", bar.x, -axisY())
  view.rangeShade:SetWidth(math.max(2, bar.range))
  view.rangeShade:Show()
end

-- A bar: its plate is the dungeon's level range, with 2px end caps; its
-- name and dots run on past the plate when they're wider than it.
local function createBarFrame()
  local frame = hoverable(view.track, dungeonTooltip)
  frame:SetHeight(BAR)
  frame:SetScript("OnEnter", function(self)
    showTooltip(self)
    showRange(self)
    self.hover:Show()
  end)
  frame:SetScript("OnLeave", function(self)
    hideTooltip()
    view.rangeShade:Hide()
    self.hover:Hide()
  end)
  frame.plate = CreateFrame("Frame", nil, frame)
  frame.plate:SetPoint("TOPLEFT")
  frame.plate:SetHeight(BAR)
  frame.background = Skin.fill(frame.plate, Skin.HOVER)
  frame.underline = Skin.fill(frame.plate, Skin.BAR, "BORDER")
  frame.underline:ClearAllPoints()
  frame.underline:SetPoint("BOTTOMLEFT")
  frame.underline:SetPoint("BOTTOMRIGHT")
  frame.underline:SetHeight(2)
  frame.caps = {}
  for i, side in ipairs({ "LEFT", "RIGHT" }) do
    local cap = frame.plate:CreateTexture(nil, "BORDER", nil, 1)
    cap:SetPoint("TOP" .. side)
    cap:SetPoint("BOTTOM" .. side)
    cap:SetWidth(CAP_WIDTH)
    frame.caps[i] = cap
  end
  -- The plate lights on hover; the plate takes no mouse itself, so the bar
  -- shows it.
  frame.hover = Skin.fill(frame.plate, Skin.HOVER, "BORDER", -1)
  frame.hover:Hide()
  -- The 1px light outline of a dungeon you share with who's picked.
  frame.outline = Skin.border(frame.plate, SHARED)
  -- What stays readable when the bar is partly scrolled off the left.
  frame.inner = CreateFrame("Frame", nil, frame)
  frame.inner:SetHeight(BAR)
  -- The raids' diamond.
  frame.diamond = frame.inner:CreateTexture(nil, "ARTWORK")
  frame.diamond:SetSize(7, 7)
  frame.diamond:SetPoint("LEFT", 2, 0)
  frame.diamond:SetColorTexture(Skin.BAR[1], Skin.BAR[2], Skin.BAR[3], 1)
  frame.diamond:SetRotation(math.rad(45))
  frame.name = Skin.label(frame.inner, SMALL)
  frame.forever = Skin.foreverMark(frame.inner)
  frame.dots = {}
  frame.more = Skin.label(frame.inner, TINY, MUTED)
  return frame
end

local function drawBar(frame, bar)
  frame.bar = bar
  frame.plate.bar = bar
  at(frame, bar.x, laneY(bar.lane), bar.width, BAR)
  frame.plate:SetWidth(bar.range)
  local attunement = bar.kind == "attunement"
  local state = bar.fits and "fits" or (bar.past and "past" or "other")
  frame.background:SetShown(not attunement)
  frame.background:SetColorTexture(1, 1, 1, PLATE[state])
  frame.underline:SetShown(bar.fits)
  for _, cap in ipairs(frame.caps) do
    cap:SetColorTexture(1, 1, 1, CAP[state])
    cap:SetShown(not attunement)
  end
  if attunement then
    dashes(frame.plate, bar.range, BAR)
  elseif frame.plate.dashes then
    hideFrom(frame.plate.dashes, 1)
  end
  for _, edge in ipairs(frame.outline) do edge:SetShown(bar.shared) end
  frame:SetAlpha(bar.faded and FADED or 1)
  frame.inner:SetAlpha(bar.past and not bar.shared and PAST_ALPHA or 1)
  local raids = bar.kind == "raids"
  frame.diamond:SetShown(raids)
  frame.name:ClearAllPoints()
  frame.name:SetPoint("LEFT", raids and 12 or 0, 0)
  frame.name:SetText(bar.name)
  Skin.color(frame.name, (bar.fits or bar.shared) and TEXT or DIM)
  local anchor, width = frame.name, (raids and 12 or 0) + frame.name:GetStringWidth()
  frame.forever:SetShown(bar.forever)
  if bar.forever then
    Skin.color(frame.forever, (bar.fits or bar.shared) and TEXT or MUTED)
    frame.forever:ClearAllPoints()
    frame.forever:SetPoint("LEFT", anchor, "RIGHT", 4, 0)
    anchor = frame.forever
    width = width + 4 + frame.forever:GetWidth()
  end
  for i, classFilename in ipairs(bar.dots) do
    local dot = frame.dots[i]
    if not dot then
      dot = frame.inner:CreateTexture(nil, "ARTWORK")
      dot:SetSize(6, 6)
      dot:SetColorTexture(1, 1, 1, 1)
      Skin.round(frame.inner, dot)
      frame.dots[i] = dot
    end
    dot:SetVertexColor(Skin.classColor(classFilename))
    dot:ClearAllPoints()
    dot:SetPoint("LEFT", anchor, "RIGHT", i == 1 and 6 or 2, 0)
    dot:Show()
    anchor = dot
    width = width + (i == 1 and 6 or 2) + 6
  end
  hideFrom(frame.dots, #bar.dots + 1)
  frame.more:SetShown(bar.moreDots > 0)
  if bar.moreDots > 0 then
    frame.more:ClearAllPoints()
    frame.more:SetPoint("LEFT", anchor, "RIGHT", 3, 0)
    frame.more:SetText("+" .. bar.moreDots)
    width = width + 3 + frame.more:GetStringWidth()
  end
  frame.innerWidth = math.ceil(width)
  frame.inner:SetWidth(frame.innerWidth)
  frame:Show()
end

local function drawDungeons(data)
  for i, bar in ipairs(data.bars) do
    local frame = barFrames[i] or createBarFrame()
    barFrames[i] = frame
    drawBar(frame, bar)
  end
  hideFrom(barFrames, #data.bars + 1)
end

-- A pooled texture on the overview strip.
local function stripTexture(list, i, layer)
  local texture = list[i]
  if not texture then
    texture = view.strip:CreateTexture(nil, layer or "ARTWORK")
    texture:SetColorTexture(1, 1, 1, 1)
    list[i] = texture
  end
  texture:ClearAllPoints()
  texture:Show()
  return texture
end

-- The overview: the whole line as a minimap. Every tenth level's mark and
-- number, the can-play band, each dungeon as a 1px line in its lane
-- (brighter where you fit), a tick per friend at the top and you in gold.
local function drawOverview(data)
  local scale = view.strip:GetWidth() / data.width
  local marks = 0
  for _, tick in ipairs(data.ticks) do
    if tick.decade then
      marks = marks + 1
      local mark = stripTexture(overviewMarks, marks, "BACKGROUND")
      mark:SetColorTexture(unpack(OVERVIEW_MARK))
      mark:SetPoint("TOPLEFT", view.strip, "TOPLEFT", tick.x * scale, 0)
      mark:SetSize(1, view.strip:GetHeight())
      local number = overviewNumbers[marks]
      if not number then
        number = Skin.label(view.strip, "tiny", OVERVIEW_NUMBER, "BACKGROUND")
        overviewNumbers[marks] = number
      end
      number:ClearAllPoints()
      number:SetPoint("TOPLEFT", view.strip, "TOPLEFT", tick.x * scale + 3, 0)
      number:SetText(tick.level)
      number:Show()
    end
  end
  hideFrom(overviewMarks, marks + 1)
  hideFrom(overviewNumbers, marks + 1)

  view.stripBand:ClearAllPoints()
  view.stripBand:SetPoint("TOPLEFT", view.strip, "TOPLEFT", data.band.left * scale, 0)
  view.stripBand:SetSize((data.band.right - data.band.left) * scale, view.strip:GetHeight())
  for i, x in ipairs({ data.band.left, data.band.right - 1 }) do
    local edge = view.stripBandEdges[i]
    edge:ClearAllPoints()
    edge:SetPoint("TOPLEFT", view.strip, "TOPLEFT", x * scale, 0)
    edge:SetHeight(view.strip:GetHeight())
  end

  local spread = math.max(1, data.lanes - 1)
  for i, bar in ipairs(data.bars) do
    local lane = stripTexture(overviewLines, i)
    lane:SetColorTexture(1, 1, 1, bar.fits and 0.6 or 0.22)
    local y = view.strip:GetHeight() - 2 - OVERVIEW_LANES + math.floor((bar.lane - 1) / spread * OVERVIEW_LANES)
    lane:SetPoint("TOPLEFT", view.strip, "TOPLEFT", bar.x * scale, -y)
    lane:SetSize(math.max(1, bar.range * scale - 1), 1)
  end
  hideFrom(overviewLines, #data.bars + 1)

  for i, group in ipairs(data.groups) do
    local tick = stripTexture(overviewTicks, i, "OVERLAY")
    tick:SetSize(2, 4)
    local r, g, b = Skin.classColor(group.classFilename)
    tick:SetVertexColor(r, g, b, group.online and 1 or 0.6)
    tick:SetPoint("TOPLEFT", view.strip, "TOPLEFT", group.x * scale - 1, 0)
  end
  hideFrom(overviewTicks, #data.groups + 1)
  view.stripYou:ClearAllPoints()
  view.stripYou:SetPoint("CENTER", view.strip, "LEFT", data.you * scale, 0)
end

-- The hover guide: while the cursor is over the line and not dragging it,
-- a line at the level under it and what that level says on the axis. Your
-- own level has its flag already.
function TogetherTab.hovered()
  local data = view.data
  if not data or view.dragFrom or not view.scroller:IsMouseOver() then
    view.guide:Hide()
    view.guideTag:Hide()
    return
  end
  local left = view.scroller:GetLeft()
  if not left then return end
  local x = cursorX() - left + view.scroller:GetHorizontalScroll()
  local layoutLevel = layout().level
  local level = math.floor((x - layout().left) / layoutLevel + 0.5) + 1
  level = math.max(1, math.min(layout().levels, level))
  local tick = data.ticks[level]
  view.guide:ClearAllPoints()
  view.guide:SetPoint("TOPLEFT", view.track, "TOPLEFT", tick.x, 0)
  view.guide:Show()
  if tick.you then
    view.guideTag:Hide()
    return
  end
  if view.guideTag.level ~= level then
    view.guideTag.level = level
    view.guideTag:SetText(data.levels[level])
  end
  view.guideTag:ClearAllPoints()
  view.guideTag:SetPoint("TOP", view.track, "TOPLEFT", tick.x, -(axisY() + 2))
  view.guideTag:Show()
end

-- Keeps what depends on where the line is scrolled up to date: the sticky
-- dungeon names, the overview's window and the back-to-you buttons.
function TogetherTab.scrolled()
  if not view or not view.data then return end
  local data = view.data
  local left = view.scroller:GetHorizontalScroll()
  local width = view.scroller:GetWidth()
  for _, frame in ipairs(barFrames) do
    if frame:IsShown() and frame.bar then
      local room = frame.bar.width - 2 * NAME_INSET - frame.innerWidth
      local shift = math.max(0, math.min(left - frame.bar.x, room))
      frame.inner:ClearAllPoints()
      frame.inner:SetPoint("LEFT", frame, "LEFT", NAME_INSET + math.max(shift, 0), 0)
    end
  end
  local scale = view.strip:GetWidth() / data.width
  view.stripWindow:ClearAllPoints()
  view.stripWindow:SetPoint("LEFT", view.strip, "LEFT", left * scale, 0)
  view.stripWindow:SetWidth(math.max(4, width * scale))
  local you = data.you - left
  view.backLeft:SetShown(you < 0)
  view.backRight:SetShown(you > width)
  for _, button in ipairs({ view.backLeft, view.backRight }) do
    button:SetWidth(button.label:GetStringWidth() + 16)
  end
  -- The hint shows while the whole window is in one empty stretch.
  local empty = false
  for _, span in ipairs(data.empty and data.empty.spans or {}) do
    if left >= span.left and left + width <= span.right then empty = true end
  end
  view.empty:SetShown(empty)
end

-- Draws the tab into parent (the panel's content) from Core, centred on the
-- Character you play when the tab wasn't on screen. campOn: the Camp's band
-- is showing, so friends are its heads.
function TogetherTab.draw(parent, theCore, campOn)
  core = theCore
  lit = campOn and true or false
  if not view then createView(parent) end
  local opening = not view:IsVisible()
  view:Show()
  local data = core:together(measure, selected)
  view.data = data
  view.guideTag.level = nil
  if not data then
    view.scroller:Hide()
    view.as:SetText("")
    view.asAlt:Hide()
    view.hidden:SetText("")
    view.clear:Hide()
    view.showButton:Hide()
    view.empty:Hide()
    if view.menu then view.menu:Hide() end
    return
  end
  view.scroller:Show()
  view.showButton:Show()
  view.showButton:SetText(data.show.label)
  view.showButton:SetWidth(view.showButton.label:GetStringWidth() + view.showButton.iconRoom + 16)
  drawMenu(data.show)
  selected = data.selected
  view.clear:SetShown(data.clear ~= nil)
  view.hidden:ClearAllPoints()
  if data.clear then
    view.clear:SetText(data.clear)
    view.clear:SetWidth(view.clear.label:GetStringWidth() + 16)
    view.hidden:SetPoint("RIGHT", view.clear, "LEFT", -8, 0)
  else
    view.hidden:SetPoint("RIGHT", view.showButton, "LEFT", -8, 0)
  end
  if data.empty then
    view.emptyText:SetText(data.empty.text .. " · ")
    view.emptyAction.label:SetText(data.empty.action)
    view.emptyAction:SetWidth(view.emptyAction.label:GetStringWidth())
    view.empty:SetWidth(view.emptyText:GetStringWidth() + view.emptyAction:GetWidth())
    view.empty:ClearAllPoints()
    view.empty:SetPoint("TOP", view.scroller, "TOP", 0, -(laneY(1) + 30))
  end

  view.as:SetText(("As %s %d"):format(classHex(data.as.classFilename) .. data.as.name .. "|r", data.as.level))
  view.asAlt:SetShown(data.as.alt)
  view.hidden:SetText(data.hidden or "")

  drawAxis(data)
  drawGroups(data)
  drawDungeons(data)
  drawOverview(data)
  if opening then
    centreOnYou()
    -- The line's width may not be laid out until the next frame.
    C_Timer.After(0, centreOnYou)
  else
    TogetherTab.scrolled()
  end
  TogetherTab.escapeKeys()
end

function TogetherTab.hide()
  if view then view:Hide() end
end
