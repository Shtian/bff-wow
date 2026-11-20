local _, ns = ...

local TrophiesTab = {}
ns.TrophiesTab = TrophiesTab

local Skin = ns.Skin

local GOLD = Skin.GOLD
local TEXT = Skin.TEXT
local MUTED = Skin.MUTED
local DIM = Skin.DIM

local INSET = 12
local HEADING = 28
local PLATE_ICON = 40
local PLATE_PAD = 10
local PLATE_MIN = 60
local MEDAL_ICON = 40
local MEDAL_FOOT = 3
local MEDAL_HEIGHT = 72
local SHELF_MEDAL = 52
local SHELF_GAP = 6
local CABINET_MEDAL = 60
local CABINET_GAP = 4
local MEDAL_ROW_GAP = 10
local SHELF = 7
local STAMP_SCALE = 1.25
local STAMP_TIME = 0.3
local SWEEP_WIDTH = 110
local SWEEP_COLOR = { 1, 0.914, 0.627, 0.32 }
local SWEEP_TIME = 0.6
local SHINE_TIME = 0.45
local SHINE_GAP = 0.15
local TILE_HEIGHT = 74
local TILE_PAD = 10
local TILE_ICON = 28
local TILE_BAR = 4
local TWO_COLUMNS = 400
local CABINET_HEAD = 38
local TRACK_LINE = 24
local TRACK_ICON = 16
local TRACK_GAP = 12
local SMALL_BUTTON = 20
local EMPTY_PAD = 10

local EMPTY_UNSETTLED = { art = "trophies", title = "Counting up the Crew",
  text = "Goals the Crew has already reached show here once everyone's records are in." }
local EMPTY_NONE = { art = "trophies", title = "The shelf is bare",
  text = "Every goal the Crew reaches, dungeon it clears and Rare it slays puts a medal here." }

local view
local core
local cabinetOpen = false
local redraw
local unveiled = false
local pools = {}
local plate, empty, seeAll, tiles, cabinetHead

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

-- WoW: hiding a frame stops its animations, even when it's shown again at once.
local drawCount = 0

local function shown(frame)
  frame.drawn = drawCount
  frame:Show()
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

local function made(name)
  return pools[name] and pools[name].items or {}
end

local function stopUnveil()
  if plate then
    plate.stamp:Stop()
    plate.sweep:Stop()
  end
  for _, medal in ipairs(made("medals")) do
    medal.shine:Stop()
    medal.shining = nil
  end
end

local function trophyKey(trophy)
  return ("%s:%s:%s"):format(trophy.track, trophy.label, trophy.time)
end

local function open(on)
  stopUnveil()
  cabinetOpen = on
  view:SetVerticalScroll(0)
  redraw()
end

local function createHeading()
  local heading = CreateFrame("Frame", nil, view.content)
  heading:SetHeight(HEADING)
  heading.label = Skin.sectionLabel(heading, INSET, -2)
  heading.count = Skin.label(heading, "small", MUTED)
  heading.count:SetPoint("RIGHT", -INSET, -2)
  heading.line = Skin.rule(heading)
  heading.line:SetPoint("LEFT", heading.label, "RIGHT", 8, 0)
  heading.line:SetPoint("RIGHT", heading.count, "LEFT", -8, 0)
  return heading
end

local function drawHeading(text, count, y)
  local heading = take(pool("headings", createHeading))
  heading:SetPoint("TOPLEFT", view.content, "TOPLEFT", 0, y)
  heading:SetPoint("RIGHT", view.content, "RIGHT")
  heading.label:SetText(text)
  heading.count:SetText(count and tostring(count) or "")
  return y - HEADING
end

local function iconOf(trophy)
  if trophy.track == "rareKills" then return Skin.RARE_ICON end
  return trophy.icon or Skin.GOAL_ICONS[trophy.track] or Skin.CLEAR_ICONS[trophy.kind]
end

local function rareLine(rare)
  return ("Level %d %s · %s"):format(rare.level, rare.elite and "Rare Elite" or "Rare", rare.zone)
end

