local _, ns = ...

local Skin = {}
ns.Skin = Skin

Skin.GOLD = { 1, 0.82, 0.29 }
Skin.TEXT = { 0.91, 0.9, 0.89 }
Skin.MUTED = { 0.68, 0.67, 0.72 }
Skin.DIM = { 0.55, 0.54, 0.6 }
Skin.ONLINE = { 0.44, 0.89, 0.44 }
Skin.OFFLINE = { 0.33, 0.32, 0.37 }
Skin.WINDOW = { 0.055, 0.051, 0.078, 0.97 }
Skin.HEADER = { 0.1, 0.095, 0.13, 1 }
Skin.WARM = { 1, 0.925, 0.784 }
function Skin.hideFrom(list, from)
  for i = from, #list do list[i]:Hide() end
end

function Skin.alpha(color, alpha)
  return { color[1], color[2], color[3], alpha }
end
-- WoW: ElvUI turns the default pixel snapping off.
function Skin.snapToPixels(frame)
  if frame.SetRoundLayoutToNearestPixel then frame:SetRoundLayoutToNearestPixel(true) end
end
function Skin.warm(alpha)
  return Skin.alpha(Skin.WARM, alpha)
end
Skin.SIDEBAR = { 0.03, 0.02, 0.024, 0.3 }
Skin.RAISED = { 0.106, 0.102, 0.137, 1 }
Skin.LINE = Skin.warm(0.075)
Skin.BORDER = Skin.warm(0.1)
Skin.HOVER = Skin.warm(0.05)
Skin.CHIP = Skin.warm(0.09)
Skin.CHIP_HOVER = Skin.warm(0.04)
Skin.RULE = Skin.warm(0.11)
Skin.TIMELINE_NEW = Skin.warm(0.16)
Skin.TIMELINE_OLD = Skin.warm(0.03)
Skin.TRACK = Skin.warm(0.08)
Skin.BAR = { 1, 1, 1, 0.3 }
Skin.SECONDARY = Skin.warm(0.06)
Skin.EMBER_DEEP = { 0.94, 0.635, 0.11 }
Skin.SETTLE = { 0.016, 0.012, 0.031, 0.55 }
Skin.LIT_FROM = Skin.alpha(Skin.GOLD, 0.1)
Skin.LIT_TO = Skin.alpha(Skin.GOLD, 0.02)
Skin.LIT_PLATE_FROM = Skin.alpha(Skin.GOLD, 0.15)
Skin.LIT_PLATE_TO = Skin.alpha(Skin.GOLD, 0.03)
Skin.LIT_PLATE_EDGE = Skin.alpha(Skin.GOLD, 0.3)
Skin.LIT_PLATE_TOP = Skin.alpha(Skin.GOLD, 0.55)
Skin.RANK_SHADES = {
  Apprentice = { 1, 1, 1, 0.11 },
  Journeyman = { 1, 1, 1, 0.19 },
  Expert = { 1, 1, 1, 0.29 },
  Artisan = { 1, 1, 1, 0.41 },
}
Skin.TILE_CAPPED = { 1, 1, 1, 0.66 }
Skin.TILE_NONE = { 1, 1, 1, 0.035 }
Skin.FAINT_MARK = { 1, 1, 1, 0.35 }

Skin.HEADER_HEIGHT = 30

Skin.FEED_ICON_COLOR = { 0.82, 0.8, 0.86 }
Skin.FEED_ICONS = {
  maxLevel = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1",
  death = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull",
  newCharacter = "Interface\\FriendsFrame\\UI-Toast-FriendRequestIcon",
  joined = "Interface\\FriendsFrame\\UI-Toast-FriendOnlineIcon",
  left = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
  gave = "Interface\\GossipFrame\\VendorGossipIcon",
  claimed = "Interface\\GossipFrame\\VendorGossipIcon",
  given = "Interface\\MINIMAP\\TRACKING\\Mailbox",
}

