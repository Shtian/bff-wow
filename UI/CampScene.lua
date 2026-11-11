-- CampScene: draws Core's camp() as pixel art: a band with the night
-- backdrop, the fire, and each actor, grave and spark where Core placed
-- them. The panel's band and the While you were away popup's use it, and
-- small seated figures stand in for class icons on Roster rows and toasts.
-- It works out nothing about the Crew: positions are Core's, in art pixels
-- from the fire. One art pixel is a whole number of screen pixels near a
-- target size (artUnit), so the art stays crisp at any UI scale. One
-- OnUpdate on the band steps the fire, embers and sleep marks, and
-- runs only while the band is shown. Silent. See docs/design/camp.md.

local _, ns = ...

local CampScene = {}
ns.CampScene = CampScene

local Skin = ns.Skin
local Sheet = ns.CampSheet
local LAYOUT = ns.Core.CAMP_LAYOUT

-- About 3 UI units per art pixel in the band, and 2 on rows and toasts.
CampScene.BAND_TARGET = 3
CampScene.FIGURE_TARGET = 2
-- The band's height in UI units, and the panel's shorter one in a small
-- window; each rounds down to whole art pixels.
CampScene.HEIGHT = 120
CampScene.SHORT_HEIGHT = 78
-- Animation ticks per second, and how long a Cheer's hop lasts.
local FPS = 6
local HOP_FOR = 0.7
-- Rows up from the band's bottom: where the ground line is, and where each
-- sprite's bottom sits on it (from the prototype).
local ROW = {
  seat = 3, seated = 4, hop = 6, asleep = 3, grave = 3, flower = 2,
  logs = 3, fire = 5, tent = 5, ember = 16,
}
-- Each sprite's x from its actor's (or grave's) left edge. A spark sits
-- by a seated figure's head, or on a sleeper's blanket, so even the short
-- band never crops it.
local OFFSET = { seat = -1, flower = 2, seatedSpark = 9, asleepSpark = 11 }
-- A sleeper's three z's, small to normal, staggered up from the head:
-- each one's x from the sleeper's left edge and its bottom row from the
-- bedroll's top. They appear one at a time, hold, then clear, a step every
-- SLEEP_STEP ticks; the name sits above the tallest.
local SLEEP = { { x = 7, row = 0 }, { x = 12, row = 3 }, { x = 6, row = 5 } }
local SLEEP_STEP = 4
local SPARK_ROW = { seated = 13, asleep = 4 }
-- The name's gap above a figure's head, in art rows.
local LABEL_GAP = 1

-- One art pixel in a frame's UI units: a whole number of screen pixels,
-- the nearest to target UI units (BAND_TARGET or FIGURE_TARGET).
function CampScene.artUnit(frame, target)
  local factor = PixelUtil and PixelUtil.GetPixelToUIUnitFactor and PixelUtil.GetPixelToUIUnitFactor() or 1
  local onePixel = factor / frame:GetEffectiveScale()
  local pixels = math.max(1, math.floor(target / onePixel + 0.5))
  return pixels * onePixel
end

-- A texture on the sprite sheet, filtered nearest so texels stay square.
-- The file and filter are set once.
local function texture(parent, layer, sublevel)
  local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sublevel or 0)
  t:SetTexture(Sheet.file, "CLAMP", "CLAMP", "NEAREST")
  return t
end

-- Shows a sprite of the sheet on a texture, at its size in art pixels.
local function setSprite(t, name, unit)
  local s = Sheet.sprites[name]
  if t.sprite ~= name then
    t:SetTexCoord(s[1] / Sheet.width, (s[1] + s[3]) / Sheet.width, s[2] / Sheet.height, (s[2] + s[4]) / Sheet.height)
    t.sprite = name
  end
  t:SetSize(s[3] * unit, s[4] * unit)
  t:Show()
end

local function tint(t, classFilename)
  t:SetVertexColor(Skin.classColor(classFilename))
end

-- A small seated figure, two layers on one rectangle: the cloth in the
-- class colour under skin and outline. :SetClass(classFilename) draws it;
-- :Layout() sizes it at target (default FIGURE_TARGET), after the UI scale
-- changes.
function CampScene.figure(parent, target)
  local frame = CreateFrame("Frame", nil, parent)
  frame.cloth = texture(frame, "ARTWORK", 0)
  frame.cloth:SetPoint("BOTTOMLEFT")
  frame.skin = texture(frame, "ARTWORK", 1)
  frame.skin:SetPoint("BOTTOMLEFT")
  function frame:Layout()
    local unit = CampScene.artUnit(self, target or CampScene.FIGURE_TARGET)
    local s = Sheet.sprites.seated
    self:SetSize(s[3] * unit, s[4] * unit)
    setSprite(self.cloth, "seatedCloth", unit)
    setSprite(self.skin, "seated", unit)
  end
  function frame:SetClass(classFilename)
    self:Layout()
    tint(self.cloth, classFilename)
    self:Show()
  end
  return frame