local function showMedalTooltip(medal)
  local trophy, slot = medal.trophy, medal.slot
  if not (trophy or slot) then return end
  GameTooltip:SetOwner(medal, "ANCHOR_RIGHT")
  if not trophy and slot.kind == "rare" then
    GameTooltip:AddLine(slot.name, TEXT[1], TEXT[2], TEXT[3])
    GameTooltip:AddLine(rareLine(slot), MUTED[1], MUTED[2], MUTED[3])
    GameTooltip:AddLine("Not slain yet", DIM[1], DIM[2], DIM[3])
    return GameTooltip:Show()
  end
  if not trophy then
    GameTooltip:AddLine(slot.name, TEXT[1], TEXT[2], TEXT[3])
    GameTooltip:AddLine("Levels " .. slot.levels, MUTED[1], MUTED[2], MUTED[3])
    GameTooltip:AddLine("Not cleared yet", DIM[1], DIM[2], DIM[3])
    return GameTooltip:Show()
  end
  local quality = Skin.TROPHY_QUALITIES[trophy.quality] or TEXT
  if trophy.track == "clears" then
    GameTooltip:AddLine(trophy.instance, quality[1], quality[2], quality[3])
    GameTooltip:AddLine("Cleared " .. trophy.date, MUTED[1], MUTED[2], MUTED[3])
    if #trophy.party > 0 then
      GameTooltip:AddLine(table.concat(trophy.party, ", "), TEXT[1], TEXT[2], TEXT[3], true)
    end
  elseif trophy.track == "rareKills" then
    GameTooltip:AddLine(trophy.label, quality[1], quality[2], quality[3])
    GameTooltip:AddLine(rareLine(trophy), MUTED[1], MUTED[2], MUTED[3])
    GameTooltip:AddLine("Slain " .. trophy.date, MUTED[1], MUTED[2], MUTED[3])
    local by = trophy.by
    if trophy.character and trophy.character ~= by then by = ("%s (%s)"):format(by, trophy.character) end
    GameTooltip:AddLine("By " .. by, TEXT[1], TEXT[2], TEXT[3], true)
  else
    GameTooltip:AddLine(trophy.title, TEXT[1], TEXT[2], TEXT[3])
    GameTooltip:AddLine(trophy.label, quality[1], quality[2], quality[3])
    GameTooltip:AddLine("Reached " .. trophy.date, MUTED[1], MUTED[2], MUTED[3])
  end
  GameTooltip:Show()
end

local function createMedal()
  local medal = CreateFrame("Frame", nil, view.content)
  medal:SetHeight(MEDAL_HEIGHT)
  medal:EnableMouse(true)
  medal:SetScript("OnEnter", showMedalTooltip)
  medal:SetScript("OnLeave", hideTooltip)
  medal.picture = Skin.feedPicture(medal, MEDAL_ICON)
  medal.picture:SetPoint("TOP")
  medal.shine = Skin.shine(medal.picture, GOLD, SHINE_TIME)
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

local function newMedal(width)
  local medal = take(pool("medals", createMedal))
  medal:SetWidth(width)
  medal.value:SetWidth(width)
  medal.date:SetWidth(width)
  medal.picture.picture:SetDesaturated(false)
  medal.picture.picture:SetAlpha(1)
  medal.foot:Show()
  return medal
end

local function drawMedal(trophy, width)
  local medal = newMedal(width)
  if medal.shining and medal.shining ~= trophyKey(trophy) then
    medal.shine:Stop()
    medal.shining = nil
  end
  medal.trophy, medal.slot = trophy, nil
  local quality = Skin.TROPHY_QUALITIES[trophy.quality] or MUTED
  medal.picture:SetPicture(iconOf(trophy))
  medal.picture.edge:SetColorTexture(quality[1], quality[2], quality[3], 1)
  medal.foot:SetColorTexture(quality[1], quality[2], quality[3], 1)
  medal.value:SetText(trophy.label)
  Skin.color(medal.value, trophy.fresh and GOLD or TEXT)
  medal.date:SetText(trophy.date)
  return medal
end

local function drawSlot(slot, width)
  if slot.trophy then return drawMedal(slot.trophy, width) end
  local medal = newMedal(width)
  medal.trophy, medal.slot = nil, slot
  medal.picture:SetPicture(slot.kind == "rare" and Skin.RARE_ICON or Skin.CLEAR_ICONS[slot.kind], Skin.BORDER)
  medal.picture.picture:SetDesaturated(true)
  medal.picture.picture:SetAlpha(0.35)
  medal.foot:Hide()
  medal.value:SetText(slot.label)
  Skin.color(medal.value, DIM)
  medal.date:SetText(slot.levels)
  return medal
