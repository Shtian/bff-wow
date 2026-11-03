-- GoalsTab: the panel's Goals tab as a trophy cabinet, drawn from Core's
-- trophies() and goals(). On top the latest win in a gold plate, then the
-- trophy shelf (the newest medals and a See all tile), then Working on: a
-- tile per track with its progress. See all opens the full cabinet, every
-- track's medals oldest first, in the same tab; Back returns. Before the
-- baseline has settled, or with nothing reached, a composed empty state
-- takes the latest win's and the shelf's place. Track hues and medal tiers
-- are Skin's trophy colours; Core decides which tier and what is fresh.
-- Panel owns the scroll view; this fills its content. See
-- docs/design/goals.md.

local _, ns = ...

local GoalsTab = {}
ns.GoalsTab = GoalsTab

local Skin = ns.Skin

local GOLD = Skin.GOLD
local TEXT = Skin.TEXT
local MUTED = Skin.MUTED
local DIM = Skin.DIM

local INSET = 12
local HEADING = 28
-- The latest win's plate.
local PLATE_ICON = 40
local PLATE_PAD = 10
local PLATE_MIN = 60
-- Medals: a 40px icon with a 3px foot, the value and the date under it.
local MEDAL_ICON = 40
local MEDAL_FOOT = 3
local MEDAL_HEIGHT = 72
local SHELF_MEDAL = 52
local SHELF_GAP = 6
local CABINET_MEDAL = 60
local CABINET_GAP = 4
local MEDAL_ROW_GAP = 10
-- The shelf's newest medals; the rest are behind See all.
local SHELF = 7
-- Working on: tiles in two columns, one when the panel is narrow.
local TILE_HEIGHT = 74
local TILE_PAD = 10
local TILE_ICON = 28
local TILE_BAR = 4
local TWO_COLUMNS = 400
-- The cabinet: its header row and each track's line.
local CABINET_HEAD = 38
local TRACK_LINE = 24
local TRACK_ICON = 16
local TRACK_GAP = 12
local SMALL_BUTTON = 20
-- The empty state, in the latest win's and the shelf's place.
local EMPTY_HEIGHT = 96
local EMPTY_TEXT = 240

local EMPTY_UNSETTLED = { "Counting up the Crew", "Goals the Crew has already reached show here once everyone's records are in." }
local EMPTY_NONE = { "No trophies yet", "Every goal the Crew reaches puts a medal on this shelf." }

local view
local cabinetOpen = false
local redraw
local pools = {}
local plate, empty, seeAll, tiles, cabinetHead

-- Reused frames of one kind: take() hands out the next, done() hides the
-- ones not taken since start().
local function pool(name, make)
  pools[name] = pools[name] or { items = {}, used = 0, make = make }
  return pools[name]
end

local function take(p)
  p.used = p.used + 1
  local item = p.items[p.used] or p.make()
  p.items[p.used] = item
  item:ClearAllPoints()
  item:Show()
  return item
end

local function startPools()
  for _, p in pairs(pools) do p.used = 0 end
end

local function hideUnused()
  for _, p in pairs(pools) do
    for i = p.used + 1, #p.items do p.items[i]:Hide() end
  end
end

local function hideTooltip()
  GameTooltip:Hide()
end

local function open(on)
  cabinetOpen = on
  view:SetVerticalScroll(0)
  redraw()
end

-- "TROPHY SHELF ————— 12".
local function createHeading()
  local heading = CreateFrame("Frame", nil, view.content)
  heading:SetHeight(HEADING)
  heading.label = Skin.label(heading, "label", DIM)
  heading.label:SetPoint("LEFT", INSET, -2)
  heading.count = Skin.label(heading, "small", MUTED)
  heading.count:SetPoint("RIGHT", -INSET, -2)
  heading.line = heading:CreateTexture(nil, "ARTWORK")
  heading.line:SetColorTexture(Skin.LINE[1], Skin.LINE[2], Skin.LINE[3], Skin.LINE[4])
  heading.line:SetHeight(1)
  heading.line:SetPoint("LEFT", heading.label, "RIGHT", 8, 0)
  heading.line:SetPoint("RIGHT", heading.count, "LEFT", -8, 0)
  return heading
