-- CatchesTab: the panel's Catches tab, a field guide drawn from Core's
-- catchesTab(). On top "25 of 46 types caught", the Group and Show
-- pickers (the game's menus) and a bar with a tick at each trophy step;
-- then a section per water (or per type) of 28px tiles that scrolls; and
-- at the bottom Recent first catches. Core groups, filters and words
-- everything; this asks the game for each item's name, icon and quality,
-- and draws them. What's picked in Group and Show is the UI's, as the
-- Roster's sort is; the names checkbox is Core's setting. See
-- docs/design/catches.md.

local _, ns = ...

local CatchesTab = {}
ns.CatchesTab = CatchesTab

local Skin = ns.Skin

local GOLD = Skin.GOLD
local TEXT = Skin.TEXT
local MUTED = Skin.MUTED
local DIM = Skin.DIM

local INSET = 12
local SMALL_BUTTON = 20
local PICKER_GAP = 6
-- The summary: the count line, the bar and the next trophy.
local BAR = 4
local TICK = 8
local SUMMARY_PAD = 9
-- The grid's tiles, and the gaps between them across and down (room
-- for the 2px gold line under a fresh one).
local TILE = 28
local GAP_X = 4
local GAP_Y = 7
local FRESH_LINE = 2
-- A section's heading and its zones line.
local SECTION_PAD = 9
local HEADING = 16
-- Recent first catches: a label, then a row each.
local RECENT_ROW = 22
local RECENT_ICON = 16
local RECENT_LABEL = 14
-- Under this content height Recent first catches shows two, and under
-- this width it leaves out the zone.
local RECENT_SHORT = 300
local RECENT_NARROW = 400
local THUMB = 6
local SCROLL_STEP = 40
local EMPTY_PAD = 18
-- A tile not caught: its icon faint and grey, or a "?".
local UNCAUGHT_ALPHA = 0.45
local QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"

local view
local core
-- Group and Show, as the UI remembers them; Core falls back to its
-- defaults for anything it doesn't know.
local group = "where"
local show = "all"
local sectionFrames, tileFrames, recentRows = {}, {}, {}

local function hideFrom(list, from)
  for i = from, #list do list[i]:Hide() end
end

-- An item as the game has it: name (or Core's fallback until it's
-- cached), icon and quality colour (nil for
-- common, or while not cached). Asking starts loading it, and the panel
-- redraws when it arrives.
local function item(itemId, fallback)
  local name, icon, quality = Skin.item(itemId)
  return name or fallback, icon or QUESTION_MARK, quality
end

local function colored(text, color)
  return Skin.hex(color) .. text .. "|r"
end

-- A Member as a catch names them: "You" in Ash Text, anyone else in their
-- Character's class colour.
local function who(first)
  if first.own or not first.classFilename then return colored(first.who, TEXT) end
  local r, g, b = Skin.classColor(first.classFilename)
  return colored(first.who, { r, g, b })
end

local function line(text, color, wrap)
  color = color or MUTED
  GameTooltip:AddLine(text, color[1], color[2], color[3], wrap)
end

local function tileTooltip(frame)
  local t = frame.tile
  local tip = t.tooltip
  GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
  if t.named then
    local name, _, quality = item(t.itemId, t.name)
    line(name, quality or TEXT)
  else
    line(tip.unnamed, DIM)
  end
  if tip.note then line(tip.note, MUTED, true) end
  if tip.extra then line(tip.extra, MUTED, true) end
  if tip.first then
    local first = tip.first
    local by = tip.firstBy .. " " .. who(first)
    if not first.own and first.character and first.character ~= first.displayName then
      by = by .. colored(" (" .. first.character .. ")", MUTED)
    end
    line(by, TEXT)
    line(tip.when, MUTED)
    GameTooltip:AddDoubleLine(tip.crew, tostring(tip.count), MUTED[1], MUTED[2], MUTED[3], TEXT[1], TEXT[2], TEXT[3])
    if tip.also then line(tip.also, MUTED, true) end
  end
  if tip.none then line(tip.none, MUTED, true) end
  if tip.hint then line(tip.hint, DIM, true) end
  if tip.where then line(tip.where, MUTED, true) end
  GameTooltip:Show()
end

local function hideTooltip()
  GameTooltip:Hide()
end

