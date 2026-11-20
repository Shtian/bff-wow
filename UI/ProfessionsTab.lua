local _, ns = ...

local ProfessionsTab = {}
ns.ProfessionsTab = ProfessionsTab

local Skin = ns.Skin

local INSET = 12
local HEAD = 26
local ICON = 16
local NAME = 82
local NAME_MAX = 140
local TILE = 18
local GAP = 1
local DIVIDER = 6
local ROW = 25
local BAR = 2
local EMPTY = { art = "professions", title = "No trades yet",
  text = "When anyone learns a profession, it shows up here with their skill." }
local QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"

local MUTED = Skin.MUTED
local DIM = Skin.DIM
local TEXT = Skin.TEXT

local core
local page
local view
local sortBy
local rosterOrder = function() return nil end

function ProfessionsTab.sortLike(order)
  rosterOrder = order
end

local function showTooltip(owner)
  if not owner.tooltip then return end
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  owner.tooltip(owner)
  GameTooltip:Show()
end

local function hoverable(parent)
  local item = CreateFrame("Frame", nil, parent)
  item:EnableMouse(true)
  item:SetScript("OnEnter", function(self)
    if self.column then
      view.columnWash:ClearAllPoints()
      view.columnWash:SetPoint("TOPLEFT", view.list.content, "TOPLEFT", self.x, 0)
      view.columnWash:SetPoint("BOTTOMLEFT", view.list.content, "BOTTOMLEFT", self.x, 0)
      view.columnWash:SetWidth(self.width)
      view.columnWash:Show()
    end
    if self.row then self.row.hover:Show() end
    showTooltip(self)
  end)
  item:SetScript("OnLeave", function(self)
    view.columnWash:Hide()
    if self.row then self.row.hover:Hide() end
    GameTooltip:Hide()
  end)
  return item
end

local function createView()
  view = CreateFrame("Frame", nil, page.frame)
  view:SetAllPoints()
  view.head = CreateFrame("Frame", nil, view)
  view.head:SetPoint("TOPLEFT")
  view.head:SetPoint("TOPRIGHT")
  view.head:SetHeight(HEAD)
  Skin.edge(view.head, "BOTTOM", Skin.LINE)
  view.icons = {}
  view.sortMark = Skin.fill(view.head, TEXT, "ARTWORK")
  view.sortMark:ClearAllPoints()
  view.sortMark:SetSize(ICON, 2)
  view.divider = view:CreateTexture(nil, "ARTWORK")
  view.divider:SetColorTexture(Skin.LINE[1], Skin.LINE[2], Skin.LINE[3], Skin.LINE[4])
  view.divider:SetWidth(1)
  view.list = page:scrollView()
  view.list:Between(HEAD, 0)
  view.columnWash = Skin.fill(view.list.content, Skin.HOVER, "BORDER")
  view.columnWash:Hide()
  view.rows = {}
  view.empty = ns.EmptyState.new(view)
end

