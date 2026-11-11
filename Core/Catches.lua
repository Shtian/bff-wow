-- Catches: the pure parts of the Crew's fishing catches. The list of types
-- (data: a new type or zone is one row), reading what was fished from
-- the loot window (handed the API, so offline tests can fake it), how catches are
-- kept in a Member's own record, the Crew's catches over every record
-- (per type, the earliest catch and the Crew's count), and the Catches
-- tab over them. Stateless, tested through Core. See docs/design/catches.md and
-- docs/research/fishing-catches.md.

local _, ns = ...

local Catches = {}
ns.Catches = Catches

-- Waters by zone level, lowest first: low and high are the band's zone
-- levels (none for New on Forever). Zones are as an English client names
-- them, for showing which zones a band covers.
Catches.WATERS = {
  { id = "1-10", low = 1, high = 10, name = "Level 1–10", zones = { "Elwynn Forest", "Dun Morogh", "Teldrassil", "Durotar", "Mulgore",
    "Tirisfal Glades", "the capitals" } },
  { id = "10-25", low = 10, high = 25, name = "Level 10–25", zones = { "Westfall", "Loch Modan", "Darkshore", "Silverpine Forest",
    "The Barrens", "Redridge Mountains" } },
  { id = "20-35", low = 20, high = 35, name = "Level 20–35", zones = { "Ashenvale", "Duskwood", "Hillsbrad Foothills", "Wetlands",
    "Stonetalon Mountains", "Thousand Needles" } },
  { id = "30-45", low = 30, high = 45, name = "Level 30–45", zones = { "Stranglethorn Vale", "Arathi Highlands", "Alterac Mountains",
    "Desolace", "Dustwallow Marsh", "Swamp of Sorrows" } },
  { id = "40-55", low = 40, high = 55, name = "Level 40–55", zones = { "Tanaris", "Feralas", "The Hinterlands", "Azshara", "Felwood",
    "Un'Goro Crater" } },
  { id = "50-60", low = 50, high = 60, name = "Level 50–60", zones = { "Western Plaguelands", "Eastern Plaguelands", "Winterspring",
    "Burning Steppes", "Silithus", "Moonglade", "Deadwind Pass" } },
  { id = "new", name = "New on Forever", zones = { "Riverglades", "Gilneas", "Shen'dralas", "Mount Hyjal",
    "Shark-Infested Waters" } },
}

-- Water ids, lowest first, for the list below.
local W1, W2, W3, W4, W5, W6, NEW = (function()
  local ids = {}
  for i, w in ipairs(Catches.WATERS) do ids[i] = w.id end
  return unpack(ids)
end)()

-- The types, in the list's order. id is the item ID, or a family's key
-- for fish sold by weight (any of its items counts as it). name is the
-- English name, for when the game hasn't the item cached; the game's name
-- and icon come from the item ID. kind: "fish", "quest" (Nat Pagle's),
-- "bloated", "family", "contest", "treasure" or "notFish" (fished, but not
-- a fish). waters: lowest first. extra: shown but never counted, and why:
-- "season", "contest", "unconfirmed" (not confirmed on Forever yet),
-- "questItem" (only while on its quest) or "notFish". note: a line for the
-- tooltip, where there's something to know (where it bites, how to open it).
local OPEN = "Right-click it to open it"
local LOCKED = "Needs lockpicking"
local CONTEST = "Only on Sundays, in the Stranglethorn Fishing Extravaganza (a fishing contest)"
local function fish(id, name, waters, note, extra)
  return { id = id, name = name, kind = "fish", waters = waters, note = note, extra = extra }
end
local function quest(id, name, waters, where)
  return { id = id, name = name, kind = "quest", waters = waters, note = "For Nat Pagle's quest. " .. where }
end
local function bloated(id, name, waters)
  return { id = id, name = name, kind = "bloated", waters = waters, note = OPEN }
end
local function family(id, name, fishName, items, waters)
  return { id = id, name = name, kind = "family", items = items, waters = waters,
    note = ('Any %s with a weight in its name, like "19 Pound Catfish". Any weight counts. Heavier ones sell for more')
      :format(fishName) }
end
local function contest(id, name)
  return { id = id, name = name, kind = "contest", waters = { W4 }, note = CONTEST, extra = "contest" }
end
local function treasure(id, name, waters, note)
  return { id = id, name = name, kind = "treasure", waters = waters, note = note, extra = "unconfirmed" }
end
local function notFish(id, name, waters, note)
  return { id = id, name = name, kind = "notFish", waters = waters, note = note, extra = "notFish" }
end

Catches.TYPES = {
  -- Fish (25 counted).
  fish(6291, "Raw Brilliant Smallfish", { W1, W2, W3 }),
  fish(6303, "Raw Slitherskin Mackerel", { W1, W2 }),
  fish(6289, "Raw Longjaw Mud Snapper", { W1, W2, W3 }),
  fish(6299, "Sickly Looking Fish", { W1 }, "Tirisfal Glades"),
  fish(6317, "Raw Loch Frenzy", { W2 }, "Only in Loch Modan"),
  fish(6361, "Raw Rainbow Fin Albacore", { W2, W3 }),
  fish(6308, "Raw Bristle Whisker Catfish", { W2, W3, W4 }),
  fish(21071, "Raw Sagefish", { W2, W3 }),
  fish(6522, "Deviate Fish", { W2 }, "The Barrens, in the pools near Wailing Caverns"),
  fish(12238, "Darkshore Grouper", { W2 }, "Darkshore"),
  fish(6358, "Oily Blackmouth", { W3, W4, W5 }),
  fish(6359, "Firefin Snapper", { W3, W4, W5 }),
  fish(8365, "Raw Mithril Head Trout", { W4, W5, W6 }),
  fish(6362, "Raw Rockscale Cod", { W4, W5 }),
  fish(21153, "Raw Greater Sagefish", { W4 }, "Alterac Mountains, Stranglethorn Vale"),
  fish(4603, "Raw Spotted Yellowtail", { W4, W5 }),
  fish(13754, "Raw Glossy Mightfish", { W4, W5 }),
  fish(13422, "Stonescale Eel", { W4, W5, W6 }),
  fish(13758, "Raw Redgill", { W5, W6 }),
  fish(13759, "Raw Nightfin Snapper", { W5, W6 }, "Bites best at night"),
  fish(13760, "Raw Sunscale Salmon", { W5, W6 }, "Bites best in the day"),
  fish(13893, "Large Raw Mightfish", { W5, W6 }, "Azshara, Eastern Plaguelands"),
  fish(13888, "Darkclaw Lobster", { W5, W6 }, "Azshara, Eastern Plaguelands"),
  fish(13757, "Lightning Eel", { W6 }),
  fish(13889, "Raw Whitescale Salmon", { W6 }),
  -- Nat Pagle's quest fish (4).
  quest(16970, "Misty Reed Mahi Mahi", { W4 }, "Swamp of Sorrows"),
  quest(16968, "Sar'theris Striker", { W4 }, "Desolace"),
  quest(16969, "Savage Coast Blue Sailfin", { W4 }, "Stranglethorn Vale"),
  quest(16967, "Feralas Ahi", { W5 }, "Feralas"),
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
  family("mudSnapper", "Mud Snapper (by weight)", "Mud Snapper", { 6292, 6294, 6295 }, { W1, W2 }),
  family("catfish", "Catfish (by weight)", "Catfish", { 6309, 6310, 6311, 6363, 6364 }, { W2, W3 }),
  family("yellowtail", "Yellowtail (by weight)", "Yellowtail", { 13876, 13877, 13878, 13879, 13880 }, { W4, W5 }),
  family("redgill", "Redgill (by weight)", "Redgill", { 13882, 13883, 13884, 13885, 13886, 13887 }, { W5, W6 }),
  family("mightfish", "Mightfish (by weight)", "Mightfish", { 13914, 13915, 13916, 13917 }, { W5, W6 }),
  family("lobster", "Lobster (by weight)", "Lobster", { 13907, 13908, 13909, 13910, 13911, 13912, 13913 }, { W5, W6 }),
  family("salmon", "Salmon (by weight)", "Salmon", { 13901, 13902, 13903, 13904, 13905, 13906 }, { W6 }),
  -- Extras: seasonal, the Sunday fishing contest, a quest item, not a fish,
  -- and not confirmed on Forever yet.
  fish(13756, "Raw Summer Bass", { W4, W5, W6 }, "Only in summer", "season"),
  fish(13755, "Raw Winter Squid", { W4, W5 }, "Only in winter", "season"),
  contest(19807, "Speckled Tastyfish"),
  contest(19805, "Keefer's Angelfish"),
  contest(19806, "Dezian Queenfish"),
  contest(19803, "Brownell's Blue Striped Racer"),
  fish(1467, "Spotted Sunfish", { W2 }, "For a quest in Redridge Mountains", "questItem"),
  notFish(3820, "Stranglekelp", { W2, W3, W4, W5 }, "A herb, for Alchemy"),
  notFish(20709, "Rumsey Rum Light", { W2 }),
  notFish(21114, "Rumsey Rum Dark", { W3 }),
  notFish(21151, "Rumsey Rum Black Label", { W2, W4, W5 }),
  fish(251524, "Whimsyfin", { W2 }, "New on Forever. Reported in Redridge Mountains", "unconfirmed"),
  fish(13890, "Raw Plated Armorfish", { NEW }, "Forever adds a recipe for it. No one knows yet where it bites", "unconfirmed"),
  treasure(6356, "Battered Chest", { W2, W3 }),
  treasure(6351, "Dented Crate", { W2, W3 }),
  treasure(6352, "Waterlogged Crate", { W2, W3 }),
  treasure(6354, "Small Locked Chest", { W2, W3 }, LOCKED),
  treasure(6357, "Sealed Crate", { W3, W4 }),
  treasure(6355, "Sturdy Locked Chest", { W3, W4 }, LOCKED),
  treasure(13874, "Heavy Crate", { W4, W5 }),
  treasure(13875, "Ironbound Locked Chest", { W4, W5 }, LOCKED),
  treasure(21150, "Iron Bound Trunk", { W4, W5 }),
  treasure(21113, "Watertight Trunk", { W4, W5 }),
  treasure(7973, "Big-mouth Clam", { W4, W5 }),
  treasure(6307, "Message in a Bottle", { W4, W5 }),
  treasure(13918, "Reinforced Locked Chest", { W5, W6 }, LOCKED),
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
-- isSecret (issecretvalue, optional). The fished loot: { items, a { itemId,
-- quantity } per item slot (not coin or currency), zone, subzone, mapId
-- (each nil when unknown) }. Nil when the loot isn't from fishing, holds
-- no item, a value reads secret, or the read errors.
function Catches.read(api)
  local ok, loot = pcall(readAll, api)
  if ok then return loot end
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

-- Adds fished loot (as read() gives it) to the own record, caught at time by
-- the Character with GUID character. Its catches are { [key] = { t, n, z,
-- s, m, c } }: key the type's id, or the item ID of an unlisted catch; t
-- the first catch's time, z, s and m its zone, subzone and map ID, c the
-- Character's GUID, and n how many caught. Unlisted catches past
-- UNLISTED_CAP are dropped. Returns true if the record changed.
function Catches.add(record, loot, time, character)
  if type(loot) ~= "table" or type(loot.items) ~= "table" then return false end
  local changed = false
  for _, item in ipairs(loot.items) do
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
          t = time, n = quantity, z = text(loot.zone), s = text(loot.subzone),
          m = isItemId(loot.mapId) and loot.mapId or nil, c = text(character),
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
-- family; a key this list doesn't know as a family is skipped. Unlisted
-- catches past UNLISTED_CAP (the earliest kept) are skipped too.
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
  local unlisted = {}
  for id, entry in pairs(list) do
    if not BY_ID[id] then unlisted[#unlisted + 1] = { id = id, t = entry.t } end
  end
  table.sort(unlisted, function(a, b)
    if a.t ~= b.t then return a.t < b.t end
    return a.id < b.id
  end)
  for i = Catches.UNLISTED_CAP + 1, #unlisted do list[unlisted[i].id] = nil end
  return pairs(list)
end

-- How many catches a record holds in all: every type's count. The Pocket
-- Camp shows a Member fishing when it grows (Core:pocketCamp()).
function Catches.total(record)
  local total = 0
  for _, entry in valid(record) do total = total + entry.n end
  return total
end

-- Kinds whose Crew-first catch is a rare find: Feed news.
local RARE = { quest = true, contest = true }

-- The rare types a record holds, as a set of type ids.
function Catches.rareHeld(record)
  local held = {}
  for key in valid(record) do
    if BY_ID[key] and RARE[BY_ID[key].kind] then held[key] = true end
  end
  return held
end

-- The rare finds in a record: rare types it holds that aren't in had (as
-- rareHeld gives it) and that no other of the given records holds, so the
-- Crew hasn't had them. Oldest first: { id, itemId, name, time, guid (the
-- Character who caught it, nil when unknown) }.
function Catches.rareFinds(had, record, records)
  local taken = {}
  for _, other in ipairs(records) do
    if other.id ~= record.id then
      for key in pairs(Catches.rareHeld(other)) do taken[key] = true end
    end
  end
  local finds = {}
  local entries = {}
  for key, entry in valid(record) do entries[key] = entry end
  for key in pairs(Catches.rareHeld(record)) do
    if not had[key] and not taken[key] then
      local t, entry = BY_ID[key], entries[key]
      finds[#finds + 1] = { id = key, itemId = t.itemId, name = t.name, time = entry.t, guid = entry.c }
    end
  end
  table.sort(finds, function(a, b)
    if a.time ~= b.time then return a.time < b.time end
    return a.id < b.id
  end)
  return finds
end

-- How many counted types anyone in the given records has caught.
function Catches.typesCaught(records)
  local caught, n = {}, 0
  for _, record in ipairs(records) do
    for key in valid(record) do
      local t = BY_ID[key]
      if t and not t.extra and not caught[key] then
        caught[key] = true
        n = n + 1
      end
    end
  end
  return n
end

-- Who caught something first and where, in words: "Bob (Bobby),
-- Westfall, The Jansen Stead, 5m ago", or "You" for your own.
local function catchText(first)
  local who = first.own and "You" or first.displayName or "Someone"
  if first.character and first.character ~= first.displayName then who = who .. " (" .. first.character .. ")" end
  local parts = { who }
  if first.zone then parts[#parts + 1] = first.zone end
  if first.subzone and first.subzone ~= first.zone then parts[#parts + 1] = first.subzone end
  parts[#parts + 1] = first.since
  return table.concat(parts, ", ")
end

-- Who caught something first, for the read.
local function catcher(record, entry, ownId, now)
  local character = entry.c and type(record.characters) == "table" and record.characters[entry.c]
  local first = {
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
  first.who = first.own and "You" or first.displayName or "Someone"
  first.text = catchText(first)
  return first
end

local function earlier(entry, record, best)
  if not best then return true end
  if entry.t ~= best.entry.t then return entry.t < best.entry.t end
  return record.id < best.record.id
end

-- The other Members who caught something, after the first, in the order
-- they first caught it: { memberId, displayName, own }.
local function others(found, ownId)
  local list = {}
  if not found then return list end
  local catchers = {}
  for _, c in ipairs(found.catchers) do
    if c.record ~= found.best.record then catchers[#catchers + 1] = c end
  end
  table.sort(catchers, function(a, b)
    if a.entry.t ~= b.entry.t then return a.entry.t < b.entry.t end
    return a.record.id < b.record.id
  end)
  for i, c in ipairs(catchers) do
    list[i] = { memberId = c.record.id, displayName = c.record.displayName, own = c.record.id == ownId }
  end
  return list
end

-- The Crew's catches over the given records (ownId: your Member id, now:
-- the time). See Core:catches().
function Catches.collect(records, ownId, now)
  local found = {}
  for _, record in ipairs(records) do
    for key, entry in valid(record) do
      local f = found[key]
      if not f then
        f = { count = 0, catchers = {} }
        found[key] = f
      end
      f.count = f.count + entry.n
      f.catchers[#f.catchers + 1] = { entry = entry, record = record }
      if earlier(entry, record, f.best) then f.best = { entry = entry, record = record } end
    end
  end

  local view = { total = Catches.TOTAL, caught = 0, types = {}, unlisted = {}, waters = Catches.WATERS }
  for i, t in ipairs(Catches.TYPES) do
    local f = found[t.id]
    view.types[i] = {
      id = t.id, itemId = t.itemId, items = t.items, name = t.name, kind = t.kind, waters = t.waters,
      extra = t.extra, note = t.note, count = f and f.count or 0,
      first = f and catcher(f.best.record, f.best.entry, ownId, now) or nil,
      others = others(f, ownId),
    }
    if f and not t.extra then view.caught = view.caught + 1 end
  end
  for key, f in pairs(found) do
    if not BY_ID[key] then
      view.unlisted[#view.unlisted + 1] = { itemId = key, count = f.count,
        first = catcher(f.best.record, f.best.entry, ownId, now), others = others(f, ownId) }
    end
  end
  table.sort(view.unlisted, function(a, b)
    if a.first.time ~= b.first.time then return a.first.time < b.first.time end
    return a.itemId < b.itemId
  end)
  view.title = ("The Crew has caught %d of %d types."):format(view.caught, view.total)
  return view
end

-- Whether you've caught a type yourself (collect()'s view of it).
local function caughtByYou(t)
  if t.first.own then return true end
  for _, other in ipairs(t.others) do
    if other.own then return true end
  end
  return false
end

-- While you were away's line over the Crew's catches (collect()'s view):
-- the counted types not in told (a set of type ids) that others caught and
-- you haven't, each under whoever was first, "4 new types caught (Tor 3,
-- Mira 1)", most first. Nil when there are none.
function Catches.newTypesLine(view, told)
  local byWho, names, total = {}, {}, 0
  for _, t in ipairs(view.types) do
    local first = t.first
    if first and not t.extra and not told[t.id] and not caughtByYou(t) then
      total = total + 1
      if not byWho[first.who] then names[#names + 1] = first.who end
      byWho[first.who] = (byWho[first.who] or 0) + 1
    end
  end
  if total == 0 then return nil end
  table.sort(names, function(a, b)
    if byWho[a] ~= byWho[b] then return byWho[a] > byWho[b] end
    return a < b
  end)
  local parts = {}
  for i, name in ipairs(names) do parts[i] = ("%s %d"):format(name, byWho[name]) end
  return ("%d new %s caught (%s)"):format(total, total == 1 and "type" or "types", table.concat(parts, ", "))
end

-- Adds the counted types caught in view to told, and returns it. With
-- since, only those first caught from then on.
function Catches.markTold(told, view, since)
  for _, t in ipairs(view.types) do
    if t.first and not t.extra and (not since or t.first.time >= since) then told[t.id] = true end
  end
  return told
end

-- The Catches tab ------------------------------------------------------

-- The trophy steps: how many types the Crew has caught when a trophy
-- comes, the last being every type.
Catches.STEPS = { 10, 20, 30, 40, Catches.TOTAL }
-- A first catch this recent is fresh: a gold line under its tile, and in
-- the tab's Recent first catches.
Catches.FRESH = 3 * 24 * 60 * 60
local RECENT = 3

-- The Group and Show menus' choices, in order. A tile's category is
-- what Show's Fish and Rare catches pick.
local GROUPS = { { id = "where", label = "Where to fish" }, { id = "type", label = "Type" } }
local SHOWS = {
  { id = "all", label = "All" },
  { id = "fish", label = "Fish" },
  { id = "rare", label = "Rare catches" },
  { id = "extras", label = "Extras" },
  { id = "missing", label = "Not caught yet" },
}
local CATEGORY = { fish = "fish", quest = "rare", bloated = "rare", family = "rare", contest = "rare" }
local EXTRA_WHY = {
  season = "only in one season",
  contest = "only in the Sunday fishing contest",
  unconfirmed = "not confirmed on Forever yet",
  questItem = "a quest item, only caught while on its quest",
  notFish = "not a fish",
}
local UNLISTED_NOTE = "Not on BFF's list yet. Saved, so it can be added"
local NAMES_LABEL = "Show names of fish not caught yet"

local function pick(list, id)
  for _, option in ipairs(list) do
    if option.id == id then return option end
  end
  return list[1]
end

local WATER_NAME = {}
for _, w in ipairs(Catches.WATERS) do WATER_NAME[w.id] = w.name end

-- "Tor", "Tor and you", "Tor, Simba and you".
local function names(list)
  local words = {}
  for i, who in ipairs(list) do words[i] = who.own and "you" or who.displayName or "someone" end
  if #words <= 1 then return words[1] end
  return table.concat(words, ", ", 1, #words - 1) .. " and " .. words[#words]
end

local function place(first)
  local parts = {}
  if first.zone then parts[#parts + 1] = first.zone end
  if first.subzone and first.subzone ~= first.zone then parts[#parts + 1] = first.subzone end
  if #parts == 0 then return first.since end
  return first.since .. " · " .. table.concat(parts, ", ")
end

-- A tile's tooltip, under its name (which the game gives; unnamed when it
-- can't show): note, extra, firstBy and first, when, crew and count, also, none, hint and where (each nil
-- when there's nothing to say).
local function tooltip(entry, named)
  local tip = { unnamed = "???" }
  if named then tip.note = entry.note end
  if entry.extra then tip.extra = "Extra, not counted: " .. EXTRA_WHY[entry.extra] end
  if entry.first then
    tip.first = entry.first
    tip.firstBy = "First caught by"
    tip.when = place(entry.first)
    tip.crew = "The Crew has caught"
    tip.count = entry.count
    if #entry.others > 0 then tip.also = "Also caught by " .. names(entry.others) end
  else
    tip.none = "No one in the Crew has caught this yet."
    if not named then tip.hint = "To see its name: Show > " .. NAMES_LABEL end
  end
  if entry.waters then
    local where = {}
    for i, id in ipairs(entry.waters) do where[i] = WATER_NAME[id] end
    tip.where = "Where: " .. table.concat(where, ", ")
  end
  return tip
end

local function tile(entry, opts)
  local caught = entry.first ~= nil
  local named = caught or opts.names
  return {
    id = entry.id or entry.itemId,
    itemId = entry.itemId,
    name = entry.name or ("Item %d"):format(entry.itemId),
    caught = caught,
    named = named,
    fresh = caught and opts.now - entry.first.time < Catches.FRESH,
    extra = entry.extra,
    unlisted = entry.unlisted,
    category = not entry.unlisted and CATEGORY[entry.kind] or nil,
    first = entry.first,
    tooltip = tooltip(entry, named),
  }
end

-- Whether Show's choice shows a tile.
local function shows(show, t)
  if show == "all" then return true end
  if show == "missing" then return not t.caught end
  if show == "extras" then return t.extra ~= nil end
  return t.category == show
end

-- The sections before Show picks from them: each { title, sub, tiles,
-- extras and uncounted (its count is how many were caught) }.
local function sectionsFor(group, tiles)
  local sections = {}
  if group == "type" then
    local fishes = { title = "Fish", tiles = {} }
    local rare = { title = "Rare catches", tiles = {} }
    for _, t in ipairs(tiles) do
      if not t.unlisted and not t.extra then
        local s = t.category == "fish" and fishes or rare
        s.tiles[#s.tiles + 1] = t
      end
    end
    sections = { fishes, rare }
  else
    local byWater = {}
    for i, w in ipairs(Catches.WATERS) do
      sections[i] = { title = w.name, sub = table.concat(w.zones, ", "), tiles = {} }
      byWater[w.id] = sections[i]
    end
    for _, t in ipairs(tiles) do
      if not t.unlisted and not t.extra then
        local s = byWater[t.water]
        s.tiles[#s.tiles + 1] = t
      end
    end
  end
  -- Unlisted catches aren't placed in any water, since the list doesn't
  -- know where they bite.
  local unlisted = { title = "Not on the list yet", sub = "Not counted", tiles = {}, uncounted = true }
  for _, t in ipairs(tiles) do
    if t.unlisted then unlisted.tiles[#unlisted.tiles + 1] = t end
  end
  if #unlisted.tiles > 0 then sections[#sections + 1] = unlisted end
  local extras = { title = "Extras", sub = "Not counted", tiles = {}, extras = true, uncounted = true }
  for _, t in ipairs(tiles) do
    if t.extra then extras.tiles[#extras.tiles + 1] = t end
  end
  sections[#sections + 1] = extras
  return sections
end

-- A section's count on the right: "8 / 12" for counted types, "2 caught"
-- for a section that isn't counted, nil when it has neither.
local function counted(s)
  local n, got, caught = 0, 0, 0
  for _, t in ipairs(s.tiles) do
    if t.caught then caught = caught + 1 end
    if not t.extra and not t.unlisted then
      n = n + 1
      if t.caught then got = got + 1 end
    end
  end
  if n > 0 then return ("%d / %d"):format(got, n), n, got end
  if s.uncounted then return ("%d caught"):format(caught) end
  return nil
end

local function levelWaters(level)
  local found
  for _, w in ipairs(Catches.WATERS) do
    if w.low and level and level >= w.low then found = w end
  end
  return found
end

-- The Catches tab over the Crew's catches (collect()'s view). opts: group
-- ("where" or "type"), show ("all", "fish", "rare", "extras" or
-- "missing"), names (show names of types not caught yet), now and level
-- (the Character you play, or nil). See Core:catchesTab().
function Catches.tab(view, opts)
  local group = pick(GROUPS, opts.group)
  local show = pick(SHOWS, opts.show)
  local tiles = {}
  for i, entry in ipairs(view.types) do
    local t = tile(entry, opts)
    -- Each type shows once, in the lowest water it's found in.
    t.water = entry.waters[1]
    tiles[i] = t
  end
  local unlisted = {}
  for _, entry in ipairs(view.unlisted) do
    local t = tile({ itemId = entry.itemId, count = entry.count, first = entry.first, others = entry.others,
      note = UNLISTED_NOTE, unlisted = true }, opts)
    tiles[#tiles + 1] = t
    unlisted[#unlisted + 1] = t
  end

  local tab = { caught = view.caught, total = view.total, done = view.caught >= view.total }
  if tab.done then
    tab.count = ("All %d types caught"):format(view.total)
    tab.next = "Every type on the list. Extras and new finds still show up below."
  else
    tab.count = ("%d of %d types caught"):format(view.caught, view.total)
    tab.countOf = ("of %d types caught"):format(view.total)
    for _, step in ipairs(Catches.STEPS) do
      if step > view.caught then
        tab.next = ("Next trophy at %s: %d more to catch"):format(
          step == view.total and "every type" or step .. " types", step - view.caught)
        break
      end
    end
  end
  tab.fill = view.total > 0 and view.caught / view.total or 0
  tab.ticks = {}
  for i = 1, #Catches.STEPS - 1 do
    if view.total > 0 then tab.ticks[i] = Catches.STEPS[i] / view.total end
  end

  local all = sectionsFor(group.id, tiles)
  local function filtered(id)
    local list = {}
    for _, s in ipairs(all) do
      local shown = {}
      for _, t in ipairs(s.tiles) do
        if (id ~= "extras" or s.extras) and shows(id, t) then shown[#shown + 1] = t end
      end
      if #shown > 0 then
        local count, n, got = counted(s)
        list[#list + 1] = { title = s.title, sub = s.sub, count = count, counted = n, got = got,
          done = n ~= nil and got == n, tiles = shown }
      end
    end
    return list
  end
  tab.sections = filtered(show.id)

  tab.group = { title = "Group by", label = "Group: " .. group.label, options = {} }
  for i, option in ipairs(GROUPS) do
    tab.group.options[i] = { id = option.id, label = option.label, picked = option.id == group.id }
  end
  tab.show = { title = "Show", label = "Show: " .. show.label, options = {},
    names = { label = NAMES_LABEL, value = opts.names and true or false } }
  for i, option in ipairs(SHOWS) do
    local count
    if option.id ~= "all" then
      count = 0
      for _, s in ipairs(filtered(option.id)) do count = count + #s.tiles end
    end
    tab.show.options[i] = { id = option.id, label = option.label, count = count, picked = option.id == show.id }
  end

  local anyCaught = #unlisted > 0
  for _, t in ipairs(tiles) do anyCaught = anyCaught or t.caught end
  if not anyCaught then
    local waters = levelWaters(opts.level)
    tab.empty = {
      title = "No catches yet",
      text = "When anyone in the Crew catches a fish, it shows up here. Start in the waters for your level"
        .. (waters and ": " .. waters.name .. "." or "."),
    }
  elseif #tab.sections == 0 then
    tab.filtered = {
      title = show.id == "missing" and "The Crew has caught every type." or "Nothing to show for this choice.",
      text = 'Change "Show" to see more.',
    }
  end

  local recent = {}
  for _, t in ipairs(tiles) do
    if t.fresh then recent[#recent + 1] = t end
  end
  table.sort(recent, function(a, b)
    if a.first.time ~= b.first.time then return a.first.time > b.first.time end
    return tostring(a.id) < tostring(b.id)
  end)
  tab.recentTitle = "RECENT FIRST CATCHES"
  tab.recent = {}
  for i = 1, math.min(RECENT, #recent) do
    local t = recent[i]
    local first = t.first
    tab.recent[i] = { itemId = t.itemId, name = t.name, first = first, caught = "caught",
      when = first.zone and (first.zone .. " · " .. first.since) or first.since }
  end
  return tab
end
