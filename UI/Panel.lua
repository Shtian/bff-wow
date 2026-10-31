-- Panel: the BFF window. Draws Core's rows and nothing else; it never sees a
-- Member record.

local _, ns = ...

local Panel = {}
ns.Panel = Panel

local WIDTH = 420
local ROW_HEIGHT = 40
local PADDING = 12
local TOP = 32

local core
local frame
local rowFrames = {}

local function classColor(classFilename)
  local color = classFilename and RAID_CLASS_COLORS[classFilename]
  if color then return color.r, color.g, color.b end
  return 1, 1, 1
end

local function createRow(index)
  local row = CreateFrame("Frame", nil, frame)
  row:SetHeight(ROW_HEIGHT)
  row:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -TOP - (index - 1) * ROW_HEIGHT)
  row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PADDING, -TOP - (index - 1) * ROW_HEIGHT)

  row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  row.name:SetPoint("TOPLEFT", 0, -4)

  row.class = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.class:SetPoint("LEFT", row.name, "RIGHT", 6, 0)

  row.level = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.level:SetPoint("LEFT", row.class, "RIGHT", 6, 0)

  row.zone = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.zone:SetPoint("TOPRIGHT", 0, -4)

  row.xp = CreateFrame("StatusBar", nil, row)
  row.xp:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -4)
  row.xp:SetPoint("RIGHT", row, "RIGHT", 0, 0)
  row.xp:SetHeight(8)
  row.xp:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  row.xp:SetStatusBarColor(0.58, 0.0, 0.55)
  local background = row.xp:CreateTexture(nil, "BACKGROUND")
  background:SetAllPoints()
  background:SetColorTexture(0, 0, 0, 0.5)

  rowFrames[index] = row
  return row
end

local function drawRow(row, data)
  row.name:SetText(data.name)
  row.name:SetTextColor(classColor(data.classFilename))
  row.class:SetText(LOCALIZED_CLASS_NAMES_MALE[data.classFilename] or data.classFilename or "")
  row.level:SetText(("Lv %d"):format(data.level or 0))
  row.zone:SetText(data.zone or "")
  local maxXp = data.maxXp or 0
  row.xp:SetMinMaxValues(0, math.max(maxXp, 1))
  row.xp:SetValue(maxXp > 0 and (data.xp or 0) or 0)
  row:Show()
end

local function create()
  frame = CreateFrame("Frame", "BFFPanel", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(WIDTH, TOP + ROW_HEIGHT + PADDING)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("DIALOG")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:SetScript("OnShow", Panel.refresh)
  frame:Hide()
  -- Closes on Escape.
  table.insert(UISpecialFrames, "BFFPanel")

  local title = frame.TitleText
  if not title then
    title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", 0, -5)
  end
  title:SetText("BFF")
end

-- Redraws from Core's rows, if the panel is open.
function Panel.refresh()
  if not frame or not frame:IsShown() then return end
  local rows = core:rows()
  for i, data in ipairs(rows) do
    drawRow(rowFrames[i] or createRow(i), data)
  end
  for i = #rows + 1, #rowFrames do rowFrames[i]:Hide() end
  frame:SetHeight(TOP + math.max(#rows, 1) * ROW_HEIGHT + PADDING)
end

function Panel.toggle()
  if not frame then create() end
  frame:SetShown(not frame:IsShown())
end

function Panel.start(theCore)
  core = theCore
end
