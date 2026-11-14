-- Skin: BFF's own flat look, shared by the panel, the While you were away
-- popup, toasts and map pins. Dark windows, a gold accent, Arial Narrow
-- for text and Friz Quadrata for titles. Built from solid colour textures
-- and a few long-standing game textures, so it doesn't depend on Blizzard's
-- frame templates looking the same in every client.

local _, ns = ...

local Skin = {}
ns.Skin = Skin

Skin.GOLD = { 1, 0.82, 0.29 }
Skin.TEXT = { 0.91, 0.9, 0.89 }
Skin.MUTED = { 0.68, 0.67, 0.72 }
Skin.DIM = { 0.55, 0.54, 0.6 }
Skin.ONLINE = { 0.44, 0.89, 0.44 }
Skin.OFFLINE = { 0.33, 0.32, 0.37 }
-- 97% opaque: at 95%, bright world text read through a panel's empty
-- space.
Skin.WINDOW = { 0.055, 0.051, 0.078, 0.97 }
Skin.HEADER = { 0.1, 0.095, 0.13, 1 }
-- Washes and hairlines are in the firelight's cream, not pure white, so
-- the window feels lit by the Camp's fire (DESIGN.md, the Firelit Window
-- Rule). Skin.warm(alpha) is one at any strength.
Skin.WARM = { 1, 0.925, 0.784 }
-- A colour's RGB at another alpha.
function Skin.alpha(color, alpha)
  return { color[1], color[2], color[3], alpha }
end
function Skin.warm(alpha)
  return Skin.alpha(Skin.WARM, alpha)
end
Skin.SIDEBAR = { 0.03, 0.02, 0.024, 0.3 }
Skin.RAISED = { 0.106, 0.102, 0.137, 1 }
Skin.LINE = Skin.warm(0.075)
Skin.BORDER = Skin.warm(0.1)
Skin.HOVER = Skin.warm(0.05)
-- The selected sidebar tab's chip, and a hovered one's.
Skin.CHIP = Skin.warm(0.09)
Skin.CHIP_HOVER = Skin.warm(0.04)
-- A section label's rule: this strong by the label, fading out to its end.
Skin.RULE = Skin.warm(0.11)
-- The Feed's timeline: this strong at the top, fading to the end as the
-- entries get older.
Skin.TIMELINE_NEW = Skin.warm(0.16)
Skin.TIMELINE_OLD = Skin.warm(0.03)
-- Every bar: a faint track and a neutral fill. Colour on a bar means
-- something (levels gained, a goal complete).
Skin.TRACK = Skin.warm(0.08)
Skin.BAR = { 1, 1, 1, 0.3 }
-- A secondary button's plate: the small buttons and the Skin buttons.
Skin.SECONDARY = Skin.warm(0.06)
-- Ember Gold Deep, the Camp's deep gold: the arms of the spark that opens
-- a section label.
Skin.EMBER_DEEP = { 0.94, 0.635, 0.11 }
-- The night settling at the panel's foot, away from the fire: this dark
-- at the very bottom, clear at the top of its rise.
Skin.SETTLE = { 0.016, 0.012, 0.031, 0.55 }
-- News catching the light: a gold wash this strong at its left, where
-- the news starts, fading to the right. Your own rows take LIT_FROM and
-- LIT_TO; the latest-win plate is brighter, with its edge brighter along
-- the top.
Skin.LIT_FROM = Skin.alpha(Skin.GOLD, 0.1)
Skin.LIT_TO = Skin.alpha(Skin.GOLD, 0.02)
Skin.LIT_PLATE_FROM = Skin.alpha(Skin.GOLD, 0.15)
Skin.LIT_PLATE_TO = Skin.alpha(Skin.GOLD, 0.03)
Skin.LIT_PLATE_EDGE = Skin.alpha(Skin.GOLD, 0.3)
Skin.LIT_PLATE_TOP = Skin.alpha(Skin.GOLD, 0.55)
-- The Professions tab's tiles: neutral washes by rank (gold is news, not a
-- scale here), a lighter plate at 300, and a faint one for none.
Skin.RANK_SHADES = {
  Apprentice = { 1, 1, 1, 0.11 },
  Journeyman = { 1, 1, 1, 0.19 },
  Expert = { 1, 1, 1, 0.29 },
  Artisan = { 1, 1, 1, 0.41 },
}
Skin.TILE_CAPPED = { 1, 1, 1, 0.66 }
Skin.TILE_NONE = { 1, 1, 1, 0.035 }
-- A faint mark on the window: a bar's step ticks, a tile's "?".
Skin.FAINT_MARK = { 1, 1, 1, 0.35 }

