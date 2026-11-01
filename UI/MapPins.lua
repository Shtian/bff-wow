-- MapPins: a pin on the world map for where each other Member was last
-- seen, from Core's mapPins(), drawn through HereBeDragons-Pins. A pin is
-- a dot in the shown Character's class colour, ringed green while online
-- and faded while offline, and shows on its own map and on the zone,
-- continent and world maps above it. Hovering one says who, where and
-- when. Your own Member has none; the game already shows you.

local _, ns = ...

local MapPins = {}
ns.MapPins = MapPins

local Skin = ns.Skin
local HBDPins = LibStub("HereBeDragons-Pins-2.0")

local SIZE = 12
local RING = 3
local OFFLINE_ALPHA = 0.5

local core
-- Pin frames, reused across refreshes.
local frames = {}

local function showTooltip(frame)
  local pin = frame.pin
  if not pin then return end
  GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
  GameTooltip:AddLine(pin.displayName or pin.name, 1, 1, 1)
  GameTooltip:AddLine(("%s, level %d"):format(pin.name, pin.level), Skin.classColor(pin.classFilename))
  -- Inside an instance the zone is usually the instance itself.
  if pin.zone and pin.zone ~= pin.instance then
    GameTooltip:AddLine(pin.zone, Skin.MUTED[1], Skin.MUTED[2], Skin.MUTED[3])
  end
  if pin.instance then
    GameTooltip:AddLine("in " .. pin.instance, Skin.MUTED[1], Skin.MUTED[2], Skin.MUTED[3])
  end
  if pin.online then
    GameTooltip:AddLine("Online now", Skin.ONLINE[1], Skin.ONLINE[2], Skin.ONLINE[3])
  else
    GameTooltip:AddLine("Last seen " .. Skin.ago(pin.sinceSeen) .. " ago", Skin.MUTED[1], Skin.MUTED[2], Skin.MUTED[3])
  end
  GameTooltip:Show()
end

local function hideTooltip()
  GameTooltip:Hide()
end

local function createFrame()
  local frame = CreateFrame("Frame", nil, UIParent)
  frame:SetSize(SIZE + 2 * RING, SIZE + 2 * RING)
  frame:EnableMouse(true)
  frame.ring = frame:CreateTexture(nil, "OVERLAY", nil, 1)
  frame.ring:SetAllPoints()
  frame.ring:SetColorTexture(1, 1, 1, 1)
  Skin.round(frame, frame.ring)
  frame.dot = frame:CreateTexture(nil, "OVERLAY", nil, 2)
  frame.dot:SetSize(SIZE, SIZE)
  frame.dot:SetPoint("CENTER")
  frame.dot:SetColorTexture(1, 1, 1, 1)
  Skin.round(frame, frame.dot)
  frame:SetScript("OnEnter", showTooltip)
  frame:SetScript("OnLeave", hideTooltip)
  frame:Hide()
  return frame
end

local function draw(frame, pin)
  frame.pin = pin
  frame.dot:SetVertexColor(Skin.classColor(pin.classFilename))
  Skin.color(frame.ring, pin.online and Skin.ONLINE or Skin.WINDOW)
  frame:SetAlpha(pin.online and 1 or OFFLINE_ALPHA)
end

-- Redraws every pin from Core.
function MapPins.refresh()
  if not core then return end
  HBDPins:RemoveAllWorldMapIcons(MapPins)
  local pins = core:mapPins()
  for i, pin in ipairs(pins) do
    local frame = frames[i] or createFrame()
    frames[i] = frame
    draw(frame, pin)
    HBDPins:AddWorldMapIconMap(MapPins, frame, pin.mapId, pin.x, pin.y, HBD_PINS_WORLDMAP_SHOW_WORLD)
  end
  for i = #pins + 1, #frames do
    frames[i].pin = nil
    frames[i]:Hide()
  end
end

function MapPins.start(c)
  core = c
  -- Last seen goes stale, so opening the map redraws it.
  if WorldMapFrame then WorldMapFrame:HookScript("OnShow", MapPins.refresh) end
  MapPins.refresh()
end
