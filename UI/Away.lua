-- Away: the While you were away popup from the Feed decision (#14). Draws
-- Core's summary as one block per Member, most recent activity first: the
-- Member's events condensed onto one line, then max level, joined and left
-- on their own highlighted lines. Open Feed and Close. App shows it once
-- out of combat. See docs/design/feed.md.

local _, ns = ...

local Away = {}
ns.Away = Away

local WIDTH = 340
local PADDING = 12
local TOP = 30
local INTRO = 22
local BUTTONS = 40
local GAP = 6

local GOLD = "|cffffd100"

local frame
local lines = {}

local function classColor(classFilename)
  local color = classFilename and RAID_CLASS_COLORS[classFilename]
  return color and color:GenerateHexColor() or "ffffffff"
end

-- "Ann (Main Thrall): 18 → 24, died 3×", the name in gold and the Main in
-- its class colour.
local function headline(member)
  local text = GOLD .. member.displayName .. "|r"
  if member.main and member.main ~= member.displayName then
    text = ("%s (Main |c%s%s|r)"):format(text, classColor(member.classFilename), member.main)
  end
  if member.line then text = text .. ": " .. member.line end
  return text
end

local function createButton(text, onClick)
  local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  button:SetSize(110, 22)
  button:SetText(text)
  button:SetScript("OnClick", onClick)
  return button
end

local function create()
  frame = CreateFrame("Frame", "BFFAway", UIParent, "BasicFrameTemplateWithInset")
  frame:SetWidth(WIDTH)
  frame:SetPoint("CENTER", 0, 120)
  frame:SetFrameStrata("DIALOG")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:Hide()
  -- Closes on Escape.
  table.insert(UISpecialFrames, "BFFAway")

  local title = frame.TitleText
  if not title then
    title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", 0, -5)
  end
  title:SetText("BFF: While you were away")

  frame.intro = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  frame.intro:SetPoint("TOPLEFT", PADDING + 4, -TOP - 4)

  local open = createButton("Open Feed", function()
    frame:Hide()
    ns.Panel.show("feed")
  end)
  open:SetPoint("BOTTOMRIGHT", frame, "BOTTOM", -4, PADDING)
  local close = createButton(CLOSE or "Close", function() frame:Hide() end)
  close:SetPoint("BOTTOMLEFT", frame, "BOTTOM", 4, PADDING)
end

local function line(index)
  local text = lines[index]
  if not text then
    text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetJustifyH("LEFT")
    text:SetWordWrap(true)
    lines[index] = text
  end
  return text
end

-- Shows the summary from Core's awaySummary: { members, count }.
function Away.show(summary)
  if not frame then create() end
  frame.intro:SetText(summary.count == 1 and "1 thing happened while you were away."
    or ("%d things happened while you were away."):format(summary.count))

  local y, count = -TOP - INTRO - 4, 0
  local function add(text, gap, indent)
    count = count + 1
    local label = line(count)
    label:ClearAllPoints()
    label:SetPoint("TOPLEFT", PADDING + 4 + indent, y - gap)
    label:SetWidth(WIDTH - 2 * PADDING - 8 - indent)
    label:SetText(text)
    label:Show()
    y = y - gap - label:GetStringHeight()
  end
  for _, member in ipairs(summary.members) do
    add(headline(member), GAP, 0)
    for _, highlight in ipairs(member.highlights) do add(GOLD .. highlight.text .. "|r", 2, 12) end
  end
  for i = count + 1, #lines do lines[i]:Hide() end

  frame:SetHeight(-y + BUTTONS + PADDING)
  frame:Show()
end