local function columns(professions)
  local divider = 0
  for _, p in ipairs(professions) do
    if p.secondary then divider = DIVIDER end
  end
  local count = math.max(#professions, 1)
  local room = page.listWidth - INSET - divider
  local name = math.max(NAME, math.min(NAME_MAX, room - count * (TILE + GAP)))
  local width = math.floor((room - name) / count) - GAP
  local xs, dividerX = {}, nil
  local x = INSET + name
  for i, p in ipairs(professions) do
    if p.secondary and not dividerX then
      dividerX = x + DIVIDER / 2 - 1
      x = x + DIVIDER
    end
    xs[i] = x
    x = x + width + GAP
  end
  return xs, width, dividerX, name
end

local function iconTooltip(icon)
  local p = icon.profession
  GameTooltip:AddLine(p.name, 1, 1, 1)
  local count = 0
  for _, member in ipairs(view.data.members) do
    if member.cells[icon.index] then count = count + 1 end
  end
  local text = count == 0 and "Nobody in the Crew has it yet"
    or ("%d Member%s %s it"):format(count, count == 1 and "" or "s", count == 1 and "has" or "have")
  GameTooltip:AddLine(text, MUTED[1], MUTED[2], MUTED[3])
  GameTooltip:AddLine(sortBy == p.skillLine and "Click to sort as the Roster" or "Click to sort by it",
    DIM[1], DIM[2], DIM[3])
end

local function professionIcon(index)
  local icon = view.icons[index]
  if icon then return icon end
  icon = hoverable(view.head)
  icon:SetSize(ICON, ICON)
  icon.texture = icon:CreateTexture(nil, "ARTWORK")
  icon.texture:SetAllPoints()
  icon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  icon.tooltip = iconTooltip
  icon:SetScript("OnMouseUp", function(self)
    sortBy = sortBy ~= self.profession.skillLine and self.profession.skillLine or nil
    ProfessionsTab.draw(page)
    if GameTooltip:IsOwned(self) then showTooltip(self) end
  end)
  view.icons[index] = icon
  return icon
end

local function tileTooltip(tile)
  local member, profession = tile.member, tile.profession
  GameTooltip:AddLine(profession.name, 1, 1, 1)
  local cell = member.cells[tile.index]
  if not cell then
    local who = member.own and "You don't" or ("%s doesn't"):format(member.displayName or "They")
    GameTooltip:AddLine(who .. " have it", MUTED[1], MUTED[2], MUTED[3])
    return
  end
  for _, character in ipairs(cell.characters) do
    local skill = ("%d/%d"):format(character.skill, character.max)
    if character.rank then skill = Skin.hex(MUTED) .. character.rank .. "|r " .. skill end
    local r, g, b = Skin.classColor(character.classFilename)
    GameTooltip:AddDoubleLine(character.fullName, skill, r, g, b, TEXT[1], TEXT[2], TEXT[3])
  end
end

local function professionTile(row, index)
  local tile = row.tiles[index]
  if tile then return tile end
  tile = hoverable(row)
  tile.row = row
  tile.column = true
  tile.tooltip = tileTooltip
  tile.plate = tile:CreateTexture(nil, "ARTWORK")
  tile.plate:SetPoint("TOPLEFT")
  tile.plate:SetPoint("TOPRIGHT")
  tile.plate:SetHeight(TILE)
  tile.value = Skin.label(tile, "tiny")
  tile.value:SetPoint("CENTER", tile.plate, "CENTER", 0, 0)
  tile.track = Skin.fill(tile, Skin.TRACK, "ARTWORK")
  tile.track:ClearAllPoints()
  tile.track:SetPoint("BOTTOMLEFT")
  tile.track:SetPoint("BOTTOMRIGHT")
  tile.track:SetHeight(BAR)
  tile.bar = Skin.fill(tile, Skin.BAR, "OVERLAY")
  tile.bar:ClearAllPoints()
  tile.bar:SetPoint("BOTTOMLEFT")
  tile.bar:SetHeight(BAR)
  row.tiles[index] = tile
  return tile
end

local function drawTile(tile, cell, width)
  tile:SetSize(width, TILE + 2 + BAR)
  tile.width = width
  local shade = not cell and Skin.TILE_NONE or cell.capped and Skin.TILE_CAPPED
    or Skin.RANK_SHADES[cell.rank] or Skin.RANK_SHADES.Apprentice
  tile.plate:SetColorTexture(shade[1], shade[2], shade[3], shade[4])
  tile.value:SetShown(cell ~= false)
  tile.track:SetShown(cell ~= false)
  tile.bar:SetShown(cell ~= false and cell.skill > 0)
  if cell then
    tile.value:SetText(cell.skill)
    Skin.color(tile.value, cell.capped and Skin.WINDOW or TEXT)
    tile.bar:SetWidth(math.max(1, width * math.min(cell.skill / cell.max, 1)))
  end
  tile:Show()
end

local function professionRow(index)
  local row = view.rows[index]
  if row then return row end
  row = CreateFrame("Frame", nil, view.list.content)
  row:SetHeight(ROW)
  row.ownBackground = Skin.litWash(row)
  row.hover = Skin.fill(row, Skin.HOVER, "BORDER")
  row.hover:Hide()
  row.edge = Skin.edge(row, "TOP", Skin.LINE)
  row.name = Skin.label(row, "body")
  row.name:SetPoint("LEFT", INSET, 0)
  row.name:SetWordWrap(false)
  row.unknown = Skin.label(row, "small", MUTED)
  row.unknown:SetText("Not shared yet")
  row.tiles = {}
  view.rows[index] = row
  return row
end

function ProfessionsTab.draw(thePage)
  page, core = thePage, thePage.core
  if not view then createView() end
  local data = core:professions(rosterOrder(), sortBy)
  view.data = data
  local xs, width, dividerX, nameWidth = columns(data.professions)

  for i, p in ipairs(data.professions) do
    local icon = professionIcon(i)
    icon.profession, icon.index = p, i
    icon:ClearAllPoints()
    icon:SetPoint("TOPLEFT", view.head, "TOPLEFT", xs[i] + (width - ICON) / 2, -5)
    icon.texture:SetTexture(p.icon or QUESTION_MARK)
    icon.texture:SetDesaturated(not p.had)
    icon:SetAlpha(p.had and 1 or 0.55)
    icon:Show()
  end
  Skin.hideFrom(view.icons, #data.professions + 1)
  local sorted
  for i, p in ipairs(data.professions) do
    if p.skillLine == sortBy then sorted = i end
  end
  view.sortMark:SetShown(sorted ~= nil)
  if sorted then
    view.sortMark:ClearAllPoints()
    view.sortMark:SetPoint("BOTTOMLEFT", view.head, "BOTTOMLEFT", xs[sorted] + (width - ICON) / 2, 1)
  end

  local members = data.none and {} or data.members
  if data.none then
    view.empty:Set(ns.EmptyState.view(EMPTY, not core:setting("camp")))
    view.empty:Place(view, page.width, page.height - HEAD, HEAD)
  else
    view.empty:Hide()
  end
  local y = 0
  for i, member in ipairs(members) do
    local row = professionRow(i)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", view.list.content, "TOPLEFT", 0, y)
    row:SetPoint("TOPRIGHT", view.list.content, "TOPRIGHT", 0, y)
    row.ownBackground:SetShown(member.own)
    row.edge:SetShown(i > 1)
    row.name:SetWidth(nameWidth - 4)
    row.name:SetText(member.displayName or (member.own and "You") or "")
    row.unknown:ClearAllPoints()
    row.unknown:SetPoint("LEFT", INSET + nameWidth, 0)
    Skin.color(row.name, TEXT)
    row.unknown:SetShown(not member.known)
    for c, p in ipairs(data.professions) do
      local tile = professionTile(row, c)
      if member.known then
        tile.member, tile.profession, tile.index, tile.x = member, p, c, xs[c]
        tile:ClearAllPoints()
        tile:SetPoint("TOPLEFT", row, "TOPLEFT", xs[c], -2)
        drawTile(tile, member.cells[c], width)
      else
        tile:Hide()
      end
    end
    Skin.hideFrom(row.tiles, #data.professions + 1)
    row:Show()
    y = y - ROW
  end
  Skin.hideFrom(view.rows, #members + 1)

  view.divider:ClearAllPoints()
  view.divider:SetShown(dividerX ~= nil)
  if dividerX then
    view.divider:SetPoint("TOPLEFT", view, "TOPLEFT", dividerX, -4)
    view.divider:SetPoint("BOTTOMLEFT", view, "BOTTOMLEFT", dividerX, 4)
  end

  view.list:Fit(-y + 6)
end
