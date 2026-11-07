-- Catches: the pure parts of the Crew's fishing catches. The list of types
-- (data: a new type or zone is one row), reading a catch from the loot
-- window (handed the API, so offline tests can fake it), how catches are
-- kept in a Member's own record, and the Crew's catches over every record:
-- per type, the earliest catch and the Crew's count. Stateless, tested
-- through Core. See docs/design/catches.md and
-- docs/research/fishing-catches.md.

local _, ns = ...

local Catches = {}
ns.Catches = Catches

-- Waters by zone level, lowest first. Zones are as an English client names
-- them, for showing which zones a band covers.
Catches.WATERS = {
  { id = "1-10", name = "Level 1–10", zones = { "Elwynn Forest", "Dun Morogh", "Teldrassil", "Durotar", "Mulgore",
    "Tirisfal Glades", "the capitals" } },
  { id = "10-25", name = "Level 10–25", zones = { "Westfall", "Loch Modan", "Darkshore", "Silverpine Forest",
    "The Barrens", "Redridge Mountains" } },
  { id = "20-35", name = "Level 20–35", zones = { "Ashenvale", "Duskwood", "Hillsbrad Foothills", "Wetlands",
    "Stonetalon Mountains", "Thousand Needles" } },
  { id = "30-45", name = "Level 30–45", zones = { "Stranglethorn Vale", "Arathi Highlands", "Alterac Mountains",
    "Desolace", "Dustwallow Marsh", "Swamp of Sorrows" } },
  { id = "40-55", name = "Level 40–55", zones = { "Tanaris", "Feralas", "The Hinterlands", "Azshara", "Felwood",
    "Un'Goro Crater" } },
  { id = "50-60", name = "Level 50–60", zones = { "Western Plaguelands", "Eastern Plaguelands", "Winterspring",
    "Burning Steppes", "Silithus", "Moonglade", "Deadwind Pass" } },
  { id = "new", name = "New on Forever", zones = { "Riverglades", "Gilneas", "Shen'dralas", "Mount Hyjal",
    "Shark-Infested Waters" } },
}

-- Water ids, lowest first, for the list below.
local W1, W2, W3, W4, W5, W6, NEW = "1-10", "10-25", "20-35", "30-45", "40-55", "50-60", "new"

