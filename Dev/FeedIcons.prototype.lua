-- PROTOTYPE, throw away. Question: the Feed tab's icons (a 16px grey,
-- desaturated texture on a dark disc) are hard to see; what should the
-- timeline node look like instead?
--
-- Four variants restyle the real Feed tab's nodes (hooked from
-- drawFeedEntry in UI/Panel.lua). /bfficons opens a switcher bar at the
-- bottom of the screen; /bfficons A-F jumps straight to one. E is today's
-- look, for comparison. In memory only: a /reload goes back to A.
--
--   A  Brighter    same node, lighter disc and ring, 20px white icon
--   B  Kind ring   ring and icon tinted by kind (gold, red, green, blue...)
--   C  Bare        no disc or ring, a 24px full-colour icon on the line
--   D  Picture     a round full-colour Interface\Icons picture fills the node
--   E  Current     what ships today
--   F  Square      D's pictures as squares, a faded 1px kind-coloured edge

local _, ns = ...
local Skin = ns.Skin

local P = {}
ns.FeedIconsPrototype = P

local NODE = 26
local VARIANTS = { "A", "B", "C", "D", "E", "F" }
local NAMES = { A = "Brighter", B = "Kind ring", C = "Bare", D = "Picture", E = "Current", F = "Square" }
local current = "A"

