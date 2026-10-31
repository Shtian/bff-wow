-- Panel: the BFF window. Without a Crew it shows the setup view (display
-- name, Start or Join); in one, Core's rows and the Crew code to share. It
-- never sees a Member record.

local _, ns = ...

local Panel = {}
ns.Panel = Panel

local WIDTH = 420
local ROW_HEIGHT = 40
local PADDING = 12
local TOP = 32
local FOOTER = 52
local SETUP_HEIGHT = 230

local WAITING = "Waiting for your Crew. Members show up when they or someone who has seen them is online."
local LEAVING = "Leaving the Crew. It finishes once BFF's channel is reachable."
local RECEIVE_ONLY = "Trial accounts can join a Crew and see it, but the others won't see you."

local core
local frame
local setup
local footer
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

-- Other Members show their display name too, and fade while offline.
local function drawRow(row, data)
  if data.own or not data.displayName then
    row.name:SetText(data.name)
  else
    row.name:SetText(("%s (%s)"):format(data.name, data.displayName))
  end
  row.name:SetTextColor(classColor(data.classFilename))
  row:SetAlpha(data.online and 1 or 0.5)
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

local function createLabel(parent, text, template)
  local label = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormal")
  label:SetJustifyH("LEFT")
  label:SetText(text)
  return label
end

local function createEditBox(parent, width)
  local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  box:SetSize(width, 20)
  box:SetAutoFocus(false)
  box:SetScript("OnEscapePressed", box.ClearFocus)
  return box
end

local function createButton(parent, text, onClick)
  local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  button:SetSize(110, 22)
  button:SetText(text)
  button:SetScript("OnClick", onClick)
  return button
end

-- The setup view: display name, then Start a Crew or Join a Crew.
local function createSetup()
  setup = CreateFrame("Frame", nil, frame)
  setup:SetPoint("TOPLEFT", PADDING + 4, -TOP)
  setup:SetPoint("BOTTOMRIGHT", -PADDING - 4, PADDING)

  local nameLabel = createLabel(setup, "Display name")
  nameLabel:SetPoint("TOPLEFT", 0, -4)
  setup.name = createEditBox(setup, 200)
  setup.name:SetMaxLetters(16)
  setup.name:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 6, -6)
  setup.nameError = createLabel(setup, "", "GameFontRedSmall")
  setup.nameError:SetPoint("TOPLEFT", setup.name, "BOTTOMLEFT", -6, -4)

  local startLabel = createLabel(setup, "Start a Crew")
  startLabel:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 0, -56)
  setup.start = createButton(setup, "Start", function()
    local _, reason = core:startCrew(setup.name:GetText())
    setup.nameError:SetText(reason and ns.MESSAGES[reason] or "")
  end)
  setup.start:SetPoint("TOPLEFT", startLabel, "BOTTOMLEFT", 0, -6)
  setup.receiveOnly = createLabel(setup, RECEIVE_ONLY, "GameFontHighlightSmall")
  setup.receiveOnly:SetPoint("TOPLEFT", startLabel, "BOTTOMLEFT", 0, -8)
  setup.receiveOnly:SetPoint("RIGHT", setup, "RIGHT")

  local joinLabel = createLabel(setup, "Join a Crew")
  joinLabel:SetPoint("TOPLEFT", startLabel, "BOTTOMLEFT", 0, -48)
  setup.code = createEditBox(setup, 140)
  setup.code:SetMaxLetters(12)
  setup.code:SetPoint("TOPLEFT", joinLabel, "BOTTOMLEFT", 6, -6)
  local function join()
    local _, reason = core:joinCrew(setup.code:GetText(), setup.name:GetText())
    setup.nameError:SetText(reason == "invalidName" and ns.MESSAGES.invalidName or "")
    setup.codeError:SetText(reason and reason ~= "invalidName" and ns.MESSAGES[reason] or "")
  end
  setup.code:SetScript("OnEnterPressed", join)
  setup.join = createButton(setup, "Join", join)
  setup.join:SetPoint("LEFT", setup.code, "RIGHT", 8, 0)
  setup.codeError = createLabel(setup, "", "GameFontRedSmall")
  setup.codeError:SetPoint("TOPLEFT", setup.code, "BOTTOMLEFT", -6, -4)
end

local function showSetup()
  if not setup then createSetup() end
  if not setup:IsShown() then
    setup.name:SetText(ns.defaultDisplayName())
    setup.code:SetText("")
    setup.nameError:SetText("")
    setup.codeError:SetText("")
  end
  local receiveOnly = core:isReceiveOnly()
  setup.start:SetShown(not receiveOnly)
  setup.receiveOnly:SetShown(receiveOnly)
  setup:Show()
  frame:SetHeight(SETUP_HEIGHT)
end

-- Below the rows: the waiting or leaving line, and the Crew code in a
-- read-only box with the text selected, since addons can't copy to the
-- clipboard.
local function createFooter()
  footer = CreateFrame("Frame", nil, frame)
  footer:SetHeight(FOOTER)
  footer:SetPoint("BOTTOMLEFT", PADDING, PADDING)
  footer:SetPoint("BOTTOMRIGHT", -PADDING, PADDING)

  footer.status = createLabel(footer, "", "GameFontHighlightSmall")
  footer.status:SetPoint("TOPLEFT")
  footer.status:SetPoint("RIGHT")

  local codeLabel = createLabel(footer, "Crew code", "GameFontNormalSmall")
  codeLabel:SetPoint("BOTTOMLEFT", 0, 6)
  footer.code = createEditBox(footer, 110)
  footer.code:SetPoint("LEFT", codeLabel, "RIGHT", 12, 0)
  footer.code:SetScript("OnEditFocusGained", footer.code.HighlightText)
  footer.code:SetScript("OnTextChanged", function(box, userInput)
    if userInput then
      box:SetText(box.crewCode)
      box:HighlightText()
    end
  end)
end

local function drawFooter(crew)
  if not footer then createFooter() end
  footer.code.crewCode = crew.code
  footer.code:SetText(crew.code)
  footer.code:HighlightText()
  if crew.leaving then
    footer.status:SetText(LEAVING)
  elseif crew.alone then
    footer.status:SetText(WAITING)
  else
    footer.status:SetText("")
  end
  footer:Show()
end

-- Redraws from Core, if the panel is open.
function Panel.refresh()
  if not frame or not frame:IsShown() then return end
  local crew = core:crew()
  local rows = crew and core:rows() or {}
  for i, data in ipairs(rows) do
    drawRow(rowFrames[i] or createRow(i), data)
  end
  for i = #rows + 1, #rowFrames do rowFrames[i]:Hide() end

  if not crew then
    if footer then footer:Hide() end
    showSetup()
    return
  end
  if setup then setup:Hide() end
  drawFooter(crew)
  frame:SetHeight(TOP + math.max(#rows, 1) * ROW_HEIGHT + FOOTER + PADDING)
end

function Panel.toggle()
  if not frame then create() end
  frame:SetShown(not frame:IsShown())
end

function Panel.start(theCore)
  core = theCore
end