-- A square item picture: an opaque back, the quality edge (1px, faded)
-- and the icon inset 1px with its bevel cropped. :Draw(tile) shows a
-- caught tile in full colour, a tile not caught faint, its icon grey when
-- named and a "?" when not.
local function picture(parent, size)
  local frame = Skin.feedPicture(parent, size)
  frame.border = {}
  for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
    frame.border[#frame.border + 1] = Skin.edge(frame, side, Skin.BORDER, "OVERLAY")
  end
  frame.question = Skin.label(frame, "small", Skin.FAINT_MARK)
  frame.question:SetPoint("CENTER", 0, 0)
  frame.question:SetText("?")
  function frame:Draw(t)
    local _, icon, quality = item(t.itemId, t.name)
    local caught = t.caught
    self.picture:SetTexture(icon)
    self.picture:SetDesaturated(not caught)
    self.picture:SetAlpha(caught and 1 or UNCAUGHT_ALPHA)
    self.picture:SetShown(t.named)
    self.question:SetShown(not t.named)
    if caught then
      self.back:SetColorTexture(Skin.RAISED[1], Skin.RAISED[2], Skin.RAISED[3], 1)
    else
      local none = Skin.TILE_NONE
      self.back:SetColorTexture(none[1], none[2], none[3], none[4])
    end
    for _, edge in ipairs(self.border) do edge:SetShown(not caught) end
    self.edge:SetShown(caught and quality ~= nil)
    if quality then self.edge:SetColorTexture(quality[1], quality[2], quality[3], Skin.ITEM_EDGE_ALPHA) end
  end
  return frame
end

local function createTile()
  local frame = picture(view.content, TILE)
  frame:EnableMouse(true)
  local hover = frame:CreateTexture(nil, "HIGHLIGHT")
  hover:SetAllPoints()
  hover:SetColorTexture(Skin.HOVER[1], Skin.HOVER[2], Skin.HOVER[3], Skin.HOVER[4])
  frame.fresh = frame:CreateTexture(nil, "ARTWORK")
  frame.fresh:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
  frame.fresh:SetHeight(FRESH_LINE)
  frame.fresh:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -2)
  frame.fresh:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, -2)
  frame:SetScript("OnEnter", tileTooltip)
  frame:SetScript("OnLeave", hideTooltip)
  return frame
end

local function createSection()
  local frame = CreateFrame("Frame", nil, view.content)
  frame.line = Skin.edge(frame, "TOP", Skin.LINE)
  frame.title = Skin.label(frame, "heading", TEXT)
  frame.title:SetPoint("TOPLEFT", INSET, -SECTION_PAD)
  frame.count = Skin.label(frame, "small", MUTED)
  frame.count:SetPoint("TOPRIGHT", -INSET, -SECTION_PAD)
  frame.sub = Skin.label(frame, "small", DIM)
  frame.sub:SetPoint("TOPLEFT", INSET, -SECTION_PAD - HEADING)
  frame.sub:SetWordWrap(true)
  return frame
end

local function scrollBy(delta)
  local scroller = view.scroller
  local range = scroller:GetVerticalScrollRange()
  scroller:SetVerticalScroll(math.min(range, math.max(0, scroller:GetVerticalScroll() - delta * SCROLL_STEP)))
  CatchesTab.updateThumb()
end

function CatchesTab.updateThumb()
  local scroller = view.scroller
  local range = scroller:GetVerticalScrollRange()
  local thumb = view.thumb
  if range <= 0 then
    scroller:SetVerticalScroll(0)
    thumb:Hide()
    return
  end
  if scroller:GetVerticalScroll() > range then scroller:SetVerticalScroll(range) end
  local visible = scroller:GetHeight()
  local height = math.max(24, visible * visible / (visible + range))
  thumb:SetHeight(height)
  thumb:ClearAllPoints()
  thumb:SetPoint("TOPRIGHT", scroller, "TOPRIGHT", THUMB - 2, -(visible - height) * scroller:GetVerticalScroll() / range)
  thumb:Show()
end

local function redraw()
  if view and view:IsShown() then CatchesTab.draw(view:GetParent(), core) end
end

-- Group and Show: the app's small picker buttons, opening the game's
-- menu. The names checkbox keeps Show's menu open.
local function showMenu(owner, menu, onPick)
  MenuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateTitle(menu.title)
    for _, option in ipairs(menu.options) do
      local label = option.label
      if option.count then label = label .. "  " .. colored(tostring(option.count), DIM) end
      root:CreateRadio(label, function() return option.picked end, function()
        onPick(option.id)
        redraw()
      end)
    end
    if menu.names then
      root:CreateDivider()
      -- view.data is redrawn after each click, so this reads the setting
      -- as it is now.
      root:CreateCheckbox(menu.names.label, function() return view.data.show.names.value end, function()
        core:setSetting("catchesNames", not view.data.show.names.value)
        redraw()
        return MenuResponse and MenuResponse.Refresh
      end)
    end
  end)