Skin.FEED_PICTURES = {
  ding = "Interface\\Icons\\Spell_ChargePositive",
  maxLevel = "Interface\\Icons\\Achievement_Level_80",
  death = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
  newCharacter = "Interface\\Icons\\INV_Misc_GroupNeedMore",
  joined = "Interface\\Icons\\INV_Misc_GroupLooking",
  left = "Interface\\Icons\\Ability_Vanish",
  goal = "Interface\\Icons\\Achievement_General",
  gave = "Interface\\Icons\\INV_Misc_Bag_08",
  claimed = "Interface\\Icons\\INV_Misc_Bag_08",
  given = "Interface\\Icons\\INV_Letter_15",
  rareFind = "Interface\\Icons\\INV_Misc_Fish_18",
  catches = "Interface\\Icons\\INV_Misc_Fish_18",
  newProfession = "Interface\\Icons\\INV_Misc_Book_11",
  professionSkill = "Interface\\Icons\\INV_Misc_Book_11",
  professionMaxed = "Interface\\Icons\\INV_Misc_Book_11",
}
local SPARE = { 0.78, 0.6, 1 }
local CREW = { 0.4, 0.75, 1 }
local PROFESSION = { 0.9, 0.72, 0.42 }
local DEATH = { 0.95, 0.4, 0.36 }
Skin.FEED_EDGES = {
  ding = Skin.ONLINE,
  maxLevel = Skin.GOLD,
  goal = Skin.GOLD,
  death = DEATH,
  newCharacter = CREW,
  joined = CREW,
  left = { 0.6, 0.6, 0.66 },
  gave = SPARE,
  claimed = SPARE,
  given = SPARE,
  newProfession = PROFESSION,
  professionSkill = PROFESSION,
  professionMaxed = Skin.GOLD,
  rareFind = false,
}
local EDGE_ALPHA = 0.55

Skin.CHANGE_PICTURES = {
  major = "Interface\\Icons\\Ability_Warrior_BattleShout",
  minor = "Interface\\Icons\\INV_Misc_Gift_01",
  patch = "Interface\\Icons\\INV_Misc_Wrench_01",
}
Skin.CHANGE_EDGES = {
  major = Skin.GOLD,
  minor = Skin.ONLINE,
  patch = { 0.6, 0.6, 0.66 },
}
local GIVEN_EDGE = { 1, 1, 1, 0.3 }

Skin.TROPHY_HUES = {
  crewLevels = Skin.ONLINE,
  everyone = Skin.ONLINE,
  deaths = DEATH,
  professions = SPARE,
  crewSkill = SPARE,
  everyoneRank = SPARE,
  catches = CREW,
  rares = DEATH,
}
Skin.TROPHY_QUALITIES = {
  uncommon = { 0.12, 1, 0 },
  rare = { 0.23, 0.61, 1 },
  epic = { 0.71, 0.36, 0.96 },
  legendary = { 1, 0.5, 0 },
}
Skin.ITEM_QUALITIES = {
  [0] = { 0.62, 0.62, 0.62 },
  [2] = { 0.12, 1, 0 },
  [3] = { 0.23, 0.61, 1 },
  [4] = { 0.71, 0.36, 0.96 },
  [5] = { 1, 0.5, 0 },
}
Skin.ITEM_EDGE_ALPHA = EDGE_ALPHA

local getItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
local getItemIcon = C_Item and C_Item.GetItemIconByID or GetItemIcon

-- WoW: item info is nil until the item is cached; asking starts the load,
-- and GET_ITEM_INFO_RECEIVED fires once it's in.
function Skin.item(itemId)
  local name, _, quality = getItemInfo(itemId)
  return name, getItemIcon(itemId), quality and Skin.ITEM_QUALITIES[quality]
end

function Skin.itemLook(itemId)
  local name, icon, quality = Skin.item(itemId)
  local text = name
  if name and quality then text = Skin.hex(quality) .. name .. "|r" end
  return { text = text, icon = icon, edge = quality }
end
Skin.GOAL_ICONS = {
  crewLevels = "Interface\\Icons\\Achievement_Level_20",
  everyone = "Interface\\Icons\\Achievement_Level_30",
  deaths = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
  professions = "Interface\\Icons\\INV_Misc_Book_11",
  crewSkill = "Interface\\Icons\\INV_Pick_02",
  everyoneRank = "Interface\\Icons\\INV_Misc_Note_06",
  catches = "Interface\\Icons\\INV_Misc_Fish_18",
  rares = "Interface\\Icons\\Ability_Hunter_SniperShot",
}

Skin.CLEAR_ICONS = {
  dungeon = "Interface\\Icons\\INV_Misc_Head_Human_01",
  raid = "Interface\\Icons\\INV_Misc_Head_Dragon_Black",
}

Skin.RARE_ICON = "Interface\\Icons\\INV_Misc_MonsterClaw_04"

