local _, ns = ...

local Minimap = {}
ns.Minimap = Minimap

local NAME = "BFF"
local ICON = "Interface\\AddOns\\BFF\\Media\\BFF"

local core
local icons
local badge
local shown

local function showTooltip(tooltip)
  tooltip:AddDoubleLine("BFF", ns.VERSION, nil, nil, nil, 0.6, 0.6, 0.6)
  if not core:crew() then
    tooltip:AddLine("Not in a Crew. Click to start or join one.", 1, 1, 1)
  else
    local counts = core:rosterCounts()
    tooltip:AddLine(("%d of %d online · %d can play with you now"):format(counts.online,
      counts.members, counts.canPlay), 1, 1, 1)
    local unseen = core:unseen()
    if not core:isAwayPopupOn() and unseen > 0 then
      tooltip:AddLine(("%d new in Feed"):format(unseen), 1, 0.82, 0)
    end
    if core:isPaused() then tooltip:AddLine("You appear offline.", 0.6, 0.6, 0.6) end
  end
  tooltip:AddLine("Click: open BFF. Right-click: options.", 0.6, 0.6, 0.6)
end

local function hideButton()
  core:setMinimapShown(false)
  ns.say(ns.MESSAGES.minimapHidden)
end

local function showMenu(owner)
  MenuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateTitle("BFF")
    root:CreateButton("Settings", function() ns.Panel.show("settings") end)
    local pause = root:CreateCheckbox("Appear offline", function() return core:isPaused() end,
      function() core:setPaused(not core:isPaused()) end)
    pause:SetEnabled(core:crew() ~= nil)
    root:CreateButton("Hide minimap button", hideButton)
  end)
end

local function onClick(owner, mouse)
  if mouse == "RightButton" then
    GameTooltip:Hide()
    showMenu(owner)
  else
    ns.Panel.toggle()
  end
end

local function createBadge()
  local button = icons:GetMinimapButton(NAME)
  if not button then return end
  local Skin = ns.Skin
  badge = Skin.badge(button, "tiny", Skin.TEXT, Skin.WINDOW)
  badge:SetFrameLevel(button:GetFrameLevel() + 5)
  badge:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -3, 4)
end

local function showButton(on)
  if on == shown then return end
  shown = on
  if shown then icons:Show(NAME) else icons:Hide(NAME) end
end

function Minimap.settingChanged(key, on)
  if key == "minimap" and icons then showButton(on) end
end

function Minimap.refresh()
  if not icons then return end
  showButton(core:isMinimapShown())
  if not badge then return end
  local online = core:crew() and core:rosterCounts().online or 0
  badge:SetText(online)
  badge:SetShown(online > 0)
end

function Minimap.start(theCore)
  core = theCore
  icons = LibStub("LibDBIcon-1.0")
  local broker = LibStub("LibDataBroker-1.1"):NewDataObject(NAME, {
    type = "launcher",
    label = "BFF",
    icon = ICON,
    OnClick = onClick,
    OnTooltipShow = showTooltip,
  })
  icons:Register(NAME, broker, core:minimapIcon())
  createBadge()
  Minimap.refresh()
end
