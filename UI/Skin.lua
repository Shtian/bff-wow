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
Skin.SIDEBAR = { 0, 0, 0, 0.25 }
Skin.RAISED = { 0.106, 0.102, 0.137, 1 }
Skin.LINE = { 1, 1, 1, 0.07 }
Skin.BORDER = { 1, 1, 1, 0.1 }
Skin.HOVER = { 1, 1, 1, 0.05 }

Skin.HEADER_HEIGHT = 30

-- Feed entries shown in gold: the news. Leaving keeps its grey edge and
-- plain text.
Skin.FEED_HIGHLIGHT = { maxLevel = true, joined = true, goal = true }
-- A muted grey for a picture's edge when its kind has no colour, and for
-- the overflow toast's icon.
Skin.FEED_ICON_COLOR = { 0.82, 0.8, 0.86 }
-- Each Feed kind's small icon, inline in the While you were away popup,
-- and the Goals and Spares tabs' sidebar icons. The Feed tab and toasts
-- draw Skin.FEED_PICTURES instead.
Skin.FEED_ICONS = {
  maxLevel = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1",
  death = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull",
  newCharacter = "Interface\\FriendsFrame\\UI-Toast-FriendRequestIcon",
  joined = "Interface\\FriendsFrame\\UI-Toast-FriendOnlineIcon",
  left = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
  goal = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3",
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
}
local SPARE = { 0.78, 0.6, 1 }
local CREW = { 0.4, 0.75, 1 }
Skin.FEED_EDGES = {
  ding = Skin.ONLINE,
  maxLevel = Skin.GOLD,
  goal = Skin.GOLD,
  death = { 0.95, 0.4, 0.36 },
  newCharacter = CREW,
  joined = CREW,
  left = { 0.6, 0.6, 0.66 },
  gave = SPARE,
  claimed = SPARE,
  given = SPARE,
}
local EDGE_ALPHA = 0.55
-- A given Reaction's edge: a quiet frame, not gold, so the Feed's gold stays
-- on the news.
local GIVEN_EDGE = { 1, 1, 1, 0.3 }

-- A square picture `size` wide: an opaque back (so a line behind it is
-- covered), the edge, and the icon inset 1px with its own bevel cropped.
-- :SetKind(kind) draws a Feed kind; :SetPicture(texture, edgeColor) any
-- icon.
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
    self.picture:SetTexture(texture)
  end
  function frame:SetKind(kind)
    self:SetPicture(Skin.FEED_PICTURES[kind] or Skin.FEED_PICTURES.ding, Skin.FEED_EDGES[kind])
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
  return ("|T%s:%d:%d:0:0:64:64:5:59:5:59|t"):format(icon, size, size)
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
-- carries everything else; tiny is for badges and chart captions.
Skin.fonts = {
  title = font("BFFFontTitle", FRIZ, 13),
  heading = font("BFFFontHeading", FRIZ, 12),
  label = font("BFFFontLabel", FRIZ, 10),
  body = font("BFFFontBody", NARROW, 15),
  text = font("BFFFontText", NARROW, 14),
  small = font("BFFFontSmall", NARROW, 12),
  tiny = font("BFFFontTiny", NARROW, 11),
}

-- A class's colour as r, g, b; white for an unknown class.
function Skin.classColor(classFilename)
  local color = classFilename and RAID_CLASS_COLORS[classFilename]
  if color then return color.r, color.g, color.b end
  return 1, 1, 1
end

-- How long ago, as Last seen words it: 5m, 3h, 2d.
function Skin.ago(seconds)
  seconds = math.max(0, seconds)
  if seconds < 60 * 60 then return ("%dm"):format(math.floor(seconds / 60)) end
  if seconds < 24 * 60 * 60 then return ("%dh"):format(math.floor(seconds / 3600 + 0.5)) end
  return ("%dd"):format(math.floor(seconds / 86400 + 0.5))
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

-- A label on a small dark plate, like a level: call :SetText on the result.
function Skin.badge(parent, fontName, textColor, plateColor)
  local plate = CreateFrame("Frame", nil, parent)
  plate:SetHeight(14)
  Skin.fill(plate, plateColor or { 1, 1, 1, 0.08 })
  plate.label = Skin.label(plate, fontName or "small", textColor or Skin.TEXT)
  plate.label:SetPoint("CENTER", 0, 0)
  function plate:SetText(text)
    self.label:SetText(text)
    self:SetWidth(math.max(self.label:GetStringWidth() + 8, self:GetHeight()))
  end
  return plate
end

local function hover(button, shown)
  if button:IsEnabled() then button.hover:SetShown(shown) end
end

local SECONDARY = { 1, 1, 1, 0.06 }
local ON_GOLD = { 0.1, 0.08, 0 }

-- A button's plate and label for its kind and state. A disabled button,
-- primary or not, is a secondary plate with dim text: faded gold read as a
-- second primary.
local function look(button, enabled)
  local gold = button.primary and enabled
  local fill = gold and Skin.GOLD or SECONDARY
  button.background:SetColorTexture(fill[1], fill[2], fill[3], fill[4] or 1)
  for _, line in ipairs(button.lines) do line:SetShown(not gold) end
  button.hover:SetColorTexture(1, 1, 1, gold and 0.18 or 0.06)
  if not enabled then button.hover:Hide() end
  Skin.color(button.label, gold and ON_GOLD or enabled and Skin.TEXT or Skin.DIM)
end

-- A flat button. Primary ones are gold with dark text.
function Skin.button(parent, text, onClick, primary)
  local button = CreateFrame("Button", nil, parent)
  button:SetSize(96, 24)
  button.primary = primary == true
  button.background = Skin.fill(button, SECONDARY)
  button.lines = Skin.border(button, Skin.BORDER)
  button.hover = Skin.fill(button, { 1, 1, 1, 0.06 }, "HIGHLIGHT")
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
