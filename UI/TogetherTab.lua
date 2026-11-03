-- TogetherTab: the panel's Together tab, laid out from Core's together().
-- A toolbar ("As Gahzuria 24", what's hidden), the answer line, then a
-- 1–60 level line that scrolls sideways: friends' dots and labels above the
-- axis, dungeon bars in lanes below it, and an overview strip under it to
-- jump along. Clicking friends picks them to see the dungeons you share,
-- and the Show menu filters the line. Core places and words everything;
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

local INSET = 12
local TOOLBAR = 28
local ANSWER = 46
local OVERVIEW = 22
-- Inside the line, from its top: the band's label, the label rows, the dot
-- rail, the axis and the dungeon lanes.
local ROW = 18
local ROWS_TOP = 18
local LABEL_HEIGHT = 17
local AXIS = 18
local LANE = 20
local BAR = 17
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
local MENU_WIDTH = 212
local MENU_PAD = 10

local view
local core
-- The Members picked on the line, as memberIds; Core drops any it doesn't
-- know.
local selected = {}
-- Bars and chips by frame, for the sticky names while scrolling.
local barFrames, chipFrames = {}, {}
local labelFrames, dotFrames, stemTextures = {}, {}, {}
local tickTextures, numberLabels, overviewTicks = {}, {}, {}

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
    label = Skin.label(view, font)
    label:Hide()
    measurers[font] = label
  end
  label:SetText(text)
  return math.ceil(label:GetStringWidth())
end

local function layout()
  return ns.Core.TOGETHER_LAYOUT
end

-- Rows count up from the axis; y is from the line's top.
local function rowY(row)
  return ROWS_TOP + (layout().rows - row) * ROW
end

local function railY()
  return ROWS_TOP + layout().rows * ROW + 6
end

local function axisY()
  return railY() + 14
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

local function groupTooltip(owner)
  for _, character in ipairs(owner.group.characters) do
    local parts = {
      colored(character.member, TEXT),
      classHex(character.classFilename) .. character.name .. "|r",
      colored(tostring(character.level), MUTED),
    }
    if character.alt then parts[#parts + 1] = colored("alt", DIM) end
    if character.online and not character.own then parts[#parts + 1] = colored("online", ONLINE) end
    if character.canPlay then
      parts[#parts + 1] = colored(character.apart, GOLD)
    elseif character.apart then
      parts[#parts + 1] = colored(character.apart, DIM)
    end
    line(table.concat(parts, " "))
  end
end

local function dungeonTooltip(owner)
  local tooltip = owner.bar.tooltip
  GameTooltip:AddLine(tooltip.title, 1, 1, 1)
  if tooltip.detail then line(tooltip.detail, DIM) end
  if tooltip.forever then line(tooltip.forever, MUTED) end
  for _, raid in ipairs(tooltip.raids or {}) do
    line(colored(raid.name, TEXT) .. " " .. colored(raid.detail, DIM)
      .. (raid.forever and " " .. colored("NEW", MUTED) or ""))
  end
  line(tooltip.you, tooltip.fits and TEXT or DIM)
  for _, fitter in ipairs(tooltip.fitters) do
    local parts = {
      colored(fitter.member, TEXT),
      classHex(fitter.classFilename) .. fitter.name .. "|r",
      colored(tostring(fitter.level), MUTED),
    }
    if fitter.online then parts[#parts + 1] = colored("online", ONLINE) end
    if fitter.far then parts[#parts + 1] = colored("· " .. fitter.far, DIM) end
    line(table.concat(parts, " "))
  end
  if tooltip.none then line(tooltip.none, DIM) end
  if tooltip.almost then line(tooltip.almost, DIM) end
end

local function chipTooltip(owner)
  GameTooltip:AddLine(owner.chip.title, 1, 1, 1)
  for _, item in ipairs(owner.chip.items) do
    line(colored(item.name, TEXT) .. " " .. colored(item.detail, DIM))
  end
end

local function redraw()
  if view then TogetherTab.draw(view:GetParent(), core) end
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

local function startDrag()
  view.dragFrom = cursorX()
  view.pressFrom = view.dragFrom
  view.dragScroll = view.scroller:GetHorizontalScroll()
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
    swatch.badge = Skin.badge(swatch, "tiny", MUTED)
    swatch.badge:SetPoint("LEFT")
    swatch.badge:SetText("NEW")
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
      check:SetPoint("TOPLEFT", MENU_PAD, -(y + 3))
      menu.checks[key] = check
      y = y + 22
      if option.sub then
        local sub = Skin.label(menu, "tiny", DIM)
        sub:SetPoint("TOPLEFT", check.label, "BOTTOMLEFT", 0, -1)
        sub:SetText(option.sub)
        y = y + 12
      end
    end
  end
  heading(show.key.title)
  for _, item in ipairs(show.key.items) do
    local swatch = keySwatch(menu, item.kind)
    swatch:SetPoint("TOPLEFT", MENU_PAD, -(y + 4))
    if swatch.dashed then dashes(swatch, 22, 9) end
    local label = Skin.label(menu, "small", MUTED)
    label:SetPoint("LEFT", swatch, "RIGHT", 7, 0)
    label:SetText(item.text)
    y = y + 17
  end
  local help = Skin.label(menu, "small", DIM)
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
  view.as = Skin.label(view.toolbar, "small", MUTED)
  view.as:SetPoint("LEFT", INSET, 0)
  view.asAlt = Skin.badge(view.toolbar, "tiny", MUTED)
  view.asAlt:SetPoint("LEFT", view.as, "RIGHT", 4, 0)
  view.asAlt:SetText("alt")
  view.showButton = Skin.button(view.toolbar, "Show", toggleMenu)
  view.showButton:SetHeight(20)
  view.showButton.label:SetFontObject(Skin.fonts.small)
  view.showButton:SetPoint("RIGHT", -8, 0)
  view.hidden = Skin.label(view.toolbar, "small", DIM)
  view.hidden:SetPoint("RIGHT", view.showButton, "LEFT", -8, 0)
  view.hidden:SetJustifyH("RIGHT")

  -- The answer line.
  view.answer = CreateFrame("Frame", nil, view)
  view.answer:SetPoint("TOPLEFT", 0, -TOOLBAR)
  view.answer:SetPoint("TOPRIGHT", 0, -TOOLBAR)
  view.answer:SetHeight(ANSWER)
  Skin.edge(view.answer, "BOTTOM", Skin.LINE)
  view.clear = Skin.button(view.answer, "Clear", clearSelection)
  view.clear:SetHeight(20)
  view.clear.label:SetFontObject(Skin.fonts.small)
  view.clear:SetPoint("TOPRIGHT", -8, -6)
  view.first = Skin.label(view.answer, "body", TEXT)
  view.first:SetPoint("TOPLEFT", INSET, -6)
  view.first:SetWordWrap(false)
  view.second = Skin.label(view.answer, "small", MUTED)
  view.second:SetPoint("TOPLEFT", view.first, "BOTTOMLEFT", 0, -4)
  view.second:SetPoint("RIGHT", -INSET, 0)
  view.second:SetWordWrap(false)

  -- The overview strip.
  view.overview = CreateFrame("Frame", nil, view)
  view.overview:SetPoint("BOTTOMLEFT")
  view.overview:SetPoint("BOTTOMRIGHT")
  view.overview:SetHeight(OVERVIEW)
  Skin.edge(view.overview, "TOP", Skin.LINE)
  view.strip = CreateFrame("Frame", nil, view.overview)
  view.strip:SetPoint("LEFT", INSET, 0)
  view.strip:SetPoint("RIGHT", -INSET, 0)
  view.strip:SetHeight(10)
  view.strip:EnableMouse(true)
  Skin.fill(view.strip, Skin.TRACK)
  view.stripYou = Skin.fill(view.strip, GOLD, "OVERLAY")
  view.stripYou:ClearAllPoints()
  view.stripYou:SetSize(2, 14)
  view.stripWindow = CreateFrame("Frame", nil, view.strip)
  view.stripWindow:SetHeight(16)
  Skin.border(view.stripWindow, Skin.BAR)
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
  view.scroller:SetPoint("TOPLEFT", 0, -(TOOLBAR + ANSWER))
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
  view.scroller:SetScript("OnUpdate", function(self)
    if not view.dragFrom then return end
    if not IsMouseButtonDown("LeftButton") then
      stopDrag()
      return
    end
    local x = GetCursorPosition() / self:GetEffectiveScale()
    scrollTo(view.dragScroll - (x - view.dragFrom))
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
  view.bandLabel = Skin.label(view.track, "tiny", GOLD)

  -- The axis.
  view.axis = view.track:CreateTexture(nil, "BACKGROUND", nil, 1)
  view.axis:SetColorTexture(unpack(Skin.SIDEBAR))
  view.axisTop = view.track:CreateTexture(nil, "BORDER")
  view.axisTop:SetColorTexture(Skin.BORDER[1], Skin.BORDER[2], Skin.BORDER[3], Skin.BORDER[4])
  view.axisTop:SetHeight(1)
  view.axisBottom = view.track:CreateTexture(nil, "BORDER")
  view.axisBottom:SetColorTexture(Skin.BORDER[1], Skin.BORDER[2], Skin.BORDER[3], Skin.BORDER[4])
  view.axisBottom:SetHeight(1)

  -- Back to you, when you've scrolled away.
  view.backLeft = Skin.button(view, "‹ You", centreOnYou)
  view.backLeft:SetHeight(20)
  view.backLeft.label:SetFontObject(Skin.fonts.small)
  view.backLeft:SetPoint("TOPLEFT", view.scroller, "TOPLEFT", 6, -4)
  view.backLeft:SetFrameLevel(view.scroller:GetFrameLevel() + 10)
  view.backRight = Skin.button(view, "You ›", centreOnYou)
  view.backRight:SetHeight(20)
  view.backRight.label:SetFontObject(Skin.fonts.small)
  view.backRight:SetPoint("TOPRIGHT", view.scroller, "TOPRIGHT", -6, -4)
  view.backRight:SetFrameLevel(view.scroller:GetFrameLevel() + 10)

  -- With only near your level on: what's said over a stretch of the line
  -- with no dungeons, and the link that turns the filter off.
  view.empty = CreateFrame("Frame", nil, view)
  view.empty:SetSize(1, 16)
  view.empty:SetFrameLevel(view.scroller:GetFrameLevel() + 10)
  view.emptyText = Skin.label(view.empty, "small", DIM)
  view.emptyText:SetPoint("LEFT")
  view.emptyAction = CreateFrame("Button", nil, view.empty)
  view.emptyAction:SetHeight(16)
  view.emptyAction:SetPoint("LEFT", view.emptyText, "RIGHT", 0, 0)
  view.emptyAction.label = Skin.label(view.emptyAction, "small", MUTED)
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
  local trackHeight = view.scroller:GetHeight()
  view.track:SetSize(data.width, trackHeight)

  at(view.band, data.band.left, 0, data.band.right - data.band.left, trackHeight)
  at(view.bandLeft, data.band.left, 0, nil, trackHeight)
  at(view.bandRight, data.band.right - 1, 0, nil, trackHeight)
  at(view.bandLabel, data.band.left + 5, 3)
  view.bandLabel:SetText(data.band.text)

  local y = axisY()
  at(view.axis, 0, y, data.width, AXIS)
  at(view.axisTop, 0, y, data.width)
  at(view.axisBottom, 0, y + AXIS - 1, data.width)

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
    if tick.number then
      numbers = numbers + 1
      local label = numberLabels[numbers]
      if not label then
        label = Skin.label(view.track, "tiny")
        numberLabels[numbers] = label
      end
      label:SetText(tick.level)
      Skin.color(label, tick.you and TEXT or MUTED)
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
  frame.count = Skin.badge(frame, "tiny", TEXT, Skin.RAISED)
  frame.count:SetPoint("BOTTOMLEFT", frame, "CENTER", 4, 3)
  return frame
end

local function createLabelFrame()
  local frame = memberFrame()
  frame:SetHeight(LABEL_HEIGHT)
  frame.hover = Skin.fill(frame, Skin.LINE, "HIGHLIGHT")
  frame.kin = Skin.fill(frame, Skin.LINE)
  frame.kin:Hide()
  frame.name = Skin.label(frame, "small", TEXT)
  frame.name:SetPoint("LEFT", 3, 0)
  frame.name:SetWordWrap(false)
  frame.alt = Skin.badge(frame, "tiny", MUTED)
  frame.alt:SetText("alt")
  frame.level = Skin.label(frame, "tiny", MUTED)
  frame.more = Skin.label(frame, "small", MUTED)
  return frame
end

local function drawGroups(data)
  local rail = railY()
  local stems = 0
  for i, group in ipairs(data.groups) do
    local dot = dotFrames[i] or createDotFrame()
    dotFrames[i] = dot
    dot.group = group
    dot:ClearAllPoints()
    dot:SetPoint("CENTER", view.track, "TOPLEFT", group.x, -rail)
    dot.dot:SetVertexColor(Skin.classColor(group.classFilename))
    Skin.color(dot.ring, group.online and ONLINE or OFFLINE)
    dot.outline:SetShown(group.own)
    dot.count:SetShown(group.row == nil and group.count > 1)
    dot.count:SetText(group.count)
    dot:SetAlpha(group.faded and FADED or 1)
    dot:Show()

    local label = labelFrames[i] or createLabelFrame()
    labelFrames[i] = label
    label.group = group
    if group.row then
      local y = rowY(group.row)
      at(label, group.labelX, y, group.labelWidth)
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
      at(stem, group.x, y + LABEL_HEIGHT - 2, 1, rail - y - LABEL_HEIGHT - 3)
      stem:SetAlpha(group.faded and FADED or 1)
      stem:Show()
    else
      label:Hide()
    end
  end
  hideFrom(dotFrames, #data.groups + 1)
  hideFrom(labelFrames, #data.groups + 1)
  hideFrom(stemTextures, stems + 1)
end

local function createBarFrame()
  local frame = hoverable(view.track, dungeonTooltip)
  frame:SetHeight(BAR)
  frame.background = Skin.fill(frame, Skin.HOVER)
  frame.underline = Skin.fill(frame, Skin.BAR, "BORDER")
  frame.underline:ClearAllPoints()
  frame.underline:SetPoint("BOTTOMLEFT")
  frame.underline:SetPoint("BOTTOMRIGHT")
  frame.underline:SetHeight(2)
  frame.hover = Skin.fill(frame, Skin.HOVER, "HIGHLIGHT")
  -- The 1px light outline of a dungeon you share with who's picked.
  frame.outline = Skin.border(frame, SHARED)
  -- What stays readable when the bar is partly scrolled off the left.
  frame.inner = CreateFrame("Frame", nil, frame)
  frame.inner:SetHeight(BAR)
  -- The raids' diamond.
  frame.diamond = frame.inner:CreateTexture(nil, "ARTWORK")
  frame.diamond:SetSize(7, 7)
  frame.diamond:SetPoint("LEFT", 2, 0)
  frame.diamond:SetColorTexture(Skin.BAR[1], Skin.BAR[2], Skin.BAR[3], 1)
  frame.diamond:SetRotation(math.rad(45))
  frame.name = Skin.label(frame.inner, "small")
  frame.forever = Skin.badge(frame.inner, "tiny", MUTED)
  frame.forever:SetText("NEW")
  frame.dots = {}
  frame.more = Skin.label(frame.inner, "tiny", MUTED)
  return frame
end

local function drawBar(frame, bar)
  frame.bar = bar
  at(frame, bar.x, laneY(bar.lane), bar.width, BAR)
  local attunement = bar.kind == "attunement"
  frame.background:SetShown(not attunement)
  frame.background:SetColorTexture(1, 1, 1, bar.fits and 0.12 or 0.05)
  frame.underline:SetShown(bar.fits)
  if attunement then
    dashes(frame, bar.width, BAR)
  elseif frame.dashes then
    hideFrom(frame.dashes, 1)
  end
  for _, edge in ipairs(frame.outline) do edge:SetShown(bar.shared) end
  frame:SetAlpha(bar.faded and FADED or 1)
  local raids = bar.kind == "raids"
  frame.diamond:SetShown(raids)
  frame.name:ClearAllPoints()
  frame.name:SetPoint("LEFT", raids and 12 or 0, 0)
  frame.name:SetText(bar.name)
  Skin.color(frame.name, (bar.fits or bar.shared) and TEXT or DIM)
  local anchor, width = frame.name, (raids and 12 or 0) + frame.name:GetStringWidth()
  frame.forever:SetShown(bar.forever)
  if bar.forever then
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

local function createChipFrame()
  local frame = hoverable(view.track, chipTooltip)
  frame:SetHeight(BAR)
  Skin.border(frame, Skin.BORDER)
  frame.hover = Skin.fill(frame, Skin.HOVER, "HIGHLIGHT")
  frame.text = Skin.label(frame, "small", MUTED)
  frame.text:SetPoint("CENTER")
  return frame
end

local function drawDungeons(data)
  for i, bar in ipairs(data.bars) do
    local frame = barFrames[i] or createBarFrame()
    barFrames[i] = frame
    drawBar(frame, bar)
  end
  hideFrom(barFrames, #data.bars + 1)
  for i, chip in ipairs(data.chips) do
    local frame = chipFrames[i] or createChipFrame()
    chipFrames[i] = frame
    frame.chip = chip
    at(frame, chip.x, laneY(chip.lane), chip.width, BAR)
    frame.text:SetText(chip.text)
    frame:SetAlpha(chip.faded and FADED or 1)
    frame:Show()
  end
  hideFrom(chipFrames, #data.chips + 1)
end

local function drawOverview(data)
  local stripWidth = view.strip:GetWidth()
  local scale = stripWidth / data.width
  for i, group in ipairs(data.groups) do
    local tick = overviewTicks[i]
    if not tick then
      tick = view.strip:CreateTexture(nil, "ARTWORK")
      tick:SetSize(2, 6)
      tick:SetColorTexture(1, 1, 1, 1)
      overviewTicks[i] = tick
    end
    local r, g, b = Skin.classColor(group.classFilename)
    tick:SetVertexColor(r, g, b, group.online and 1 or 0.5)
    tick:ClearAllPoints()
    tick:SetPoint("LEFT", view.strip, "LEFT", group.x * scale - 1, 0)
    tick:Show()
  end
  hideFrom(overviewTicks, #data.groups + 1)
  view.stripYou:ClearAllPoints()
  view.stripYou:SetPoint("CENTER", view.strip, "LEFT", data.you * scale, 0)
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
      local room = frame.bar.width - 8 - frame.innerWidth
      local shift = math.max(0, math.min(left - frame.bar.x, room))
      frame.inner:ClearAllPoints()
      frame.inner:SetPoint("LEFT", frame, "LEFT", 4 + math.max(shift, 0), 0)
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

local function answerText(segments, default)
  local parts = {}
  for i, segment in ipairs(segments) do
    local color = segment.style == "highlight" and GOLD or segment.style == "muted" and MUTED or TEXT
    parts[i] = color == default and segment.text or colored(segment.text, color)
  end
  return table.concat(parts)
end

-- Draws the tab into parent (the panel's content) from Core, centred on the
-- Character you play when the tab wasn't on screen.
function TogetherTab.draw(parent, theCore)
  core = theCore
  if not view then createView(parent) end
  local opening = not view:IsVisible()
  view:Show()
  local data = core:together(measure, selected)
  view.data = data
  if not data then
    view.scroller:Hide()
    view.as:SetText("")
    view.asAlt:Hide()
    view.hidden:SetText("")
    view.first:SetText("")
    view.second:SetText("")
    view.clear:Hide()
    view.showButton:Hide()
    view.empty:Hide()
    if view.menu then view.menu:Hide() end
    return
  end
  view.scroller:Show()
  view.showButton:Show()
  view.showButton:SetText(data.show.label)
  view.showButton:SetWidth(view.showButton.label:GetStringWidth() + 16)
  drawMenu(data.show)
  selected = data.selected
  view.clear:SetShown(data.clear ~= nil)
  view.first:ClearAllPoints()
  view.first:SetPoint("TOPLEFT", INSET, -6)
  if data.clear then
    view.clear:SetText(data.clear)
    view.clear:SetWidth(view.clear.label:GetStringWidth() + 16)
    view.first:SetPoint("RIGHT", view.clear, "LEFT", -8, 0)
  else
    view.first:SetPoint("RIGHT", -INSET, 0)
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
  view.first:SetText(answerText(data.answer[1], TEXT))
  view.second:SetText(answerText(data.answer[2], MUTED))

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
