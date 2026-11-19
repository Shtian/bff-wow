local _, ns = ...

local CampScene = {}
ns.CampScene = CampScene

local Skin = ns.Skin
local Sheet = ns.CampSheet
local LAYOUT = ns.Core.CAMP_LAYOUT

CampScene.BAND_TARGET = 3
CampScene.FIGURE_TARGET = 2
CampScene.HEIGHT = 120
CampScene.SHORT_HEIGHT = 78
local FPS = 6
local HOP_FOR = 0.7
local CHEER_BURST = { x = 5.5, row = 2, reach = 0.9, fade = 0.6,
  colors = { "glint", "glintPale", "ember", "emberWarm" },
  ways = { { 0, 1 }, { 0.75, 0.75 }, { -0.75, 0.75 }, { 1, 0.1 }, { -1, 0.1 }, { 0.4, 1 }, { -0.4, 1 } } }
local BLOOM = { step = 1.5, lasts = 1.6, solid = 3, fade = 0.5,
  petals = { { -1, 3 }, { 3, 3 }, { 1, 4 } } }
local ANIMATION_FOR = { ding = 10, maxLevel = 10, death = 10, rareFind = 10, goal = 10, quest = 6, arrive = 6,
  welcome = 4, shift = 1 }
local STAR_RISES_FOR = 1.2
local SMOKE_FOR = 1.6
local BURST_EVERY = 1.8
local WALK_FOR = 2.5
local WALK_STEP = 2
local BOUNCE_TICKS = 3
local ROW = {
  seat = 3, seated = 4, hop = 6, standing = 3, asleep = 3, grave = 3, flower = 2,
  logs = 3, fire = 5, tent = 5, ember = 16, crate = 1, cup = 19,
}
local CRATE_X = -1
local CUP_X = -6
local CUP_BOB = 4
local CUP_SPARKLE_EVERY = 18
local CUP_SPARKLE_FOR = 4
local CUP_SPARKLES = { { -9, 24 }, { 5, 21 } }
local OFFSET = { seat = -1, flower = 2, seatedSpark = 9, asleepSpark = 11 }
local POSE = {
  adventuring = { standing = true, tool = { "torch", 6, 11 } },
  fighting = { standing = true, tool = { "blade", 6, 12 } },
  crafting = { standing = true, tool = { "hammer", 5, 11 }, front = { "anvil", 5, -1, true } },
  gathering = { standing = true, tool = { "pick", 3, 11 } },
  fishing = { tool = { "rod", 10, 3, true } },
  vendor = { front = { "bag", 7, -2, true } },
  auction = { front = { "coins", 8, -2, true } },
  resting = { back = { "innSign", -1, -1, true } },
  afk = { away = true },
  flying = { lift = 9, back = { "griffin", -4, -7, true }, front = { "griffinWing", -6, -3, true },
    flap = "griffinWingUp" },
}
local DOORWAY = { rim = 4 }
local FLAP_TICKS = 3
local STAR = { x = 3, rise = 3 }
local QUEST = { x = 3 }
local HI = { x = 1, row = 1 }
local FISH = { x = 2 }
local SMOKE = { x = 2, row = -4, rise = 6 }
local BURST = { x = 4, row = 5, reach = 9,
  ways = { { -1, 1 }, { 1, 1 }, { -1, 0 }, { 1, 0 }, { 0, 1 }, { -1, -1 }, { 1, -1 } } }
local SLEEP = { { x = 7, row = 0 }, { x = 12, row = 3 }, { x = 6, row = 5 } }
local SLEEP_STEP = 4
local AWAY = { x = -1, row = 1, every = 6 }
local ALT = { x = -1, row = 1 }
local SPARK_ROW = { seated = 13, asleep = 4 }
local FORM = {
  wolf = { trot = { "wolfRun1", "wolfRun2" }, glow = { "wolfGlow1", "wolfGlow2" }, puff = "spirit" },
  bear = { idle = { "bearStand1", "bearStand2" }, breathe = true, swipe = true },
  cat = { idle = { "catElf1", "catElf2" }, horde = { "catLion1", "catLion2" } },
  travel = { trot = { "travelRun1", "travelRun2" } },
  seal = { idle = { "seal1", "seal2" } },
  moonkin = { idle = { "moonkin1", "moonkin2" } },
}
local BREATHE_TICKS = 9
local BLINK = { every = 24, ticks = 3 }
local TROT = { step = 2, span = 4 }
local SWIPE = { every = 60, rear = 3, swipe = 2, after = 2 }
local CLAWS = { x = 16, row = 4 }
local GHOST = { alpha = 0.6, glow = 0.15, pulseAlpha = 0.7, pulseGlow = 0.25 }
local PULSE = { every = 9, ticks = 2 }
local PUFF = { row = 2, solid = 4, fade = 0.5 }
local LABEL_GAP = 1