local WHITE = { 1, 1, 1 }
local ACCENT = {
  ding = { 0.44, 0.89, 0.44 },
  maxLevel = Skin.GOLD,
  goal = Skin.GOLD,
  death = { 0.95, 0.4, 0.36 },
  newCharacter = { 0.4, 0.75, 1 },
  joined = { 0.4, 0.75, 1 },
  left = { 0.6, 0.6, 0.66 },
  gave = { 0.78, 0.6, 1 },
  claimed = { 0.78, 0.6, 1 },
  given = { 0.78, 0.6, 1 },
}
local PICTURES = {
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

local function mix(color, amount)
  return {
    color[1] + (1 - color[1]) * amount,
    color[2] + (1 - color[2]) * amount,
    color[3] + (1 - color[3]) * amount,
  }
end

local function setColor(texture, color, alpha)
  texture:SetColorTexture(color[1], color[2], color[3], alpha or 1)
end

-- Back to what createFeedEntry built, so every variant starts clean.
local function reset(line)
  line.ring:Show()
  line.ring:SetSize(NODE + 2, NODE + 2)
  setColor(line.ring, WHITE, 0.12)
  line.gap:Show()
  setColor(line.gap, Skin.WINDOW)
  line.disc:Show()
  setColor(line.disc, { 0.13, 0.12, 0.16 })
  line.icon:SetSize(16, 16)
  line.icon:SetDesaturated(true)
  Skin.color(line.icon, Skin.FEED_ICON_COLOR)
  line.glyph:SetFontObject(Skin.fonts.glyph)
  Skin.color(line.glyph, Skin.FEED_ICON_COLOR)
  if line.picture then line.picture:Hide() end
  if line.square then
    line.square:Hide()
    line.squareBack:Hide()
    line.squarePicture:Hide()
  end
end

local style = {}

function style.A(line)
  setColor(line.ring, WHITE, 0.3)
  setColor(line.disc, { 0.26, 0.25, 0.3 })
  line.icon:SetSize(20, 20)
  Skin.color(line.icon, WHITE)
  Skin.color(line.glyph, WHITE)
end

function style.B(line, kind)
  local accent = ACCENT[kind] or Skin.FEED_ICON_COLOR
  setColor(line.ring, accent)
  setColor(line.disc, { accent[1] * 0.28, accent[2] * 0.28, accent[3] * 0.28 })
  line.icon:SetSize(18, 18)
  Skin.color(line.icon, mix(accent, 0.35))
  Skin.color(line.glyph, mix(accent, 0.2))
end

function style.C(line)
  line.ring:Hide()
  line.disc:Hide()
  line.icon:SetSize(24, 24)
  line.icon:SetDesaturated(false)
  Skin.color(line.icon, WHITE)
  Skin.color(line.glyph, WHITE)
end

function style.D(line, kind)
  local accent = ACCENT[kind] or Skin.FEED_ICON_COLOR
  if not line.picture then
    line.picture = line.node:CreateTexture(nil, "OVERLAY", nil, 4)
    line.picture:SetSize(NODE - 2, NODE - 2)
    line.picture:SetPoint("CENTER")
    line.picture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    Skin.round(line.node, line.picture)
  end
  line.picture:SetTexture(PICTURES[kind] or "Interface\\Icons\\INV_Misc_QuestionMark")
  line.picture:Show()
  setColor(line.ring, accent)
  line.icon:Hide()
  line.glyph:SetText("")
end

function style.E() end

-- Square: a faded 1px kind-coloured edge on the line (a window-coloured
-- square under it covers the line), the picture inset 1px, cropped only
-- by the icon's own border.
function style.F(line, kind)
  local accent = ACCENT[kind] or Skin.FEED_ICON_COLOR
  if not line.square then
    line.squareBack = line.node:CreateTexture(nil, "OVERLAY", nil, 2)
    line.squareBack:SetSize(NODE, NODE)
    line.squareBack:SetPoint("CENTER")
    setColor(line.squareBack, Skin.WINDOW)
    line.square = line.node:CreateTexture(nil, "OVERLAY", nil, 3)
    line.square:SetSize(NODE, NODE)
    line.square:SetPoint("CENTER")
    line.squarePicture = line.node:CreateTexture(nil, "OVERLAY", nil, 4)
    line.squarePicture:SetSize(NODE - 2, NODE - 2)
    line.squarePicture:SetPoint("CENTER")
    line.squarePicture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  end
  line.ring:Hide()
  line.gap:Hide()
  line.disc:Hide()
  setColor(line.square, accent, 0.55)
  line.square:Show()
  line.squareBack:Show()
  line.squarePicture:SetTexture(PICTURES[kind] or "Interface\\Icons\\INV_Misc_QuestionMark")
  line.squarePicture:Show()
  line.icon:Hide()
  line.glyph:SetText("")
end

function P.style(line, kind)
  reset(line)
  style[current](line, kind)
end

-- The switcher: a pill at the bottom of the screen, obviously not BFF's.
local bar
local function label()
  return ("PROTOTYPE  %s (%s)"):format(current, NAMES[current])
end

local function set(variant)
  current = variant
  if bar then bar.label:SetText(label()) end
  ns.Panel.show("feed")
end

local function step(by)
  for i, v in ipairs(VARIANTS) do
    if v == current then
      set(VARIANTS[(i - 1 + by) % #VARIANTS + 1])
      return
    end
  end
end

local function arrow(text, by)
  local button = CreateFrame("Button", nil, bar)
  button:SetSize(28, 24)
  button.label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  button.label:SetPoint("CENTER")
  button.label:SetText(text)
  button:SetScript("OnClick", function() step(by) end)
  return button
end

local function showBar()
  if not bar then
    bar = CreateFrame("Frame", nil, UIParent)
    bar:SetSize(260, 30)
    bar:SetPoint("BOTTOM", 0, 140)
    bar:SetFrameStrata("TOOLTIP")
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.85, 0.2, 0.55, 0.9)
    bar.label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    bar.label:SetPoint("CENTER")
    arrow("<", -1):SetPoint("LEFT", 2, 0)
    arrow(">", 1):SetPoint("RIGHT", -2, 0)
    local close = arrow("x", 0)
    close:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 22)
    close:SetScript("OnClick", function() bar:Hide() end)
  end
  bar.label:SetText(label())
  bar:Show()
end

SLASH_BFFICONS1 = "/bfficons"
SlashCmdList.BFFICONS = function(input)
  local variant = ((input or ""):match("^%s*(%a)") or ""):upper()
  if variant and NAMES[variant] then set(variant) else set(current) end
  showBar()
end