Skin.HEADER_HEIGHT = 30

-- A muted grey for a picture's edge when its kind has no colour, and for
-- the overflow toast's icon.
Skin.FEED_ICON_COLOR = { 0.82, 0.8, 0.86 }
-- Small icons inline in the While you were away popup: the max-level star,
-- the death skull and the Spare lines. The Feed tab and toasts draw
-- Skin.FEED_PICTURES instead.
Skin.FEED_ICONS = {
  maxLevel = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1",
  death = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull",
  newCharacter = "Interface\\FriendsFrame\\UI-Toast-FriendRequestIcon",
  joined = "Interface\\FriendsFrame\\UI-Toast-FriendOnlineIcon",
  left = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
  -- Spares: a Give in the Feed, and the notices.
  gave = "Interface\\GossipFrame\\VendorGossipIcon",
  claimed = "Interface\\GossipFrame\\VendorGossipIcon",
  given = "Interface\\MINIMAP\\TRACKING\\Mailbox",
}

-- Each Feed kind's picture, on the Feed tab and on toasts: a full-colour
-- spell or item icon, square, with a faded 1px edge in the kind's colour.
-- The small grey icons were hard to see on the dark window. A kind with no
-- picture gets the ding's plus.
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
  -- A rare find draws its item's icon; this is until the game has it. The
  -- Catches line in While you were away has no item of its own.
  rareFind = "Interface\\Icons\\INV_Misc_Fish_18",
  catches = "Interface\\Icons\\INV_Misc_Fish_18",
  -- Profession entries draw the profession's own icon; this is for one
  -- whose icon wasn't shared.
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
  -- A rare find's edge is its item's quality: none for common.
  rareFind = false,
}
local EDGE_ALPHA = 0.55
-- A given Reaction's edge: a quiet frame, not gold, so the Feed's gold stays
-- on the news.
local GIVEN_EDGE = { 1, 1, 1, 0.3 }

-- Trophy colours (DESIGN.md, Trophy colours). Each Crew goal track's hue
-- is the Feed kind its news looks like: green for levels, red for deaths,
-- violet for professions. On the track icon's edge and its bar's fill.
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
-- A trophy's tier, in WoW's item quality colours (Core says which): on a
-- medal's edge and foot. Rare is lifted from the game's #0070dd so it
-- reads on Night Window.
Skin.TROPHY_QUALITIES = {
  uncommon = { 0.12, 1, 0 },
  rare = { 0.23, 0.61, 1 },
  epic = { 0.71, 0.36, 0.96 },
  legendary = { 1, 0.5, 0 },
}
-- Item quality colours on items in Catches (DESIGN.md, the Catch Colours
-- Rule): a caught tile's faded edge and an item's name, by the game's
-- quality number. Common (1) has none: no edge, and its name in Ash Text.
-- Uncommon to legendary are the same shades as the trophy tiers.
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

-- An item as the game has it: its name, icon and quality colour (nil for
-- common), each nil while it isn't cached. Asking starts loading it, and
-- GET_ITEM_INFO_RECEIVED says when it has.
function Skin.item(itemId)
  local name, _, quality = getItemInfo(itemId)
  return name, getItemIcon(itemId), quality and Skin.ITEM_QUALITIES[quality]
end

-- How a rare find shows its item, for Core: { text (the name in its
-- quality colour), icon, edge (the quality colour) }.
function Skin.itemLook(itemId)
  local name, icon, quality = Skin.item(itemId)
  local text = name
  if name and quality then text = Skin.hex(quality) .. name .. "|r" end
  return { text = text, icon = icon, edge = quality }
end
-- Each track's icon, on its Working on tile, its medals (but Every
-- profession's, which show the profession) and the cabinet.
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

-- A clear's medal icon, by kind: a dungeon's and a raid's (DESIGN.md,
-- Medal). Classic icons, so Forever has them.
Skin.CLEAR_ICONS = {
  dungeon = "Interface\\Icons\\INV_Misc_Head_Human_01",
  raid = "Interface\\Icons\\INV_Misc_Head_Dragon_Black",
}

-- A Rare kill's medal icon (DESIGN.md, Medal). A classic icon, so Forever
-- has it.
Skin.RARE_ICON = "Interface\\Icons\\INV_Misc_MonsterClaw_04"