function Skin.feedPicture(parent, size)
  local frame = CreateFrame("Frame", nil, parent)
  frame:SetSize(size, size)
  frame.back = frame:CreateTexture(nil, "ARTWORK", nil, 1)
  frame.back:SetAllPoints()
  frame.back:SetColorTexture(Skin.WINDOW[1], Skin.WINDOW[2], Skin.WINDOW[3], 1)
  frame.edge = frame:CreateTexture(nil, "ARTWORK", nil, 2)
  frame.edge:SetAllPoints()
  frame.picture = frame:CreateTexture(nil, "ARTWORK", nil, 3)
  frame.picture:SetPoint("TOPLEFT", 1, -1)
  frame.picture:SetPoint("BOTTOMRIGHT", -1, 1)
  frame.picture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  function frame:SetPicture(texture, edgeColor)
    local color = edgeColor or Skin.FEED_ICON_COLOR
    self.edge:SetColorTexture(color[1], color[2], color[3], EDGE_ALPHA)
    self.edge:SetShown(edgeColor ~= false)
    self.picture:SetTexture(texture)
  end
  function frame:SetKind(kind, icon, edge)
    self:SetPicture(icon or Skin.FEED_PICTURES[kind] or Skin.FEED_PICTURES.ding, edge or Skin.FEED_EDGES[kind])
  end
  return frame
end

Skin.REACTION_ICONS = {
  cheer = "Interface\\Icons\\INV_Misc_MissileSmall_Red",
  respects = "Interface\\Icons\\INV_Misc_Flower_04",
  welcome = "Interface\\Icons\\Achievement_Reputation_01",
}
Skin.REACTION_NAMES = { cheer = "Cheer", respects = "Pay respects", welcome = "Welcome" }

function Skin.reactionGlyph(reaction, size)
  local icon = Skin.REACTION_ICONS[reaction]
  if not icon then return "" end
  return Skin.iconGlyph(icon, size)
end

local function reactionHover(button, over)
  if not button.done then button.icon:SetAlpha(over and 1 or button.restAlpha) end
  if over and button.reaction then
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetText(button.done and "You reacted" or Skin.REACTION_NAMES[button.reaction])
    GameTooltip:Show()
  elseif not over then
    GameTooltip:Hide()
  end
end

function Skin.reactionButton(parent, size, onClick)
  local button = CreateFrame("Button", nil, parent)
  button:SetSize(size, size)
  button.icon = button:CreateTexture(nil, "ARTWORK")
  button.icon:SetAllPoints()
  button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  button.edges = {}
  for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
    button.edges[#button.edges + 1] = Skin.edge(button, side, GIVEN_EDGE, "OVERLAY")
  end
  button.restAlpha = 0.55
  button:SetScript("OnClick", onClick)
  button:SetScript("OnEnter", function(self) reactionHover(self, true) end)
  button:SetScript("OnLeave", function(self) reactionHover(self, false) end)
  function button:SetReaction(reaction, done)
    self.reaction, self.done = reaction, done == true
    self.icon:SetTexture(Skin.REACTION_ICONS[reaction])
    self.icon:SetDesaturated(not self.done)
    self.icon:SetAlpha(self.done and 1 or self.restAlpha)
    for _, edge in ipairs(self.edges) do edge:SetShown(self.done) end
  end
  return button
end

local NARROW = "Fonts\\ARIALN.TTF"
local FRIZ = "Fonts\\FRIZQT__.TTF"
local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"

local function font(name, path, size)
  local object = CreateFont(name)
  object:SetFont(path, size, "")
  object:SetTextColor(Skin.TEXT[1], Skin.TEXT[2], Skin.TEXT[3])
  return object
end

Skin.fonts = {
  title = font("BFFFontTitle", FRIZ, 13),
  heading = font("BFFFontHeading", FRIZ, 12),
  label = font("BFFFontLabel", FRIZ, 10),
  body = font("BFFFontBody", NARROW, 15),
  text = font("BFFFontText", NARROW, 14),
  small = font("BFFFontSmall", NARROW, 12),
  tiny = font("BFFFontTiny", NARROW, 11),
  figure = font("BFFFontFigure", NARROW, 18),
}

function Skin.classColor(classFilename)
  local color = classFilename and RAID_CLASS_COLORS[classFilename]
  if color then return color.r, color.g, color.b end
  return 1, 1, 1
end

function Skin.iconGlyph(texture, size)
  return ("|T%s:%d:%d:0:0:64:64:5:59:5:59|t"):format(texture, size, size)
end

function Skin.hex(color)
  return ("|cff%02x%02x%02x"):format(color[1] * 255, color[2] * 255, color[3] * 255)
end

function Skin.color(target, color)
  if target.SetTextColor then
    target:SetTextColor(color[1], color[2], color[3], color[4] or 1)
  else
    target:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
  end
end

function Skin.fill(frame, color, layer, sublevel)
  local texture = frame:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel)
  texture:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
  texture:SetAllPoints()
  return texture
end

