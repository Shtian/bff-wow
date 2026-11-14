-- Firelight: the Camp's fire lighting the panel under its band (DESIGN.md,
-- the Firelit Window Rule; docs/design/camp.md). The fire's glow spills
-- onto the window and breathes with the flames, the night settles towards
-- the window's foot, and now and then an ember comes out from under the
-- fire and drifts down into the window, cooling from gold to red as it
-- falls. All of it is drawn on the owner's own layers, under every frame
-- in the window, so rows, pictures and text sit over the light and are
-- never shaded by it. One OnUpdate steps it, on a frame shown only while
-- the band is, so it stops with the Camp and with the panel. Silent.

local _, ns = ...

local Firelight = {}
ns.Firelight = Firelight

local Skin = ns.Skin
local Sheet = ns.CampSheet

-- The glow: this share of the window wide, this high at most (UI units),
-- and this strong, added to what's under it. The lip is a brighter,
-- shallow glow right under the fire, where the band's ground meets the
-- window.
local GLOW_WIDTH = 0.83
local GLOW_HEIGHT = 300
local GLOW_ALPHA = 0.16
local LIP_WIDTH = 0.68
local LIP_HEIGHT = 21
local LIP_ALPHA = 0.3
-- The flicker, like the flames': the glow's strength steps through these,
-- each held for its own time in seconds.
local FLICKER = {
  { 0.9, 0.29 }, { 1, 0.21 }, { 0.84, 0.39 }, { 0.97, 0.34 },
  { 0.88, 0.42 }, { 1, 0.39 }, { 0.86, 0.31 }, { 0.95, 0.26 },
}
local FLICKER_LOOP = 0
for _, step in ipairs(FLICKER) do FLICKER_LOOP = FLICKER_LOOP + step[2] end
-- The night settling: a shade rising from the window's foot, this high at
-- most, or half the room under the band in a short window.
local SETTLE_HEIGHT = 200

-- Embers: at most EMBERS at once. One comes out every EMBER_EVERY seconds
-- or so, and now and then (PAIR_CHANCE) a second follows PAIR_AFTER
-- later. Each starts within SPREAD of the fire's middle, then over LIFE
-- seconds falls FALL, drifts up to DRIFT to one side and sways SWAY back
-- and forth SWAY_TIMES times. Its fall speeds up along the curve t ^
-- FALL_CURVE. All in UI units and seconds.
local EMBERS = 6
local EMBER_EVERY = { 1.4, 3.6 }
local PAIR_CHANCE = 0.25
local PAIR_AFTER = { 0.15, 0.5 }
local SPREAD = 24
local LIFE = { 4.2, 7 }
local FALL = { 120, 260 }
local DRIFT = 110
local SWAY = { 6, 17 }
local SWAY_TIMES = 1.5
local FALL_CURVE = 1.35
-- An ember cools as it goes: each sprite until that share of its life.
local COOLING = { { 0.25, "ember" }, { 0.6, "emberWarm" }, { 1, "emberCool" } }
-- It fades in over FADE_IN of its life and out after FADE_OUT, and out
-- over the last EDGE_FADE UI units before the window's edges, at most
-- EMBER_ALPHA.
local FADE_IN = 0.08
local FADE_OUT = 0.7
local EDGE_FADE = 24
local EMBER_ALPHA = 0.9

local function between(range)
  return range[1] + math.random() * (range[2] - range[1])
end

