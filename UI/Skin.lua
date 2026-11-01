-- Skin: BFF's own flat look, shared by the panel and the While you were
-- away popup. Dark windows with a 1px border, a gold accent, Arial Narrow
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
Skin.WINDOW = { 0.055, 0.051, 0.078, 0.95 }
Skin.HEADER = { 0.1, 0.095, 0.13, 1 }
Skin.SIDEBAR = { 0, 0, 0, 0.25 }
Skin.RAISED = { 0.106, 0.102, 0.137, 1 }
Skin.LINE = { 1, 1, 1, 0.07 }
Skin.BORDER = { 1, 1, 1, 0.1 }
Skin.HOVER = { 1, 1, 1, 0.05 }

Skin.HEADER_HEIGHT = 30

-- Feed entries shown in gold.
Skin.FEED_HIGHLIGHT = { maxLevel = true, joined = true, left = true }
-- Each Feed kind's icon, on the Feed tab and on toasts. The icons tell kinds
-- apart, not colour: they are all drawn in the same grey. A ding is a plus
-- drawn as text, which centres better than any texture.
Skin.FEED_ICON_COLOR = { 0.82, 0.8, 0.86 }
Skin.FEED_GLYPHS = { ding = "+" }
Skin.FEED_ICONS = {
  maxLevel = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1",
  death = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull",
  newCharacter = "Interface\\FriendsFrame\\UI-Toast-FriendRequestIcon",
  joined = "Interface\\FriendsFrame\\UI-Toast-FriendOnlineIcon",
  left = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
}

-- Draws a Feed kind's icon: the glyph as text, or else the icon texture.
-- A kind with neither gets a plus.
function Skin.feedIcon(icon, glyphLabel, kind)
  local glyph = Skin.FEED_GLYPHS[kind] or not Skin.FEED_ICONS[kind] and "+" or nil
  glyphLabel:SetText(glyph or "")
  icon:SetShown(glyph == nil)
  if not glyph then
    icon:SetTexture(Skin.FEED_ICONS[kind])
    icon:SetDesaturated(true)
    Skin.color(icon, Skin.FEED_ICON_COLOR)
  end
end

-- Each Reaction's icon and name, on the Feed tab, While you were away and
-- toasts. Long-standing spell and achievement icons.
Skin.REACTION_ICONS = {
  cheer = "Interface\\Icons\\Ability_Warrior_BattleShout",
  respects = "Interface\\Icons\\Spell_Holy_Resurrection",
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
  if button.onHover then button.onHover(over) end
end

-- A small square button with a Reaction's icon. :SetReaction(reaction,
-- done) shows it dim and clickable, or bright with a gold edge once given.
function Skin.reactionButton(parent, size, onClick)
  local button = CreateFrame("Button", nil, parent)
  button:SetSize(size, size)
  button.icon = button:CreateTexture(nil, "ARTWORK")
  button.icon:SetAllPoints()
  button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  button.edges = {}
  for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
    button.edges[#button.edges + 1] = Skin.edge(button, side, Skin.GOLD, "OVERLAY")
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
  body = font("BFFFontBody", NARROW, 15),
  text = font("BFFFontText", NARROW, 14),
  small = font("BFFFontSmall", NARROW, 12),
  tiny = font("BFFFontTiny", NARROW, 10),
  glyph = font("BFFFontGlyph", NARROW, 20),
}

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

function Skin.border(frame, color)
  for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do Skin.edge(frame, side, color or Skin.BORDER) end
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

-- A flat button. Primary ones are gold with dark text.
function Skin.button(parent, text, onClick, primary)
  local button = CreateFrame("Button", nil, parent)
  button:SetSize(96, 24)
  button.background = Skin.fill(button, primary and Skin.GOLD or { 1, 1, 1, 0.06 })
  if not primary then Skin.border(button, Skin.BORDER) end
  button.hover = Skin.fill(button, { 1, 1, 1, primary and 0.18 or 0.06 }, "HIGHLIGHT")
  button.hover:SetBlendMode("ADD")
  button.label = Skin.label(button, "text", primary and { 0.1, 0.08, 0 } or Skin.TEXT)
  button.label:SetPoint("CENTER")
  button.label:SetText(text)
  button:SetScript("OnClick", onClick)
  button:SetScript("OnEnter", function(self) hover(self, true) end)
  button:SetScript("OnLeave", function(self) hover(self, false) end)
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
