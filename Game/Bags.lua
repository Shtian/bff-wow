local _, ns = ...

local Bags = {}
ns.Bags = Bags

local getItemInfo = C_Item.GetItemInfo or GetItemInfo
local FIRST_BAG = BACKPACK_CONTAINER or 0
local LAST_BAG = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4

local function find(link)
  local wanted = ns.Spares.itemString(link)
  for bag = FIRST_BAG, LAST_BAG do
    for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
      local itemLink = C_Container.GetContainerItemLink(bag, slot)
      if itemLink and ns.Spares.itemString(itemLink) == wanted then
        return ItemLocation:CreateFromBagAndSlot(bag, slot)
      end
    end
  end
  return nil
end

local function post(core, location)
  if not (location and C_Item.DoesItemExist(location)) then return nil, "notInBags" end
  local link = C_Item.GetItemLink(location)
  if not link then return nil, "invalidItem" end
  local id, reason = core:postSpare(link, ns.Snapshot.requiredLevel(link), {
    guid = C_Item.GetItemGUID(location),
    isBound = C_Item.IsBound(location),
    bindType = (select(14, getItemInfo(link))),
  })
  if not id then return nil, reason end
  return id, link
end

function Bags.postLink(core, link)
  if not ns.Spares.itemString(link) then return nil, "invalidItem" end
  return post(core, find(link))
end

function Bags.postFromCursor(core)
  local kind = GetCursorInfo()
  local location = kind == "item" and C_Cursor.GetCursorItem() or nil
  ClearCursor()
  if kind ~= "item" then return nil, "invalidItem" end
  return post(core, location)
end

-- WoW: IsItemGUIDInInventory covers the bank even while it's closed. For a gone or
-- banked item GetItemLocation gives an empty ItemLocation, and IsValid() on it errors.
function Bags.findItem(itemGuid)
  if not C_Item.IsItemGUIDInInventory then return nil, false end
  if not C_Item.IsItemGUIDInInventory(itemGuid) then return false, false end
  local location = C_Item.GetItemLocation(itemGuid)
  return true, location ~= nil and location:IsEquipmentSlot() == true
end
