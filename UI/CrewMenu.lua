local _, ns = ...

local CrewMenu = {}
ns.CrewMenu = CrewMenu

local core

local function say(reason)
  if reason and ns.MESSAGES[reason] then ns.say(ns.MESSAGES[reason]) end
end

local function run(command)
  return function()
    local _, reason = command()
    say(reason)
  end
end

StaticPopupDialogs.BFF_RENAME_CREW = {
  text = "Name this Crew. Only you see the name.",
  button1 = OKAY,
  button2 = CANCEL,
  hasEditBox = true,
  maxLetters = ns.Core.MAX_CREW_LABEL,
  OnShow = function(self, label)
    local box = self.editBox or self.EditBox
    box:SetText(label or "")
    box:HighlightText()
  end,
  OnAccept = function(self)
    local box = self.editBox or self.EditBox
    run(function() return core:renameCrew(box:GetText()) end)()
  end,
  EditBoxOnEnterPressed = function(box)
    local dialog = box:GetParent()
    run(function() return core:renameCrew(box:GetText()) end)()
    dialog:Hide()
  end,
  EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
}

StaticPopupDialogs.BFF_DELETE_CREW = {
  text = "Delete %s? Its Feed, goals and records on this computer are gone for good.",
  button1 = YES,
  button2 = NO,
  OnAccept = function(_, id) run(function() return core:deleteLeftCrew(id) end)() end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
}

local function locked(element, row, crews)
  if not row.locked then return end
  element:SetEnabled(false)
  element:SetTooltip(function(tooltip) tooltip:AddLine(crews.lockedText, 1, 1, 1, true) end)
end

local function addLeft(parent, crews)
  for _, row in ipairs(crews.left) do
    local item = parent:CreateButton(row.leftLine)
    locked(item:CreateButton("Rejoin", run(function() return core:rejoinCrew(row.id) end)), row, crews)
    item:CreateButton("Delete…", function()
      StaticPopup_Show("BFF_DELETE_CREW", row.label, nil, row.id)
    end)
  end
end

function CrewMenu.show(owner)
  local crews = core:crews()
  MenuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateTitle("Your Crews")
    for _, row in ipairs(crews.list) do
      local radio = root:CreateRadio(row.label, function() return row.current end,
        run(function() return core:switchCrew(row.id) end))
      locked(radio, row, crews)
    end
    root:CreateDivider()
    if crews.current then
      root:CreateButton("Rename this Crew…", function()
        StaticPopup_Show("BFF_RENAME_CREW", nil, nil, crews.current.renamed and crews.current.label or "")
      end)
      locked(root:CreateButton("Start or join another Crew…", run(function()
        local ok, reason = core:startAnother()
        if ok then ns.Panel.show("roster") end
        return ok, reason
      end)), { locked = crews.locked }, crews)
    end
    if #crews.left > 0 then addLeft(root:CreateButton("Left Crews"), crews) end
  end)
end

function CrewMenu.showLeft(owner)
  local crews = core:crews()
  MenuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateTitle("Left Crews")
    addLeft(root, crews)
  end)
end

function CrewMenu.start(theCore)
  core = theCore
end