end

-- A name above a figure: centred, cut to its width, never wrapped.
local function nameLabel(parent)
  local label = Skin.label(parent, "small", nil, "OVERLAY")
  label:SetJustifyH("CENTER")
  label:SetWordWrap(false)
  return label
end

-- Pools of parts, made as needed and hidden when unused.
local function pool(make)
  return { make = make, used = 0 }
end

local function take(list)
  list.used = list.used + 1
  local item = list[list.used]
  if not item then
    item = list.make()
    list[list.used] = item
  end
  return item
end

local function hideRest(list)
  for i = list.used + 1, #list do
    for _, part in pairs(list[i]) do
      if type(part) == "table" and part.Hide then part:Hide() end
    end
  end
end

-- Places a texture with its bottom left at art pixel x from the fire and
-- `row` rows up from the band's bottom.
local function put(scene, t, x, row)
  t:ClearAllPoints()
  t:SetPoint("BOTTOMLEFT", scene.art, "BOTTOMLEFT", (scene.fire + x) * scene.unit, row * scene.unit)
end

local function hopping(scene, actor)
  local untilTime = actor.pose == "seated" and scene.hops[actor.memberId]
  return untilTime ~= nil and untilTime and untilTime > GetTime()
end

-- Draws one actor's figure, seat or sleep marks, spark and name, for the
-- animation frame f.
local function drawActor(scene, parts, actor, f)
  local x = actor.x
  local top
  if actor.pose == "seated" then
    local hop = hopping(scene, actor)
    local row = hop and ROW.hop or ROW.seated
    setSprite(parts.seat, "seat", scene.unit)
    put(scene, parts.seat, x + OFFSET.seat, ROW.seat)
    setSprite(parts.cloth, hop and "hopCloth" or "seatedCloth", scene.unit)
    setSprite(parts.skin, hop and "hop" or "seated", scene.unit)
    put(scene, parts.cloth, x, row)
    put(scene, parts.skin, x, row)
    for _, z in ipairs(parts.sleep) do z:Hide() end
    top = row + Sheet.sprites.seated[4]
  else
    parts.seat:Hide()
    setSprite(parts.cloth, "asleepCloth", scene.unit)
    setSprite(parts.skin, "asleep", scene.unit)
    put(scene, parts.cloth, x, ROW.asleep)
    put(scene, parts.skin, x, ROW.asleep)
    local bed = ROW.asleep + Sheet.sprites.asleep[4]
    -- Steps 0-2 add a z each, 3 holds all three, 4 clears.
    local shown = math.floor(f / SLEEP_STEP) % 5
    shown = shown == 4 and 0 or math.min(shown + 1, 3)
    for i, z in ipairs(parts.sleep) do
      if i <= shown then
        setSprite(z, "sleep" .. i, scene.unit)
        put(scene, z, x + SLEEP[i].x, bed + SLEEP[i].row)
      else
        z:Hide()
      end
    end
    top = bed + SLEEP[3].row + Sheet.sprites.sleep3[4]
  end
  tint(parts.cloth, actor.classFilename)

  local centre = x + actor.width / 2
  local label = parts.label
  label:ClearAllPoints()
  label:SetPoint("BOTTOM", scene.art, "BOTTOMLEFT", (scene.fire + centre) * scene.unit, (top + LABEL_GAP) * scene.unit)
  label:SetWidth(actor.labelWidth * scene.unit)
  local text = scene.gains and actor.gained or (not scene.gains and actor.label) or nil
  label:SetText(text or "")
  if scene.gains then
    Skin.color(label, actor.highlight and Skin.GOLD or Skin.ONLINE)
  else
    label:SetTextColor(Skin.classColor(actor.classFilename))
  end
  label:SetShown(text ~= nil)

  if actor.spark then
    setSprite(parts.spark, "spark", scene.unit)
    local seated = actor.pose == "seated"
    local lift = seated and hopping(scene, actor) and ROW.hop - ROW.seated or 0
    put(scene, parts.spark, x + (seated and OFFSET.seatedSpark or OFFSET.asleepSpark),
      SPARK_ROW[actor.pose] + lift)
  else
    parts.spark:Hide()
  end
end