end

local function picker(kind, onClick)
  local button = CreateFrame("Button", nil, view.summary)
  button:SetHeight(SMALL_BUTTON)
  Skin.fill(button, Skin.SECONDARY)
  Skin.border(button, Skin.BORDER)
  Skin.fill(button, Skin.HOVER, "HIGHLIGHT")
  button.label = Skin.label(button, "small", MUTED)
  button.iconRoom = Skin.leadIcon(button, kind, MUTED)
  button:SetScript("OnClick", onClick)
  return button
end

local function setPicker(button, text)
  button.label:SetText(text)
  button:SetWidth(button.label:GetStringWidth() + button.iconRoom + 16)
end

local function createView(parent)
  view = CreateFrame("Frame", nil, parent)
  view:SetAllPoints()

  view.summary = CreateFrame("Frame", nil, view)
  view.summary:SetPoint("TOPLEFT")
  view.summary:SetPoint("TOPRIGHT")
  view.summary.line = Skin.edge(view.summary, "BOTTOM", Skin.LINE)
  view.count = Skin.label(view.summary, "body", TEXT)
  view.countOf = Skin.label(view.summary, "small", MUTED)
  view.countOf:SetPoint("BOTTOMLEFT", view.count, "BOTTOMRIGHT", 4, 1)
  view.show = picker("filter", function(self) showMenu(self, view.data.show, function(id) show = id end) end)
  view.group = picker("group", function(self) showMenu(self, view.data.group, function(id) group = id end) end)
  view.track = view.summary:CreateTexture(nil, "ARTWORK")
  view.track:SetColorTexture(Skin.TRACK[1], Skin.TRACK[2], Skin.TRACK[3], Skin.TRACK[4])
  view.track:SetHeight(BAR)
  view.fill = view.summary:CreateTexture(nil, "ARTWORK", nil, 1)
  view.fill:SetHeight(BAR)
  view.fill:SetPoint("LEFT", view.track, "LEFT")
  view.ticks = {}
  view.next = Skin.label(view.summary, "small", MUTED)

  view.recent = CreateFrame("Frame", nil, view)
  view.recent:SetPoint("BOTTOMLEFT")
  view.recent:SetPoint("BOTTOMRIGHT")
  Skin.edge(view.recent, "TOP", Skin.LINE)
  view.recent.label = Skin.label(view.recent, "label", DIM)
  view.recent.label:SetPoint("TOPLEFT", INSET, -7)

  view.scroller = CreateFrame("ScrollFrame", nil, view)
  view.scroller:EnableMouseWheel(true)
  view.scroller:SetScript("OnMouseWheel", function(_, delta) scrollBy(delta) end)
  view.content = CreateFrame("Frame", nil, view.scroller)
  view.content:SetSize(1, 1)
  view.scroller:SetScrollChild(view.content)
  view.scroller:SetScript("OnSizeChanged", function(_, width)
    view.content:SetWidth(width)
    CatchesTab.updateThumb()
  end)
  view.thumb = view.scroller:CreateTexture(nil, "OVERLAY")
  view.thumb:SetColorTexture(1, 1, 1, 0.18)
  view.thumb:SetWidth(3)

  -- No catches yet, or nothing for this Show: a heading and a line,
  -- centred at the top of the list.
  view.message = CreateFrame("Frame", nil, view.content)
  view.message.title = Skin.label(view.message, "heading", TEXT)
  view.message.title:SetPoint("TOP", 0, -EMPTY_PAD)
  view.message.title:SetJustifyH("CENTER")
  view.message.text = Skin.label(view.message, "small", MUTED)
  view.message.text:SetPoint("TOP", view.message.title, "BOTTOM", 0, -4)
  view.message.text:SetJustifyH("CENTER")
  view.message.text:SetWordWrap(true)

  -- Hiding the tab closes a tile's tooltip, not anyone else's.
  view:SetScript("OnHide", function()
    local owner = GameTooltip:GetOwner()
    if owner and owner.tile then GameTooltip:Hide() end
  end)
