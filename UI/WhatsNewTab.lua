local _, ns = ...

local WhatsNewTab = {}
ns.WhatsNewTab = WhatsNewTab

local Skin = ns.Skin

local GOLD = Skin.GOLD
local TEXT = Skin.TEXT
local MUTED = Skin.MUTED
local DIM = Skin.DIM

local INSET = 12
local TOP_GAP = 10
local PLATE_PAD_X = 12
local PLATE_PAD_Y = 10
local PLATE_GAP = 8
local SECTION = 26
local RELEASE_GAP = 10
local ENTRY_PAD = 5
local PICTURE = 18
local PICTURE_GAP = 8
local DETAIL_GAP = 2
local DETAIL_LINES = 2
local DOT = Skin.UNREAD_DOT

local view
local redraw
local head, plate, older
local sections, entries = {}, {}
local expanded = {}

local function createHead()
  head = CreateFrame("Frame", nil, view.content)
  head.title = Skin.label(head, "heading", TEXT)
  head.title:SetPoint("TOPLEFT")
  head.line = Skin.label(head, "small", MUTED)
  head.line:SetPoint("TOPLEFT", head.title, "BOTTOMLEFT", 0, -4)
end

local function createPlate()
  plate = CreateFrame("Frame", nil, view.content)
  Skin.fill(plate, Skin.RAISED, "BACKGROUND")
  Skin.border(plate, GOLD)
  plate.title = Skin.label(plate, "heading", TEXT)
  plate.title:SetPoint("TOPLEFT", PLATE_PAD_X, -PLATE_PAD_Y)
  plate.title:SetText("Make sure your friends update too")
  plate.text = Skin.label(plate, "small", MUTED)
  plate.text:SetPoint("TOPLEFT", plate.title, "BOTTOMLEFT", 0, -4)
  plate.who = Skin.label(plate, "small", MUTED)
  plate.who:SetPoint("TOPLEFT", plate.text, "BOTTOMLEFT", 0, -6)
end

local function section(index)
  if sections[index] then return sections[index] end
  local item = CreateFrame("Frame", nil, view.content)
  item:SetHeight(SECTION)
  item.label = Skin.sectionLabel(item, 0, 0)
  local rule = Skin.rule(item)
  rule:SetPoint("LEFT", item.label, "RIGHT", 8, 0)
  rule:SetPoint("RIGHT")
  sections[index] = item
  return item
end

local function entry(index)
  if entries[index] then return entries[index] end
  local item = CreateFrame("Button", nil, view.content)
  Skin.fill(item, Skin.HOVER, "HIGHLIGHT")
  item.picture = Skin.feedPicture(item, PICTURE)
  item.picture:SetPoint("TOPLEFT", INSET, -ENTRY_PAD)
  item.dot = Skin.unreadDot(item)
  item.dot:SetPoint("CENTER", item.picture, "LEFT", -(DOT / 2 + 3), 0)
  item.title = Skin.label(item, "body", TEXT)
  item.title:SetPoint("TOPLEFT", item.picture, "TOPRIGHT", PICTURE_GAP, 1)
  item.detail = Skin.label(item, "small", MUTED)
  item.detail:SetPoint("TOPLEFT", item.title, "BOTTOMLEFT", 0, -DETAIL_GAP)
  item:SetScript("OnClick", function(self)
    if not self.key then return end
    expanded[self.key] = not expanded[self.key] or nil
    redraw()
  end)
  item:SetScript("OnEnter", function(self)
    if not self.kindName then return end
    GameTooltip:SetOwner(self.picture, "ANCHOR_RIGHT")
    GameTooltip:SetText(self.kindName)
    GameTooltip:Show()
  end)
  item:SetScript("OnLeave", function() GameTooltip:Hide() end)
  entries[index] = item
  return item
end

local function classHex(classFilename)
  local color = classFilename and RAID_CLASS_COLORS[classFilename]
  if color then return Skin.hex({ color.r, color.g, color.b }) end
  return Skin.hex(TEXT)
end

