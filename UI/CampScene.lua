-- CampScene: draws Core's camp() as pixel art: a band with the night
-- backdrop, the fire, and each actor, grave and spark where Core placed
-- them. The panel's band and the While you were away popup's use it, and
-- small seated figures stand in for class icons on Roster rows and toasts.
-- It works out nothing about the Crew: positions are Core's, in art pixels
-- from the fire. One art pixel is a whole number of screen pixels near a
-- target size (artUnit), so the art stays crisp at any UI scale. One
-- OnUpdate on the band steps the fire, embers and sleep marks, and
-- runs only while the band is shown. Silent. See docs/design/camp.md.
-- The Pocket Camp (UI/PocketCamp.lua) is a band of its own: its actors
-- are also drawn doing what Core says they're doing (POSE: a torch in a
-- doorway, a rod out to the fire, a griffin under them and so on), and
-- :Animate plays its one-off animations. See
-- docs/design/pocket-camp.md.

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
-- How long each one-off animation plays (band:Animate), in seconds: a
-- quick opening, then a tail long enough to notice at a glance.
local ANIMATION_FOR = { ding = 10, maxLevel = 10, death = 10, rareFind = 10, goal = 10, quest = 6 }
-- The openings: a ding's star rises for this long, and a death's smoke
-- rises while the figure flickers. A max level's burst repeats this often.
local STAR_RISES_FOR = 1.2
local SMOKE_FOR = 1.6
local BURST_EVERY = 1.8
-- A celebrating figure (a ding or a max level) and a held-up fish bounce:
-- up for this many ticks, then down for as many.
local BOUNCE_TICKS = 3
-- Rows up from the band's bottom: where the ground line is, and where each
-- sprite's bottom sits on it (from the prototype).
local ROW = {
  seat = 3, seated = 4, hop = 6, standing = 3, asleep = 3, grave = 3, flower = 2,
  logs = 3, fire = 5, tent = 5, ember = 16,
}
-- Each sprite's x from its actor's (or grave's) left edge. A spark sits
-- by a seated figure's head, or on a sleeper's blanket, so even the short
-- band never crops it.
local OFFSET = { seat = -1, flower = 2, seatedSpark = 9, asleepSpark = 11 }
-- How each pose but "seated" is drawn (docs/design/pocket-camp.md).
-- standing: on its feet with its arms up, and no seat. lift: rows the
-- figure is raised, with no seat either. tool (in its hand), back (behind
-- it) and front (over it) are sprites: { name, x from the figure's left
-- edge, rows from its bottom row, whether it turns to face the fire }. One
-- that turns is drawn mirrored on the fire's right, at the same distance
-- from the figure's other edge. flap is front's other frame. The griffin
-- reaches as far past the figure as Core keeps clear for it
-- (LAYOUT.griffinFore and griffinAft).
local POSE = {
  adventuring = { standing = true, tool = { "torch", 6, 11 }, back = { "arch", -2, 0 }, raid = "archRaid" },
  fighting = { standing = true, tool = { "blade", 6, 12 } },
  crafting = { standing = true, tool = { "hammer", 5, 11 }, front = { "anvil", 5, -1, true } },
  gathering = { standing = true, tool = { "pick", 3, 11 } },
  fishing = { tool = { "rod", 10, 3, true } },
  vendor = { front = { "bag", 7, -2, true } },
  auction = { front = { "coins", 8, -2, true } },
  resting = { back = { "innSign", -1, -1, true } },
  flying = { lift = 9, back = { "griffin", -4, -7, true }, front = { "griffinWing", -6, -3, true },
    flap = "griffinWingUp" },
}
-- A griffin's wing is up for this many ticks, then down for twice as many.
local FLAP_TICKS = 3
-- What plays over a figure's head, from the figure's left edge: a ding's
-- star and a death's smoke rise this many rows, a rare find's fish is held.
local STAR = { x = 3, rise = 3 }
local QUEST = { x = 3 }
local FISH = { x = 2 }
local SMOKE = { x = 2, row = -4, rise = 6 }
-- A max level's burst: sparks fly this far out from the figure's middle,
-- one each way.
local BURST = { x = 4, row = 5, reach = 9,
  ways = { { -1, 1 }, { 1, 1 }, { -1, 0 }, { 1, 0 }, { 0, 1 }, { -1, -1 }, { 1, -1 } } }
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
-- mirrored flips it left to right.
local function setSprite(t, name, unit, mirrored)
  local s = Sheet.sprites[name]
  local key = mirrored and name .. " mirrored" or name
  if t.sprite ~= key then
    local left, right = s[1] / Sheet.width, (s[1] + s[3]) / Sheet.width
    if mirrored then left, right = right, left end
    t:SetTexCoord(left, right, s[2] / Sheet.height, (s[2] + s[4]) / Sheet.height)
    t.sprite = key
  end
  t:SetSize(s[3] * unit, s[4] * unit)
  t:Show()
end

local function tint(t, classFilename)
  t:SetVertexColor(Skin.classColor(classFilename))
end

-- A small seated figure, two layers on one rectangle: the cloth in the
-- class colour under skin and outline. :SetClass(classFilename) draws it;
-- :Layout() sizes it at its target (FIGURE_TARGET unless :SetTarget(target)
-- says otherwise, as map pins do), after the UI scale changes.
function CampScene.figure(parent)
  local frame = CreateFrame("Frame", nil, parent)
  frame.target = CampScene.FIGURE_TARGET
  frame.cloth = texture(frame, "ARTWORK", 0)
  frame.cloth:SetPoint("BOTTOMLEFT")
  frame.skin = texture(frame, "ARTWORK", 1)
  frame.skin:SetPoint("BOTTOMLEFT")
  function frame:Layout()
    local unit = CampScene.artUnit(self, self.target)
    local s = Sheet.sprites.seated
    self:SetSize(s[3] * unit, s[4] * unit)
    setSprite(self.cloth, "seatedCloth", unit)
    setSprite(self.skin, "seated", unit)
  end
  function frame:SetTarget(target)
    self.target = target
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

local function hideParts(parts)
  for _, part in pairs(parts) do
    if type(part) == "table" then
      if part.Hide then part:Hide() else hideParts(part) end
    end
  end
end

local function hideRest(list)
  for i = list.used + 1, #list do hideParts(list[i]) end
end

-- Places a texture with its bottom left at art pixel x from the fire and
-- `row` rows up from the band's bottom.
local function put(scene, t, x, row)
  t:ClearAllPoints()
  t:SetPoint("BOTTOMLEFT", scene.art, "BOTTOMLEFT", (scene.fire + x) * scene.unit, row * scene.unit)
end

local function hopping(scene, actor)
  local untilTime = actor.pose ~= "asleep" and scene.hops[actor.memberId]
  return untilTime ~= nil and untilTime and untilTime > GetTime()
end

-- How many seconds a one-off animation has played, or nil when it isn't
-- playing. The newest of its kind counts. memberId is nil for the fire's.
local function playing(scene, kind, memberId)
  local now = GetTime()
  for i = #scene.animations, 1, -1 do
    local animation = scene.animations[i]
    if animation.kind == kind and animation.memberId == memberId and now < animation.ends then
      return now - animation.start
    end
  end
  return nil
end

-- Up or down, swapping every BOUNCE_TICKS ticks.
local function bounced(f)
  return math.floor(f / BOUNCE_TICKS) % 2 == 0
end

-- Whether a figure is up on its feet celebrating: a Cheer's hop, or the
-- bounce a ding and a max level keep up while they play.
local function celebrating(scene, actor, f)
  if hopping(scene, actor) then return true end
  local ding = playing(scene, "ding", actor.memberId)
  if ding and ding < STAR_RISES_FOR then return true end
  return (ding or playing(scene, "maxLevel", actor.memberId)) ~= nil and bounced(f)
end

-- A mark's bottom row: `row`, or as near under it as keeps the mark inside
-- a band of a set height (the Pocket Camp's), where a raised figure's head
-- is close to the top.
local function markRow(scene, name, row)
  local rows = scene.view.rows
  if not rows then return row end
  return math.min(row, rows - Sheet.sprites[name][4])
end

-- Draws what plays over one upright actor: a ding's star, a rare find's
-- fish held up, a handed-in quest's mark, a death's smoke and flicker, and
-- a max level's bursts.
-- row is the figure's bottom row and top the row above its head.
local function drawAnimations(scene, parts, actor, f, row, top)
  local unit, x, id = scene.unit, actor.x, actor.memberId
  local ding, fish, death = playing(scene, "ding", id), playing(scene, "rareFind", id), playing(scene, "death", id)
  local quest = playing(scene, "quest", id)
  local smoke = death and death < SMOKE_FOR and death / SMOKE_FOR
  if fish then
    setSprite(parts.mark, "fish", unit)
    put(scene, parts.mark, x + FISH.x, markRow(scene, "fish", top + 1 + (bounced(f) and 1 or 0)))
  elseif ding then
    -- The star rises, then stays over the head while the figure bounces.
    setSprite(parts.mark, "star", unit)
    put(scene, parts.mark, x + STAR.x,
      markRow(scene, "star", top + 1 + math.floor(math.min(1, ding / STAR_RISES_FOR) * STAR.rise)))
  elseif quest then
    setSprite(parts.mark, "quest", unit)
    put(scene, parts.mark, x + QUEST.x, markRow(scene, "quest", top + 1 + (bounced(f) and 1 or 0)))
  elseif smoke then
    setSprite(parts.mark, smoke < 0.5 and "smoke1" or "smoke2", unit)
    put(scene, parts.mark, x + SMOKE.x, top + SMOKE.row + math.floor(smoke * SMOKE.rise))
  else
    parts.mark:Hide()
  end
  -- The skeleton flickers on alternate ticks while the smoke rises.
  local alpha = smoke and f % 2 == 0 and 0.3 or 1
  parts.cloth:SetAlpha(alpha)
  parts.skin:SetAlpha(alpha)

  local burst = playing(scene, "maxLevel", id)
  if burst then
    burst = burst % BURST_EVERY / BURST_EVERY
    parts.burst = parts.burst or {}
    local reach = math.floor(burst * BURST.reach)
    for i, way in ipairs(BURST.ways) do
      local spark = parts.burst[i] or scene.texture("OVERLAY", 1)
      parts.burst[i] = spark
      setSprite(spark, burst < 0.6 and "spark" or "ember", unit)
      put(scene, spark, x + BURST.x + way[1] * reach, row + BURST.row + way[2] * reach)
    end
  elseif parts.burst then
    for _, spark in ipairs(parts.burst) do spark:Hide() end
  end
end

-- Shows one of a pose's sprites (POSE) on a texture, for a figure whose
-- bottom row is `row`. name is the sprite to show in its place, if given.
local function posePart(scene, t, actor, part, row, name)
  name = name or part[1]
  local mirrored = part[4] and actor.x > 0 or false
  setSprite(t, name, scene.unit, mirrored)
  local x = part[2]
  if mirrored then x = LAYOUT.seated - x - Sheet.sprites[name][3] end
  put(scene, t, actor.x + x, row + part[3])
end

-- Draws one actor's figure, seat or sleep marks, what its pose adds, spark
-- and name, for the animation frame f. Upright poses: "seated" and the
-- Pocket Camp's (POSE). After a death the figure is a skeleton for a
-- while, whatever its pose.
local function drawActor(scene, parts, actor, f)
  local x = actor.x
  local top
  if actor.pose ~= "asleep" then
    local dead = playing(scene, "death", actor.memberId) ~= nil
    local pose = not dead and POSE[actor.pose] or {}
    local standing = pose.standing == true
    local hop = not dead and celebrating(scene, actor, f)
    local row = (standing and ROW.standing or ROW.seated) + (pose.lift or 0) + (hop and ROW.hop - ROW.seated or 0)
    if standing or pose.lift then
      parts.seat:Hide()
    else
      setSprite(parts.seat, "seat", scene.unit)
      put(scene, parts.seat, x + OFFSET.seat, ROW.seat)
    end
    local armsUp = hop or standing
    if dead then
      parts.cloth:Hide()
      setSprite(parts.skin, "skeleton", scene.unit)
    else
      setSprite(parts.cloth, armsUp and "hopCloth" or "seatedCloth", scene.unit)
      setSprite(parts.skin, armsUp and "hop" or "seated", scene.unit)
    end
    put(scene, parts.cloth, x, row)
    put(scene, parts.skin, x, row)
    for _, z in ipairs(parts.sleep) do z:Hide() end
    -- Marks play over the head, in front of whatever the pose holds up.
    top = row + Sheet.sprites.seated[4]
    if pose.tool then posePart(scene, parts.tool, actor, pose.tool, row) else parts.tool:Hide() end
    if pose.back then
      posePart(scene, parts.back, actor, pose.back, row, actor.raid and pose.raid or nil)
    else
      parts.back:Hide()
    end
    if pose.front then
      local flapping = pose.flap and math.floor(f / FLAP_TICKS) % 3 == 0
      posePart(scene, parts.front, actor, pose.front, row, flapping and pose.flap or nil)
    else
      parts.front:Hide()
    end
    drawAnimations(scene, parts, actor, f, row, top)
  else
    parts.seat:Hide()
    parts.tool:Hide()
    parts.back:Hide()
    parts.front:Hide()
    parts.mark:Hide()
    parts.cloth:SetAlpha(1)
    parts.skin:SetAlpha(1)
    if parts.burst then
      for _, spark in ipairs(parts.burst) do spark:Hide() end
    end
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
  local text
  if scene.gains then text = actor.gained elseif scene.names then text = actor.label end
  label:SetText(text or "")
  if scene.gains then
    Skin.color(label, actor.highlight and Skin.GOLD or Skin.ONLINE)
  else
    label:SetTextColor(Skin.classColor(actor.classFilename))
  end
  label:SetShown(text ~= nil)

  if actor.spark then
    setSprite(parts.spark, "spark", scene.unit)
    local upright = actor.pose ~= "asleep"
    local lift = upright and celebrating(scene, actor, f) and ROW.hop - ROW.seated or 0
    put(scene, parts.spark, x + (upright and OFFSET.seatedSpark or OFFSET.asleepSpark),
      (upright and SPARK_ROW.seated or SPARK_ROW.asleep) + lift)
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
  -- A Crew goal flares the fire for a moment.
  setSprite(scene.flame, (playing(scene, "goal", nil) and "flare" or "fire") .. (f % 3 + 1), unit)
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
  for _, grave in ipairs(view.graves or {}) do
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
  local now = GetTime()
  local f = math.floor(now * FPS)
  if f == scene.frame then return end
  scene.frame = f
  for i = #scene.animations, 1, -1 do
    if scene.animations[i].ends <= now then table.remove(scene.animations, i) end
  end
  drawFrame(scene, f)
end

-- A Camp band in parent. options (all optional): gains shows each
-- actor's gained text (While you were away) instead of names; names false
-- leaves the names out (the Pocket Camp, whose figures have a tooltip);
-- target is the art pixel's size to aim for in UI units (default
-- BAND_TARGET); shadow gives its text a shadow, for a band over the game
-- world; and backdrop is the backdrop art to draw in the usual one's place
-- with no sky filled in behind it (CampSheet.pocketBackdrop, soft-edged).
function CampScene.new(parent, options)
  options = options or {}
  local band = CreateFrame("Frame", nil, parent)
  band:SetClipsChildren(true)
  local function shadowed(label)
    if options.shadow then
      label:SetShadowColor(0, 0, 0, 1)
      label:SetShadowOffset(1, -1)
    end
    return label
  end
  local scene = {
    band = band,
    gains = options.gains,
    names = options.names ~= false,
    backdropArt = options.backdrop or Sheet.backdrop,
    target = options.target or CampScene.BAND_TARGET,
    hops = {},
    -- The one-off animations playing: { kind, memberId, start, ends }.
    animations = {},
    texture = function(layer, sublevel) return texture(band.art, layer, sublevel) end,
    actorParts = pool(function()
      return {
        back = texture(band.art, "ARTWORK", -1),
        seat = texture(band.art, "ARTWORK", 0),
        cloth = texture(band.art, "ARTWORK", 1),
        skin = texture(band.art, "ARTWORK", 2),
        sleep = {
          texture(band.art, "ARTWORK", 2),
          texture(band.art, "ARTWORK", 2),
          texture(band.art, "ARTWORK", 2),
        },
        tool = texture(band.art, "ARTWORK", 3),
        front = texture(band.art, "ARTWORK", 4),
        spark = texture(band.art, "OVERLAY", 0),
        mark = texture(band.art, "OVERLAY", 1),
        label = shadowed(nameLabel(band.art)),
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
  -- Art with its own shape has no sky behind it.
  sky:SetShown(options.backdrop == nil)
  scene.sky = sky

  -- The art's origin, on a whole pixel: everything is placed from it.
  scene.art = CreateFrame("Frame", nil, band)
  scene.art:SetPoint("BOTTOMLEFT")
  scene.art:SetPoint("TOPRIGHT")
  if scene.art.SetRoundLayoutToNearestPixel then scene.art:SetRoundLayoutToNearestPixel(true) end
  band.art = scene.art
  scene.backdrop = scene.art:CreateTexture(nil, "BACKGROUND", nil, 1)
  scene.backdrop:SetTexture(scene.backdropArt.file, "CLAMP", "CLAMP", "NEAREST")
  scene.tent = texture(scene.art, "BORDER", 0)
  scene.logs = texture(scene.art, "ARTWORK", 0)
  scene.flame = texture(scene.art, "ARTWORK", 1)
  scene.embers = { texture(scene.art, "ARTWORK", 2), texture(scene.art, "ARTWORK", 2), texture(scene.art, "ARTWORK", 2) }
  -- Hidden until there's a view, so the more label has a home too.
  scene.more = shadowed(Skin.label(band, "small", Skin.MUTED, "OVERLAY"))
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
    scene.backdrop:SetSize(scene.backdropArt.width * scene.unit, scene.backdropArt.height * scene.unit)
    put(scene, scene.backdrop, -scene.backdropArt.fire, 0)
    scene.more:SetText(view.moreText or "")
    band:Show()
    onUpdate(band)
  end

  -- How many art columns fit `width` UI units, and the band's height for
  -- `height` UI units, both in whole art pixels. Call before Draw.
  function band:Measure(width, height)
    scene.unit = CampScene.artUnit(band, scene.target)
    local columns = math.floor(width / scene.unit)
    local rows = math.floor(height / scene.unit)
    scene.fire = math.floor(columns / 2)
    return columns, rows * scene.unit
  end

  -- The band's size in UI units for a Camp exactly `columns` by `rows`
  -- art pixels (the Pocket Camp's). Call before Draw, in Measure's place.
  function band:Fit(columns, rows)
    scene.unit = CampScene.artUnit(band, scene.target)
    scene.fire = math.floor(columns / 2)
    return columns * scene.unit, rows * scene.unit
  end

  -- How solid the sky and backdrop are, 0 to 1. At 0 only the fire, the
  -- figures and the text show.
  function band:SetBackdropAlpha(alpha)
    scene.sky:SetAlpha(alpha)
    scene.backdrop:SetAlpha(alpha)
  end

  -- The actor whose figure is at x, in UI units from the band's left edge,
  -- or nil over the fire and between figures. Half the gap each side of a
  -- figure counts as it.
  function band:ActorAt(x)
    if not scene.view or not scene.unit then return nil end
    local at = x / scene.unit - scene.fire
    local reach = LAYOUT.gap / 2
    for _, actor in ipairs(scene.view.actors) do
      if at >= actor.x - reach and at < actor.x + actor.width + reach then return actor end
    end
    return nil
  end

  -- Plays a one-off animation: "ding", "maxLevel", "death" or "rareFind"
  -- on that Member's figure, if it's up by the fire here, or "goal" on the
  -- fire.
  function band:Animate(kind, memberId)
    local lasts = ANIMATION_FOR[kind]
    if not lasts then return end
    local now = GetTime()
    scene.animations[#scene.animations + 1] = { kind = kind, memberId = memberId, start = now, ends = now + lasts }
    scene.frame = nil
  end

  -- A Cheer for a Member: if they're up by the fire here, they hop for a
  -- moment.
  function band:Hop(memberId)
    if not scene.view then return end
    for _, actor in ipairs(scene.view.actors) do
      if actor.memberId == memberId and actor.pose ~= "asleep" then
        scene.hops[memberId] = GetTime() + HOP_FOR
        scene.frame = nil
      end
    end
  end

  return band
end
