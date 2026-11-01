-- Spares: the pure parts of Spares. The trimmed item string a
-- Spare stores and the item string the game resolves it from,
-- whether an item in the bags can be traded, how
-- Spares and Claims are stored in records (short field names, a
-- malformed item skipped), the caps and pruning, and who wins: the
-- earliest Claim by server time, ties broken by Member id (docs/adr/0003).
-- Giving works out each Spare's state from the Ledger. See
-- docs/design/spares.md.

local _, ns = ...

local Spares = {}
ns.Spares = Spares

local DAY = 24 * 60 * 60
-- A Spare ends this long after posting; a Claim too.
Spares.KEEP_FOR = 30 * DAY
-- Open Spares per owner, and open Claims per Member.
Spares.MAX_OPEN = 20
Spares.MAX_CLAIMS = 20

-- An item link's fields after "item:": 1 item ID, 2 enchant, 3–6 gems,
-- 7 suffix, 8 unique ID.
local ITEM_ID, ENCHANT, SUFFIX, UNIQUE = 1, 2, 7, 8

-- A colon-separated string's fields, empty ones kept.
local function fieldsOf(text)
  local fields = {}
  for field in (text .. ":"):gmatch("([^:]*):") do fields[#fields + 1] = field end
  return fields
end

-- Whether a link field holds a number other than 0.
local function isSet(field)
  return field ~= nil and field ~= "" and tonumber(field) ~= nil and tonumber(field) ~= 0
end

-- The trimmed item string from an item link, or from an item string
-- ("item:..."): "itemID[:enchant[:suffix[:factor]]]", unset fields left
-- out from the end. The unique ID is only kept for a negative suffix,
-- where it carries the suffix factor the item's stats scale by. Nil when
-- it isn't an item.
function Spares.itemString(link)
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

-- Whether a trimmed item string from the wire looks right.
function Spares.validItem(item)
  if type(item) ~= "string" or #item > 48 or not item:match("^%d+[%-%d:]*$") then return false end
  local fields = fieldsOf(item)
  if #fields > 4 then return false end
  for i = 2, #fields do
    if fields[i] ~= "" and not fields[i]:match("^%-?%d+$") then return false end
  end
  return true
end

-- The item string the game resolves a trimmed one from, with every field
-- where an item link has it: "item:15210::::::-19:1238425".
function Spares.fullItemString(item)
  local fields = fieldsOf(item)
  local id, enchant, suffix, unique = fields[1], fields[2] or "", fields[3] or "", fields[4] or ""
  if suffix == "" and unique == "" then
    return enchant == "" and "item:" .. id or ("item:%s:%s"):format(id, enchant)
  end
  return (("item:%s:%s:::::%s:%s"):format(id, enchant, suffix, unique):gsub(":$", ""))
end

-- Enum.ItemBind values an item can't be passed on with, whatever it reads
-- now: Quest, and the account bindings (ToWoWAccount, ToBnetAccount,
-- ToBnetAccountUntilEquipped).
local REFUSED_BINDINGS = { [4] = "questItem", [7] = "accountBound", [8] = "accountBound", [9] = "accountBound" }

-- Whether an item in the bags can be offered to the Crew, from
-- C_Item.IsBound (its state now) and its bindType (14th return of
-- C_Item.GetItemInfo). Returns true, or nil and "bound", "questItem" or
-- "accountBound". isBound decides first: an heirloom reads bindType 1.
-- Conjured items aren't caught; the mail window refuses them anyway.
function Spares.tradeable(isBound, bindType)
  if isBound then return nil, "bound" end
  local reason = REFUSED_BINDINGS[bindType]
  if reason then return nil, reason end
  return true
end

-- What the wire fields must be: a non-empty string, a number from 0.
local function isText(value) return type(value) == "string" and value ~= "" end
local function isCount(value) return type(value) == "number" and value >= 0 end

-- itemLink for a client that can't resolve items: never cached.
function Spares.NO_LINK() return nil end

-- The item's link for a text, from itemLink(itemString), or "an item"
-- until the game has it.
function Spares.linkText(itemLink, item)
  return itemLink(Spares.fullItemString(item)) or "an item"
end

-- A new Spare as stored in the owner's record.
function Spares.item(id, item, level, time)
  return { i = id, s = item, l = level, t = time }
end

-- A new Claim as stored in the claimer's record.
function Spares.claim(owner, id, guid, time)
  return { m = owner, i = id, c = guid, t = time }
end

-- The well-formed Spares in a record, in the order stored, as
-- { id, item, level, time, to, guid }: to and guid name who it was Given
-- to, both or neither. A malformed item, or a list that isn't one, is
-- skipped rather than refused.
function Spares.inRecord(record)
  local list = {}
  if type(record) ~= "table" or type(record.spares) ~= "table" then return list end
  for _, item in ipairs(record.spares) do
    if type(item) == "table" and isCount(item.i) and Spares.validItem(item.s)
        and isCount(item.l) and type(item.t) == "number"
        and (item.r == nil) == (item.c == nil)
        and (item.r == nil or (isText(item.r) and isText(item.c))) then
      list[#list + 1] = { id = item.i, item = item.s, level = item.l, time = item.t, to = item.r, guid = item.c }
    end
  end
  return list
end

-- The well-formed Claims in a record, as { owner, id, guid, time }: one
-- per Spare, the earliest if a record carries more.
function Spares.claimsIn(record)
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

-- Whether a Spare ({ time, to }) is still open: not Given, and
-- under 30 days old.
function Spares.isOpen(spare, now)
  return spare.to == nil and now - spare.time <= Spares.KEEP_FOR
end

-- Whether a stored item is malformed or past its 30 days.
local function expired(item, now)
  return type(item) ~= "table" or type(item.t) ~= "number" or now - item.t > Spares.KEEP_FOR
end

-- Drops the owner's Spares 30 days after posting, Given or not.
function Spares.prune(list, now)
  for i = #list, 1, -1 do
    if expired(list[i], now) then table.remove(list, i) end
  end
end

-- Drops the Claims older than 30 days, and those isOpen(owner, id) says
-- have ended.
function Spares.pruneClaims(list, now, isOpen)
  for i = #list, 1, -1 do
    local item = list[i]
    if expired(item, now) or not isOpen(item.m, item.i) then table.remove(list, i) end
  end
end

-- The Spares Given in the after record that weren't in before (nil
-- on first sight counts as none), as in inRecord.
function Spares.newlyGiven(before, after)
  local had, list = {}, {}
  for _, spare in ipairs(Spares.inRecord(before)) do
    if spare.to then had[spare.id] = true end
  end
  for _, spare in ipairs(Spares.inRecord(after)) do
    if spare.to and not had[spare.id] then list[#list + 1] = spare end
  end
  return list
end

-- The winning Claim among { memberId, time, ... }: the earliest, ties
-- broken by Member id, so every client holding the same Claims agrees.
-- Nil without any.
function Spares.winner(claims)
  local best
  for _, claim in ipairs(claims) do
    if not best or claim.time < best.time or (claim.time == best.time and claim.memberId < best.memberId) then
      best = claim
    end
  end
  return best
end

-- What to do about an own Spare from where its item is (docs/adr/0004):
-- "keep", "note" (it has left your bags this session; a sold item can still
-- be bought back), "withdraw" or "ask" (whether to Give it to the winning
-- Claim or withdraw it). Gone means not in the bags or bank, or equipped.
-- Only the next login decides, as buyback is empty by then. inInventory
-- nil means the game couldn't say, which keeps it.
function Spares.itemCheck(isOpen, hasClaim, inInventory, isEquipped, isNextLogin)
  if not isOpen or inInventory == nil then return "keep" end
  if inInventory and not isEquipped then return "keep" end
  if not isNextLogin then return "note" end
  return hasClaim and "ask" or "withdraw"
end