local function drawPlate(friends, y, width)
  if not plate then createPlate() end
  plate:ClearAllPoints()
  plate:SetPoint("TOPLEFT", view.content, "TOPLEFT", INSET, y)
  plate:SetWidth(width)
  local inner = width - 2 * PLATE_PAD_X
  plate.title:SetWidth(inner)
  plate.text:SetWidth(inner)
  plate.text:SetText(friends.text)
  local who = friends.who
  if #friends.behind > 0 then
    local names = {}
    for i, friend in ipairs(friends.behind) do
      names[i] = ("%s%s|r (%s)"):format(classHex(friend.classFilename), friend.name, friend.version)
    end
    who = "Still on an older BFF: " .. table.concat(names, ", ")
  end
  plate.who:SetWidth(inner)
  plate.who:SetText(who or "")
  plate.who:SetShown(who ~= nil)
  local height = PLATE_PAD_Y + plate.title:GetStringHeight() + 4 + plate.text:GetStringHeight()
    + (who and 6 + plate.who:GetStringHeight() or 0) + PLATE_PAD_Y
  plate:SetHeight(height)
  plate:Show()
  return y - height - PLATE_GAP
end

local function drawEntry(item, change, key, new, y, width)
  item.key = change.detail and key or nil
  item.kindName = change.kindName
  item.picture:SetPicture(Skin.CHANGE_PICTURES[change.kind] or Skin.CHANGE_PICTURES.patch,
    Skin.CHANGE_EDGES[change.kind] or Skin.CHANGE_EDGES.patch)
  item:ClearAllPoints()
  item:SetPoint("TOPLEFT", view.content, "TOPLEFT", 0, y)
  item:SetPoint("RIGHT", view.content, "RIGHT", -INSET, 0)
  item.dot:SetShown(new)
  item.title:SetWidth(width)
  item.title:SetText(change.title)
  Skin.color(item.title, new and TEXT or MUTED)
  local open = expanded[key] == true
  local showDetail = change.detail ~= nil and (new or open)
  item.detail:SetShown(showDetail)
  local height = ENTRY_PAD + math.max(PICTURE, item.title:GetStringHeight() - 1) + ENTRY_PAD
  if showDetail then
    item.detail:SetWidth(width)
    item.detail:SetMaxLines(open and 0 or DETAIL_LINES)
    item.detail:SetText(change.detail)
    height = math.max(height, ENTRY_PAD + item.title:GetStringHeight() + DETAIL_GAP
      + item.detail:GetStringHeight() + ENTRY_PAD)
  end
  item:SetHeight(height)
  item:Show()
  return y - height
end

function WhatsNewTab.draw(scrollView, core, width, onChange)
  view, redraw = scrollView, onChange
  local data = core:whatsNew()
  if not head then createHead() end
  if not older then older = Skin.label(view.content, "small", DIM) end
  head:SetShown(data ~= nil)
  local inner = width - 2 * INSET
  local y = -INSET

  head:ClearAllPoints()
  head:SetPoint("TOPLEFT", view.content, "TOPLEFT", INSET, y)
  head:SetSize(inner, 1)
  head.line:SetWidth(inner)
  if data then
    head.title:SetText(data.title)
    head.line:SetText(data.line)
    y = y - head.title:GetStringHeight() - 4 - head.line:GetStringHeight() - TOP_GAP
  end

  if plate then plate:Hide() end
  if data and data.friends then y = drawPlate(data.friends, y, inner) end

  local sectionCount, entryCount = 0, 0
  for _, release in ipairs(data and data.releases or {}) do
    sectionCount = sectionCount + 1
    if sectionCount > 1 then y = y - RELEASE_GAP end
    local label = section(sectionCount)
    label:ClearAllPoints()
    label:SetPoint("TOPLEFT", view.content, "TOPLEFT", INSET - 4, y)
    label:SetPoint("RIGHT", view.content, "RIGHT", -INSET, 0)
    label.label:SetText((release.version .. " · " .. release.date):upper())
    label:Show()
    y = y - SECTION
    for i, change in ipairs(release.entries) do
      entryCount = entryCount + 1
      y = drawEntry(entry(entryCount), change, release.version .. ":" .. i, release.new, y,
        inner - PICTURE - PICTURE_GAP)
    end
  end
  for i = sectionCount + 1, #sections do sections[i]:Hide() end
  for i = entryCount + 1, #entries do entries[i]:Hide() end

  older:SetShown(data ~= nil and data.older ~= nil)
  if data and data.older then
    older:ClearAllPoints()
    older:SetPoint("TOPLEFT", view.content, "TOPLEFT", INSET, y - TOP_GAP)
    older:SetWidth(inner)
    older:SetText(data.older)
    y = y - TOP_GAP - older:GetStringHeight()
  end
  view.content:SetHeight(-y + INSET)
end

function WhatsNewTab.leave()
  expanded = {}
end