-- The types, in the list's order. id is the item ID, or a family's key
-- for fish sold by weight (any of its items counts as it). name is the
-- English name, for when the game hasn't the item cached; the game's name
-- and icon come from the item ID. kind: "fish", "quest" (Nat Pagle's),
-- "bloated", "family", "contest" or "treasure". waters: lowest first.
-- extra: shown but never counted, and why: "season", "contest" or
-- "unconfirmed" (not confirmed on Forever yet).
local function fish(id, name, waters, extra)
  return { id = id, name = name, kind = "fish", waters = waters, extra = extra }
end
local function quest(id, name, waters)
  return { id = id, name = name, kind = "quest", waters = waters }
end
local function bloated(id, name, waters)
  return { id = id, name = name, kind = "bloated", waters = waters }
end
local function family(id, name, items, waters)
  return { id = id, name = name, kind = "family", items = items, waters = waters }
end
local function contest(id, name)
  return { id = id, name = name, kind = "contest", waters = { W4 }, extra = "contest" }
end
local function treasure(id, name, waters)
  return { id = id, name = name, kind = "treasure", waters = waters, extra = "unconfirmed" }
end

Catches.TYPES = {
  -- Fish (25 counted).
  fish(6291, "Raw Brilliant Smallfish", { W1, W2, W3 }),
  fish(6303, "Raw Slitherskin Mackerel", { W1, W2 }),
  fish(6289, "Raw Longjaw Mud Snapper", { W1, W2, W3 }),
  fish(6299, "Sickly Looking Fish", { W1 }),
  fish(6317, "Raw Loch Frenzy", { W2 }),
  fish(6361, "Raw Rainbow Fin Albacore", { W2, W3 }),
  fish(6308, "Raw Bristle Whisker Catfish", { W2, W3, W4 }),
  fish(21071, "Raw Sagefish", { W2, W3 }),
  fish(6522, "Deviate Fish", { W2 }),
  fish(12238, "Darkshore Grouper", { W2 }),
  fish(6358, "Oily Blackmouth", { W3, W4, W5 }),
  fish(6359, "Firefin Snapper", { W3, W4, W5 }),
  fish(8365, "Raw Mithril Head Trout", { W4, W5, W6 }),
  fish(6362, "Raw Rockscale Cod", { W4, W5 }),
  fish(21153, "Raw Greater Sagefish", { W4 }),
  fish(4603, "Raw Spotted Yellowtail", { W4, W5 }),
  fish(13754, "Raw Glossy Mightfish", { W4, W5 }),
  fish(13422, "Stonescale Eel", { W4, W5, W6 }),
  fish(13758, "Raw Redgill", { W5, W6 }),
  fish(13759, "Raw Nightfin Snapper", { W5, W6 }),
  fish(13760, "Raw Sunscale Salmon", { W5, W6 }),
  fish(13893, "Large Raw Mightfish", { W5, W6 }),
  fish(13888, "Darkclaw Lobster", { W5, W6 }),
  fish(13757, "Lightning Eel", { W6 }),
  fish(13889, "Raw Whitescale Salmon", { W6 }),
  -- Nat Pagle's quest fish (4).
  quest(16970, "Misty Reed Mahi Mahi", { W4 }),
  quest(16968, "Sar'theris Striker", { W4 }),
  quest(16969, "Savage Coast Blue Sailfin", { W4 }),
  quest(16967, "Feralas Ahi", { W5 }),
  -- Bloated fish (10).
  bloated(6643, "Bloated Brilliant Smallfish", { W1, W2 }),
  bloated(6645, "Bloated Mud Snapper", { W1, W2 }),
  bloated(6647, "Bloated Bristle Whisker Catfish", { W2, W3 }),
  bloated(21162, "Bloated Oily Blackmouth", { W3, W4 }),
  bloated(21163, "Bloated Firefin Snapper", { W3, W4 }),
  bloated(8366, "Bloated Mithril Head Trout", { W4 }),
  bloated(21164, "Bloated Rockscale Cod", { W4, W5 }),
  bloated(21243, "Bloated Glossy Mightfish", { W5 }),
  bloated(13881, "Bloated Redgill", { W5, W6 }),
  bloated(13891, "Bloated Whitescale Salmon", { W6 }),
  -- Fish sold by weight (7 families).
  family("mudSnapper", "Mud Snapper (by weight)", { 6292, 6294, 6295 }, { W1, W2 }),
  family("catfish", "Catfish (by weight)", { 6309, 6310, 6311, 6363, 6364 }, { W2, W3 }),
  family("yellowtail", "Yellowtail (by weight)", { 13876, 13877, 13878, 13879, 13880 }, { W4, W5 }),
  family("redgill", "Redgill (by weight)", { 13882, 13883, 13884, 13885, 13886, 13887 }, { W5, W6 }),
  family("mightfish", "Mightfish (by weight)", { 13914, 13915, 13916, 13917 }, { W5, W6 }),
  family("lobster", "Lobster (by weight)", { 13907, 13908, 13909, 13910, 13911, 13912, 13913 }, { W5, W6 }),
  family("salmon", "Salmon (by weight)", { 13901, 13902, 13903, 13904, 13905, 13906 }, { W6 }),
  -- Extras: seasonal, the Sunday fishing contest, and not confirmed on
  -- Forever yet.
  fish(13756, "Raw Summer Bass", { W4, W5, W6 }, "season"),
  fish(13755, "Raw Winter Squid", { W4, W5 }, "season"),
  contest(19807, "Speckled Tastyfish"),
  contest(19805, "Keefer's Angelfish"),
  contest(19806, "Dezian Queenfish"),
  contest(19803, "Brownell's Blue Striped Racer"),
  fish(251524, "Whimsyfin", { W2 }, "unconfirmed"),
  fish(13890, "Raw Plated Armorfish", { NEW }, "unconfirmed"),
  treasure(6356, "Battered Chest", { W2, W3 }),
  treasure(6351, "Dented Crate", { W2, W3 }),
  treasure(6352, "Waterlogged Crate", { W2, W3 }),
  treasure(6354, "Small Locked Chest", { W2, W3 }),
  treasure(6357, "Sealed Crate", { W3, W4 }),
  treasure(6355, "Sturdy Locked Chest", { W3, W4 }),
  treasure(13874, "Heavy Crate", { W4, W5 }),
  treasure(13875, "Ironbound Locked Chest", { W4, W5 }),
  treasure(21150, "Iron Bound Trunk", { W4, W5 }),
  treasure(21113, "Watertight Trunk", { W4, W5 }),
  treasure(7973, "Big-mouth Clam", { W4, W5 }),
  treasure(6307, "Message in a Bottle", { W4, W5 }),
  treasure(13918, "Reinforced Locked Chest", { W5, W6 }),
  treasure(21228, "Mithril Bound Trunk", { W5, W6 }),
  treasure(20708, "Tightly Sealed Trunk", { W5, W6 }),
}

-- Each type by id, each item ID to its type's id, and how many types count.
local BY_ID, TYPE_OF = {}, {}
Catches.TOTAL = 0
for _, t in ipairs(Catches.TYPES) do
  t.items = t.items or { t.id }
  -- The item whose name and icon the game shows for the type.
  t.itemId = t.items[1]
  BY_ID[t.id] = t
  for _, item in ipairs(t.items) do TYPE_OF[item] = t.id end
  if not t.extra then Catches.TOTAL = Catches.TOTAL + 1 end
end

-- How many unlisted catches a record keeps: past it, a new one is dropped.
Catches.UNLISTED_CAP = 50
-- A catches field with more entries than this is ignored as a whole.
local MAX_ENTRIES = 400

-- The id of the type an item ID counts as, or nil when it isn't listed.
function Catches.typeOf(itemId)
  return TYPE_OF[itemId]
end

local function isItemId(value)
  return type(value) == "number" and value > 0 and value == math.floor(value)
end

local function text(value)
  if type(value) == "string" and value ~= "" then return value end
  return nil
end

local function readAll(api)
  local isSecret = api.isSecret or function() return false end
  local fishing = api.isFishingLoot()
  if isSecret(fishing) or fishing ~= true then return nil end
  local count = api.getNumLootItems()
  if isSecret(count) or type(count) ~= "number" then return nil end
  local items = {}
  for slot = 1, count do
    local link = api.getLootSlotLink(slot)
    local _, _, quantity, currencyId, _, _, _, _, _, isCoin = api.getLootSlotInfo(slot)
    -- A plain loop: ipairs would stop at a nil link before the rest.
    local values = { link, quantity, currencyId, isCoin }
    for i = 1, 4 do
      if isSecret(values[i]) then return nil end
    end
    local itemId = type(link) == "string" and tonumber(link:match("|Hitem:(%d+)"))
    if itemId and not isCoin and currencyId == nil then
      if not isItemId(quantity) then quantity = 1 end
      items[#items + 1] = { itemId = itemId, quantity = quantity }
    end
  end
  if #items == 0 then return nil end
  local zone, subzone, mapId = api.zone(), api.subzone(), api.mapId()
  if isSecret(zone) then zone = nil end
  if isSecret(subzone) then subzone = nil end
  if isSecret(mapId) then mapId = nil end
  return { items = items, zone = text(zone), subzone = text(subzone), mapId = isItemId(mapId) and mapId or nil }
end

-- What the loot window holds when it's fishing loot, through api:
-- isFishingLoot (IsFishingLoot), getNumLootItems, getLootSlotLink and
-- getLootSlotInfo (the globals of those names), zone (GetRealZoneText),
-- subzone (GetSubZoneText), mapId (C_Map.GetBestMapForUnit("player")) and
-- isSecret (issecretvalue, optional). A catch: { items, a { itemId,
-- quantity } per item slot (not coin or currency), zone, subzone, mapId
-- (each nil when unknown) }. Nil when the loot isn't from fishing, holds
-- no item, a value reads secret, or the read errors.
function Catches.read(api)
  local ok, catch = pcall(readAll, api)
  if ok then return catch end
  return nil
end

-- The key a fished item is kept under: its type's id, or its own item ID
-- when unlisted.
local function keyOf(itemId)
  return TYPE_OF[itemId] or itemId
end

local function unlistedCount(catches)
  local n = 0
  for key in pairs(catches) do
    if not BY_ID[key] and not (type(key) == "number" and TYPE_OF[key]) then n = n + 1 end
  end
  return n
end

-- Adds a catch (as read() gives it) to the own record, caught at time by
-- the Character with GUID character. Its catches are { [key] = { t, n, z,
-- s, m, c } }: key the type's id, or the item ID of an unlisted catch; t
-- the first catch's time, z, s and m its zone, subzone and map ID, c the
-- Character's GUID, and n how many caught. Unlisted catches past
-- UNLISTED_CAP are dropped. Returns true if the record changed.
function Catches.add(record, catch, time, character)
  if type(catch) ~= "table" or type(catch.items) ~= "table" then return false end
  local changed = false
  for _, item in ipairs(catch.items) do
    if type(item) == "table" and isItemId(item.itemId) then
      local quantity = isItemId(item.quantity) and item.quantity or 1
      local key = keyOf(item.itemId)
      record.catches = record.catches or {}
      local entry = record.catches[key]
      if entry then
        entry.n = entry.n + quantity
        changed = true
      elseif BY_ID[key] or unlistedCount(record.catches) < Catches.UNLISTED_CAP then
        record.catches[key] = {
          t = time, n = quantity, z = text(catch.zone), s = text(catch.subzone),
          m = isItemId(catch.mapId) and catch.mapId or nil, c = text(character),
        }
        changed = true
      end
    end
  end
  return changed
end

local function optional(check)
  return function(value) return value == nil or check(value) end
end
local isText = optional(function(value) return type(value) == "string" end)
local isMap = optional(isItemId)

local function validEntry(entry)
  return type(entry) == "table" and type(entry.t) == "number" and isItemId(entry.n)
    and isText(entry.z) and isText(entry.s) and isMap(entry.m) and isText(entry.c)
end

-- A record's catches, skipping anything malformed (a record from the wire
-- isn't shape-checked for them): for key, entry in valid(record), with
-- key a listed type's id or the item ID of an unlisted catch. A
-- family's item kept under its own ID (by an older list) counts as the
-- family; a key this list doesn't know as a family is skipped.
local function valid(record)
  local list = {}
  local catches = record.catches
  if type(catches) ~= "table" then return pairs(list) end
  local n = 0
  for _ in pairs(catches) do n = n + 1 end
  if n > MAX_ENTRIES then return pairs(list) end
  for key, entry in pairs(catches) do
    local id = (type(key) == "string" and BY_ID[key] and key) or (isItemId(key) and keyOf(key)) or nil
    if id and validEntry(entry) then
      local had = list[id]
      if had then
        -- Two keys for one type: the earlier first catch, both counts.
        local merged = entry.t < had.t and entry or had
        list[id] = { t = merged.t, z = merged.z, s = merged.s, m = merged.m, c = merged.c, n = had.n + entry.n }
      else
        list[id] = entry
      end
    end
  end
  return pairs(list)
end

-- Who caught something first, for the read.
local function catcher(record, entry, ownId, now)
  local character = entry.c and type(record.characters) == "table" and record.characters[entry.c]
  return {
    memberId = record.id,
    displayName = record.displayName,
    own = record.id == ownId,
    character = character and character.name or nil,
    classFilename = character and character.classFilename or nil,
    time = entry.t,
    since = ns.Text.since(now - entry.t),
    zone = entry.z,
    subzone = entry.s,
    mapId = entry.m,
  }
end

local function earlier(entry, record, best)
  if not best then return true end
  if entry.t ~= best.entry.t then return entry.t < best.entry.t end
  return record.id < best.record.id
end

-- The Crew's catches over the given records (ownId: your Member id, now:
-- the time). See Core:catches().
function Catches.collect(records, ownId, now)
  local found = {}
  for _, record in ipairs(records) do
    for key, entry in valid(record) do
      local f = found[key]
      if not f then
        f = { count = 0 }
        found[key] = f
      end
      f.count = f.count + entry.n
      if earlier(entry, record, f.best) then f.best = { entry = entry, record = record } end
    end
  end

  local view = { total = Catches.TOTAL, caught = 0, types = {}, unlisted = {}, waters = Catches.WATERS }
  for i, t in ipairs(Catches.TYPES) do
    local f = found[t.id]
    view.types[i] = {
      id = t.id, itemId = t.itemId, items = t.items, name = t.name, kind = t.kind, waters = t.waters,
      extra = t.extra, count = f and f.count or 0,
      first = f and catcher(f.best.record, f.best.entry, ownId, now) or nil,
    }
    if f and not t.extra then view.caught = view.caught + 1 end
  end
  for key, f in pairs(found) do
    if not BY_ID[key] then
      view.unlisted[#view.unlisted + 1] = { itemId = key, count = f.count,
        first = catcher(f.best.record, f.best.entry, ownId, now) }
    end
  end
  table.sort(view.unlisted, function(a, b)
    if a.first.time ~= b.first.time then return a.first.time < b.first.time end
    return a.itemId < b.itemId
  end)
  return view
end
