local _, ns = ...

local Firelight = {}
ns.Firelight = Firelight

local Skin = ns.Skin
local Sheet = ns.CampSheet

local GLOW_WIDTH = 0.83
local GLOW_HEIGHT = 300
local GLOW_ALPHA = 0.16
local LIP_WIDTH = 0.68
local LIP_HEIGHT = 21
local LIP_ALPHA = 0.3
local FLICKER = {
  { 0.9, 0.29 }, { 1, 0.21 }, { 0.84, 0.39 }, { 0.97, 0.34 },
  { 0.88, 0.42 }, { 1, 0.39 }, { 0.86, 0.31 }, { 0.95, 0.26 },
}
local FLICKER_LOOP = 0
for _, step in ipairs(FLICKER) do FLICKER_LOOP = FLICKER_LOOP + step[2] end
local SETTLE_HEIGHT = 200

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
local COOLING = { { 0.25, "ember" }, { 0.6, "emberWarm" }, { 1, "emberCool" } }
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

local function flickerAt(now)
  local into = now % FLICKER_LOOP
  for _, step in ipairs(FLICKER) do
    if into < step[2] then return step[1] end
    into = into - step[2]
  end
  return FLICKER[#FLICKER][1]
end

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

function Firelight.new(owner)
  local driver = CreateFrame("Frame", nil, owner)
  driver:Hide()
  local band, room, width

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
