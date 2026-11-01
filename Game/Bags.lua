-- Bags: reads items in the bags for Hand-me-downs. Offers the item on the
-- cursor (dropped on the Hand-me-downs tab) or the first bag item matching
-- a link (/bff hmd add), after checking it can be traded, and passes its
-- item GUID to Core. See docs/design/hand-me-downs.md and
-- docs/research/bag-items.md.

local _, ns = ...

local Bags = {}
ns.Bags = Bags

local getItemInfo = C_Item.GetItemInfo or GetItemInfo
-- The backpack and the equipped bags, the reagent bag included.
local FIRST_BAG = BACKPACK_CONTAINER or 0
local LAST_BAG = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4

-- Where the first item in the bags with the same trimmed item string as
-- link is, or nil.
function Bags.find(link)
  local wanted = ns.HandMeDowns.itemString(link)
  if not wanted then return nil end
  for bag = FIRST_BAG, LAST_BAG do
    for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
      local itemLink = C_Container.GetContainerItemLink(bag, slot)
      if itemLink and ns.HandMeDowns.itemString(itemLink) == wanted then
        return ItemLocation:CreateFromBagAndSlot(bag, slot)
      end
    end
  end
  return nil
end

-- Offers the item at a location (an ItemLocation) to the Crew, unless it
-- can't be traded. Returns the Hand-me-down's id and the item's link, or
-- nil and a reason (see BFF.lua's MESSAGES).
function Bags.offer(core, location)
  if not (location and C_Item.DoesItemExist(location)) then return nil, "notInBags" end
  local link = C_Item.GetItemLink(location)
  if not link then return nil, "invalidItem" end
  local ok, reason = ns.HandMeDowns.tradeable(C_Item.IsBound(location), (select(14, getItemInfo(link))))
  if not ok then return nil, reason end
  local id
  id, reason = core:postHandMeDown(link, ns.Snapshot.requiredLevel(link), C_Item.GetItemGUID(location))
  if not id then return nil, reason end
  return id, link
end

-- Offers the item on the cursor, then puts it back in its slot whether it
-- was taken or not. Returns as offer, or nil and "invalidItem" when the
-- cursor holds something else (a spell, money), or nothing.
function Bags.offerFromCursor(core)
  local kind = GetCursorInfo()
  local location = kind == "item" and C_Cursor.GetCursorItem() or nil
  ClearCursor()
  if kind ~= "item" then return nil, "invalidItem" end
  return Bags.offer(core, location)
end