-- Draws the fire, embers and everything Core placed, for frame f.
local function drawFrame(scene, f)
  local view = scene.view
  local unit = scene.unit
  setSprite(scene.logs, "logs", unit)
  put(scene, scene.logs, -7, ROW.logs)
  setSprite(scene.flame, "fire" .. (f % 3 + 1), unit)
  put(scene, scene.flame, -5, ROW.fire)
  for i, ember in ipairs(scene.embers) do
    local life = math.floor((f * 0.7 + (i - 1) * 5) % 14)
    local ex = math.floor(math.sin((i - 1) * 2 + f * 0.35) * 3 + (i - 2) * 2 + 0.5)
    setSprite(ember, life < 7 and "ember" or "emberCool", unit)
    put(scene, ember, ex, ROW.ember + life)
  end

  scene.actorParts.used = 0
  for _, actor in ipairs(view.actors) do drawActor(scene, take(scene.actorParts), actor, f) end
  hideRest(scene.actorParts)

  scene.graveParts.used = 0
  for _, grave in ipairs(view.graves) do
    local parts = take(scene.graveParts)
    setSprite(parts.grave, "grave", unit)
    put(scene, parts.grave, grave.x, ROW.grave)
    if grave.flower then
      setSprite(parts.flower, "flower", unit)
      put(scene, parts.flower, grave.x + OFFSET.flower, ROW.flower)
    else
      parts.flower:Hide()
    end
  end
  hideRest(scene.graveParts)

  if view.tent then
    setSprite(scene.tent, "tent", unit)
    local s = Sheet.sprites.tent
    put(scene, scene.tent, view.tent.x + math.floor((LAYOUT.tent - s[3]) / 2), ROW.tent)
  else
    scene.tent:Hide()
  end
end

local function onUpdate(band)
  local scene = band.scene
  if not scene.view then return end
  local f = math.floor(GetTime() * FPS)
  if f == scene.frame then return end
  scene.frame = f
  drawFrame(scene, f)
end

-- A Camp band in parent. gains: show each actor's gained text (While you
-- were away) instead of names.
function CampScene.new(parent, gains)
  local band = CreateFrame("Frame", nil, parent)
  band:SetClipsChildren(true)
  local scene = {
    band = band,
    gains = gains,
    hops = {},
    actorParts = pool(function()
      return {
        seat = texture(band.art, "ARTWORK", 0),
        cloth = texture(band.art, "ARTWORK", 1),
        skin = texture(band.art, "ARTWORK", 2),
        sleep = {
          texture(band.art, "ARTWORK", 2),
          texture(band.art, "ARTWORK", 2),
          texture(band.art, "ARTWORK", 2),
        },
        spark = texture(band.art, "OVERLAY", 0),
        label = nameLabel(band.art),
      }
    end),
    graveParts = pool(function()
      return {
        grave = texture(band.art, "ARTWORK", 0),
        flower = texture(band.art, "ARTWORK", 1),
      }
    end),
  }
  band.scene = scene
  local sky = band:CreateTexture(nil, "BACKGROUND", nil, 0)
  sky:SetAllPoints()
  sky:SetColorTexture(Sheet.sky[1], Sheet.sky[2], Sheet.sky[3], 1)

  -- The art's origin, on a whole pixel: everything is placed from it.
  scene.art = CreateFrame("Frame", nil, band)
  scene.art:SetPoint("BOTTOMLEFT")
  scene.art:SetPoint("TOPRIGHT")
  if scene.art.SetRoundLayoutToNearestPixel then scene.art:SetRoundLayoutToNearestPixel(true) end
  band.art = scene.art
  scene.backdrop = scene.art:CreateTexture(nil, "BACKGROUND", nil, 1)
  scene.backdrop:SetTexture(Sheet.backdrop.file, "CLAMP", "CLAMP", "NEAREST")
  scene.tent = texture(scene.art, "BORDER", 0)
  scene.logs = texture(scene.art, "ARTWORK", 0)
  scene.flame = texture(scene.art, "ARTWORK", 1)
  scene.embers = { texture(scene.art, "ARTWORK", 2), texture(scene.art, "ARTWORK", 2), texture(scene.art, "ARTWORK", 2) }
  -- Hidden until there's a view, so the more label has a home too.
  scene.more = Skin.label(band, "small", Skin.MUTED, "OVERLAY")
  scene.more:SetPoint("BOTTOMRIGHT", -6, 4)
  band:SetScript("OnUpdate", onUpdate)
  band:Hide()

  function band:Draw(view)
    scene.view = view
    if not view then
      band:Hide()
      return
    end
    scene.frame = nil
    scene.backdrop:SetSize(Sheet.backdrop.width * scene.unit, Sheet.backdrop.height * scene.unit)
    put(scene, scene.backdrop, -Sheet.backdrop.fire, 0)
    scene.more:SetText(view.moreText or "")
    band:Show()
    onUpdate(band)
  end

  -- How many art columns fit `width` UI units, and the band's height for
  -- `height` UI units, both in whole art pixels. Call before Draw.
  function band:Measure(width, height)
    scene.unit = CampScene.artUnit(band, CampScene.BAND_TARGET)
    local columns = math.floor(width / scene.unit)
    local rows = math.floor(height / scene.unit)
    scene.fire = math.floor(columns / 2)
    return columns, rows * scene.unit
  end

  -- A Cheer for a Member: if they're seated here, they hop for a moment.
  function band:Hop(memberId)
    if not scene.view then return end
    for _, actor in ipairs(scene.view.actors) do
      if actor.memberId == memberId and actor.pose == "seated" then
        scene.hops[memberId] = GetTime() + HOP_FOR
        scene.frame = nil
      end
    end
  end

  return band
end