end

-- Places a heading at y. Returns the y under it.
local function drawHeading(text, count, y)
  local heading = take(pool("headings", createHeading))
  heading:SetPoint("TOPLEFT", view.content, "TOPLEFT", 0, y)
  heading:SetPoint("RIGHT", view.content, "RIGHT")
  heading.label:SetText(text)
  heading.count:SetText(count and tostring(count) or "")
  return y - HEADING
end

local function showMedalTooltip(medal)
  local trophy = medal.trophy
  if not trophy then return end
  local quality = Skin.TROPHY_QUALITIES[trophy.quality] or TEXT
  GameTooltip:SetOwner(medal, "ANCHOR_RIGHT")
  GameTooltip:AddLine(trophy.title, TEXT[1], TEXT[2], TEXT[3])
  GameTooltip:AddLine(trophy.label, quality[1], quality[2], quality[3])
  GameTooltip:AddLine("Reached " .. trophy.date, MUTED[1], MUTED[2], MUTED[3])
  GameTooltip:Show()
end

-- A medal: the track's icon (or the profession's) edged in its tier's
-- colour with a 3px foot, its value (gold while fresh) and date under it.
local function createMedal()
  local medal = CreateFrame("Frame", nil, view.content)
  medal:SetHeight(MEDAL_HEIGHT)
  medal:EnableMouse(true)
  medal:SetScript("OnEnter", showMedalTooltip)
  medal:SetScript("OnLeave", hideTooltip)
  medal.picture = Skin.feedPicture(medal, MEDAL_ICON)
  medal.picture:SetPoint("TOP")
  medal.foot = medal.picture:CreateTexture(nil, "ARTWORK", nil, 4)
  medal.foot:SetPoint("BOTTOMLEFT")
  medal.foot:SetPoint("BOTTOMRIGHT")
  medal.foot:SetHeight(MEDAL_FOOT)
  medal.value = Skin.label(medal, "small")
  medal.value:SetJustifyH("CENTER")
  medal.value:SetWordWrap(false)
  medal.value:SetPoint("TOP", medal.picture, "BOTTOM", 0, -4)
  medal.date = Skin.label(medal, "tiny", DIM)
  medal.date:SetJustifyH("CENTER")
  medal.date:SetPoint("TOP", medal.value, "BOTTOM", 0, -1)
  return medal
end

local function drawMedal(trophy, width)
  local medal = take(pool("medals", createMedal))
  medal.trophy = trophy
  medal:SetWidth(width)
  medal.value:SetWidth(width)
  medal.date:SetWidth(width)
  local quality = Skin.TROPHY_QUALITIES[trophy.quality] or MUTED
  medal.picture:SetPicture(trophy.icon or Skin.GOAL_ICONS[trophy.track])
  medal.picture.edge:SetColorTexture(quality[1], quality[2], quality[3], 1)
  medal.foot:SetColorTexture(quality[1], quality[2], quality[3], 1)
  medal.value:SetText(trophy.label)
  Skin.color(medal.value, trophy.fresh and GOLD or TEXT)
  medal.date:SetText(trophy.date)
  return medal
end