-- A square picture `size` wide: an opaque back (so a line behind it is
-- covered), the edge, and the icon inset 1px with its own bevel cropped.
-- :SetKind(kind, icon, edge) draws a Feed kind, with the entry's own icon
-- and edge if it has them (a profession's icon, a rare find's item);
-- :SetPicture(texture, edgeColor) any icon, with no edge when edgeColor is
-- false.
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

-- Each Reaction's icon and name, on the Feed tab, While you were away and
-- toasts. Long-standing spell and achievement icons.
Skin.REACTION_ICONS = {
  cheer = "Interface\\Icons\\INV_Misc_MissileSmall_Red",
  respects = "Interface\\Icons\\INV_Misc_Flower_04",
  welcome = "Interface\\Icons\\Achievement_Reputation_01",
}
Skin.REACTION_NAMES = { cheer = "Cheer", respects = "Pay respects", welcome = "Welcome" }

-- A Reaction's icon inline in text: "|T...|t".
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

-- A small square button with a Reaction's icon. :SetReaction(reaction,
-- done) shows it dim and clickable, or in full colour with a faint edge
-- once given.
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

-- Friz names things: window titles, headings (goal names) and labels
-- (section, day and column labels, written in capitals). Arial Narrow
-- carries everything else; tiny is for badges and chart captions, and
-- figure for the Goals tab's big progress numbers.
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

-- A class's colour as r, g, b; white for an unknown class.
function Skin.classColor(classFilename)
  local color = classFilename and RAID_CLASS_COLORS[classFilename]
  if color then return color.r, color.g, color.b end
  return 1, 1, 1
end

-- A game icon inline in text, cropped inside its bevel: "|T...|t".
function Skin.iconGlyph(texture, size)
  return ("|T%s:%d:%d:0:0:64:64:5:59:5:59|t"):format(texture, size, size)
end

-- A colour as a text escape: "|cffrrggbb".
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

-- A solid texture, filling `frame` unless placed afterwards.
function Skin.fill(frame, color, layer, sublevel)
  local texture = frame:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel)
  texture:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
  texture:SetAllPoints()
  return texture
end

-- A flat chip filling `frame` inset by x and y, with its corners stepped
-- in over `radius` pixels so it reads as rounded (textures have no corner
-- radius). Returns an object whose :SetShown shows or hides every part.
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

-- Shades a texture from one colour to another: left to right
-- ("HORIZONTAL") or bottom to top ("VERTICAL"). Set a white colour
-- texture first; the gradient tints it.
function Skin.gradient(texture, orientation, from, to)
  texture:SetGradient(orientation, CreateColor(from[1], from[2], from[3], from[4] or 1),
    CreateColor(to[1], to[2], to[3], to[4] or 1))
end

-- A gold wash on `frame` that's strongest at its left, for news that
-- catches the fire's light: your own row and the latest win.
function Skin.litWash(frame, from, to)
  local texture = Skin.fill(frame, { 1, 1, 1, 1 })
  Skin.gradient(texture, "HORIZONTAL", from or Skin.LIT_FROM, to or Skin.LIT_TO)
  return texture
end

-- A section label's rule, from the label to whatever ends it: a hairline
-- that fades out as it goes. Place it with SetPoint; its height is set.
function Skin.rule(parent)
  local line = parent:CreateTexture(nil, "ARTWORK")
  line:SetColorTexture(1, 1, 1, 1)
  Skin.gradient(line, "HORIZONTAL", Skin.RULE, Skin.alpha(Skin.RULE, 0))
  line:SetHeight(1)
  return line
end

-- A 1px line along one edge of `frame`.
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

-- 1px lines round `frame`. Returns them.
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

-- Masks `texture` to a circle.
function Skin.round(parent, texture)
  local mask = parent:CreateMaskTexture()
  mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  mask:SetAllPoints(texture)
  texture:AddMaskTexture(mask)
  return texture
end