-- WoW: a size that isn't a whole number of screen pixels draws some art
-- pixels a screen pixel wider than others.
function CampScene.artUnit(frame, target)
  local factor = PixelUtil and PixelUtil.GetPixelToUIUnitFactor and PixelUtil.GetPixelToUIUnitFactor() or 1
  local onePixel = factor / frame:GetEffectiveScale()
  local pixels = math.max(1, math.floor(target / onePixel + 0.5))
  return pixels * onePixel
end

-- WoW: the "NEAREST" filter keeps texels square; the default one blurs them.
local function texture(parent, layer, sublevel)
  local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sublevel or 0)
  t:SetTexture(Sheet.file, "CLAMP", "CLAMP", "NEAREST")
  return t
end

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

CampScene.sprite = setSprite

local function setSlice(t, name, unit, from, count, width)
  local s = Sheet.sprites[name]
  local key = ("%s %d %d"):format(name, from, count)
  if t.sprite ~= key then
    t:SetTexCoord((s[1] + from) / Sheet.width, (s[1] + from + count) / Sheet.width,
      s[2] / Sheet.height, (s[2] + s[4]) / Sheet.height)
    t.sprite = key
  end
  t:SetSize(math.max(width, 1) * unit, s[4] * unit)
  t:SetShown(width > 0)
end

local function tint(t, classFilename)
  t:SetVertexColor(Skin.classColor(classFilename))
end

local HAT_FORE = 2

local function hatPlace(name, row)
  local hat = name and Sheet.hats[name]
  if not hat then return nil end
  local s = Sheet.sprites[hat.sprite]
  local bottom = row + Sheet.sprites.seated[4] - HAT_FORE + hat.brow + 2 - s[4]
  return hat.sprite, math.floor((LAYOUT.seated - s[3]) / 2), bottom, bottom + s[4]
end

function CampScene.figure(parent)
  local frame = CreateFrame("Frame", nil, parent)
  frame.target = CampScene.FIGURE_TARGET
  frame.cloth = texture(frame, "ARTWORK", 0)
  frame.cloth:SetPoint("BOTTOMLEFT")
  frame.skin = texture(frame, "ARTWORK", 1)
  frame.skin:SetPoint("BOTTOMLEFT")
  frame.hat = texture(frame, "ARTWORK", 2)
  function frame:Layout()
    local unit = CampScene.artUnit(self, self.target)
    local s = Sheet.sprites.seated
    local sprite, x, row, top = hatPlace(self.hatName, 0)
    self:SetSize(s[3] * unit, math.max(s[4], top or 0) * unit)
    setSprite(self.cloth, "seatedCloth", unit)
    setSprite(self.skin, "seated", unit)
    if sprite then
      setSprite(self.hat, sprite, unit)
      self.hat:ClearAllPoints()
      self.hat:SetPoint("BOTTOMLEFT", x * unit, row * unit)
    else
      self.hat:Hide()
    end
  end
  function frame:SetTarget(target)
    self.target = target
  end
  function frame:SetClass(classFilename, hat)
    self.hatName = hat
    self:Layout()
    tint(self.cloth, classFilename)
    self:Show()
  end
  return frame
end

CampScene.HEAD_ROWS = 7

local function setSpriteTop(t, name, unit, rows)
  local s = Sheet.sprites[name]
  t:SetTexCoord(s[1] / Sheet.width, (s[1] + s[3]) / Sheet.width, s[2] / Sheet.height, (s[2] + rows) / Sheet.height)
  t.sprite = name .. " top"
  t:SetSize(s[3] * unit, rows * unit)
  t:Show()
end

local function setSpriteBottom(t, name, unit, rows)
  local s = Sheet.sprites[name]
  t:SetTexCoord(s[1] / Sheet.width, (s[1] + s[3]) / Sheet.width, (s[2] + s[4] - rows) / Sheet.height,
    (s[2] + s[4]) / Sheet.height)
  t.sprite = name .. " bottom"
  t:SetSize(s[3] * unit, rows * unit)
  t:Show()
end

function CampScene.hat(parent)
  local frame = CreateFrame("Frame", nil, parent)
  frame.art = texture(frame, "ARTWORK", 0)
  frame.art:SetPoint("CENTER")
  function frame:SetHat(name)
    local hat = Sheet.hats[name]
    if not hat then return self.art:Hide() end
    setSprite(self.art, hat.sprite, CampScene.artUnit(self, CampScene.FIGURE_TARGET))
  end
  return frame
end