-- See all: a plain slot with how many more, opening the cabinet.
local function createSeeAll()
  local tile = CreateFrame("Button", nil, view.content)
  tile:SetHeight(MEDAL_HEIGHT)
  tile:SetScript("OnClick", function() open(true) end)
  tile.slot = CreateFrame("Frame", nil, tile)
  tile.slot:SetSize(MEDAL_ICON, MEDAL_ICON)
  tile.slot:SetPoint("TOP")
  Skin.fill(tile.slot, Skin.SECONDARY)
  Skin.border(tile.slot, Skin.BORDER)
  local hover = Skin.fill(tile.slot, Skin.HOVER, "HIGHLIGHT")
  hover:SetBlendMode("ADD")
  tile.more = Skin.label(tile.slot, "text")
  tile.more:SetPoint("CENTER")
  tile.value = Skin.label(tile, "small")
  tile.value:SetJustifyH("CENTER")
  tile.value:SetPoint("TOP", tile.slot, "BOTTOM", 0, -4)
  tile.value:SetText("See all")
  tile.total = Skin.label(tile, "tiny", DIM)
  tile.total:SetJustifyH("CENTER")
  tile.total:SetPoint("TOP", tile.value, "BOTTOM", 0, -1)
  return tile
end

-- Lays frames out left to right, wrapping, `cell` wide with `gap` between,
-- from y in a width. Returns the y under them.
local function flow(frames, cell, gap, y, width)
  local columns = math.max(1, math.floor((width + gap) / (cell + gap)))
  for i, item in ipairs(frames) do
    local column, row = (i - 1) % columns, math.floor((i - 1) / columns)
    item:SetPoint("TOPLEFT", view.content, "TOPLEFT", INSET + column * (cell + gap), y - row * (MEDAL_HEIGHT + MEDAL_ROW_GAP))
  end
  if #frames == 0 then return y end
  local rows = math.ceil(#frames / columns)
  return y - rows * MEDAL_HEIGHT - (rows - 1) * MEDAL_ROW_GAP
end

-- The newest win, worded like its Feed entry, in a gold plate.
local function createPlate()
  local frame = CreateFrame("Frame", nil, view.content)
  Skin.fill(frame, { GOLD[1], GOLD[2], GOLD[3], 0.07 })
  Skin.border(frame, { GOLD[1], GOLD[2], GOLD[3], 0.35 })
  frame.picture = Skin.feedPicture(frame, PLATE_ICON)
  frame.picture:SetPoint("LEFT", PLATE_PAD + 2, 0)
  frame.title = Skin.label(frame, "title", GOLD)
  frame.title:SetWordWrap(true)
  frame.sub = Skin.label(frame, "small", MUTED)
  return frame
end

local function drawPlate(trophies, y, width)
  plate = plate or createPlate()
  local latest = trophies.latest
  plate:ClearAllPoints()
  plate:SetPoint("TOPLEFT", view.content, "TOPLEFT", INSET, y)
  plate:SetWidth(width)
  plate.picture:SetPicture(latest.icon or Skin.GOAL_ICONS[latest.track], GOLD)
  local textWidth = width - PLATE_ICON - 3 * PLATE_PAD - 2
  plate.title:SetWidth(textWidth)
  plate.title:SetText(latest.text)
  local sub = latest.date
  if trophies.sinceSeen > 0 then
    sub = ("%s · %d more since you last looked"):format(sub, trophies.sinceSeen)
  end
  plate.sub:SetWidth(textWidth)
  plate.sub:SetText(sub)
  local textHeight = plate.title:GetStringHeight() + 3 + plate.sub:GetStringHeight()
  local height = math.max(PLATE_MIN, textHeight + 2 * PLATE_PAD)
  plate.title:ClearAllPoints()
  plate.title:SetPoint("TOPLEFT", plate.picture, "RIGHT", PLATE_PAD, textHeight / 2)
  plate.sub:ClearAllPoints()
  plate.sub:SetPoint("TOPLEFT", plate.title, "BOTTOMLEFT", 0, -3)
  plate:SetHeight(height)
  plate:Show()
  return y - height
end

-- Nothing on the shelf: a faint medal and what will come, centred.
local function createEmpty()
  local frame = CreateFrame("Frame", nil, view.content)
  frame:SetHeight(EMPTY_HEIGHT)
  frame.group = CreateFrame("Frame", nil, frame)
  frame.group:SetHeight(MEDAL_ICON)
  frame.picture = Skin.feedPicture(frame.group, MEDAL_ICON)
  frame.picture:SetPoint("LEFT")
  frame.picture:SetPicture(Skin.FEED_PICTURES.goal)
  frame.picture.picture:SetDesaturated(true)
  frame.picture.picture:SetAlpha(0.5)
  frame.title = Skin.label(frame.group, "heading", TEXT)
  frame.title:SetPoint("TOPLEFT", frame.picture, "TOPRIGHT", 10, -2)
  frame.line = Skin.label(frame.group, "small", MUTED)
  frame.line:SetWordWrap(true)
  frame.line:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -4)
  return frame