local function spriteAt(t)
  for _, stage in ipairs(COOLING) do
    if t < stage[1] then return stage[2] end
  end
  return COOLING[#COOLING][2]
end

-- The glow's strength at a time, through the flicker's loop.
local function flickerAt(now)
  local into = now % FLICKER_LOOP
  for _, step in ipairs(FLICKER) do
    if into < step[2] then return step[1] end
    into = into - step[2]
  end
  return FLICKER[#FLICKER][1]
end

-- Where an ember is at t, 0 to 1 through its life: x from the band's left
-- edge, y down from its bottom (negative), and its alpha before the edge
-- fade.
local function emberAt(ember, t)
  local x = ember.x + ember.drift * (1 - (1 - t) ^ 2) + ember.sway * math.sin(t * math.pi * 2 * SWAY_TIMES)
  local y = -ember.fall * t ^ FALL_CURVE
  local alpha = 1
  if t < FADE_IN then
    alpha = t / FADE_IN
  elseif t > FADE_OUT then
    alpha = math.max(0, 1 - (t - FADE_OUT) / (1 - FADE_OUT))
  end
  return x, y, alpha * EMBER_ALPHA
end

-- The firelight in `owner` (the panel). Call :Place after each layout.
function Firelight.new(owner)
  local driver = CreateFrame("Frame", nil, owner)
  driver:Hide()
  local band, room, width

  -- Over the window's fill, under everything else.
  local settle = owner:CreateTexture(nil, "BACKGROUND", nil, 1)
  settle:SetColorTexture(1, 1, 1, 1)
  Skin.gradient(settle, "VERTICAL", Skin.SETTLE, Skin.alpha(Skin.SETTLE, 0))
  settle:SetPoint("BOTTOMLEFT", 1, 1)
  settle:SetPoint("BOTTOMRIGHT", -1, 1)
  settle:Hide()

  local function glowTexture(sublevel, alpha)
    local texture = owner:CreateTexture(nil, "BACKGROUND", nil, sublevel)
    texture:SetTexture(Sheet.light.file, "CLAMP", "CLAMP")
    texture:SetBlendMode("ADD")
    texture:SetAlpha(alpha)
    texture:Hide()
    return texture
  end
  local glow = glowTexture(2, GLOW_ALPHA)
  local lip = glowTexture(3, LIP_ALPHA)

  local embers = {}
  for i = 1, EMBERS do
    local texture = owner:CreateTexture(nil, "ARTWORK")
    texture:SetTexture(Sheet.file, "CLAMP", "CLAMP", "NEAREST")
    texture:Hide()
    embers[i] = { texture = texture }
  end

  local function spawn(now)
    for _, ember in ipairs(embers) do
      if not ember.start then
        ember.start = now
        ember.life = between(LIFE)
        ember.x = band:FireX() + (math.random() * 2 - 1) * SPREAD
        ember.fall = between(FALL)
        ember.drift = (math.random() * 2 - 1) * DRIFT
        ember.sway = between(SWAY) * (math.random() < 0.5 and -1 or 1)
        return
      end
    end
  end

  local function putOut(ember)
    ember.start = nil
    ember.texture:Hide()
  end

  local nextEmber, pairAt, strength
  driver:SetScript("OnShow", function()
    nextEmber = GetTime() + between({ 0.5, EMBER_EVERY[1] })
    pairAt = nil
    strength = nil
    for _, ember in ipairs(embers) do putOut(ember) end
  end)
  driver:SetScript("OnHide", function()
    for _, ember in ipairs(embers) do putOut(ember) end
  end)

  driver:SetScript("OnUpdate", function()
    local now = GetTime()
    local flicker = flickerAt(now)
    if flicker ~= strength then
      strength = flicker
      glow:SetAlpha(GLOW_ALPHA * flicker)
      lip:SetAlpha(LIP_ALPHA * flicker)
    end

    if now >= nextEmber then
      spawn(now)
      if math.random() < PAIR_CHANCE then pairAt = now + between(PAIR_AFTER) end
      nextEmber = now + between(EMBER_EVERY)
    end
    if pairAt and now >= pairAt then
      spawn(now)
      pairAt = nil
    end

    local unit = band:Unit()
    for _, ember in ipairs(embers) do
      if ember.start then
        local t = (now - ember.start) / ember.life
        local x, y, alpha = emberAt(ember, math.min(t, 1))
        -- How far it is from the nearest edge it could leave by.
        local edge = math.min(room + y, x, width - x) - unit
        if t >= 1 or edge <= 0 then
          putOut(ember)
        else
          ns.CampScene.sprite(ember.texture, spriteAt(t), unit)
          ember.texture:SetAlpha(alpha * math.min(1, edge / EDGE_FADE))
          ember.texture:ClearAllPoints()
          ember.texture:SetPoint("TOPLEFT", band, "BOTTOMLEFT", x - unit / 2, y)
        end
      end
    end
  end)

  -- Lights the window under `campBand` (a CampScene band, measured and
  -- drawn), with `below` UI units of window under it, or puts the light
  -- out when below is nil (no Camp).
  function driver:Place(campBand, below)
    local lit = below ~= nil and below > 0 and campBand:IsShown()
    settle:SetShown(lit)
    glow:SetShown(lit)
    lip:SetShown(lit)
    if not lit then
      driver:Hide()
      return
    end
    band, room, width = campBand, below, owner:GetWidth()
    local fire = band:FireX()

    -- The glow hangs from the fire; in a short window its foot is cut
    -- off, not squashed.
    local height = math.min(GLOW_HEIGHT, below)
    glow:ClearAllPoints()
    glow:SetPoint("TOP", band, "BOTTOMLEFT", fire, 0)
    glow:SetSize(width * GLOW_WIDTH, height)
    glow:SetTexCoord(0, 1, 0, height / GLOW_HEIGHT)
    lip:ClearAllPoints()
    lip:SetPoint("TOP", band, "BOTTOMLEFT", fire, 0)
    lip:SetSize(width * LIP_WIDTH, math.min(LIP_HEIGHT, below))

    settle:SetHeight(math.min(SETTLE_HEIGHT, below / 2))
    driver:Show()
  end

  return driver
end