-- WoW: textures have no corner radius, so the corners are stepped in.
function Skin.chip(frame, color, x, y, radius, layer)
  local chip = { parts = {} }
  local function part()
    local texture = frame:CreateTexture(nil, layer or "BACKGROUND")
    texture:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    chip.parts[#chip.parts + 1] = texture
    return texture
  end
  local middle = part()
  middle:SetPoint("TOPLEFT", x, -(y + radius))
  middle:SetPoint("BOTTOMRIGHT", -x, y + radius)
  for row = 0, radius - 1 do
    local inset = x + radius - row
    local top = part()
    top:SetPoint("TOPLEFT", inset, -(y + row))
    top:SetPoint("TOPRIGHT", -inset, -(y + row))
    top:SetHeight(1)
    local bottom = part()
    bottom:SetPoint("BOTTOMLEFT", inset, y + row)
    bottom:SetPoint("BOTTOMRIGHT", -inset, y + row)
    bottom:SetHeight(1)
  end
  function chip:SetShown(shown)
    for _, texture in ipairs(self.parts) do texture:SetShown(shown) end
  end
  return chip
end

function Skin.gradient(texture, orientation, from, to)
  texture:SetGradient(orientation, CreateColor(from[1], from[2], from[3], from[4] or 1),
    CreateColor(to[1], to[2], to[3], to[4] or 1))
end

function Skin.litWash(frame, from, to)
  local texture = Skin.fill(frame, { 1, 1, 1, 1 })
  Skin.gradient(texture, "HORIZONTAL", from or Skin.LIT_FROM, to or Skin.LIT_TO)
  return texture
end

function Skin.rule(parent)
  local line = parent:CreateTexture(nil, "ARTWORK")
  line:SetColorTexture(1, 1, 1, 1)
  Skin.gradient(line, "HORIZONTAL", Skin.RULE, Skin.alpha(Skin.RULE, 0))
  line:SetHeight(1)
  return line
end

function Skin.edge(frame, side, color, layer)
  local line = frame:CreateTexture(nil, layer or "BORDER")
  line:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
  if side == "TOP" or side == "BOTTOM" then
    line:SetPoint(side .. "LEFT")
    line:SetPoint(side .. "RIGHT")
    line:SetHeight(1)
  else
    line:SetPoint("TOP" .. side)
    line:SetPoint("BOTTOM" .. side)
    line:SetWidth(1)
  end
  return line
end

function Skin.border(frame, color)
  local lines = {}
  for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
    lines[#lines + 1] = Skin.edge(frame, side, color or Skin.BORDER)
  end
  return lines
end

function Skin.label(parent, fontName, color, layer)
  local label = parent:CreateFontString(nil, layer or "OVERLAY")
  label:SetFontObject(Skin.fonts[fontName or "text"])
  label:SetJustifyH("LEFT")
  if color then Skin.color(label, color) end
  return label
end

function Skin.round(parent, texture)
  local mask = parent:CreateMaskTexture()
  mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  mask:SetAllPoints(texture)
  texture:AddMaskTexture(mask)
  return texture
end

-- WoW: the game's Arial Narrow has no glyphs for these icons.
local ICONS = {
  group = { width = 10, height = 9, rects = { { 0, 0, 4, 4 }, { 6, 0, 4, 4 }, { 0, 5, 4, 4 }, { 6, 5, 4, 4 } } },
  filter = { width = 10, height = 8, rects = { { 0, 0, 10, 2 }, { 2, 3, 6, 2 }, { 4, 6, 2, 2 } } },
  sort = { width = 11, height = 9, rects = {
    { 2, 0, 1, 1 }, { 1, 1, 3, 1 }, { 0, 2, 5, 1 }, { 2, 3, 1, 6 },
    { 8, 0, 1, 6 }, { 6, 6, 5, 1 }, { 7, 7, 3, 1 }, { 8, 8, 1, 1 },
  } },
  bug = { width = 11, height = 11, rects = {
    { 2, 0, 1, 1 }, { 8, 0, 1, 1 }, { 3, 1, 1, 1 }, { 7, 1, 1, 1 }, { 4, 2, 3, 1 },
    { 3, 3, 2, 7 }, { 6, 3, 2, 7 }, { 4, 10, 1, 1 }, { 6, 10, 1, 1 },
    { 0, 3, 1, 1 }, { 10, 3, 1, 1 }, { 1, 4, 2, 1 }, { 8, 4, 2, 1 },
    { 0, 6, 3, 1 }, { 8, 6, 3, 1 },
    { 1, 8, 2, 1 }, { 8, 8, 2, 1 }, { 0, 9, 1, 1 }, { 10, 9, 1, 1 },
  } },
  message = { width = 11, height = 10, rects = {
    { 1, 0, 9, 1 }, { 0, 1, 1, 6 }, { 10, 1, 1, 6 }, { 1, 7, 9, 1 },
    { 2, 8, 2, 1 }, { 2, 9, 1, 1 },
    { 2, 3, 7, 1 }, { 2, 5, 5, 1 },
  } },
}

local function screenPixel(frame)
  local factor = PixelUtil and PixelUtil.GetPixelToUIUnitFactor and PixelUtil.GetPixelToUIUnitFactor() or 1
  return factor / frame:GetEffectiveScale()
end

local function layOutIcon(icon)
  local pixel = screenPixel(icon)
  local unit = math.max(1, math.floor(1 / pixel + 0.5)) * pixel
  icon:SetSize(icon.spec.width * unit, icon.spec.height * unit)
  for i, rect in ipairs(icon.spec.rects) do
    local part = icon.parts[i]
    part:ClearAllPoints()
    part:SetPoint("TOPLEFT", rect[1] * unit, -rect[2] * unit)
    part:SetSize(rect[3] * unit, rect[4] * unit)
  end
end

local SPARK = { width = 5, height = 5, rects = { { 2, 0, 1, 5 }, { 0, 2, 5, 1 }, { 2, 2, 1, 1 } } }
local SPARK_ARMS = 0.75
local SPARK_GAP = 6

local function spark(parent)
  local icon = CreateFrame("Frame", nil, parent)
  icon.spec = SPARK
  icon.parts = {}
  for i = 1, #SPARK.rects do
    local part = icon:CreateTexture(nil, "ARTWORK", nil, i == #SPARK.rects and 1 or 0)
    part:SetColorTexture(1, 1, 1, 1)
    icon.parts[i] = part
  end
  local arms = Skin.alpha(Skin.EMBER_DEEP, SPARK_ARMS)
  Skin.color(icon.parts[1], arms)
  Skin.color(icon.parts[2], arms)
  Skin.color(icon.parts[3], Skin.GOLD)
  layOutIcon(icon)
  icon:SetScript("OnShow", layOutIcon)
  return icon
end

function Skin.sectionLabel(parent, x, y, point)
  local label = Skin.label(parent, "label", Skin.DIM)
  local lead = spark(parent)
  lead:SetPoint(point or "LEFT", x, y)
  label:SetPoint("LEFT", lead, "RIGHT", SPARK_GAP, 0)
  label.spark = lead
  return label
end

function Skin.icon(parent, kind, color)
  local icon = CreateFrame("Frame", nil, parent)
  icon.spec = ICONS[kind]
  icon.parts = {}
  for i = 1, #icon.spec.rects do
    local part = icon:CreateTexture(nil, "ARTWORK")
    part:SetColorTexture(1, 1, 1, 1)
    icon.parts[i] = part
  end
  layOutIcon(icon)
  -- WoW: the UI scale can change while the icon is hidden.
  icon:SetScript("OnShow", layOutIcon)
  function icon:SetColor(value)
    for _, part in ipairs(self.parts) do part:SetVertexColor(value[1], value[2], value[3], value[4] or 1) end
  end
  icon:SetColor(color or Skin.TEXT)
  return icon
end

function Skin.leadIcon(button, kind, color)
  local icon = Skin.icon(button, kind, color)
  local room = icon:GetWidth() + 4
  button.label:ClearAllPoints()
  button.label:SetPoint("CENTER", room / 2, 0)
  icon:SetPoint("RIGHT", button.label, "LEFT", -4, 0)
  button.icon = icon
  return room
end

function Skin.badge(parent, fontName, textColor, plateColor)
  local plate = CreateFrame("Frame", nil, parent)
  plate:SetHeight(14)
  Skin.fill(plate, plateColor or Skin.warm(0.08))
  plate.label = Skin.label(plate, fontName or "small", textColor or Skin.TEXT)
  plate.label:SetPoint("CENTER", 0, 0)
  function plate:SetText(text)
    self.label:SetText(text)
    self:SetWidth(math.max(self.label:GetStringWidth() + 8, self:GetHeight()))
  end
  return plate
end

Skin.UNREAD_DOT = 6

function Skin.unreadDot(parent)
  local dot = Skin.fill(parent, Skin.GOLD, "ARTWORK")
  dot:ClearAllPoints()
  dot:SetSize(Skin.UNREAD_DOT, Skin.UNREAD_DOT)
  Skin.round(parent, dot)
  return dot
end

local FOREVER_MARK = "Interface\\AddOns\\BFF\\Media\\Forever"
local FOREVER_MARK_WIDTH = 18
local FOREVER_MARK_HEIGHT = 9

function Skin.foreverMark(parent, color)
  local mark = parent:CreateTexture(nil, "ARTWORK")
  mark:SetTexture(FOREVER_MARK)
  mark:SetSize(FOREVER_MARK_WIDTH, FOREVER_MARK_HEIGHT)
  Skin.color(mark, color or Skin.MUTED)
  return mark
end

function Skin.foreverGlyph(color)
  return ("|T%s:%d:%d:0:0:64:32:0:64:0:32:%d:%d:%d|t"):format(FOREVER_MARK, FOREVER_MARK_HEIGHT,
    FOREVER_MARK_WIDTH, color[1] * 255, color[2] * 255, color[3] * 255)
end

local function hover(button, shown)
  if button:IsEnabled() then button.hover:SetShown(shown) end
end

local ON_GOLD = { 0.1, 0.08, 0 }

local function look(button, enabled)
  local gold = button.primary and enabled
  local fill = gold and Skin.GOLD or Skin.SECONDARY
  button.background:SetColorTexture(fill[1], fill[2], fill[3], fill[4] or 1)
  for _, line in ipairs(button.lines) do line:SetShown(not gold) end
  button.hover:SetColorTexture(1, 1, 1, gold and 0.18 or 0.06)
  button.hover:SetShown(enabled and button:IsMouseOver())
  Skin.color(button.label, gold and ON_GOLD or enabled and Skin.TEXT or Skin.DIM)
end

function Skin.button(parent, text, onClick, primary)
  local button = CreateFrame("Button", nil, parent)
  button:SetSize(96, 24)
  button.primary = primary == true
  button.background = Skin.fill(button, Skin.SECONDARY)
  button.lines = Skin.border(button, Skin.BORDER)
  button.hover = Skin.fill(button, Skin.warm(0.06), "HIGHLIGHT")
  button.hover:SetBlendMode("ADD")
  button.label = Skin.label(button, "text")
  button.label:SetPoint("CENTER")
  button.label:SetText(text)
  look(button, true)
  button:SetScript("OnClick", onClick)
  button:SetScript("OnEnter", function(self) hover(self, true) end)
  button:SetScript("OnLeave", function(self) hover(self, false) end)
  button:SetScript("OnEnable", function(self) look(self, true) end)
  button:SetScript("OnDisable", function(self) look(self, false) end)
  function button:SetText(value) self.label:SetText(value) end
  return button
end

function Skin.checkbox(parent, text, onClick)
  local check = CreateFrame("CheckButton", nil, parent)
  check:SetSize(14, 14)
  local box = Skin.fill(check, { 1, 1, 1, 0.04 })
  Skin.border(check, { 1, 1, 1, 0.25 })
  local tick = Skin.fill(check, Skin.GOLD, "ARTWORK")
  tick:ClearAllPoints()
  tick:SetPoint("TOPLEFT", 3, -3)
  tick:SetPoint("BOTTOMRIGHT", -3, 3)
  check:SetCheckedTexture(tick)
  local hoverTexture = Skin.fill(check, { 1, 1, 1, 0.1 }, "HIGHLIGHT")
  hoverTexture:SetAllPoints(box)
  check.label = Skin.label(check, "small", Skin.MUTED)
  check.label:SetPoint("LEFT", check, "RIGHT", 6, 0)
  check.label:SetText(text)
  check:SetHitRectInsets(0, -(check.label:GetStringWidth() + 6), 0, 0)
  check:SetScript("OnClick", onClick)
  return check
end

Skin.SWITCH_ON = Skin.EMBER_DEEP
Skin.SWITCH_OFF = Skin.OFFLINE
Skin.SWITCH_KNOB_ON = Skin.HEADER
Skin.SWITCH_KNOB_OFF = Skin.MUTED
local SWITCH_WIDTH, SWITCH_HEIGHT = 28, 16
local KNOB, KNOB_INSET = 14, 1
local SWITCH_SLIDE = 0.12

function Skin.switch(parent)
  local switch = CreateFrame("Frame", nil, parent)
  switch:SetSize(SWITCH_WIDTH, SWITCH_HEIGHT)
  local track = {}
  local function part()
    local texture = switch:CreateTexture(nil, "ARTWORK")
    texture:SetColorTexture(1, 1, 1, 1)
    track[#track + 1] = texture
    return texture
  end
  -- WoW: textures have no corner radius.
  for _, side in ipairs({ "LEFT", "RIGHT" }) do
    local cap = part()
    cap:SetSize(SWITCH_HEIGHT, SWITCH_HEIGHT)
    cap:SetPoint(side)
    Skin.round(switch, cap)
  end
  local middle = part()
  middle:SetPoint("TOPLEFT", SWITCH_HEIGHT / 2, 0)
  middle:SetPoint("BOTTOMRIGHT", -SWITCH_HEIGHT / 2, 0)
  local knob = switch:CreateTexture(nil, "OVERLAY")
  knob:SetColorTexture(1, 1, 1, 1)
  knob:SetSize(KNOB, KNOB)
  Skin.round(switch, knob)

  local travel = SWITCH_WIDTH - KNOB - 2 * KNOB_INSET
  local function place(share)
    knob:ClearAllPoints()
    knob:SetPoint("LEFT", KNOB_INSET + travel * share, 0)
  end
  local function slide(self, elapsed)
    self.share = self.on and math.min(1, self.share + elapsed / SWITCH_SLIDE)
      or math.max(0, self.share - elapsed / SWITCH_SLIDE)
    place(self.share)
    if self.share == (self.on and 1 or 0) then self:SetScript("OnUpdate", nil) end
  end

  function switch:SetOn(on, animate)
    on = on and true or false
    if self.on == on then return end
    self.on = on
    local color = on and Skin.SWITCH_ON or Skin.SWITCH_OFF
    for _, texture in ipairs(track) do Skin.color(texture, color) end
    Skin.color(knob, on and Skin.SWITCH_KNOB_ON or Skin.SWITCH_KNOB_OFF)
    if animate and self:IsVisible() then
      self:SetScript("OnUpdate", slide)
    else
      self:SetScript("OnUpdate", nil)
      self.share = on and 1 or 0
      place(self.share)
    end
  end

  function switch:SetEnabled(enabled)
    self:SetAlpha(enabled and 1 or 0.4)
  end

  switch.share = 0
  switch:SetOn(false)
  return switch
end

function Skin.editBox(parent, width)
  local box = CreateFrame("EditBox", nil, parent)
  box:SetSize(width, 24)
  box:SetFontObject(Skin.fonts.text)
  box:SetTextInsets(8, 8, 0, 0)
  box:SetAutoFocus(false)
  Skin.fill(box, { 0, 0, 0, 0.35 })
  Skin.border(box, Skin.BORDER)
  box:SetScript("OnEscapePressed", box.ClearFocus)
  return box
end

function Skin.closeButton(parent, target)
  local button = CreateFrame("Button", nil, parent)
  button:SetSize(22, 22)
  local hoverTexture = Skin.fill(button, Skin.HOVER, "HIGHLIGHT")
  hoverTexture:SetBlendMode("ADD")
  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetTexture("Interface\\Buttons\\UI-StopButton")
  icon:SetSize(12, 12)
  icon:SetPoint("CENTER")
  icon:SetDesaturated(true)
  Skin.color(icon, Skin.MUTED)
  button:SetScript("OnClick", function() target:Hide() end)
  return button
end

function Skin.headerButton(parent, kind, tooltip, onClick)
  local button = CreateFrame("Button", nil, parent)
  button:SetSize(22, 22)
  local hoverTexture = Skin.fill(button, Skin.HOVER, "HIGHLIGHT")
  hoverTexture:SetBlendMode("ADD")
  button.icon = Skin.icon(button, kind, Skin.MUTED)
  button.icon:SetPoint("CENTER")
  button:SetScript("OnClick", onClick)
  button:SetScript("OnEnter", function(self)
    self.icon:SetColor(Skin.TEXT)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(tooltip)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function(self)
    self.icon:SetColor(Skin.MUTED)
    GameTooltip:Hide()
  end)
  return button
end

function Skin.window(name, width, titleText)
  local frame = CreateFrame("Frame", name, UIParent)
  frame:SetWidth(width)
  frame:SetFrameStrata("DIALOG")
  frame:SetToplevel(true)
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:Hide()
  table.insert(UISpecialFrames, name)

  Skin.fill(frame, Skin.WINDOW)
  Skin.border(frame, Skin.BORDER)

  local header = CreateFrame("Frame", nil, frame)
  header:SetPoint("TOPLEFT", 1, -1)
  header:SetPoint("TOPRIGHT", -1, -1)
  header:SetHeight(Skin.HEADER_HEIGHT - 1)
  Skin.fill(header, Skin.HEADER)
  Skin.edge(header, "BOTTOM", Skin.LINE)
  frame.header = header

  frame.title = header:CreateFontString(nil, "OVERLAY")
  frame.title:SetFontObject(Skin.fonts.title)
  Skin.color(frame.title, Skin.GOLD)
  frame.title:SetPoint("LEFT", 12, 0)
  frame.title:SetText(titleText)

  frame.close = Skin.closeButton(header, frame)
  frame.close:SetPoint("RIGHT", -4, 0)
  frame.headerRight = Skin.label(header, "small", Skin.MUTED)
  frame.headerRight:SetJustifyH("RIGHT")
  frame.headerRight:SetPoint("RIGHT", frame.close, "LEFT", -6, 0)
  return frame
end

local Animation = {}
Animation.__index = Animation

function Animation:Play(delay)
  self.group:Stop()
  if self.prepare then self.prepare() end
  for _, animation in ipairs(self.delayed) do animation:SetStartDelay(delay or 0) end
  self.group:Play()
end

function Animation:Stop()
  self.group:Stop()
end

local function animation(group, delayed, prepare)
  return setmetatable({ group = group, delayed = delayed, prepare = prepare }, Animation)
end

function Skin.stamp(frame, scale, duration)
  local group = frame:CreateAnimationGroup()
  local grow = group:CreateAnimation("Scale")
  grow:SetScaleFrom(scale, scale)
  grow:SetScaleTo(1, 1)
  grow:SetOrigin("CENTER", 0, 0)
  grow:SetDuration(duration)
  grow:SetSmoothing("OUT")
  local fade = group:CreateAnimation("Alpha")
  fade:SetFromAlpha(0)
  fade:SetToAlpha(1)
  fade:SetDuration(duration * 0.6)
  fade:SetSmoothing("OUT")
  return animation(group, { grow, fade })
end

function Skin.sweep(frame, width, color, duration)
  local clip = CreateFrame("Frame", nil, frame)
  clip:SetAllPoints()
  clip:SetClipsChildren(true)
  clip:SetFrameLevel(frame:GetFrameLevel() + 5)
  local band = CreateFrame("Frame", nil, clip)
  band:SetPoint("TOPRIGHT", clip, "TOPLEFT")
  band:SetPoint("BOTTOMRIGHT", clip, "BOTTOMLEFT")
  band:SetWidth(width)
  local clear = Skin.alpha(color, 0)
  for i, side in ipairs({ "LEFT", "RIGHT" }) do
    local half = band:CreateTexture(nil, "OVERLAY")
    half:SetColorTexture(1, 1, 1, 1)
    half:SetBlendMode("ADD")
    half:SetPoint("TOP" .. side)
    half:SetPoint("BOTTOM" .. side)
    half:SetWidth(width / 2)
    Skin.gradient(half, "HORIZONTAL", i == 1 and clear or color, i == 1 and color or clear)
  end
  local group = band:CreateAnimationGroup()
  local move = group:CreateAnimation("Translation")
  move:SetDuration(duration)
  move:SetSmoothing("IN_OUT")
  -- WoW: a frame's set width is there at once; a region sized by anchors
  -- reads 0 until layout runs.
  return animation(group, { move }, function() move:SetOffset(frame:GetWidth() + width, 0) end)
end

local function ring(frame, outset, thickness, color)
  local function line()
    local texture = frame:CreateTexture(nil, "OVERLAY")
    texture:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    texture:SetBlendMode("ADD")
    return texture
  end
  local top, bottom, left, right = line(), line(), line(), line()
  top:SetPoint("TOPLEFT", -outset, outset)
  top:SetPoint("TOPRIGHT", outset, outset)
  top:SetHeight(thickness)
  bottom:SetPoint("BOTTOMLEFT", -outset, -outset)
  bottom:SetPoint("BOTTOMRIGHT", outset, -outset)
  bottom:SetHeight(thickness)
  left:SetPoint("TOPLEFT", top, "BOTTOMLEFT")
  left:SetPoint("BOTTOMLEFT", bottom, "TOPLEFT")
  left:SetWidth(thickness)
  right:SetPoint("TOPRIGHT", top, "BOTTOMRIGHT")
  right:SetPoint("BOTTOMRIGHT", bottom, "TOPRIGHT")
  right:SetWidth(thickness)
end

function Skin.shine(frame, color, duration)
  local glow = CreateFrame("Frame", nil, frame)
  glow:SetAllPoints()
  glow:SetFrameLevel(frame:GetFrameLevel() + 5)
  glow:SetAlpha(0)
  ring(glow, 1, 2, color)
  ring(glow, 3, 2, Skin.alpha(color, 0.35))
  local group = glow:CreateAnimationGroup()
  local rise = group:CreateAnimation("Alpha")
  rise:SetFromAlpha(0)
  rise:SetToAlpha(1)
  rise:SetDuration(duration / 3)
  rise:SetSmoothing("OUT")
  rise:SetOrder(1)
  local fall = group:CreateAnimation("Alpha")
  fall:SetFromAlpha(1)
  fall:SetToAlpha(0)
  fall:SetDuration(duration * 2 / 3)
  fall:SetSmoothing("IN")
  fall:SetOrder(2)
  return animation(group, { rise })
end
