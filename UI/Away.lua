-- Away: the While you were away popup from the Feed decision (#14), in the
-- Skin's flat look. Draws Core's summary as one block per Member, most
-- recent activity first: the Member's name and Main, their events condensed
-- onto one line, then max level, joined and left on their own highlighted
-- lines. Dismiss and Open Feed. App shows it once out of combat. See
-- docs/design/feed.md.

local _, ns = ...

local Away = {}
ns.Away = Away

local Skin = ns.Skin

local WIDTH = 360
local INSET = 14
local ICON = 22
local INTRO = 30
local BUTTONS = 46
local GAP = 8
-- Set outright so wrapped text has a height before the frame is laid out.
local TEXT_WIDTH = WIDTH - 2 * INSET - ICON - 10

local frame
local blocks = {}

local function classColor(classFilename)
  local color = classFilename and RAID_CLASS_COLORS[classFilename]
  if color then return color.r, color.g, color.b end
  return 1, 1, 1
end

local function hex(color)
  return ("|cff%02x%02x%02x"):format(color[1] * 255, color[2] * 255, color[3] * 255)
end

local function create()
  frame = Skin.window("BFFAway", WIDTH, "While you were away")
  frame:SetPoint("CENTER", 0, 120)

  frame.intro = Skin.label(frame, "small", Skin.MUTED)
  frame.intro:SetPoint("TOPLEFT", INSET, -Skin.HEADER_HEIGHT - 10)

  local open = Skin.button(frame, "Open Feed", function()
    frame:Hide()
    ns.Panel.show("feed")
  end, true)
  open:SetPoint("BOTTOMRIGHT", -INSET, INSET)
  local dismiss = Skin.button(frame, "Dismiss", function() frame:Hide() end)
  dismiss:SetPoint("RIGHT", open, "LEFT", -8, 0)
end

-- A Member's block: a line above it, the class icon of their Main, the
-- name, then what happened.
local function block(index)
  local item = blocks[index]
  if item then return item end
  item = CreateFrame("Frame", nil, frame)
  Skin.edge(item, "TOP", Skin.LINE)
  item.icon = item:CreateTexture(nil, "ARTWORK")
  item.icon:SetSize(ICON, ICON)
  item.icon:SetPoint("TOPLEFT", 0, -GAP)
  item.name = Skin.label(item, "text")
  item.name:SetPoint("TOPLEFT", item.icon, "TOPRIGHT", 10, 1)
  item.name:SetWidth(TEXT_WIDTH)
  item.line = Skin.label(item, "text", { 0.78, 0.76, 0.82 })
  item.line:SetPoint("TOPLEFT", item.name, "BOTTOMLEFT", 0, -2)
  item.line:SetWidth(TEXT_WIDTH)
  item.line:SetWordWrap(true)
  item.highlights = Skin.label(item, "text", Skin.GOLD)
  item.highlights:SetWidth(TEXT_WIDTH)
  item.highlights:SetWordWrap(true)
  blocks[index] = item
  return item
end

-- Draws one Member and returns the block's height.
local function drawBlock(item, member)
  item.icon:SetAtlas("classicon-" .. (member.classFilename or ""):lower())
  item.icon:SetShown(member.classFilename ~= nil)
  local r, g, b = classColor(member.classFilename)
  local name = ("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255, member.displayName)
  if member.main and member.main ~= member.displayName then
    name = ("%s  %s· Main %s|r"):format(name, hex(Skin.DIM), member.main)
  end
  item.name:SetText(name)
  item.line:SetText(member.line or "")

  local texts = {}
  for _, highlight in ipairs(member.highlights) do texts[#texts + 1] = highlight.text end
  item.highlights:SetText(table.concat(texts, "\n"))
  item.highlights:ClearAllPoints()
  item.highlights:SetPoint("TOPLEFT", member.line and item.line or item.name, "BOTTOMLEFT", 0, -2)

  local height = GAP + item.name:GetStringHeight() + 2
  if member.line then height = height + item.line:GetStringHeight() + 2 end
  if #texts > 0 then height = height + item.highlights:GetStringHeight() + 2 end
  height = math.max(height, GAP + ICON) + GAP
  item:SetHeight(height)
  item:Show()
  return height
end

-- Shows the summary from Core's awaySummary: { members, count }.
function Away.show(summary)
  if not frame then create() end
  frame.intro:SetText(summary.count == 1 and "1 thing happened while you were away."
    or ("%d things happened while you were away."):format(summary.count))

  local y = -Skin.HEADER_HEIGHT - INTRO
  for i, member in ipairs(summary.members) do
    local item = block(i)
    item:ClearAllPoints()
    item:SetPoint("TOPLEFT", INSET, y)
    item:SetPoint("TOPRIGHT", -INSET, y)
    y = y - drawBlock(item, member)
  end
  for i = #summary.members + 1, #blocks do blocks[i]:Hide() end

  frame:SetHeight(-y + BUTTONS)
  frame:Show()
end
