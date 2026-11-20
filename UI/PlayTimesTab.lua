local _, ns = ...

local PlayTimesTab = {}
ns.PlayTimesTab = PlayTimesTab

local Skin = ns.Skin

local INSET = 12
local SMALL_BUTTON = 20
local CELL = 11
local ROW = 18
local DAYS = 30
local TOP = -INSET - SMALL_BUTTON - 8 - 36
local BELOW = 74
local DAY_NAMES = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" }
local EMPTY_TITLE = "Too soon to tell"

local GOLD = Skin.GOLD
local MUTED = Skin.MUTED
local DIM = Skin.DIM
local TEXT = Skin.TEXT

local core
local page
local view
local member

function PlayTimesTab.pick(memberId)
  member = memberId
end

local function showMenu(owner)
  MenuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateTitle("Show")
    root:CreateRadio("The Crew", function() return member == nil end, function()
      member = nil
      page.redraw()
    end)
    for _, row in ipairs(core:rows("name")) do
      local label = row.own and "You" or row.displayName or row.name
      root:CreateRadio(label, function() return member == row.memberId end, function()
        member = row.memberId
        page.redraw()
      end)
    end
  end)
end

local function shade(cell, value, max)
  if value <= 0 or max <= 0 then
    cell.texture:SetColorTexture(1, 1, 1, 0.05)
  else
    cell.texture:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.2 + 0.8 * math.min(value / max, 1))
  end
end

local function showCellTooltip(cell)
  local data = view.data
  if not data then return end
  local value = data.grid[cell.day][cell.hour]
  GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
  GameTooltip:AddLine(("%s %02d:00-%02d:00"):format(DAY_NAMES[cell.day], cell.hour - 1, cell.hour % 24), 1, 1, 1)
  if data.memberId then
    local who = data.own and "You" or data.displayName or "They"
    GameTooltip:AddLine(("%s played %d of the last %d weeks"):format(who, value, data.weeks),
      MUTED[1], MUTED[2], MUTED[3])
  else
    GameTooltip:AddLine(("%d of %d Members usually play"):format(value, data.max), MUTED[1], MUTED[2], MUTED[3])
  end
  GameTooltip:Show()
end

local function hideTooltip()
  GameTooltip:Hide()
end

