-- HandMeDowns: the pure parts of Hand-me-downs. The trimmed item string a
-- Hand-me-down stores and the item string the game resolves it from, how
-- Hand-me-downs and Claims are stored in records (short field names, a
-- malformed item skipped), the caps and pruning, and who wins: the
-- earliest Claim by server time, ties broken by Member id (docs/adr/0003).
-- Giving works out each Hand-me-down's state from the Ledger. See
-- docs/design/hand-me-downs.md.

local _, ns = ...

local HandMeDowns = {}
ns.HandMeDowns = HandMeDowns

local DAY = 24 * 60 * 60
-- A Hand-me-down ends this long after posting; a Claim too.
HandMeDowns.KEEP_FOR = 30 * DAY
-- Open Hand-me-downs per owner, and open Claims per Member.
HandMeDowns.MAX_OPEN = 20
HandMeDowns.MAX_CLAIMS = 20

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
function HandMeDowns.itemString(link)
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
function HandMeDowns.validItem(item)
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
function HandMeDowns.itemLink(item)
  local fields = fieldsOf(item)
  local id, enchant, suffix, unique = fields[1], fields[2] or "", fields[3] or "", fields[4] or ""
  if suffix == "" and unique == "" then
    return enchant == "" and "item:" .. id or ("item:%s:%s"):format(id, enchant)
  end
  return (("item:%s:%s:::::%s:%s"):format(id, enchant, suffix, unique):gsub(":$", ""))
end

-- The item ID of a trimmed item string.
function HandMeDowns.itemId(item)
  return tonumber(item:match("^%d+"))
end

-- What the wire fields must be: a non-empty string, a number from 0.
local function isText(value) return type(value) == "string" and value ~= "" end
local function isCount(value) return type(value) == "number" and value >= 0 end

-- itemLink for a client that can't resolve items: never cached.
function HandMeDowns.NO_LINK() return nil end

-- The item's link for a text, from itemLink(itemString), or "an item"
-- until the game has it.
function HandMeDowns.linkText(itemLink, item)
  return itemLink(HandMeDowns.itemLink(item)) or "an item"
end

-- A new Hand-me-down as stored in the owner's record.
function HandMeDowns.item(id, item, level, time)
  return { i = id, s = item, l = level, t = time }
end

-- A new Claim as stored in the claimer's record.
function HandMeDowns.claim(owner, id, guid, time)
  return { m = owner, i = id, c = guid, t = time }
end

-- The well-formed Hand-me-downs in a record, in the order stored, as
-- { id, item, level, time, to, guid }: to and guid name who it was Given
-- to, both or neither. A malformed item, or a list that isn't one, is
-- skipped rather than refused.
function HandMeDowns.inRecord(record)
  local list = {}
  if type(record) ~= "table" or type(record.handMeDowns) ~= "table" then return list end
  for _, item in ipairs(record.handMeDowns) do
    if type(item) == "table" and isCount(item.i) and HandMeDowns.validItem(item.s)
        and isCount(item.l) and type(item.t) == "number"
        and (item.r == nil) == (item.c == nil)
        and (item.r == nil or (isText(item.r) and isText(item.c))) then
      list[#list + 1] = { id = item.i, item = item.s, level = item.l, time = item.t, to = item.r, guid = item.c }
    end
  end
  return list
end

-- The well-formed Claims in a record, as { owner, id, guid, time }: one
-- per Hand-me-down, the earliest if a record carries more.
function HandMeDowns.claimsIn(record)
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

-- Whether a Hand-me-down ({ time, to }) is still open: not Given, and
-- under 30 days old.
function HandMeDowns.isOpen(handMeDown, now)
  return handMeDown.to == nil and now - handMeDown.time <= HandMeDowns.KEEP_FOR
end

-- Whether a stored item is malformed or past its 30 days.
local function expired(item, now)
  return type(item) ~= "table" or type(item.t) ~= "number" or now - item.t > HandMeDowns.KEEP_FOR
end

-- Drops the owner's Hand-me-downs 30 days after posting, Given or not.
function HandMeDowns.prune(list, now)
  for i = #list, 1, -1 do
    if expired(list[i], now) then table.remove(list, i) end
  end
end

-- Drops the Claims older than 30 days, and those isOpen(owner, id) says
-- have ended.
function HandMeDowns.pruneClaims(list, now, isOpen)
  for i = #list, 1, -1 do
    local item = list[i]
    if expired(item, now) or not isOpen(item.m, item.i) then table.remove(list, i) end
  end
end

-- The Hand-me-downs Given in the after record that weren't in before (nil
-- on first sight counts as none), as in inRecord.
function HandMeDowns.newlyGiven(before, after)
  local had, list = {}, {}
  for _, handMeDown in ipairs(HandMeDowns.inRecord(before)) do
    if handMeDown.to then had[handMeDown.id] = true end
  end
  for _, handMeDown in ipairs(HandMeDowns.inRecord(after)) do
    if handMeDown.to and not had[handMeDown.id] then list[#list + 1] = handMeDown end
  end
  return list
end

-- The winning Claim among { memberId, time, ... }: the earliest, ties
-- broken by Member id, so every client holding the same Claims agrees.
-- Nil without any.
function HandMeDowns.winner(claims)
  local best
  for _, claim in ipairs(claims) do
    if not best or claim.time < best.time or (claim.time == best.time and claim.memberId < best.memberId) then
      best = claim
    end
  end
  return best
end
