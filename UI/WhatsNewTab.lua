-- WhatsNewTab: the panel's What's new view, drawn from Core's whatsNew(),
-- opened from the sidebar's version label. On top a Heading and a Small
-- line (what changed since you last looked), then, when a major release is
-- new, a raised plate with a gold edge asking you to make sure your friends
-- update, naming those on an older BFF. Then a section per release (its
-- version and date as a section label, with room above it) with a row per
-- change: a small Feed picture for its kind (Skin.CHANGE_PICTURES: big
-- change, new feature, small change or fix; hover names it), its title in
-- Body, and its detail in Small, cut to two lines; a click shows it whole.
-- The pictures mark where each change starts, so rows need no Hairlines,
-- which would read like the releases' rules. Releases new on this visit
-- carry the Unread dot left of each picture; the rest show titles only, in
-- Smoke Muted, until clicked. Panel owns the scroll
-- view; this fills its content. See docs/design/whats-new.md.

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
-- A release's section label, as the Feed's day labels, with room above
-- every one but the first so releases read as groups.
local SECTION = 26
local RELEASE_GAP = 10
local ENTRY_PAD = 5
-- A change's kind picture, and the title's indent past it.
local PICTURE = 18
local PICTURE_GAP = 8
local DETAIL_GAP = 2
local DETAIL_LINES = 2
-- The Unread dot, in the margin left of a change's title.
local DOT = Skin.UNREAD_DOT

local view
local redraw
local head, plate, older
local sections, entries = {}, {}
-- Changes shown whole, by "version:index". Forgotten on leaving the view.
local expanded = {}

local function createHead()
  head = CreateFrame("Frame", nil, view.content)
  head.title = Skin.label(head, "heading", TEXT)
  head.title:SetPoint("TOPLEFT")
  head.line = Skin.label(head, "small", MUTED)
  head.line:SetPoint("TOPLEFT", head.title, "BOTTOMLEFT", 0, -4)
end

-- Make sure your friends update: a lighter plate with a gold edge (the
-- Flat Ledger Rule's way to stand out).
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
  -- The Unread dot in the margin, level with the picture's centre, as on
  -- the Feed.
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

-- Draws the plate at y for friends ({ version, behind, everyone, text,
-- who }) and returns the y under it.
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
    -- The names in their class colours, which only the UI knows.
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

-- Draws a change at y and returns the y under it.
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

-- Draws whatsNew into the scroll view. onChange redraws the panel.
function WhatsNewTab.draw(scrollView, core, width, onChange)
  view, redraw = scrollView, onChange
  local data = core:whatsNew()
  if not head then createHead() end
  if not older then older = Skin.label(view.content, "small", DIM) end
  -- A checkout carries no changelog, and the version label doesn't open
  -- the view there; should it be shown anyway, it's empty.
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

-- The view was left: changes opened whole close again.
function WhatsNewTab.leave()
  expanded = {}
end