function CampScene.head(parent)
  local frame = CreateFrame("Frame", nil, parent)
  frame.cloth = texture(frame, "ARTWORK", 0)
  frame.cloth:SetPoint("BOTTOMLEFT")
  frame.skin = texture(frame, "ARTWORK", 1)
  frame.skin:SetPoint("BOTTOMLEFT")
  function frame:SetClass(classFilename)
    local unit = CampScene.artUnit(self, CampScene.FIGURE_TARGET)
    self:SetSize(Sheet.sprites.seated[3] * unit, CampScene.HEAD_ROWS * unit)
    setSpriteTop(self.cloth, "seatedCloth", unit, CampScene.HEAD_ROWS)
    setSpriteTop(self.skin, "seated", unit, CampScene.HEAD_ROWS)
    tint(self.cloth, classFilename)
    self:Show()
  end
  return frame
end

local function nameLabel(parent)
  local label = Skin.label(parent, "small", nil, "OVERLAY")
  label:SetJustifyH("CENTER")
  label:SetWordWrap(false)
  return label
end

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

local function put(scene, t, x, row)
  t:ClearAllPoints()
  t:SetPoint("BOTTOMLEFT", scene.art, "BOTTOMLEFT", (scene.fire + x) * scene.unit, row * scene.unit)
end

local function hopping(scene, actor)
  local start = actor.pose ~= "asleep" and scene.hops[actor.memberId]
  local played = start and GetTime() - start
  return played and played < HOP_FOR and played or nil
end

local function playing(scene, kind, memberId)
  local now = GetTime()
  for i = #scene.animations, 1, -1 do
    local animation = scene.animations[i]
    if animation.kind == kind and animation.memberId == memberId and now < animation.ends then
      return now - animation.start, animation
    end
  end
  return nil
end

local function bounced(f)
  return math.floor(f / BOUNCE_TICKS) % 2 == 0
end

local function celebrating(scene, actor, f)
  if hopping(scene, actor) then return true end
  local ding = playing(scene, "ding", actor.memberId)
  if ding and ding < STAR_RISES_FOR then return true end
  return (ding or playing(scene, "maxLevel", actor.memberId)) ~= nil and bounced(f)
end

local function markRow(scene, name, row)
  local rows = scene.view.rows or scene.rows
  if not rows then return row end
  return math.min(row, rows - Sheet.sprites[name][4])
end

local function drawAnimations(scene, parts, actor, f, row, top, away)
  local unit, x, id = scene.unit, actor.x, actor.memberId
  local ding, fish, death = playing(scene, "ding", id), playing(scene, "rareFind", id), playing(scene, "death", id)
  local quest = playing(scene, "quest", id)
  local smoke = death and death < SMOKE_FOR and death / SMOKE_FOR
  if fish then
    setSprite(parts.mark, "fish", unit)
    put(scene, parts.mark, x + FISH.x, markRow(scene, "fish", top + 1 + (bounced(f) and 1 or 0)))
  elseif ding then
    setSprite(parts.mark, "star", unit)
    put(scene, parts.mark, x + STAR.x,
      markRow(scene, "star", top + 1 + math.floor(math.min(1, ding / STAR_RISES_FOR) * STAR.rise)))
  elseif quest then
    setSprite(parts.mark, "quest", unit)
    put(scene, parts.mark, x + QUEST.x, markRow(scene, "quest", top + 1 + (bounced(f) and 1 or 0)))
  elseif smoke then
    setSprite(parts.mark, smoke < 0.5 and "smoke1" or "smoke2", unit)
    put(scene, parts.mark, x + SMOKE.x, top + SMOKE.row + math.floor(smoke * SMOKE.rise))
  elseif away then
    setSprite(parts.mark, "afk", unit)
    put(scene, parts.mark, x + AWAY.x, markRow(scene, "afk", top + AWAY.row + math.floor(f / AWAY.every) % 2))
  else
    parts.mark:Hide()
  end
  local marked = (fish or ding or quest or smoke or away) and true or false
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
  return marked
end

local function drawAlt(scene, parts, actor, top)
  setSprite(parts.alt, "alt", scene.unit)
  put(scene, parts.alt, actor.x + ALT.x, markRow(scene, "alt", top + ALT.row))
end

local function partTop(part, row)
  return part and row + part[3] + Sheet.sprites[part[1]][4] or 0
end

local function posePart(scene, t, actor, part, row, name)
  name = name or part[1]
  local mirrored = part[4] and actor.x > 0 or false
  setSprite(t, name, scene.unit, mirrored)
  local x = part[2]
  if mirrored then x = LAYOUT.seated - x - Sheet.sprites[name][3] end
  put(scene, t, actor.x + x, row + part[3])