end

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

local function createPlate()
  local frame = CreateFrame("Frame", nil, view.content)
  Skin.litWash(frame, Skin.LIT_PLATE_FROM, Skin.LIT_PLATE_TO)
  for _, side in ipairs({ "BOTTOM", "LEFT", "RIGHT" }) do Skin.edge(frame, side, Skin.LIT_PLATE_EDGE) end
  Skin.edge(frame, "TOP", Skin.LIT_PLATE_TOP)
  frame.picture = Skin.feedPicture(frame, PLATE_ICON)
  frame.picture:SetPoint("LEFT", PLATE_PAD + 2, 0)
  frame.title = Skin.label(frame, "title", GOLD)
  frame.title:SetWordWrap(true)
  frame.sub = Skin.label(frame, "small", MUTED)
  frame.stamp = Skin.stamp(frame.picture, STAMP_SCALE, STAMP_TIME)
  frame.stamp.group:SetScript("OnFinished", function()
    local sound = core:unveilSound()
    if sound then ns.Toasts.play(sound) end
  end)
  frame.sweep = Skin.sweep(frame, SWEEP_WIDTH, SWEEP_COLOR, SWEEP_TIME)
  return frame
end

local function drawPlate(trophies, y, width)
  plate = plate or createPlate()
  local latest = trophies.latest
  plate:ClearAllPoints()
  plate:SetPoint("TOPLEFT", view.content, "TOPLEFT", INSET, y)
  plate:SetWidth(width)
  plate.picture:SetPicture(iconOf(latest), GOLD)
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
  shown(plate)
  return y - height
end

local function drawEmpty(settled, y, width)
  empty = empty or ns.EmptyState.new(view.content)
  empty:Set(ns.EmptyState.view(settled and EMPTY_NONE or EMPTY_UNSETTLED, not core:setting("camp")))
  empty:ClearAllPoints()
  empty:SetPoint("TOPLEFT", view.content, "TOPLEFT", INSET, y - EMPTY_PAD)
  local height = empty:Layout(width)
  shown(empty)
  return y - EMPTY_PAD - height - EMPTY_PAD
end

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
    GameTooltip:AddLine("Every profession is in the Crew", MUTED[1], MUTED[2], MUTED[3])
  else
    GameTooltip:AddLine("Nobody yet: " .. table.concat(missing, ", "), MUTED[1], MUTED[2], MUTED[3], true)
  end
  GameTooltip:Show()
end

local function createTile()
  local tile = CreateFrame("Frame", nil, tiles)
  tile:SetHeight(TILE_HEIGHT)
  tile:EnableMouse(true)
  tile:SetScript("OnEnter", showTileTooltip)
  tile:SetScript("OnLeave", hideTooltip)
  tile.right = tile:CreateTexture(nil, "BACKGROUND")
  tile.right:SetColorTexture(Skin.LINE[1], Skin.LINE[2], Skin.LINE[3], Skin.LINE[4])
  tile.right:SetPoint("TOPLEFT", tile, "TOPRIGHT")
  tile.right:SetPoint("BOTTOMLEFT", tile, "BOTTOMRIGHT")
  tile.right:SetWidth(1)
  tile.below = tile:CreateTexture(nil, "BACKGROUND")
  tile.below:SetColorTexture(Skin.LINE[1], Skin.LINE[2], Skin.LINE[3], Skin.LINE[4])
  tile.below:SetPoint("TOPRIGHT", tile, "BOTTOMRIGHT")
  tile.below:SetHeight(1)
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

