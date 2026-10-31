-- Minimap: the minimap button from the panel decision (#7), through
-- LibDataBroker and LibDBIcon. Click toggles the panel, the badge counts
-- Members online, the tooltip says who is online and can play, and
-- right-click gives Settings, Pause sharing and Hide minimap button. Its
-- position and hidden flag live in Core's account-wide minimap table.

local _, ns = ...

local Minimap = {}
ns.Minimap = Minimap

local NAME = "BFF"
local ICON = "Interface\\Icons\\INV_Misc_GroupNeedMore"

local core
local icons
local badge
-- Whether the button is shown, so refresh only calls LibDBIcon on a change.
local shown

-- "N of M online · K can play with you now", or how to get started.
local function showTooltip(tooltip)
  tooltip:AddLine("BFF")
  if not core:crew() then
    tooltip:AddLine("Not in a Crew. Click to start or join one.", 1, 1, 1)
  else
    local summary = core:summary()
    tooltip:AddLine(("%d of %d online · %d can play with you now"):format(summary.online,
      summary.members, summary.canPlay), 1, 1, 1)
    if core:isPaused() then tooltip:AddLine("Sharing is paused.", 0.6, 0.6, 0.6) end
  end
  tooltip:AddLine("Click: open BFF. Right-click: options.", 0.6, 0.6, 0.6)
end

local function hideButton()
  core:setMinimapShown(false)
  ns.say(ns.MESSAGES.minimapHidden)
end

-- Settings comes once the settings page exists (ns.Settings).
local function showMenu(owner)
  MenuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateTitle("BFF")
    if ns.Settings then
      root:CreateButton("Settings", function() ns.Settings.open() end)
    end
    local pause = root:CreateCheckbox("Pause sharing", function() return core:isPaused() end,
      function() core:setPaused(not core:isPaused()) end)
    pause:SetEnabled(core:crew() ~= nil and not core:isReceiveOnly())
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

-- The count of Members online, over the icon's lower right.
local function createBadge()
  local button = icons:GetMinimapButton(NAME)
  if not button then return end
  badge = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
  badge:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -4, 5)
end

-- Shows or hides the button and redraws the badge, from Core.
function Minimap.refresh()
  if not icons then return end
  if core:isMinimapShown() ~= shown then
    shown = core:isMinimapShown()
    if shown then icons:Show(NAME) else icons:Hide(NAME) end
  end
  if not badge then return end
  local online = core:crew() and core:summary().online or 0
  badge:SetText(online > 0 and online or "")
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