end

local function hideExtras(parts)
  parts.tool:Hide()
  parts.back:Hide()
  parts.front:Hide()
  parts.mark:Hide()
  parts.alt:Hide()
  for _, z in ipairs(parts.sleep) do z:Hide() end
  if parts.burst then
    for _, spark in ipairs(parts.burst) do spark:Hide() end
  end
  for _, glint in ipairs(parts.cheer) do glint:Hide() end
  parts.cloth:SetAlpha(1)
  parts.skin:SetAlpha(1)
  parts.back:SetAlpha(1)
end

local function drawHat(scene, parts, actor, x, row, mirrored)
  local sprite, dx, bottom, top = hatPlace(actor.hat, row)
  if not sprite then
    parts.hat:Hide()
    return nil
  end
  setSprite(parts.hat, sprite, scene.unit, mirrored)
  put(scene, parts.hat, x + dx, bottom)
  return top
end

local function drawArrival(scene, parts, actor, f, played)
  local unit, x = scene.unit, actor.x
  local pose = POSE[actor.pose] or {}
  if pose.standing or pose.lift then
    parts.seat:Hide()
  else
    setSprite(parts.seat, "seat", unit)
    put(scene, parts.seat, x + OFFSET.seat, ROW.seat)
  end
  hideExtras(parts)
  local fromRight = actor.x > 0
  local frame = math.floor(f / WALK_STEP) % 2 + 1
  local walking = played ~= nil and played < WALK_FOR
  if walking then
    local edge = fromRight and scene.view.columns - scene.fire or -scene.fire - actor.width
    x = math.floor(edge + (actor.x - edge) * played / WALK_FOR + 0.5)
  end
  local sprite = walking and "walk" or "wave"
  setSprite(parts.cloth, sprite .. "Cloth" .. frame, unit, fromRight)
  setSprite(parts.skin, sprite .. frame, unit, fromRight)
  put(scene, parts.cloth, x, ROW.standing)
  put(scene, parts.skin, x, ROW.standing)
  local hatTop = drawHat(scene, parts, actor, x, ROW.standing, fromRight)
  local top = ROW.standing + Sheet.sprites.seated[4]
  if not walking then
    setSprite(parts.mark, "hi", unit)
    put(scene, parts.mark, x + HI.x, markRow(scene, "hi", top + HI.row + (hatTop and 1 or 0)))
  end
  return x, top, hatTop
end

local function drawForm(scene, parts, actor, f)
  local form, unit = FORM[actor.form], scene.unit
  local seed = math.abs(actor.x)
  local right = actor.x > 0
  local x, mirrored = actor.x, right
  local name
  local clawing = false
  if form.trot then
    local step = math.floor(f / TROT.step)
    local p = (step + seed) % (TROT.span * 2)
    local outward = p < TROT.span
    local off = outward and p or TROT.span * 2 - p
    x = right and x + off or x - off
    mirrored = right ~= outward
    name = form.trot[step % 2 + 1]
  else
    local phase = (f + seed * 9) % SWIPE.every
    if form.swipe and phase < SWIPE.rear + SWIPE.swipe + SWIPE.after then
      clawing = phase >= SWIPE.rear and phase < SWIPE.rear + SWIPE.swipe
      name = clawing and "bearSwipe" or "bearRear"
    else
      local frames = form.horde and scene.horde and form.horde or form.idle
      local beat
      if form.breathe then
        beat = math.floor((f + seed) / BREATHE_TICKS) % 2
      else
        beat = (f + seed) % BLINK.every < BLINK.ticks and 1 or 0
      end
      name = frames[beat + 1]
    end
  end
  local s = Sheet.sprites[name]
  local left = x + math.floor(LAYOUT.seated / 2) - math.floor(s[3] / 2)
  left = math.max(-scene.fire, math.min(scene.view.columns - scene.fire - s[3], left))
  setSprite(parts.skin, name, unit, mirrored)
  put(scene, parts.skin, left, ROW.standing)
  if form.glow then
    local pulse = f % PULSE.every < PULSE.ticks
    local frame = form.trot and math.floor(f / TROT.step) % 2 + 1 or 1
    setSprite(parts.back, form.glow[frame], unit, mirrored)
    put(scene, parts.back, left - 1, ROW.standing - 1)
    parts.back:SetAlpha(pulse and GHOST.pulseGlow or GHOST.glow)
    parts.skin:SetAlpha(pulse and GHOST.pulseAlpha or GHOST.alpha)
  end
  if clawing then
    local claws = Sheet.sprites.bearClaws
    setSprite(parts.front, "bearClaws", unit, mirrored)
    put(scene, parts.front, mirrored and left + s[3] - CLAWS.x - claws[3] or left + CLAWS.x,
      ROW.standing + s[4] - CLAWS.row - claws[4])
  end
  return ROW.standing + s[4]
