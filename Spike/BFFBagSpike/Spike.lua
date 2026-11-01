-- Throwaway spike for the retail bag item tests in docs/research/bag-items.md (#67).
-- Everything is printed to chat and kept in BFFBagSpikeDB.log
-- (WTF\Account\<ACCOUNT>\SavedVariables\BFFBagSpike.lua).
--
-- /bagtest            help
-- /bagtest frame      show or hide the drop frame (tests 1-3, 7)
-- /bagtest item       describe the item on the cursor (tests 8, 9, 11, 14)
-- /bagtest item B S   describe the item in bag B, slot S (e.g. /bagtest item 0 1)
-- /bagtest track      track the item on the cursor by its GUID (tests 11-15)
-- /bagtest where      where are the tracked items now?
-- /bagtest untrack    forget all tracked items
-- /bagtest bank       list bank containers and their first item (test 12)
-- /bagtest hook       hook HandleModifiedItemClick for this session (tests 4, 5, 7)
-- /bagtest mods       print the modified-click bindings (test 6)
-- /bagtest link       split the cursor item's link into fields (test 17)
-- /bagtest clear      clear the saved log

local ADDON = ...
local MAX_LOG = 3000
local t0 = GetTimePreciseSec()
local db

-- Logging ------------------------------------------------------------------

local function str(v)
  if issecretvalue and issecretvalue(v) then return "<secret>" end
  local ok, s = pcall(tostring, v)
  return ok and s or "<?>"
end

local function args(...)
  local out = {}
  for i = 1, select("#", ...) do out[#out + 1] = str((select(i, ...))) end
  return table.concat(out, " | ")
end

local function write(kind, text)
  local line = ("%s +%.3f [%s] %s"):format(date("%H:%M:%S"), GetTimePreciseSec() - t0, kind, text)
  print("|cff33ff99BagSpike|r " .. line)
  if db then
    db.log[#db.log + 1] = line
    if #db.log > MAX_LOG then table.remove(db.log, 1) end
  end
end

-- Call fn safely; returns its results as one string, or the error.
local function try(fn, ...)
  if not fn then return "n/a (missing API)" end
  local res = { pcall(fn, ...) }
  if not res[1] then return "ERROR " .. str(res[2]) end
  return args(unpack(res, 2, table.maxn(res)))
end

local function state()
  local lockdown = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
  local inInstance, instanceType = IsInInstance()
  return ("combat=%s encounter=%s instance=%s/%s chatLockdown=%s"):format(
    str(InCombatLockdown()), str(IsEncounterInProgress and IsEncounterInProgress()),
    str(inInstance), str(instanceType), lockdown and try(lockdown) or "n/a")
end

-- Items ----------------------------------------------------------------------

-- Never trust loc:IsValid() blindly: for a bank item found by GUID it raised
-- "bad argument #1 to 'DoesItemExist'", so report the raw fields and the error.
local function isValid(loc)
  local ok, valid = pcall(loc.IsValid, loc)
  if ok then return valid end
  return false, valid
end

local function whereIs(loc)
  if not loc then return "nil" end
  local raw = ("raw{bag=%s slot=%s equip=%s}"):format(
    str(loc.bagID), str(loc.slotIndex), str(loc.equipmentSlotIndex))
  local valid, err = isValid(loc)
  if err then return raw .. " IsValid ERROR: " .. str(err) end
  if not valid then return raw .. " invalid" end
  if loc:IsBagAndSlot() then
    local bag, slot = loc:GetBagAndSlot()
    return ("bag %s slot %s"):format(str(bag), str(slot))
  end
  if loc:IsEquipmentSlot() then
    return "equipped, slot " .. str(loc:GetEquipmentSlot())
  end
  return raw .. " valid but neither bag nor equipment"
end

local function describe(loc, label)
  label = label or "item"
  if not loc or not isValid(loc) then
    write(label, "no valid item location: " .. whereIs(loc))
    return
  end
  if not C_Item.DoesItemExist(loc) then
    write(label, whereIs(loc) .. ": no item there")
    return
  end
  local link = C_Item.GetItemLink(loc)
  local id = C_Item.GetItemID(loc)
  local bindType = select(14, C_Item.GetItemInfo(link or id))
  write(label, ("%s at %s"):format(str(link), whereIs(loc)))
  write(label, ("  itemID=%s stack=%s IsBound=%s bindType=%s"):format(
    str(id), try(C_Item.GetStackCount, loc), try(C_Item.IsBound, loc), str(bindType)))
  write(label, "  GUID=" .. try(C_Item.GetItemGUID, loc))
  if loc:IsBagAndSlot() then
    local info = C_Container.GetContainerItemInfo(loc:GetBagAndSlot())
    if info then
      write(label, ("  containerInfo: isBound=%s quality=%s"):format(str(info.isBound), str(info.quality)))
    end
  end
end

local function cursorLocation()
  local loc = C_Cursor and C_Cursor.GetCursorItem and C_Cursor.GetCursorItem()
  return loc
end

-- Item link fields --------------------------------------------------------------

local function splitKeepEmpty(s, sep)
  local out, start = {}, 1
  while true do
    local i = s:find(sep, start, true)
    if not i then
      out[#out + 1] = s:sub(start)
      return out
    end
    out[#out + 1] = s:sub(start, i - 1)
    start = i + 1
  end
end

local function linkFields(link)
  if not link then
    write("link", "no link")
    return
  end
  write("link", "raw: " .. link:gsub("|", "||"))
  local itemString = link:match("|H(item:[^|]+)|h")
  if not itemString then
    write("link", "no item string found")
    return
  end
  local fields = splitKeepEmpty(itemString, ":")
  local parts = {}
  -- fields[1] is "item"; field N in the doc is fields[N + 1].
  for i = 2, #fields do parts[#parts + 1] = ("%d=%s"):format(i - 1, fields[i]) end
  write("link", table.concat(parts, " "))
  write("link", "(1 id, 2 enchant, 7 suffix, 8 unique, 13 numBonusIDs, then bonus IDs)")
end

-- Tracking ---------------------------------------------------------------------

local function bagIndices()
  local seen, out = {}, {}
  local function add(i) if i and not seen[i] then seen[i] = true; out[#out + 1] = i end end
  for i = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do add(i) end
  if Enum.BagIndex then
    for _, v in pairs(Enum.BagIndex) do if type(v) == "number" then add(v) end end
  end
  table.sort(out)
  return out
end

-- Fallback when the GUID lookup fails: find an item with the same item string.
local function scanFor(itemString)
  local hits = {}
  for _, bag in ipairs(bagIndices()) do
    local n = C_Container.GetContainerNumSlots(bag) or 0
    for slot = 1, n do
      local link = C_Container.GetContainerItemLink(bag, slot)
      if link and link:match("|H(item:[^|]+)|h") == itemString then
        hits[#hits + 1] = ("%d/%d"):format(bag, slot)
      end
    end
  end
  return #hits > 0 and table.concat(hits, ", ") or "none"
end

local function trackedStatus(t)
  local loc = C_Item.GetItemLocation and C_Item.GetItemLocation(t.guid)
  local inInv = C_Item.IsItemGUIDInInventory and C_Item.IsItemGUIDInInventory(t.guid)
  return ("GetItemLocation=%s IsItemGUIDInInventory=%s scan=%s"):format(
    whereIs(loc), str(inInv), scanFor(t.itemString))
end

local function reportTracked(label, onlyChanged)
  if not db or #db.tracked == 0 then
    if not onlyChanged then write(label, "nothing tracked") end
    return
  end
  for i, t in ipairs(db.tracked) do
    local status = trackedStatus(t)
    if not onlyChanged or status ~= t.last then
      write(label, ("#%d %s %s: %s"):format(i, t.link, t.guid, status))
      t.last = status
    end
  end
end

local function track(loc)
  if not loc or not isValid(loc) or not C_Item.DoesItemExist(loc) then
    write("track", "pick up an item first, then type /bagtest track")
    return
  end
  local link = C_Item.GetItemLink(loc)
  local t = {
    guid = C_Item.GetItemGUID(loc),
    link = link,
    itemString = link and link:match("|H(item:[^|]+)|h"),
  }
  db.tracked[#db.tracked + 1] = t
  write("track", ("tracking #%d %s %s"):format(#db.tracked, str(link), str(t.guid)))
  ClearCursor()
  reportTracked("track")
end

-- Bags loading after login (test 16) ---------------------------------------------

local function bagSnapshot(label)
  local n = C_Container.GetContainerNumSlots(0)
  local filled = 0
  for slot = 1, n or 0 do
    if C_Container.GetContainerItemID(0, slot) then filled = filled + 1 end
  end
  write(label, ("backpack slots=%s filled=%d"):format(str(n), filled))
  reportTracked(label)
end

-- Bank (test 12) -------------------------------------------------------------------

local function bank()
  write("bank", "bank frame open=" .. str(BankFrame and BankFrame:IsShown()))
  local names = {}
  if Enum.BagIndex then
    for k, v in pairs(Enum.BagIndex) do names[v] = k end
  end
  for _, bag in ipairs(bagIndices()) do
    local name = names[bag] or ""
    if bag < 0 or bag > 5 or name:find("Bank") then
      local n = C_Container.GetContainerNumSlots(bag)
      write("bank", ("bag %d %s: slots=%s first=%s"):format(
        bag, name, str(n), str(C_Container.GetContainerItemLink(bag, 1))))
    end
  end
  write("bank", "test 12 call: GetContainerItemLink(6, 1)=" .. try(C_Container.GetContainerItemLink, 6, 1))
end

-- Modified clicks (tests 4-6) --------------------------------------------------------

local hooked = false
local function hook()
  if hooked then
    write("hook", "already hooked this session (/reload to remove)")
    return
  end
  hooked = true
  hooksecurefunc("HandleModifiedItemClick", function(link, loc)
    write("hook", ("HandleModifiedItemClick %s loc=%s alt=%s button=%s"):format(
      str(link), loc and whereIs(loc) or "nil", str(IsAltKeyDown()), str(GetMouseButtonClicked and GetMouseButtonClicked())))
  end)
  write("hook", "hooked HandleModifiedItemClick until /reload")
end

local function mods()
  for _, action in ipairs({ "CHATLINK", "DRESSUP", "EXPANDITEM", "SOCKETITEM", "SPLITSTACK", "PICKUPACTION", "SELFCAST", "FOCUSCAST" }) do
    write("mods", ("%s = %s"):format(action, try(GetModifiedClick, action)))
  end
end

-- Drop frame (tests 1-3, 7) ------------------------------------------------------------

local drop = CreateFrame("Button", "BFFBagSpikeDrop", UIParent, "BackdropTemplate")
drop:SetSize(160, 80)
drop:SetPoint("CENTER", 0, 150)
drop:SetFrameStrata("DIALOG")
drop:SetBackdrop({
  bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
drop:SetBackdropColor(0.05, 0.2, 0.1, 0.9)
drop:SetMovable(true)
drop:SetClampedToScreen(true)
drop:RegisterForClicks("AnyUp")
drop:RegisterForDrag("LeftButton")
local text = drop:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
text:SetPoint("CENTER")
text:SetText("BFF bag spike\nDrop or click an item here\n(drag to move)")
drop:Hide()

local function received(how)
  local infoType, a, b = GetCursorInfo()
  write("drop", ("%s: GetCursorInfo=%s"):format(how, args(infoType, a, b)))
  write("drop", "  " .. state())
  local loc = cursorLocation()
  write("drop", "  C_Cursor.GetCursorItem: " .. whereIs(loc))
  if loc and isValid(loc) then describe(loc, "drop") end
  ClearCursor()
  write("drop", "  ClearCursor done; is the item back in its slot?")
end

drop:SetScript("OnReceiveDrag", function() received("OnReceiveDrag") end)
drop:SetScript("OnClick", function()
  if GetCursorInfo() then received("OnClick") end
end)
drop:SetScript("OnDragStart", function(self)
  if not GetCursorInfo() then self:StartMoving() end
end)
drop:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

-- Slash command ---------------------------------------------------------------------------

SLASH_BFFBAGSPIKE1 = "/bagtest"
SlashCmdList.BFFBAGSPIKE = function(msg)
  local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = cmd:lower()
  if cmd == "frame" then
    drop:SetShown(not drop:IsShown())
  elseif cmd == "item" then
    local bag, slot = rest:match("^(%-?%d+)%s+(%d+)$")
    if bag then
      describe(ItemLocation:CreateFromBagAndSlot(tonumber(bag), tonumber(slot)))
    else
      local loc = cursorLocation()
      if loc then
        describe(loc)
        ClearCursor()
      else
        write("item", "pick up an item first, or use /bagtest item <bag> <slot>")
      end
    end
  elseif cmd == "track" then
    track(cursorLocation())
  elseif cmd == "where" then
    reportTracked("where")
  elseif cmd == "untrack" then
    wipe(db.tracked)
    write("track", "forgot all tracked items")
  elseif cmd == "bank" then
    bank()
  elseif cmd == "hook" then
    hook()
  elseif cmd == "mods" then
    mods()
  elseif cmd == "link" then
    local loc = cursorLocation()
    linkFields(loc and C_Item.GetItemLink(loc))
    ClearCursor()
  elseif cmd == "clear" then
    wipe(db.log)
    write("log", "cleared")
  else
    print("|cff33ff99BagSpike|r /bagtest frame | item [bag slot] | track | where | untrack | bank | hook | mods | link | clear")
  end
end

-- Events ------------------------------------------------------------------------------------

local events = CreateFrame("Frame")
local firstBagUpdate = true
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("ADDON_ACTION_BLOCKED")
events:RegisterEvent("ADDON_ACTION_FORBIDDEN")
events:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    if ... ~= ADDON then return end
    BFFBagSpikeDB = BFFBagSpikeDB or {}
    db = BFFBagSpikeDB
    db.log = db.log or {}
    db.tracked = db.tracked or {}
    write("login", "---- session start, build " .. args(GetBuildInfo()))
    bagSnapshot("ADDON_LOADED")
  elseif event == "PLAYER_LOGIN" then
    bagSnapshot("PLAYER_LOGIN")
  elseif event == "PLAYER_ENTERING_WORLD" then
    local isLogin, isReload = ...
    write("login", ("PLAYER_ENTERING_WORLD login=%s reload=%s"):format(str(isLogin), str(isReload)))
    bagSnapshot("PLAYER_ENTERING_WORLD")
  elseif event == "BAG_UPDATE_DELAYED" then
    if firstBagUpdate then
      firstBagUpdate = false
      bagSnapshot("first BAG_UPDATE_DELAYED")
    else
      reportTracked("bags", true)
    end
  else
    write("blocked", event .. ": " .. args(...))
  end
end)
