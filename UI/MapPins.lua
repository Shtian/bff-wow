-- MapPins: a pin on the world map for where each other Member was last
-- seen, from Core's mapPins(), drawn through HereBeDragons-Pins. A pin is
-- the Member's avatar on a dark round plate: the Camp's seated figure in
-- the shown Character's class colour, or the class icon while the Camp is
-- off. It's ringed green while online and faded while offline, and shows
-- on its own map and on the zone, continent and world maps above it.
-- Hovering one says who, where and when. Your own Member has none; the
-- game already shows you. With the map setting off Core gives no pins.

local _, ns = ...

local MapPins = {}
ns.MapPins = MapPins

local Skin = ns.Skin
local HBDPins = LibStub("HereBeDragons-Pins-2.0")

-- The avatar's art unit on the map: a bit smaller than on Roster rows.
local FIGURE_TARGET = 1.5
-- The class icon's size while the Camp is off.
local ICON = 18
-- Room round the avatar inside the plate, the ring, and a dark keyline
-- outside it so a green ring reads on a bright map.
local PAD = 2
local RING = 2
local KEYLINE = 1
local OFFLINE_ALPHA = 0.5

local core
-- Pin frames, reused across refreshes.
local frames = {}

local function showTooltip(frame)
  local pin = frame.pin
  if not pin then return end
  GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
  GameTooltip:AddLine(pin.displayName or pin.name, 1, 1, 1)
  GameTooltip:AddLine(("%s, level %d"):format(pin.fullName, pin.level), Skin.classColor(pin.classFilename))
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
    GameTooltip:AddLine("Last seen " .. pin.lastSeenText, Skin.MUTED[1], Skin.MUTED[2], Skin.MUTED[3])
  end
  GameTooltip:Show()
end

local function hideTooltip()
  GameTooltip:Hide()
end

local function disc(frame, sublevel)
  local t = frame:CreateTexture(nil, "OVERLAY", nil, sublevel)
  t:SetPoint("CENTER")
  t:SetColorTexture(1, 1, 1, 1)
  return Skin.round(frame, t)
end

local function createFrame()
  local frame = CreateFrame("Frame", nil, UIParent)
  frame:EnableMouse(true)
  frame.keyline = disc(frame, 0)
  frame.keyline:SetVertexColor(Skin.WINDOW[1], Skin.WINDOW[2], Skin.WINDOW[3], 1)
  frame.ring = disc(frame, 1)
  frame.plate = disc(frame, 2)
  frame.plate:SetVertexColor(Skin.WINDOW[1], Skin.WINDOW[2], Skin.WINDOW[3], 1)
  -- The Camp's seated figure while the Camp is on, else the class icon.
  frame.figure = ns.CampScene.figure(frame, FIGURE_TARGET)
  frame.icon = frame:CreateTexture(nil, "OVERLAY", nil, 3)
  frame.icon:SetSize(ICON, ICON)
  frame.icon:SetPoint("CENTER")
  Skin.round(frame, frame.icon)
  frame:SetScript("OnEnter", showTooltip)
  frame:SetScript("OnLeave", hideTooltip)
  frame:Hide()
  return frame
end

-- Sizes the plate round what it shows: the figure (sized by its art unit)
-- or the icon.
local function size(frame, width, height)
  local plate = math.max(width, height) + 2 * PAD
  frame.plate:SetSize(plate, plate)
  frame.ring:SetSize(plate + 2 * RING, plate + 2 * RING)
  local outer = plate + 2 * (RING + KEYLINE)
  frame.keyline:SetSize(outer, outer)
  frame:SetSize(outer, outer)
end

local function draw(frame, pin)
  frame.pin = pin
  if pin.figure then
    frame.icon:Hide()
    frame.figure:SetClass(pin.figure)
    frame.figure:ClearAllPoints()
    frame.figure:SetPoint("CENTER")
    size(frame, frame.figure:GetSize())
  else
    frame.figure:Hide()
    frame.icon:SetAtlas("classicon-" .. (pin.classFilename or ""):lower())
    frame.icon:Show()
    size(frame, ICON, ICON)
  end
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
    HBDPins:AddWorldMapIconMap(MapPins, frame, pin.mapId, pin.x, pin.y, HBD_PINS_WORLDMAP_SHOW_WORLD)
    -- Drawn once on the map's canvas, so the figure's art unit is worked
    -- out at the canvas's scale.
    draw(frame, pin)
  end
  for i = #pins + 1, #frames do
    frames[i].pin = nil
    frames[i]:Hide()
  end
end

-- The map setting: Core gives no pins while it's off.
-- A Member's live spot changed: redrawn now if the map is open, else when
-- it opens.
function MapPins.moved()
  if WorldMapFrame and WorldMapFrame:IsShown() then MapPins.refresh() end
end

function MapPins.settingChanged(key)
  if key == "mapPins" or key == "camp" then MapPins.refresh() end
end

function MapPins.start(c)
  core = c
  -- Last seen goes stale, so opening the map redraws it.
  if WorldMapFrame then WorldMapFrame:HookScript("OnShow", MapPins.refresh) end
  MapPins.refresh()
end
