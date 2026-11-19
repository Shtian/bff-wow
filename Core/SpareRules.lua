local _, ns = ...

local Rules = {}
ns.SpareRules = Rules

local DAY = 24 * 60 * 60
Rules.KEEP_FOR = 30 * DAY
Rules.MAX_OPEN = 20
Rules.MAX_CLAIMS = 20

-- WoW: an item link's fields after "item:": 1 item ID, 2 enchant, 3–6 gems,
-- 7 suffix, 8 unique ID.
local ITEM_ID, ENCHANT, SUFFIX, UNIQUE = 1, 2, 7, 8

local function fieldsOf(text)
  local fields = {}
  for field in (text .. ":"):gmatch("([^:]*):") do fields[#fields + 1] = field end
  return fields
end

local function isSet(field)
  return field ~= nil and field ~= "" and tonumber(field) ~= nil and tonumber(field) ~= 0
end

-- WoW: for a negative suffix the unique ID carries the suffix factor the
-- item's stats scale by.
function Rules.itemString(link)
  if type(link) ~= "string" then return nil end
  local body = link:match("item:([%-%d:]+)")
  if not body then return nil end
  local fields = fieldsOf(body)
  if not isSet(fields[ITEM_ID]) or tonumber(fields[ITEM_ID]) < 0 then return nil end
  local suffix = isSet(fields[SUFFIX]) and fields[SUFFIX] or ""
  local unique = suffix:sub(1, 1) == "-" and isSet(fields[UNIQUE]) and fields[UNIQUE] or ""
  local parts = {
    tostring(tonumber(fields[ITEM_ID])),
    isSet(fields[ENCHANT]) and fields[ENCHANT] or "",
    suffix,
    unique,
  }
  while parts[#parts] == "" do parts[#parts] = nil end
  return table.concat(parts, ":")
end

function Rules.validItem(item)
  if type(item) ~= "string" or #item > 48 or not item:match("^%d+[%-%d:]*$") then return false end
  local fields = fieldsOf(item)
  if #fields > 4 then return false end
  for i = 2, #fields do
    if fields[i] ~= "" and not fields[i]:match("^%-?%d+$") then return false end
  end
  return true
end

function Rules.fullItemString(item)
  local fields = fieldsOf(item)
  local id, enchant, suffix, unique = fields[1], fields[2] or "", fields[3] or "", fields[4] or ""
  if suffix == "" and unique == "" then
    return enchant == "" and "item:" .. id or ("item:%s:%s"):format(id, enchant)
  end
  return (("item:%s:%s:::::%s:%s"):format(id, enchant, suffix, unique):gsub(":$", ""))
end

-- WoW: Enum.ItemBind 4 is Quest; 7, 8 and 9 are the account bindings.
local REFUSED_BINDINGS = { [4] = "questItem", [7] = "accountBound", [8] = "accountBound", [9] = "accountBound" }

-- WoW: bindType is C_Item.GetItemInfo's 14th return, and an heirloom reads 1.
-- The mail window refuses conjured items.
function Rules.tradeable(isBound, bindType)
  if isBound then return nil, "bound" end
  local reason = REFUSED_BINDINGS[bindType]
  if reason then return nil, reason end
  return true
end

local function isText(value) return type(value) == "string" and value ~= "" end
local function isCount(value) return type(value) == "number" and value >= 0 end

function Rules.NO_LINK() return nil end

function Rules.linkText(itemLink, item)
  return itemLink(Rules.fullItemString(item)) or "an item"
end

function Rules.item(id, item, level, time)
  return { i = id, s = item, l = level, t = time }
end

function Rules.nextId(list, counter)
  local id = counter or 1
  for _, held in ipairs(list or {}) do
    if type(held) == "table" and type(held.i) == "number" and held.i >= id then id = held.i + 1 end
  end
  return id
end

function Rules.claim(owner, id, guid, time)
  return { m = owner, i = id, c = guid, t = time }
end

function Rules.inRecord(record)
  local list = {}
  if type(record) ~= "table" or type(record.spares) ~= "table" then return list end
  for _, item in ipairs(record.spares) do
    if type(item) == "table" and isCount(item.i) and Rules.validItem(item.s)
        and isCount(item.l) and type(item.t) == "number"
        and (item.r == nil) == (item.c == nil)
        and (item.r == nil or (isText(item.r) and isText(item.c))) then
      list[#list + 1] = { id = item.i, item = item.s, level = item.l, time = item.t, to = item.r, guid = item.c }
    end
  end
  return list
end

function Rules.claimsIn(record)
  local list, at = {}, {}
  if type(record) ~= "table" or type(record.claims) ~= "table" then return list end
  for _, item in ipairs(record.claims) do
    if type(item) == "table" and isText(item.m) and isCount(item.i) and isText(item.c)
        and type(item.t) == "number" then
      local key = item.m .. "|" .. item.i
      local claim = { owner = item.m, id = item.i, guid = item.c, time = item.t }
      local index = at[key]
      if not index then
        list[#list + 1] = claim
        at[key] = #list
      elseif claim.time < list[index].time then
        list[index] = claim
      end
    end
  end
  return list
end

function Rules.isOpen(spare, now)
  return spare.to == nil and now - spare.time <= Rules.KEEP_FOR
end

local function expired(item, now)
  return type(item) ~= "table" or type(item.t) ~= "number" or now - item.t > Rules.KEEP_FOR
end

function Rules.prune(list, now)
  for i = #list, 1, -1 do
    if expired(list[i], now) then table.remove(list, i) end
  end
end

function Rules.pruneClaims(list, now, isOpen)
  for i = #list, 1, -1 do
    local item = list[i]
    if expired(item, now) or not isOpen(item.m, item.i) then table.remove(list, i) end
  end
end

function Rules.newlyGiven(before, after)
  local had, list = {}, {}
  for _, spare in ipairs(Rules.inRecord(before)) do
    if spare.to then had[spare.id] = true end
  end
  for _, spare in ipairs(Rules.inRecord(after)) do
    if spare.to and not had[spare.id] then list[#list + 1] = spare end
  end
  return list
end

function Rules.winner(claims)
  local best
  for _, claim in ipairs(claims) do
    if not best or claim.time < best.time or (claim.time == best.time and claim.memberId < best.memberId) then
      best = claim
    end
  end
  return best
end

-- WoW: a sold item can be bought back until logout; buyback is empty at
-- the next login.
function Rules.itemCheck(isOpen, hasClaim, inInventory, isEquipped, isNextLogin)
  if not isOpen or inInventory == nil then return "keep" end
  if inInventory and not isEquipped then return "keep" end
  if not isNextLogin then return "note" end
  return hasClaim and "ask" or "withdraw"
end
