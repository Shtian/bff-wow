-- Throwaway spike for "Set up the Forever client for addon development".
local loadedAt = date("%H:%M:%S")

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
  print(("|cff33ff99BFF|r hello from Forever (loaded %s) project=%s build=%s interface=%s"):format(
    loadedAt, tostring(WOW_PROJECT_ID), (GetBuildInfo()), (select(4, GetBuildInfo()))))
end)

SLASH_BFFHELLO1 = "/bffhello"
SlashCmdList.BFFHELLO = function()
  print("|cff33ff99BFF|r hello, edit me and /reload (v2)")
end