local function createView()
  view = CreateFrame("Frame", nil, page.frame)
  view:SetAllPoints()

  view.pick = CreateFrame("Button", nil, view)
  view.pick:SetHeight(SMALL_BUTTON)
  view.pick:SetPoint("TOPLEFT", INSET, -INSET)
  Skin.fill(view.pick, Skin.SECONDARY)
  Skin.border(view.pick, Skin.BORDER)
  Skin.fill(view.pick, Skin.HOVER, "HIGHLIGHT")
  view.pick.label = Skin.label(view.pick, "small", TEXT)
  view.pick.iconRoom = Skin.leadIcon(view.pick, "filter", TEXT)
  view.pick:SetScript("OnClick", showMenu)

  view.intro = Skin.label(view, "small", MUTED)
  view.intro:SetPoint("TOPLEFT", view.pick, "BOTTOMLEFT", 0, -8)
  view.intro:SetWordWrap(true)
  view.intro:SetJustifyH("LEFT")

  view.hours = {}
  for hour = 0, 21, 3 do
    local label = Skin.label(view, "tiny", DIM)
    label:SetText(("%02d"):format(hour))
    label.hour = hour
    view.hours[#view.hours + 1] = label
  end
  view.days = {}
  view.cells = {}
  for day = 1, 7 do
    local label = Skin.label(view, "small", MUTED)
    label:SetText(DAY_NAMES[day])
    view.days[day] = label
    for hour = 1, 24 do
      local cell = CreateFrame("Frame", nil, view)
      cell.texture = cell:CreateTexture(nil, "ARTWORK")
      cell.texture:SetAllPoints()
      cell.day, cell.hour = day, hour
      cell:EnableMouse(true)
      cell:SetScript("OnEnter", showCellTooltip)
      cell:SetScript("OnLeave", hideTooltip)
      view.cells[#view.cells + 1] = cell
    end
  end

  view.legendLow = Skin.label(view, "tiny", DIM)
  view.legend = {}
  local anchor = view.legendLow
  for i = 1, 4 do
    local swatch = view:CreateTexture(nil, "ARTWORK")
    swatch:SetSize(CELL - 1, ROW - 2)
    swatch:SetPoint("LEFT", anchor, "RIGHT", i == 1 and 6 or 1, 0)
    view.legend[i] = { texture = swatch }
    anchor = swatch
  end
  view.legendHigh = Skin.label(view, "tiny", DIM)
  view.legendHigh:SetPoint("LEFT", anchor, "RIGHT", 6, 0)

  view.note = Skin.label(view, "small", MUTED)
  view.note:SetWordWrap(true)
  view.note:SetJustifyH("LEFT")

  view.grid = { view.intro, view.legendLow, view.legendHigh, view.note }
  for _, list in ipairs({ view.hours, view.days, view.cells }) do
    for _, item in ipairs(list) do view.grid[#view.grid + 1] = item end
  end
  for _, swatch in ipairs(view.legend) do view.grid[#view.grid + 1] = swatch.texture end
  view.empty = ns.EmptyState.new(view)
end

local function placeGrid()
  local cellWidth = math.max(CELL, math.floor((page.width - 2 * INSET - DAYS) / 24))
  local rowHeight = math.max(ROW, math.floor((page.height + TOP - BELOW) / 7))
  for _, label in ipairs(view.hours) do
    label:SetPoint("BOTTOMLEFT", view, "TOPLEFT", INSET + DAYS + label.hour * cellWidth, TOP + 2)
  end
  for day, label in ipairs(view.days) do
    label:SetPoint("LEFT", view, "TOPLEFT", INSET, TOP - (day - 1) * rowHeight + 1 - math.floor(rowHeight / 2))
  end
  for _, cell in ipairs(view.cells) do
    cell:SetSize(cellWidth - 1, rowHeight - 2)
    cell:SetPoint("TOPLEFT", INSET + DAYS + (cell.hour - 1) * cellWidth, TOP - (cell.day - 1) * rowHeight)
  end
  local below = TOP - 7 * rowHeight - 10
  view.legendLow:SetPoint("TOPLEFT", INSET + DAYS, below)
  view.note:SetPoint("TOPLEFT", INSET, below - 24)
end

function PlayTimesTab.draw(thePage)
  page, core = thePage, thePage.core
  if not view then createView() end
  local data = member and core:playTimes(member)
  if not data then
    member = nil
    data = core:playTimes()
  end
  view.data = data
  view.pick.label:SetText("Show: " .. data.title)
  view.pick:SetWidth(view.pick.label:GetStringWidth() + view.pick.iconRoom + 16)
  view.intro:SetWidth(page.width - 2 * INSET)
  view.intro:SetText(data.intro)
  view.note:SetWidth(page.width - 2 * INSET)
  view.note:SetText(data.note or "")
  placeGrid()
  for _, cell in ipairs(view.cells) do
    shade(cell, data.grid[cell.day][cell.hour], data.max)
  end
  view.legendLow:SetText(data.memberId and "0" or "None")
  view.legendHigh:SetText(data.memberId and ("%d weeks"):format(data.weeks) or "Everyone")
  for i, swatch in ipairs(view.legend) do
    shade(swatch, i - 1, 3)
  end
  if GameTooltip:GetOwner() and GameTooltip:GetOwner():GetParent() == view then
    showCellTooltip(GameTooltip:GetOwner())
  end
  local empty = data.empty and not data.memberId
  for _, item in ipairs(view.grid) do item:SetShown(not empty) end
  if empty then
    view.empty:Set(ns.EmptyState.view({ art = "playTimes", title = EMPTY_TITLE, text = data.note },
      not core:setting("camp")))
    local top = INSET + SMALL_BUTTON
    view.empty:Place(view, page.width, page.height - top, top)
  else
    view.empty:Hide()
  end
end