local function drawTiles(rows, y, width)
  if not tiles then
    tiles = CreateFrame("Frame", nil, view.content)
    Skin.border(tiles, Skin.LINE)
  end
  local columns = width >= TWO_COLUMNS and 2 or 1
  local tileWidth = (width - (columns + 1)) / columns
  local lines = math.ceil(#rows / columns)
  local p = pool("tiles", createTile)
  for i, row in ipairs(rows) do
    local tile = take(p)
    local column, line = (i - 1) % columns, math.floor((i - 1) / columns)
    tile:SetPoint("TOPLEFT", tiles, "TOPLEFT", 1 + column * (tileWidth + 1), -(1 + line * (TILE_HEIGHT + 1)))
    tile:SetWidth(tileWidth)
    tile.right:SetShown(column < columns - 1 and i < #rows)
    tile.below:SetShown(line < lines - 1)
    tile.below:SetPoint("TOPLEFT", tile, "BOTTOMLEFT", column > 0 and -1 or 0, 0)
    drawTile(tile, row)
  end
  local height = lines * (TILE_HEIGHT + 1) + 1
  tiles:ClearAllPoints()
  tiles:SetPoint("TOPLEFT", view.content, "TOPLEFT", INSET, y)
  tiles:SetSize(width, height)
  shown(tiles)
  return y - height
end

local function unveil(trophies, medals)
  local start = 0
  if trophies.latest.unseen then
    plate.stamp:Play()
    plate.sweep:Play(STAMP_TIME)
    start = STAMP_TIME
  end
  local nth = 0
  for _, medal in ipairs(medals) do
    local trophy = medal.trophy
    if trophy and trophy.unseen and trophy ~= trophies.latest then
      medal.shine:Play(start + nth * SHINE_GAP)
      medal.shining = trophyKey(trophy)
      nth = nth + 1
    end
  end
end

local function drawGoalsView(trophies, width)
  local y = -INSET
  if not trophies.latest then
    y = drawEmpty(trophies.settled, y, width)
  else
    y = drawPlate(trophies, y, width) - 4
    y = drawHeading("TROPHY SHELF", trophies.count, y)
    local shelf = {}
    for i = 1, math.min(SHELF, #trophies.shelf) do shelf[i] = drawMedal(trophies.shelf[i], SHELF_MEDAL) end
    seeAll = seeAll or createSeeAll()
    seeAll:ClearAllPoints()
    seeAll:SetWidth(SHELF_MEDAL)
    local more = #trophies.shelf - SHELF
    seeAll.more:SetText(more > 0 and ("+%d"):format(more) or "…")
    seeAll.total:SetText(("%d %s"):format(trophies.count, trophies.count == 1 and "trophy" or "trophies"))
    shown(seeAll)
    shelf[#shelf + 1] = seeAll
    y = flow(shelf, SHELF_MEDAL, SHELF_GAP, y, width) - 6
    if not unveiled then unveil(trophies, shelf) end
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
  return head
end

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
  shown(cabinetHead)
  local y = -CABINET_HEAD - 4
  local grids = {
    { "DUNGEONS CLEARED", trophies.dungeons, trophies.dungeons.cleared },
    { "RAIDS CLEARED", trophies.raids, trophies.raids.cleared },
    { "RARES SLAIN", trophies.rares, trophies.rares.slain },
  }
  for _, grid in ipairs(grids) do
    local slots = grid[2]
    y = drawHeading(grid[1], ("%d / %d"):format(grid[3], slots.total), y)
    local medals = {}
    for i, slot in ipairs(slots.slots) do medals[i] = drawSlot(slot, CABINET_MEDAL) end
    y = flow(medals, CABINET_MEDAL, CABINET_GAP, y, width) - TRACK_GAP
  end
  y = drawHeading("GOALS REACHED", trophies.goalsReached, y)
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

function TrophiesTab.draw(scrollView, theCore, width, onChange)
  view, core, redraw = scrollView, theCore, onChange
  local trophies = core:trophies()
  if trophies.count == 0 then cabinetOpen = false end
  startPools()
  drawCount = drawCount + 1
  local inner = width - 2 * INSET
  local y
  if cabinetOpen then
    y = drawCabinet(trophies, inner)
  else
    y = drawGoalsView(trophies, inner)
  end
  hideUnused()
  -- WoW: Lua 5.1's ipairs stops at the first nil; frames not made yet are nil.
  for _, frame in pairs({ plate, empty, seeAll, tiles, cabinetHead }) do
    if frame.drawn ~= drawCount then frame:Hide() end
  end
  view.content:SetHeight(-y + INSET)
  unveiled = true
end

function TrophiesTab.hidden()
  stopUnveil()
  unveiled = false
end

function TrophiesTab.leave()
  TrophiesTab.hidden()
  cabinetOpen = false
end