end

-- The count, the pickers and, when they don't fit beside it, the pickers
-- on a line of their own under it. Returns the summary's height.
local function picked(menu)
  for _, option in ipairs(menu.options) do
    if option.picked then return option.label end
  end
  return menu.label
end

local function drawSummary(data, width)
  setPicker(view.group, data.group.label)
  setPicker(view.show, data.show.label)
  -- "25" then "of 46 types caught" smaller, or "All 46 types caught".
  view.count:SetText(data.countOf and tostring(data.caught) or data.count)
  view.countOf:SetText(data.countOf or "")
  Skin.color(view.count, data.done and GOLD or TEXT)
  local countWidth = view.count:GetStringWidth() + (data.countOf and 4 + view.countOf:GetStringWidth() or 0)
  local pickers = view.group:GetWidth() + PICKER_GAP + view.show:GetWidth()
  local inner = width - 2 * INSET
  local oneLine = countWidth + 8 + pickers <= inner
  if not oneLine then
    -- Narrow: the pickers' icons say which is which, so they show only
    -- what's picked, and move under the count only if still too wide.
    setPicker(view.group, picked(data.group))
    setPicker(view.show, picked(data.show))
    pickers = view.group:GetWidth() + PICKER_GAP + view.show:GetWidth()
    oneLine = countWidth + 8 + pickers <= inner
  end
  view.count:ClearAllPoints()
  view.count:SetPoint("TOPLEFT", INSET, -SUMMARY_PAD - 2)
  view.show:ClearAllPoints()
  local pickersY = oneLine and -SUMMARY_PAD or -SUMMARY_PAD - SMALL_BUTTON - 4
  view.show:SetPoint("TOPRIGHT", -INSET, pickersY)
  view.group:ClearAllPoints()
  view.group:SetPoint("RIGHT", view.show, "LEFT", -PICKER_GAP, 0)

  local barY = pickersY - SMALL_BUTTON - 7
  view.track:ClearAllPoints()
  view.track:SetPoint("TOPLEFT", INSET, barY)
  view.track:SetPoint("TOPRIGHT", -INSET, barY)
  local color = data.done and GOLD or Skin.BAR
  view.fill:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
  view.fill:SetWidth(math.max(1, inner * data.fill))
  view.fill:SetShown(data.fill > 0)
  for i, at in ipairs(data.ticks) do
    local tick = view.ticks[i]
    if not tick then
      tick = view.summary:CreateTexture(nil, "ARTWORK", nil, 2)
      local mark = Skin.FAINT_MARK
      tick:SetColorTexture(mark[1], mark[2], mark[3], mark[4])
      tick:SetSize(1, TICK)
      view.ticks[i] = tick
    end
    tick:ClearAllPoints()
    tick:SetPoint("CENTER", view.track, "LEFT", math.floor(inner * at), 0)
    tick:Show()
  end
  hideFrom(view.ticks, #data.ticks + 1)
  view.next:ClearAllPoints()
  view.next:SetPoint("TOPLEFT", INSET, barY - BAR - 5)
  view.next:SetText(data.next)
  local height = -barY + BAR + 5 + view.next:GetStringHeight() + 8
  view.summary:SetHeight(height)
  return height
end

-- Up to 3 recent first catches ("Tor caught Feralas Ahi", the item in its
-- quality colour), 2 in a short panel, leaving the zone out when narrow.
-- Returns the strip's height, 0 when there's none.
local function drawRecent(data, width, height)
  local max = height < RECENT_SHORT and 2 or 3
  local shown = math.min(max, #data.recent)
  if shown == 0 then
    view.recent:Hide()
    hideFrom(recentRows, 1)
    return 0
  end
  view.recent.label:SetText(data.recentTitle)
  for i = 1, shown do
    local r = data.recent[i]
    local row = recentRows[i]
    if not row then
      row = CreateFrame("Frame", nil, view.recent)
      row:SetHeight(RECENT_ROW)
      row.picture = picture(row, RECENT_ICON)
      row.picture:SetPoint("LEFT", INSET, 0)
      row.when = Skin.label(row, "small", DIM)
      row.when:SetPoint("RIGHT", -INSET, 0)
      row.text = Skin.label(row, "text", TEXT)
      row.text:SetPoint("LEFT", row.picture, "RIGHT", 6, 0)
      row.text:SetPoint("RIGHT", row.when, "LEFT", -6, 0)
      row.text:SetWordWrap(false)
      recentRows[i] = row
    end
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 0, -7 - RECENT_LABEL - (i - 1) * RECENT_ROW)
    row:SetPoint("TOPRIGHT", 0, -7 - RECENT_LABEL - (i - 1) * RECENT_ROW)
    row.picture:Draw({ itemId = r.itemId, name = r.name, caught = true, named = true })
    local name, _, quality = item(r.itemId, r.name)
    row.text:SetText(who(r.first) .. " " .. r.caught .. " " .. colored(name, quality or TEXT))
    row.when:SetText(width >= RECENT_NARROW and r.when or r.first.since)
    row:Show()
  end
  hideFrom(recentRows, shown + 1)
  local stripHeight = 7 + RECENT_LABEL + shown * RECENT_ROW + 6
  view.recent:SetHeight(stripHeight)
  view.recent:Show()
  return stripHeight
end

local function drawMessage(message, width, y)
  if not message then
    view.message:Hide()
    return y
  end
  view.message:ClearAllPoints()
  view.message:SetPoint("TOPLEFT", 0, y)
  view.message:SetPoint("TOPRIGHT", 0, y)
  view.message.title:SetText(message.title)
  view.message.text:SetWidth(width - 4 * INSET)
  view.message.text:SetText(message.text)
  local height = EMPTY_PAD + view.message.title:GetStringHeight() + 4 + view.message.text:GetStringHeight() + 10
  view.message:SetHeight(height)
  view.message:Show()
  return y - height
end

local function drawSections(data, width)
  local y = drawMessage(data.empty or data.filtered, width, 0)
  local columns = math.max(1, math.floor((width - 2 * INSET + GAP_X) / (TILE + GAP_X)))
  local tiles = 0
  for i, s in ipairs(data.sections) do
    local frame = sectionFrames[i] or createSection()
    sectionFrames[i] = frame
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", 0, y)
    frame:SetPoint("TOPRIGHT", 0, y)
    frame.line:SetShown(i > 1 or y < 0)
    frame.title:SetText(s.title)
    frame.count:SetText(s.count or "")
    Skin.color(frame.count, s.done and TEXT or MUTED)
    local top = SECTION_PAD + HEADING
    if s.sub then
      frame.sub:SetWidth(width - 2 * INSET)
      frame.sub:SetText(s.sub)
      frame.sub:Show()
      top = top + frame.sub:GetStringHeight() + 7
    else
      frame.sub:Hide()
      top = top + 5
    end
    for j, t in ipairs(s.tiles) do
      tiles = tiles + 1
      local tile = tileFrames[tiles] or createTile()
      tileFrames[tiles] = tile
      tile.tile = t
      tile:Draw(t)
      tile.fresh:SetShown(t.fresh)
      local column, row = (j - 1) % columns, math.floor((j - 1) / columns)
      tile:ClearAllPoints()
      tile:SetPoint("TOPLEFT", view.content, "TOPLEFT", INSET + column * (TILE + GAP_X),
        y - top - row * (TILE + GAP_Y))
      tile:Show()
    end
    local rows = math.ceil(#s.tiles / columns)
    local height = top + rows * (TILE + GAP_Y) + 4
    frame:SetHeight(height)
    frame:Show()
    y = y - height
  end
  hideFrom(sectionFrames, #data.sections + 1)
  hideFrom(tileFrames, tiles + 1)
  return -y + 6
end

function CatchesTab.draw(parent, theCore)
  core = theCore
  if not view then createView(parent) end
  view:Show()
  local data = core:catchesTab(group, show)
  view.data = data
  local width, height = parent:GetWidth(), parent:GetHeight()

  local top = drawSummary(data, width)
  local bottom = drawRecent(data, width, height)
  view.scroller:ClearAllPoints()
  view.scroller:SetPoint("TOPLEFT", 0, -top)
  view.scroller:SetPoint("BOTTOMRIGHT", -THUMB, bottom)
  view.content:SetWidth(width - THUMB)
  view.content:SetHeight(drawSections(data, width - THUMB))
  CatchesTab.updateThumb()

  -- A tooltip open over a tile follows what it shows now.
  local owner = GameTooltip:GetOwner()
  if owner and owner.tile and owner:GetParent() == view.content and owner:IsShown() and owner:IsMouseOver() then
    tileTooltip(owner)
  end
end

function CatchesTab.hide()
  if view then view:Hide() end
end