end

local function drawPuff(scene, parts, actor)
  local played, animation = playing(scene, "shift", actor.memberId)
  if not played then
    parts.puff:Hide()
    return
  end
  local age = math.floor(played * FPS)
  local name = animation.puff .. (age % 2 + 1)
  setSprite(parts.puff, name, scene.unit)
  put(scene, parts.puff, actor.x + math.floor(LAYOUT.seated / 2) - math.floor(Sheet.sprites[name][3] / 2),
    ROW.standing + PUFF.row)
  parts.puff:SetAlpha(age >= PUFF.solid and PUFF.fade or 1)
end

local function drawCheer(scene, parts, actor, top, played)
  local step = played and math.floor(played * FPS) + 1
  local color = step and CHEER_BURST.colors[step]
  local furthest = math.floor(1 + (#CHEER_BURST.colors - 1) * CHEER_BURST.reach + 0.5)
  local centre = top + CHEER_BURST.row
  local rows = scene.view and scene.view.rows or scene.rows
  if rows then centre = math.min(centre, rows - 1 - furthest) end
  for i, way in ipairs(CHEER_BURST.ways) do
    local glint = parts.cheer[i]
    if color then
      glint = glint or scene.texture("OVERLAY", 1)
      parts.cheer[i] = glint
      local reach = 1 + (step - 1) * CHEER_BURST.reach
      setSprite(glint, color, scene.unit)
      glint:SetAlpha(step == #CHEER_BURST.colors and CHEER_BURST.fade or 1)
      put(scene, glint, actor.x + math.floor(CHEER_BURST.x + way[1] * reach + 0.5),
        centre + math.floor(way[2] * reach + 0.5))
    elseif glint then
      glint:Hide()
    end
  end
end

local function drawActor(scene, parts, actor, f)
  local x = actor.x
  local top, hatTop
  local walkedIn = actor.pose ~= "asleep" and playing(scene, "arrive", actor.memberId)
  local welcomed = not walkedIn and actor.pose ~= "asleep" and playing(scene, "welcome", actor.memberId) ~= nil
  if walkedIn or welcomed then
    x, top, hatTop = drawArrival(scene, parts, actor, f, walkedIn)
  elseif actor.form and not playing(scene, "death", actor.memberId) then
    parts.seat:Hide()
    parts.cloth:Hide()
    parts.hat:Hide()
    hideExtras(parts)
    top = drawForm(scene, parts, actor, f)
    local alpha = parts.skin:GetAlpha()
    if drawAnimations(scene, parts, actor, f, ROW.standing, top) or not actor.onAlt then
      parts.alt:Hide()
    else
      drawAlt(scene, parts, actor, top)
    end
    parts.skin:SetAlpha(alpha)
  elseif actor.pose ~= "asleep" then
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
    parts.back:SetAlpha(1)
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
    if dead then parts.hat:Hide() else hatTop = drawHat(scene, parts, actor, x, row) end
    for _, z in ipairs(parts.sleep) do z:Hide() end
    top = row + Sheet.sprites.seated[4]
    local markTop = top + (hatTop and 1 or 0)
    if pose.tool then posePart(scene, parts.tool, actor, pose.tool, row) else parts.tool:Hide() end
    if pose.back then
      posePart(scene, parts.back, actor, pose.back, row)
    else
      parts.back:Hide()
    end
    if pose.front then
      local flapping = pose.flap and math.floor(f / FLAP_TICKS) % 3 == 0
      posePart(scene, parts.front, actor, pose.front, row, flapping and pose.flap or nil)
    else
      parts.front:Hide()
    end
    drawCheer(scene, parts, actor, top, not dead and hopping(scene, actor))
    local marked = drawAnimations(scene, parts, actor, f, row, markTop, pose.away)
    if actor.onAlt and not dead and not marked then
      drawAlt(scene, parts, actor, math.max(markTop, partTop(pose.tool, row) - ALT.row, partTop(pose.back, row) - ALT.row))
    else
      parts.alt:Hide()
    end
  else
    parts.seat:Hide()
    parts.hat:Hide()
    hideExtras(parts)
    setSprite(parts.cloth, "asleepCloth", scene.unit)
    setSprite(parts.skin, "asleep", scene.unit)
    put(scene, parts.cloth, x, ROW.asleep)
    put(scene, parts.skin, x, ROW.asleep)
    local bed = ROW.asleep + Sheet.sprites.asleep[4]
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
    if actor.onAlt then drawAlt(scene, parts, actor, top) end
  end
  tint(parts.cloth, actor.classFilename)
  drawPuff(scene, parts, actor)

  local centre = x + actor.width / 2
  local label = parts.label
  label:ClearAllPoints()
  local labelRow = math.max(top, hatTop or top) + LABEL_GAP
  label:SetPoint("BOTTOM", scene.art, "BOTTOMLEFT", (scene.fire + centre) * scene.unit, labelRow * scene.unit)
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
    local lift = upright and not (walkedIn or welcomed) and celebrating(scene, actor, f) and ROW.hop - ROW.seated or 0
    put(scene, parts.spark, x + (upright and OFFSET.seatedSpark or OFFSET.asleepSpark),
      (upright and SPARK_ROW.seated or SPARK_ROW.asleep) + lift)
  else
    parts.spark:Hide()
  end
end

local function drawDoorway(scene, parts, doorway)
  local name = doorway.raid and "archRaid" or "arch"
  local unit, rim = scene.unit, DOORWAY.rim
  local full = Sheet.sprites[name][3]
  local middle = full - 2 * rim
  local fill = doorway.width - full
  local left = math.floor(fill / 2)
  local x = doorway.x
  setSlice(parts.left, name, unit, 0, rim, rim)
  put(scene, parts.left, x, ROW.standing)
  setSlice(parts.fillLeft, name, unit, rim, 1, left)
  put(scene, parts.fillLeft, x + rim, ROW.standing)
  setSlice(parts.middle, name, unit, rim, middle, middle)
  put(scene, parts.middle, x + rim + left, ROW.standing)
  setSlice(parts.fillRight, name, unit, full - rim - 1, 1, fill - left)
  put(scene, parts.fillRight, x + rim + left + middle, ROW.standing)
  setSlice(parts.right, name, unit, full - rim, rim, rim)
  put(scene, parts.right, x + doorway.width - rim, ROW.standing)
end

local function drawBloom(scene, parts, grave, played)
  local unit, tick = scene.unit, math.floor(played * FPS)
  local x = grave.x + OFFSET.flower
  local rows = Sheet.sprites.flower[4]
  setSpriteBottom(parts.flower, "flower", unit, math.min(rows, 1 + math.floor(tick / BLOOM.step)))
  put(scene, parts.flower, x, ROW.flower)
  local after = tick - math.ceil((rows - 1) * BLOOM.step) - 1
  for i, petal in ipairs(parts.petals) do
    local at, t = BLOOM.petals[i], after - (i - 1)
    if t >= 0 then
      local sway = (t + i - 1) % 2 == 0 and 0 or (i == 1 and -1 or 1)
      setSprite(petal, "petal", unit)
      petal:SetAlpha(t < BLOOM.solid and 1 or BLOOM.fade)
      put(scene, petal, x + at[1] + sway, ROW.flower + at[2] + t)
    else
      petal:Hide()
    end
  end
end

local function drawFrame(scene, f)
  local view = scene.view
  local unit = scene.unit
  setSprite(scene.logs, "logs", unit)
  put(scene, scene.logs, -7, ROW.logs)
  setSprite(scene.flame, (playing(scene, "goal", nil) and "flare" or "fire") .. (f % 3 + 1), unit)
  put(scene, scene.flame, -5, ROW.fire)
  if view.spares then
    setSprite(scene.crate, "crate", unit)
    put(scene, scene.crate, CRATE_X, ROW.crate)
  else
    scene.crate:Hide()
  end
  for i, ember in ipairs(scene.embers) do
    local life = math.floor((f * 0.7 + (i - 1) * 5) % 14)
    local ex = math.floor(math.sin((i - 1) * 2 + f * 0.35) * 3 + (i - 2) * 2 + 0.5)
    setSprite(ember, life < 7 and "ember" or "emberCool", unit)
    put(scene, ember, ex, ROW.ember + life)
  end
  local twinkle = view.trophies and f % CUP_SPARKLE_EVERY < CUP_SPARKLE_FOR
  if view.trophies then
    setSprite(scene.cup, "trophyCup", unit)
    put(scene, scene.cup, CUP_X, ROW.cup + math.floor(f / CUP_BOB) % 2)
  else
    scene.cup:Hide()
  end
  for i, sparkle in ipairs(scene.cupSparkles) do
    if twinkle then
      setSprite(sparkle, "cupSparkle" .. ((f + i) % 2 + 1), unit)
      put(scene, sparkle, CUP_SPARKLES[i][1], CUP_SPARKLES[i][2])
    else
      sparkle:Hide()
    end
  end

  scene.doorParts.used = 0
  for _, doorway in ipairs(view.doorways or {}) do drawDoorway(scene, take(scene.doorParts), doorway) end
  hideRest(scene.doorParts)

  scene.actorParts.used = 0
  for _, actor in ipairs(view.actors) do drawActor(scene, take(scene.actorParts), actor, f) end
  hideRest(scene.actorParts)

  scene.graveParts.used = 0
  for _, grave in ipairs(view.graves or {}) do
    local parts = take(scene.graveParts)
    setSprite(parts.grave, "grave", unit)
    put(scene, parts.grave, grave.x, ROW.grave)
    local started = grave.key and scene.blooms[grave.key]
    local bloomed = started and GetTime() - started
    if bloomed and bloomed < BLOOM.lasts then
      drawBloom(scene, parts, grave, bloomed)
    else
      for _, petal in ipairs(parts.petals) do petal:Hide() end
      if grave.flower then
        setSprite(parts.flower, "flower", unit)
        put(scene, parts.flower, grave.x + OFFSET.flower, ROW.flower)
      else
        parts.flower:Hide()
      end
    end
  end
  hideRest(scene.graveParts)

  if view.tent then
    setSprite(scene.tent, "tent", unit, view.tent.x > 0)
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
  for key, start in pairs(scene.blooms) do
    if now - start >= BLOOM.lasts then scene.blooms[key] = nil end
  end
  drawFrame(scene, f)
end

local function puffShifts(scene, view)
  local now, forms = GetTime(), {}
  for _, actor in ipairs(view.actors) do
    local id = actor.memberId
    local form = actor.pose ~= "asleep" and actor.form or false
    local was = scene.forms[id]
    if was ~= nil and was ~= form then
      local puff = FORM[form] and FORM[form].puff or FORM[was] and FORM[was].puff or "leaves"
      scene.animations[#scene.animations + 1] = { kind = "shift", memberId = id, start = now,
        ends = now + ANIMATION_FOR.shift, puff = puff }
    end
    forms[id] = form
  end
  scene.forms = forms
end

local function bandCoords(art, columns)
  local first = math.floor((columns - art.columns) / art.step) * art.band
  return first / art.height, (first + art.band) / art.height
end

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
    crisp = options.crisp ~= false,
    hops = {},
    blooms = {},
    forms = {},
    animations = {},
    texture = function(layer, sublevel) return texture(band.art, layer, sublevel) end,
    actorParts = pool(function()
      return {
        back = texture(band.art, "ARTWORK", -1),
        seat = texture(band.art, "ARTWORK", 0),
        cloth = texture(band.art, "ARTWORK", 1),
        skin = texture(band.art, "ARTWORK", 2),
        hat = texture(band.art, "ARTWORK", 3),
        sleep = {
          texture(band.art, "ARTWORK", 2),
          texture(band.art, "ARTWORK", 2),
          texture(band.art, "ARTWORK", 2),
        },
        tool = texture(band.art, "ARTWORK", 3),
        front = texture(band.art, "ARTWORK", 4),
        spark = texture(band.art, "OVERLAY", 0),
        mark = texture(band.art, "OVERLAY", 1),
        alt = texture(band.art, "OVERLAY", 1),
        puff = texture(band.art, "OVERLAY", 2),
        cheer = {},
        label = shadowed(nameLabel(band.art)),
      }
    end),
    doorParts = pool(function()
      return {
        left = texture(band.art, "BORDER", 1),
        fillLeft = texture(band.art, "BORDER", 1),
        middle = texture(band.art, "BORDER", 1),
        fillRight = texture(band.art, "BORDER", 1),
        right = texture(band.art, "BORDER", 1),
      }
    end),
    graveParts = pool(function()
      return {
        grave = texture(band.art, "ARTWORK", 0),
        flower = texture(band.art, "ARTWORK", 1),
        petals = {
          texture(band.art, "ARTWORK", 2),
          texture(band.art, "ARTWORK", 2),
          texture(band.art, "ARTWORK", 2),
        },
      }
    end),
  }
  band.scene = scene
  local sky = band:CreateTexture(nil, "BACKGROUND", nil, 0)
  sky:SetAllPoints()
  sky:SetColorTexture(Sheet.sky[1], Sheet.sky[2], Sheet.sky[3], 1)
  sky:SetShown(options.backdrop == nil)
  scene.sky = sky

  scene.art = CreateFrame("Frame", nil, band)
  scene.art:SetPoint("BOTTOMLEFT")
  scene.art:SetPoint("TOPRIGHT")
  Skin.snapToPixels(scene.art)
  band.art = scene.art
  scene.backdrop = scene.art:CreateTexture(nil, "BACKGROUND", nil, 1)
  scene.backdrop:SetTexture(scene.backdropArt.file, "CLAMP", "CLAMP", "NEAREST")
  scene.tent = texture(scene.art, "BORDER", 0)
  scene.logs = texture(scene.art, "ARTWORK", 0)
  scene.flame = texture(scene.art, "ARTWORK", 1)
  scene.crate = texture(scene.art, "ARTWORK", 2)
  scene.crate:Hide()
  scene.embers = { texture(scene.art, "ARTWORK", 2), texture(scene.art, "ARTWORK", 2), texture(scene.art, "ARTWORK", 2) }
  scene.cup = texture(scene.art, "ARTWORK", 3)
  scene.cup:Hide()
  scene.cupSparkles = { texture(scene.art, "ARTWORK", 3), texture(scene.art, "ARTWORK", 3) }
  for _, sparkle in ipairs(scene.cupSparkles) do sparkle:Hide() end
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
    scene.horde = UnitFactionGroup ~= nil and UnitFactionGroup("player") == "Horde"
    puffShifts(scene, view)
    local art = scene.backdropArt
    if art.band then
      scene.backdrop:SetTexCoord(0, 1, bandCoords(art, view.columns))
      scene.backdrop:SetSize(art.width * scene.unit, art.band * scene.unit)
    else
      scene.backdrop:SetSize(art.width * scene.unit, art.height * scene.unit)
    end
    put(scene, scene.backdrop, -art.fire, 0)
    scene.more:SetText(view.moreText or "")
    band:Show()
    onUpdate(band)
  end

  function band:Measure(width, height)
    scene.unit = CampScene.artUnit(band, scene.target)
    local columns = math.floor(width / scene.unit)
    local rows = math.floor(height / scene.unit)
    scene.fire = math.floor(columns / 2)
    scene.rows = rows
    return columns, rows * scene.unit
  end

  function band:Unit()
    return scene.unit
  end

  function band:FireX()
    return (scene.fire + 0.5) * scene.unit
  end

  function band:SetTarget(target)
    scene.target = target
  end

  function band:Fit(columns, rows)
    scene.unit = scene.crisp and CampScene.artUnit(band, scene.target) or scene.target
    scene.fire = math.floor(columns / 2)
    scene.rows = rows
    return columns * scene.unit, rows * scene.unit
  end

  function band:SetBackdropAlpha(alpha)
    scene.sky:SetAlpha(alpha)
    scene.backdrop:SetAlpha(alpha)
  end

  function band:ActorAt(x)
    if not scene.view or not scene.unit then return nil end
    local at = x / scene.unit - scene.fire
    local reach = LAYOUT.gap / 2
    for _, actor in ipairs(scene.view.actors) do
      if at >= actor.x - reach and at < actor.x + actor.width + reach then return actor end
    end
    return nil
  end

  function band:CrateAt(x, y)
    if not (scene.view and scene.view.spares and scene.unit) then return false end
    local s = Sheet.sprites.crate
    local at, row = x / scene.unit - scene.fire, y / scene.unit
    return at >= CRATE_X and at < CRATE_X + s[3] and row >= ROW.crate and row < ROW.crate + s[4]
  end

  function band:CupAt(x, y)
    if not (scene.view and scene.view.trophies and scene.unit) then return false end
    local s = Sheet.sprites.trophyCup
    local at, row = x / scene.unit - scene.fire - CUP_X, y / scene.unit - ROW.cup
    return at >= 0 and at < s[3] and row >= 0 and row < s[4] + 1
  end

  function band:Animate(kind, memberId)
    local lasts = ANIMATION_FOR[kind]
    if not lasts then return end
    local now = GetTime()
    scene.animations[#scene.animations + 1] = { kind = kind, memberId = memberId, start = now, ends = now + lasts }
    scene.frame = nil
  end

  local function upByFire(memberId)
    for _, actor in ipairs(scene.view and scene.view.actors or {}) do
      if actor.memberId == memberId and actor.pose ~= "asleep" then return true end
    end
    return false
  end

  function band:Hop(memberId)
    if upByFire(memberId) then
      scene.hops[memberId] = GetTime()
      scene.frame = nil
    end
  end

  function band:React(reaction)
    if not scene.view then return end
    if reaction.kind == "cheer" then
      self:Hop(reaction.memberId)
    elseif reaction.kind == "welcome" then
      if upByFire(reaction.memberId) then self:Animate("welcome", reaction.memberId) end
    elseif reaction.kind == "respects" and reaction.grave then
      for _, grave in ipairs(scene.view.graves or {}) do
        if grave.key == reaction.grave then
          scene.blooms[grave.key] = GetTime()
          scene.frame = nil
        end
      end
    end
  end

  return band
end
