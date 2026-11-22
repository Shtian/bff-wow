local _, ns = ...

local MapPins = {}
ns.MapPins = MapPins

local Skin = ns.Skin
local HBDPins = LibStub("HereBeDragons-Pins-2.0")

local SIZES = {
  small = { figure = 1.1, icon = 13 },
  medium = { figure = 1.4, icon = 16 },
  large = { figure = 1.8, icon = 20 },
}
local DOT = 5
local KEYLINE = 1
local OFFLINE_ALPHA = 0.5

local core
local frames = {}

local parking = CreateFrame("Frame", nil, UIParent)
parking:Hide()

-- WoW: HereBeDragons-Pins drops a released icon onto UIParent, and map addons that borrow icons (OpenMap) can show it there, at the centre of the screen.
local function keepOffScreen(frame, parent)
  if parent == UIParent then frame:SetParent(parking) end
end

local function showTooltip(frame)
  local pin = frame.pin
  if not pin then return end
  GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
  GameTooltip:AddLine(pin.displayName or pin.name, 1, 1, 1)
  GameTooltip:AddLine(("%s, level %d"):format(pin.fullName, pin.level), Skin.classColor(pin.classFilename))
  -- WoW: inside an instance the zone is usually the instance itself.
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

local function disc(parent, sublevel, size)
  local t = parent:CreateTexture(nil, "OVERLAY", nil, sublevel)
  t:SetSize(size, size)
  t:SetColorTexture(1, 1, 1, 1)
  return Skin.round(parent, t)
end

local function createFrame()
  local frame = CreateFrame("Frame", nil, parking)
  hooksecurefunc(frame, "SetParent", keepOffScreen)
  frame:EnableMouse(true)
  frame.figure = ns.CampScene.figure(frame)
  frame.figure:SetPoint("CENTER")
  frame.icon = frame:CreateTexture(nil, "ARTWORK")
  frame.icon:SetPoint("CENTER")
  Skin.round(frame, frame.icon)
  local badge = CreateFrame("Frame", nil, frame)
  badge:SetSize(DOT + 2 * KEYLINE, DOT + 2 * KEYLINE)
  badge:SetPoint("CENTER", frame, "BOTTOMRIGHT", -1, 1)
  local keyline = disc(badge, 0, DOT + 2 * KEYLINE)
  keyline:SetPoint("CENTER")
  keyline:SetVertexColor(Skin.WINDOW[1], Skin.WINDOW[2], Skin.WINDOW[3], 1)
  local dot = disc(badge, 1, DOT)
  dot:SetPoint("CENTER")
  Skin.color(dot, Skin.ONLINE)
  frame.online = badge
  frame:SetScript("OnEnter", showTooltip)
  frame:SetScript("OnLeave", hideTooltip)
  frame:Hide()
  return frame
end

local function draw(frame, pin)
  frame.pin = pin
  local size = SIZES[pin.size] or SIZES.medium
  if pin.figure then
    frame.icon:Hide()
    frame.figure:SetTarget(size.figure)
    frame.figure:SetClass(pin.figure)
    frame:SetSize(frame.figure:GetSize())
  else
    frame.figure:Hide()
    frame.icon:SetAtlas("classicon-" .. (pin.classFilename or ""):lower())
    frame.icon:SetSize(size.icon, size.icon)
    frame.icon:Show()
    frame:SetSize(size.icon, size.icon)
  end
  -- WoW: HereBeDragons-Pins reparents the pin onto the map's canvas.
  frame.online:SetFrameLevel(frame:GetFrameLevel() + 5)
  frame.online:SetShown(pin.online)
  frame:SetAlpha(pin.online and 1 or OFFLINE_ALPHA)
end

function MapPins.refresh()
  if not core then return end
  HBDPins:RemoveAllWorldMapIcons(MapPins)
  local pins = core:mapPins()
  for i, pin in ipairs(pins) do
    local frame = frames[i] or createFrame()
    frames[i] = frame
    HBDPins:AddWorldMapIconMap(MapPins, frame, pin.mapId, pin.x, pin.y, HBD_PINS_WORLDMAP_SHOW_WORLD)
    draw(frame, pin)
  end
  for i = #pins + 1, #frames do
    frames[i].pin = nil
    frames[i]:Hide()
  end
end

function MapPins.moved()
  if WorldMapFrame and WorldMapFrame:IsShown() then MapPins.refresh() end
end

function MapPins.settingChanged(key)
  if key == "mapPins" or key == "mapPinSize" or key == "camp" then MapPins.refresh() end
end

function MapPins.start(c)
  core = c
  if WorldMapFrame then WorldMapFrame:HookScript("OnShow", MapPins.refresh) end
  MapPins.refresh()
end