end

local function drawEmpty(settled, y, width)
  empty = empty or createEmpty()
  local words = settled and EMPTY_NONE or EMPTY_UNSETTLED
  empty:ClearAllPoints()
  empty:SetPoint("TOPLEFT", view.content, "TOPLEFT", INSET, y)
  empty:SetWidth(width)
  empty.title:SetText(words[1])
  local textWidth = math.min(EMPTY_TEXT, width - MEDAL_ICON - 10)
  empty.line:SetWidth(textWidth)
  empty.line:SetText(words[2])
  local groupWidth = MEDAL_ICON + 10 + math.max(empty.title:GetStringWidth(), textWidth)
  empty.group:ClearAllPoints()
  empty.group:SetPoint("LEFT", empty, "LEFT", math.max(0, (width - groupWidth) / 2), 0)
  empty.group:SetWidth(groupWidth)
  empty:Show()
  return y - EMPTY_HEIGHT
end

-- The tile of Every profession in the Crew names the ones nobody has yet.
local function showTileTooltip(tile)
  local row = tile.row
  if not (row and row.professions) then return end
  GameTooltip:SetOwner(tile, "ANCHOR_RIGHT")
  GameTooltip:AddLine(row.title, TEXT[1], TEXT[2], TEXT[3])
  local missing = {}
  for _, p in ipairs(row.professions) do
    if not p.lit then missing[#missing + 1] = p.name end
  end
  if #missing == 0 then
    GameTooltip:AddLine("Every profession is in the Crew", GOLD[1], GOLD[2], GOLD[3])
  else
    GameTooltip:AddLine("Nobody yet: " .. table.concat(missing, ", "), MUTED[1], MUTED[2], MUTED[3], true)
  end
  GameTooltip:Show()
end

-- A Working on tile: the track's icon in its hue, its name, big numbers,
-- a bar in its hue and how many rungs it has reached.
local function createTile()
  local tile = CreateFrame("Frame", nil, tiles)
  tile:SetHeight(TILE_HEIGHT)
  tile:EnableMouse(true)
  tile:SetScript("OnEnter", showTileTooltip)
  tile:SetScript("OnLeave", hideTooltip)
  Skin.fill(tile, { Skin.WINDOW[1], Skin.WINDOW[2], Skin.WINDOW[3], 1 })
  tile.picture = Skin.feedPicture(tile, TILE_ICON)
  tile.picture:SetPoint("TOPLEFT", TILE_PAD, -TILE_PAD)
  tile.title = Skin.label(tile, "heading", TEXT)
  tile.title:SetWordWrap(false)
  tile.title:SetPoint("TOPLEFT", tile.picture, "TOPRIGHT", 10, 0)
  tile.title:SetPoint("RIGHT", -TILE_PAD, 0)
  tile.numbers = Skin.label(tile, "figure", TEXT)
  tile.numbers:SetWordWrap(false)
  tile.numbers:SetPoint("BOTTOMLEFT", tile.picture, "BOTTOMRIGHT", 10, -2)
  tile.numbers:SetPoint("RIGHT", -TILE_PAD, 0)
  tile.bar = CreateFrame("StatusBar", nil, tile)
  tile.bar:SetPoint("TOPLEFT", TILE_PAD, -(TILE_PAD + TILE_ICON + 8))
  tile.bar:SetPoint("RIGHT", -TILE_PAD, 0)
  tile.bar:SetHeight(TILE_BAR)
  tile.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
  Skin.fill(tile.bar, Skin.TRACK)
  tile.caption = Skin.label(tile, "small", DIM)
  tile.caption:SetWordWrap(false)
  tile.caption:SetPoint("TOPLEFT", tile.bar, "BOTTOMLEFT", 0, -6)
  tile.caption:SetPoint("RIGHT", -TILE_PAD, 0)
  return tile
end

local function drawTile(tile, row)
  tile.row = row
  local hue = Skin.TROPHY_HUES[row.track] or Skin.BAR
  tile.picture:SetPicture(Skin.GOAL_ICONS[row.track], hue)
  tile.title:SetText(row.title)
  if row.complete then
    tile.numbers:SetText("Complete")
    Skin.color(tile.numbers, GOLD)
    tile.bar:SetMinMaxValues(0, 1)
    tile.bar:SetValue(1)
    tile.bar:SetStatusBarColor(GOLD[1], GOLD[2], GOLD[3])
  else
    tile.numbers:SetText(("%s %s/ %s%s|r"):format(ns.Core.grouped(row.value), Skin.hex(DIM),
      ns.Core.grouped(row.goal), row.unit and " " .. row.unit or ""))
    Skin.color(tile.numbers, TEXT)
    tile.bar:SetMinMaxValues(0, math.max(row.goal, 1))
    tile.bar:SetValue(math.min(row.value, row.goal))
    tile.bar:SetStatusBarColor(hue[1], hue[2], hue[3], 0.75)
  end
  if row.last then
    tile.caption:SetText(("%d reached · last %s"):format(row.reached, row.last.date))
  else
    tile.caption:SetText("Not reached yet")
  end
end

-- Working on: a tile per track, two columns (one when narrow), split by
-- hairlines.
local function drawTiles(rows, y, width)
  if not tiles then
    tiles = CreateFrame("Frame", nil, view.content)
    Skin.fill(tiles, Skin.LINE)
  end
  local columns = width >= TWO_COLUMNS and 2 or 1
  local tileWidth = (width - (columns + 1)) / columns
  local p = pool("tiles", createTile)
  for i, row in ipairs(rows) do
    local tile = take(p)
    local column, line = (i - 1) % columns, math.floor((i - 1) / columns)
    tile:SetPoint("TOPLEFT", tiles, "TOPLEFT", 1 + column * (tileWidth + 1), -(1 + line * (TILE_HEIGHT + 1)))
    tile:SetWidth(tileWidth)
    drawTile(tile, row)
  end
  local height = math.ceil(#rows / columns) * (TILE_HEIGHT + 1) + 1
  tiles:ClearAllPoints()
  tiles:SetPoint("TOPLEFT", view.content, "TOPLEFT", INSET, y)
  tiles:SetSize(width, height)
  tiles:Show()
  return y - height
end

local function drawGoalsView(core, trophies, width)
  local y = -INSET
  if not trophies.latest then
    y = drawEmpty(trophies.settled, y, width)
  else
    y = drawPlate(trophies, y, width) - 4
    y = drawHeading("TROPHY SHELF", trophies.count, y)
    local shelf = {}
    for i = 1, math.min(SHELF, #trophies.shelf) do shelf[i] = drawMedal(trophies.shelf[i], SHELF_MEDAL) end
    if #trophies.shelf > SHELF then
      seeAll = seeAll or createSeeAll()
      seeAll:ClearAllPoints()
      seeAll:SetWidth(SHELF_MEDAL)
      seeAll.more:SetText(("+%d"):format(#trophies.shelf - SHELF))
      seeAll.total:SetText(("%d trophies"):format(trophies.count))
      seeAll:Show()
      shelf[#shelf + 1] = seeAll
    end
    y = flow(shelf, SHELF_MEDAL, SHELF_GAP, y, width) - 6
  end
  y = drawHeading("WORKING ON", nil, y)
  return drawTiles(core:goals(), y, width)
end

local function createCabinetHead()
  local head = CreateFrame("Frame", nil, view.content)
  head:SetHeight(CABINET_HEAD)
  Skin.edge(head, "BOTTOM", Skin.LINE)
  head.back = Skin.button(head, "Back to Goals", function() open(false) end)
  head.back.label:SetFontObject(Skin.fonts.small)
  head.back:SetSize(head.back.label:GetStringWidth() + 16, SMALL_BUTTON)
  head.back:SetPoint("LEFT", INSET, 0)
  head.title = Skin.label(head, "heading", TEXT)
  head.title:SetPoint("LEFT", head.back, "RIGHT", 12, 0)
  head.title:SetText("Trophy cabinet")
  head.count = Skin.label(head, "small", MUTED)
  head.count:SetPoint("RIGHT", -INSET, 0)
  return head
end

-- A track's line in the cabinet: its icon, small, and its name.
local function createTrackLine()
  local line = CreateFrame("Frame", nil, view.content)
  line:SetHeight(TRACK_LINE)
  line.picture = Skin.feedPicture(line, TRACK_ICON)
  line.picture:SetPoint("LEFT", INSET, 0)
  line.title = Skin.label(line, "small", MUTED)
  line.title:SetPoint("LEFT", line.picture, "RIGHT", 8, 0)
  return line
end

local function drawCabinet(trophies, width)
  cabinetHead = cabinetHead or createCabinetHead()
  cabinetHead:ClearAllPoints()
  cabinetHead:SetPoint("TOPLEFT", view.content, "TOPLEFT", 0, 0)
  cabinetHead:SetPoint("RIGHT", view.content, "RIGHT")
  cabinetHead.count:SetText(("%d trophies"):format(trophies.count))
  cabinetHead:Show()
  local y = drawHeading("GOALS REACHED", trophies.count, -CABINET_HEAD - 4)
  for _, group in ipairs(trophies.cabinet) do
    local line = take(pool("trackLines", createTrackLine))
    line:SetPoint("TOPLEFT", view.content, "TOPLEFT", 0, y)
    line:SetPoint("RIGHT", view.content, "RIGHT")
    line.picture:SetPicture(Skin.GOAL_ICONS[group.track], Skin.TROPHY_HUES[group.track])
    line.title:SetText(group.title)
    y = y - TRACK_LINE - 4
    local medals = {}
    for i, trophy in ipairs(group.trophies) do medals[i] = drawMedal(trophy, CABINET_MEDAL) end
    y = flow(medals, CABINET_MEDAL, CABINET_GAP, y, width) - TRACK_GAP
  end
  return y
end

-- Draws the tab into Panel's scroll view, `width` wide. onChange redraws
-- the panel (See all and Back).
function GoalsTab.draw(scrollView, core, width, onChange)
  view, redraw = scrollView, onChange
  local trophies = core:trophies()
  -- Nothing to show in the cabinet: back to the Goals view.
  if trophies.count == 0 then cabinetOpen = false end
  startPools()
  -- pairs: the ones not made yet are nil.
  for _, frame in pairs({ plate, empty, seeAll, tiles, cabinetHead }) do frame:Hide() end
  local inner = width - 2 * INSET
  local y
  if cabinetOpen then
    y = drawCabinet(trophies, inner)
  else
    y = drawGoalsView(core, trophies, inner)
  end
  hideUnused()
  view.content:SetHeight(-y + INSET)
end

-- The tab was left: it opens on the Goals view next time.
function GoalsTab.leave()
  cabinetOpen = false
end
