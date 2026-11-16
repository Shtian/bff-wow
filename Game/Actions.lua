-- Actions: ordinary game actions the player takes on a Member from BFF's
-- menus (the Roster's rows, the Pocket Camp's figures): whisper, invite,
-- and open the world map on a map. Guarded, since Midnight moved some chat
-- functions and Forever may lack a helper. None of them sends anything of
-- BFF's.

local _, ns = ...

local Actions = {}
ns.Actions = Actions

-- On Forever a Character is whispered and invited as "First Last"; the
-- first name alone reaches no one (or someone else).
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