-- Small flat icons, drawn from solid rectangles ({ x, y, width, height }
-- from the icon's top left) since Arial Narrow has no such glyphs: filter
-- is three narrowing bars, a funnel; sort is an up arrow beside a down one;
-- group is two rows of two squares; bug is a beetle with its wings split;
-- message is a speech bubble with two lines of text in it.
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

-- One screen pixel in a frame's UI units.
local function screenPixel(frame)
  local factor = PixelUtil and PixelUtil.GetPixelToUIUnitFactor and PixelUtil.GetPixelToUIUnitFactor() or 1
  return factor / frame:GetEffectiveScale()
end

-- Lays an icon's rectangles out in whole screen pixels: each unit of the
-- drawing is the same number of pixels (about one UI unit's worth), so a
-- 1-unit stem and a 3-unit row keep their shape at any UI scale.
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

-- The spark that opens a section label, like one off the Camp's fire: a
-- 5-unit cross in ember (75%, enough to read at 5px) with a gold heart, laid out in whole screen
-- pixels like the icons.
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

-- A section label (Label font, Dusk Dim) behind the spark that opens it,
-- the spark at x, y from the parent's `point` (default "LEFT") and the
-- label level with it. Set its text in capitals.
function Skin.sectionLabel(parent, x, y, point)
  local label = Skin.label(parent, "label", Skin.DIM)
  local lead = spark(parent)
  lead:SetPoint(point or "LEFT", x, y)
  label:SetPoint("LEFT", lead, "RIGHT", SPARK_GAP, 0)
  label.spark = lead
  return label
end

-- An icon by kind (a key of ICONS) in a colour; :SetColor recolours it.
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
  -- The UI scale may have changed since.
  icon:SetScript("OnShow", layOutIcon)
  function icon:SetColor(value)
    for _, part in ipairs(self.parts) do part:SetVertexColor(value[1], value[2], value[3], value[4] or 1) end
  end
  icon:SetColor(color or Skin.TEXT)
  return icon
end

-- Puts an icon before a button's centred label, the pair centred together.
-- Returns the room the icon takes, to add to the button's width.
function Skin.leadIcon(button, kind, color)
  local icon = Skin.icon(button, kind, color)
  local room = icon:GetWidth() + 4
  button.label:ClearAllPoints()
  button.label:SetPoint("CENTER", room / 2, 0)
  icon:SetPoint("RIGHT", button.label, "LEFT", -4, 0)
  button.icon = icon
  return room
end

-- A label on a small dark plate, like a level: call :SetText on the result.
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

-- The Unread dot: a 6px Ember Gold dot (DESIGN.md), on a New Feed entry,
-- the sidebar's version label and What's new's changes. The caller places
-- it.
Skin.UNREAD_DOT = 6

function Skin.unreadDot(parent)
  local dot = Skin.fill(parent, Skin.GOLD, "ARTWORK")
  dot:ClearAllPoints()
  dot:SetSize(Skin.UNREAD_DOT, Skin.UNREAD_DOT)
  Skin.round(parent, dot)
  return dot
end

-- The mark for what's new in WoW: Forever: an infinity like the one in the
-- game's emblem, white in the file so a caller can tint it.
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

-- The same mark inline in text, tinted: "|T...|t".
function Skin.foreverGlyph(color)
  return ("|T%s:%d:%d:0:0:64:32:0:64:0:32:%d:%d:%d|t"):format(FOREVER_MARK, FOREVER_MARK_HEIGHT,
    FOREVER_MARK_WIDTH, color[1] * 255, color[2] * 255, color[3] * 255)
end

local function hover(button, shown)
  if button:IsEnabled() then button.hover:SetShown(shown) end
end

local ON_GOLD = { 0.1, 0.08, 0 }

-- A button's plate and label for its kind and state. A disabled button,
-- primary or not, is a secondary plate with dim text: faded gold read as a
-- second primary.
local function look(button, enabled)
  local gold = button.primary and enabled
  local fill = gold and Skin.GOLD or Skin.SECONDARY
  button.background:SetColorTexture(fill[1], fill[2], fill[3], fill[4] or 1)
  for _, line in ipairs(button.lines) do line:SetShown(not gold) end
  button.hover:SetColorTexture(1, 1, 1, gold and 0.18 or 0.06)
  button.hover:SetShown(enabled and button:IsMouseOver())
  Skin.color(button.label, gold and ON_GOLD or enabled and Skin.TEXT or Skin.DIM)
end

-- A flat button. Primary ones are gold with dark text. It restyles itself
-- from OnEnable and OnDisable, so callers add to those with HookScript, not
-- SetScript.
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

-- A small square checkbox with a label to its right; the label is clickable.
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

-- A single-line text box on a dark plate.
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

-- A grey X that hides `target`.
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

-- A small square button in a window's header holding an icon by kind,
-- Smoke Muted, Ash Text while hovered, with a one-line tooltip.
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

-- A movable window closing on Escape, with a title bar: frame.title on the
-- left, frame.headerRight for anything right of it (left of the close
-- button), and frame.header itself.
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
