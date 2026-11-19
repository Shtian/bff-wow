local _, ns = ...

local Actions = {}
ns.Actions = Actions

-- WoW: on Forever a Character is whispered and invited as "First Last"; the first
-- name alone reaches no one, or someone else.
function Actions.whisper(fullName)
  local sendTell = ChatFrameUtil and ChatFrameUtil.SendTell or ChatFrame_SendTell
  if sendTell then sendTell(fullName) end
end

function Actions.invite(fullName)
  if C_PartyInfo and C_PartyInfo.InviteUnit then C_PartyInfo.InviteUnit(fullName) end
end

function Actions.openMap(mapId)
  if OpenWorldMap then
    OpenWorldMap(mapId)
  elseif WorldMapFrame then
    ShowUIPanel(WorldMapFrame)
    WorldMapFrame:SetMapID(mapId)
  end
end
