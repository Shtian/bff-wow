local _, ns = ...

local StrayPet = {}
ns.StrayPet = StrayPet

local MUTED = ns.Skin.MUTED

function StrayPet.addTooltip(stray)
  local tip = stray.tooltip
  GameTooltip:AddLine(tip.title)
  GameTooltip:AddLine(tip.hint, MUTED[1], MUTED[2], MUTED[3])
end

function StrayPet.click(button)
  if button == "RightButton" then
    ns.core:strayNotNow()
    return
  end
  local line = ns.core:keepStray()
  if line then ns.say(line) end
end
