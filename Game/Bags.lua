-- Bags: reads items in the bags for Spares. Posts the item on the
-- cursor (dropped on the Spares tab) or the first bag item matching
-- a link (/bff spares add), with its item GUID and binding, which Core
-- checks it can be traded by. Also finds where a posted item is now. See
-- docs/design/spares.md and docs/research/bag-items.md.

local _, ns = ...

local Bags = {}
ns.Bags = Bags

local getItemInfo = C_Item.GetItemInfo or GetItemInfo
-- The backpack and the equipped bags, the reagent bag included.
local FIRST_BAG = BACKPACK_CONTAINER or 0
local LAST_BAG = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4

-- Where the first item in the bags with the same trimmed item string as
-- link is, or nil.
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

-- Posts the item at a location (an ItemLocation) as a Spare.
-- Returns the Spare's id and the item's link, or nil and a reason
-- (see BFF.lua's MESSAGES).
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

-- Posts the first item in the bags matching an item link, as post does.
-- Refuses a link that isn't an item, or one not in the bags.
function Bags.postLink(core, link)
  if not ns.Spares.itemString(link) then return nil, "invalidItem" end
  return post(core, find(link))
end

-- Posts the item on the cursor, then puts it back in its slot whether it
-- was taken or not. Returns as post, or nil and "invalidItem" when the
-- cursor holds something else (a spell, money), or nothing.
function Bags.postFromCursor(core)
  local kind = GetCursorInfo()
  local location = kind == "item" and C_Cursor.GetCursorItem() or nil
  ClearCursor()
  if kind ~= "item" then return nil, "invalidItem" end
  return post(core, location)
end

-- Where an item is by its GUID, for Core:bagsUpdated: whether it's in the
-- bags or bank (nil if the game can't say), and whether it's equipped.
-- IsItemGUIDInInventory covers the bank even while it's closed. Read the
-- location only once that's true, and never call IsValid() on it: for a
-- gone or banked item it's an empty ItemLocation, and IsValid() errors.
function Bags.findItem(itemGuid)
  if not C_Item.IsItemGUIDInInventory then return nil, false end
  if not C_Item.IsItemGUIDInInventory(itemGuid) then return false, false end
  local location = C_Item.GetItemLocation(itemGuid)
  return true, location ~= nil and location:IsEquipmentSlot() == true
end
