local _, ns = ...

local LanternSeats = {}
ns.LanternSeats = LanternSeats

local MUTED = ns.Skin.MUTED

function LanternSeats.addTooltip(saved)
  local tip = saved.tooltip
  GameTooltip:AddLine(tip.title)
  for _, line in ipairs(tip.lines) do GameTooltip:AddLine(line, 1, 1, 1) end
  if tip.hint then GameTooltip:AddLine(tip.hint, MUTED[1], MUTED[2], MUTED[3]) end
end

function LanternSeats.click(saved, button)
  if not saved.code then return false end
  if button == "RightButton" then
    ns.RosterTab.showCode()
  else
    ns.Actions.openChat(saved.invite)
  end
  return true
end
