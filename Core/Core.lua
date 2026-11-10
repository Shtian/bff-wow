-- Core: everything BFF knows and decides, in pure Lua. It never touches the
-- game; App hands it the clock, randomness, the link and saved data.
-- See docs/design/code-structure.md.

local _, ns = ...

local Core = {}
Core.__index = Core
ns.Core = Core

local required = {
  db = "table",
  now = "function",
  random = "function",
  link = "table",
  listener = "function",
  maxLevel = "number",
}

-- For the UI's wording.
Core.CAN_PLAY_LEVELS = ns.Roster.CAN_PLAY
-- A merged Reaction toast's text, from the names of who reacted and the
-- phrase in reaction news: "Bob and Cleo cheered your ding to 30".
Core.reactionText = ns.Reactions.text
Core.HIDE_AFTER_DAYS = ns.Roster.HIDE_AFTER / (24 * 60 * 60)
-- The game's dungeons and the Together tab's line geometry (see together()).
Core.DUNGEONS = ns.Together.DUNGEONS
Core.TOGETHER_LAYOUT = ns.Together.LAYOUT
-- The Camp's geometry in art pixels (see camp()).
Core.CAMP_LAYOUT = ns.Camp.LAYOUT
-- The final bosses known: encounter ID to the name of the instance a kill
-- clears (see encounterEnded()).
Core.FINAL_BOSSES = ns.Clears.FINAL_BOSSES

-- A count with thousands separators, for the UI's wording: 2,500.
Core.grouped = ns.Text.grouped

-- The tooltip's gold line for a Character's money (copper): whole gold,
-- floored, with thousands separators ("Gold: 1,234"). Nil when the
-- Character's client never shared it, so no line shows rather than "0".
function Core.goldText(money)
  if type(money) ~= "number" then return nil end
  return "Gold: " .. ns.Text.grouped(math.floor(money / 10000))
end

-- The sync trace (/bff debug sync): trace(line) gets a line of text for
-- each message sent and received, without a timestamp. Nil turns it off,
-- and then no line is ever built.
function Core:setTrace(trace)
  self.trace = type(trace) == "function" and trace or nil
end

-- A Member's name for the trace: the display name, else the id.
local function traceName(self, id, displayName)
  if id == self.ledger:memberId() then return self:displayName() or id end
  local record = self.ledger:record(id)
  return displayName or (record and record.displayName) or tostring(id)
end

-- A record in the trace: "Ann (k3j2h1) v1731000000".
local function traceRecord(self, record)
  if type(record) ~= "table" then return "?" end
  return ("%s (%s) v%s"):format(traceName(self, record.id, record.displayName),
    tostring(record.id), tostring(record.version))
end

-- A DIGEST's versions in the trace: "Ann v1731000000, Bob v1731000003",
-- sorted by name.
local function traceVersions(self, versions)
  local items = {}
  for id, version in pairs(versions) do
    items[#items + 1] = ("%s v%s"):format(traceName(self, id), tostring(version))
  end
  table.sort(items)
  return table.concat(items, ", ")
end

-- The trace's line for a message going out, `size` bytes encoded, to
-- everyone or only the Character named `to`.
local function sentLine(self, message, size, to)
  if message.type == "DIGEST" and type(message.versions) == "table" then
    local count = 0
    for _ in pairs(message.versions) do count = count + 1 end
    return ("send DIGEST%s · %d versions%s · %d B · %s"):format(to and (" to " .. to) or "", count,
      message.partial and " (more in turn)" or "", size, traceVersions(self, message.versions))
  end
  local records = {}
  for i, record in ipairs(type(message.records) == "table" and message.records or {}) do
    records[i] = traceRecord(self, record)
  end
  return ("send %s · %d B · %s"):format(tostring(message.type), size, table.concat(records, ", "))
end

-- The trace's line for a DATA record received: whether it was merged (not
-- when it isn't newer, is malformed or is from a removed Member), and
-- how late it arrived (the time since its version, the server time it was
-- written at).
local function traceReceived(self, record, kept)
  local line = traceRecord(self, record) .. (kept and " · merged" or " · not merged")
  if type(record) == "table" and type(record.version) == "number" then
    line = line .. (" · late %ds"):format(math.max(0, self.now() - record.version))
  end
  return line
end

-- deps: db, now(), random(), link (with send(string, to): to everyone, or
-- only the Character named to), listener(event, ...),
-- initialLogin, maxLevel, utcOffset (seconds local time is ahead of server
-- time, for the Feed's days; default 0) and locate() (optional: where the
-- Character being played stands, read just before own DATA goes out; see
-- Snapshot.locate), itemLink(itemString) (optional: the game's link for
-- an item string, or nil while it isn't cached; texts say "an item" then),
-- itemLook(itemId) (optional: how the game shows an item, for rare finds:
-- { text (its name in its quality colour), icon, edge (its quality's
-- colour) }, each nil while it isn't cached; texts use the English name then)
-- findItem(itemGuid) (optional: whether the item is in the bags or
-- bank, nil if the game can't say, and whether it's equipped; see
-- Bags.findItem) and finalBosses (optional: encounter ID to instance name,
-- default Core.FINAL_BOSSES; for tests and the dev sim, while Forever's
-- IDs aren't known) and gossip (optional: the Gossip module to use; for
-- tests with a client that syncs like an older BFF).
function Core.new(deps)
  for name, kind in pairs(required) do
    if type(deps[name]) ~= kind then
      error(("Core.new: %s must be a %s"):format(name, kind), 2)
    end
  end
  if type(deps.link.send) ~= "function" then
    error("Core.new: link.send must be a function", 2)
  end

  local self = setmetatable({
    db = deps.db,
    now = deps.now,
    random = deps.random,
    link = deps.link,
    listener = deps.listener,
    initialLogin = deps.initialLogin == true,
    maxLevel = deps.maxLevel,
    ledger = ns.Ledger.new(deps.db, deps.now, deps.random, deps.initialLogin == true),
    utcOffset = type(deps.utcOffset) == "number" and deps.utcOffset or 0,
    finalBosses = type(deps.finalBosses) == "table" and deps.finalBosses or ns.Clears.FINAL_BOSSES,
    linkUp = false,
  }, Core)
  local itemLink = type(deps.itemLink) == "function" and deps.itemLink or nil
  local itemLook = type(deps.itemLook) == "function" and deps.itemLook or nil
  self.log = ns.Feed.new(deps.db, self.ledger, deps.now, deps.maxLevel, self.initialLogin, itemLink, itemLook)
  -- Catches from here on happen with you online, so they aren't news
  -- for While you were away.
  self.sessionStart = deps.now()
  -- The Spares module (self.spares is the method that reads its tab).
  self.spareLife = ns.Spares.new({
    db = deps.db,
    ledger = self.ledger,
    feed = self.log,
    now = deps.now,
    listener = deps.listener,
    initialLogin = self.initialLogin,
    itemLink = itemLink,
    findItem = type(deps.findItem) == "function" and deps.findItem or nil,
  })
  self.crewGoals = ns.Goals.new(deps.db, self.ledger, deps.now, deps.maxLevel)
  -- Every message carries the sender's Member id. Where you stand is only
  -- read when own DATA goes out, so moving alone never sends anything.
  local locate = type(deps.locate) == "function" and deps.locate or nil
  local Gossip = type(deps.gossip) == "table" and deps.gossip or ns.Gossip
  self.gossip = Gossip.new(self.ledger, deps.now, deps.random, function(message, to)
    message.from = self.ledger:memberId()
    local encoded = ns.Codec.encode(message)
    if self.trace then self.trace(sentLine(self, message, #encoded, to)) end
    self.link.send(encoded, to)
  end, locate and function() self.ledger:locate(locate()) end)
  self.gossip:setPaused(self:isPaused())
  self.playTracker = ns.PlayTimes.new(deps.db, deps.now)
  -- The own record's Play times may be out of date until the first tick.
  self.playTimesDue = true
  self.online = ns.Roster.online(self.ledger, deps.now())
  return self
end

-- Gossip's link is up only while in a Crew. Settling after login starts
-- once it is, and starts over if it goes down first.
local function updateLink(self)
  local up = self.linkUp and self.db.crew ~= nil
  if up then self.log:linkUp() else self.log:linkDown() end
  if up then self.crewGoals:linkUp() else self.crewGoals:linkDown() end
  self.gossip:setLink(up)
end

-- Where Live events go: { chat, toast }, from the chat lines and toasts
-- settings.
local function outlets(self)
  return { chat = self:isChatLinesOn(), toast = self:isToastsOn() }
end

-- New Feed entries from other Members, new Reactions to your own and
-- Spare notices are Live events once settled: each goes to the outlets
-- that are on (feedEntry, reaction and spare carry them), and is seen once
-- it has. With both off nothing is announced or seen, so they wait for
-- While you were away. Entries already seen (a gave entry your notice
-- covers) make none.
-- A Feed entry as a Live event: as describe() gives it, plus figure (the
-- class of the Member's shown Character, for the toast's figure) while
-- the Camp is on and the Roster shows the Member. A rare find has none: its
-- toast shows the item.
local function liveEntry(self, entry)
  local described = self.log:describe(entry)
  if described.memberId and described.kind ~= "rareFind" and self:setting("camp") then
    for _, row in ipairs(ns.Roster.rows(self.ledger, self.now())) do
      if row.memberId == described.memberId then described.figure = row.classFilename end
    end
  end
  return described
end

local function announce(self, entries, reactions, notices)
  if not self.log:isSettled() then return end
  local to = outlets(self)
  if not (to.chat or to.toast) then return end
  for _, entry in ipairs(entries) do
    if not entry.seen then
      self.log:markSeen(entry)
      self.listener("feedEntry", liveEntry(self, entry), to)
    end
  end
  for _, item in ipairs(reactions or {}) do
    self.log:markSeen(item.reaction)
    self.listener("reaction", self.log:news(item), to)
  end
  for _, news in ipairs(notices or {}) do
    self.spareLife:markSeen(news)
    self.listener("spare", self.spareLife:describe(news), to)
  end
end

-- A record changed: Crew goals newly reached each make a Crew-wide Feed
-- entry, announced like any other. Quiet when the Members counted changed
-- rather than their progress: those rungs are only recorded.
local function checkGoals(self, quiet)
  if not self.db.crew then return end
  local reached = self.crewGoals:check(quiet)
  if #reached > 0 then announce(self, self.log:goalsReached(reached)) end
end

-- Writes the Play times summary into the own record, if it may have
-- changed and the record exists. Returns true if the record changed.
local function writePlayTimes(self)
  if not (self.playTimesDue and self.ledger:own()) then return false end
  self.playTimesDue = false
  return self.ledger:setPlayTimes(self.playTracker:summary())
end

-- Play times changing alone rides the next send. Along with another
-- change, that change's send and changed event cover it.
local function sharePlayTimes(self, otherChange)
  if writePlayTimes(self) and not otherChange then
    self.gossip:ownChanged("later")
    self.listener("changed")
  end
end

-- The own record's display name or left flag changed: it goes out now.
local function sendOwnNow(self)
  self.gossip:ownChanged("now")
end

-- The current state of the Character being played, from Snapshot: guid,
-- name, classFilename, level, xp, maxXp, zone, deaths, money (copper) and
-- professions (as Professions.read reads them, nil if never read).
function Core:updateOwn(character)
  local changed, before = self.ledger:updateOwn(character)
  -- The first report after login brings the Play times up to date.
  sharePlayTimes(self, changed)
  if changed then
    -- Your own events go into the Feed only while in a Crew.
    local entries = self.db.crew and self.log:ownChanged(before, character.guid) or {}
    -- Feed news goes out now, even a professions-only change.
    self.gossip:ownChanged(#entries > 0 and "now" or ns.Gossip.urgency(before, character))
    -- Professions first known change who counts, as for others.
    checkGoals(self, ns.Goals.professionsFirstKnown(before, self.ledger:own().characters[character.guid]))
    self.listener("changed")
  end
end

-- The Member ids of a party as the game reads it ({ guid, name } per
-- member, either nil when secret): you, and each held Member of the Crew
-- (not Left) owning a Character with that GUID, or else that name.
-- Strangers aren't named.
local function partyMembers(self, party)
  local you = self.ledger:memberId()
  local found = { [you] = true }
  local list = { you }
  local function owner(guid, name)
    for id, record in self.ledger:records() do
      if not record.left then
        for _, character in pairs(record.characters) do
          if guid and character.guid == guid then return id end
          if not guid and name and character.name:lower() == name:lower() then return id end
        end
      end
    end
  end
  for _, unit in ipairs(party) do
    if type(unit) == "table" then
      local guid = type(unit.guid) == "string" and unit.guid or nil
      local name = type(unit.name) == "string" and unit.name or nil
      local id = owner(guid, name) or (guid and name and owner(nil, name))
      if id and not found[id] then
        found[id] = true
        list[#list + 1] = id
      end
    end
  end
  table.sort(list)
  return list
end

-- A boss died (ENCOUNTER_END): { encounterId, success, instanceType (from
-- GetInstanceInfo: "party", "raid", ...), party ({ guid, name } per
-- member, you included) }, with any secret value read as nil. A known final
-- boss killed in a party or raid instance, in a Crew, is a clear: it goes
-- into your record with the Crew's Members in the party, and out with the
-- rest of it (not while the link is down: in lockdown). The Crew's first
-- clear of an instance is a trophy and a Crew-wide Feed entry, like a
-- goal's. Returns the instance's name, or nil and why not: "unreadable",
-- "wipe", "notInstance", "unknown" (not a final boss known) or "noCrew".
function Core:encounterEnded(encounter)
  local name, reason = ns.Clears.cleared(encounter, self.finalBosses)
  if not name then return nil, reason end
  if not self.db.crew then return nil, "noCrew" end
  local members = partyMembers(self, encounter.party)
  local now = self.now()
  local changed = self.ledger:changeOwn(function(record) return ns.Clears.add(record, name, now, members) end)
  if changed then
    self.gossip:ownChanged("now")
    checkGoals(self)
    self.listener("changed")
  end
  return name
end

-- Something was fished (LOOT_READY): the loot as Catches.read gives it
-- ({ items, zone, subzone, mapId }), nil when it isn't from fishing. Each item goes into your record under its type (a fish
-- family's every weight counts as the family), the first catch of a type
-- with when and where, every catch adding to its count; an item not on
-- the list is kept as an unlisted catch, up to Catches.UNLISTED_CAP. Kept
-- outside a Crew too, and shared with the next send, as professions are.
-- In a Crew, the Crew's first catch of a rare type makes a Feed entry and
-- goes out now, and types caught can reach a Crew goal step. Returns true
-- if your record changed.
function Core:caught(loot)
  if not self.ledger:own() then return false end
  local now, character = self.now(), self.ledger:playing()
  local had = ns.Catches.rareHeld(self.ledger:own())
  local changed = self.ledger:changeOwn(function(record) return ns.Catches.add(record, loot, now, character) end)
  if changed then
    local entries = self.db.crew and self.log:ownCaught(had) or {}
    self.gossip:ownChanged(#entries > 0 and "now" or "later")
    checkGoals(self)
    self.listener("changed")
  end
  return changed
end

-- The Crew's catches, over every Member held who hasn't left, you
-- included: total (how many types count, Extras not among them), caught
-- (how many of those someone has caught), title ("The Crew has caught 3
-- of 46 types."), waters (Catches.WATERS: { id,
-- name, zones }, lowest first), types (every type in the list's order:
-- id, itemId (the item whose name and icon the game shows), items (every
-- item ID that counts as it), name (English, for when the item isn't
-- cached), kind ("fish", "quest", "bloated", "family", "contest",
-- "treasure" or "notFish"), waters (water ids, lowest first), extra (nil
-- when it counts, else why not: "season", "contest", "unconfirmed",
-- "questItem" or "notFish"), count (the
-- Crew's catches of it), note (a line for its tooltip, or nil), first
-- (nil until caught) and others (every other Member who caught it, in
-- the order they first did: memberId, displayName, own)) and unlisted
-- (each fished item not on the list, the earliest first: itemId, count,
-- first, others).
-- first is the earliest catch across the Crew: memberId, displayName, own,
-- character and classFilename (nil if the record no longer has the
-- Character), time, since (in words: "5m ago"), zone, subzone, mapId, who
-- ("You" for your own, else the display name) and text (who and where in
-- words: "Bob (Bobby), Westfall, The Jansen Stead, 5m ago").
function Core:catches()
  local records = {}
  for _, record in self.ledger:records() do
    if not record.left then records[#records + 1] = record end
  end
  return ns.Catches.collect(records, self.ledger:memberId(), self.now())
end

-- The Catches tab, ready to render: the Crew's catches (catches()) as a
-- field guide, grouped by group ("where", default, or "type") and
-- filtered by show ("all", default, "fish", "rare", "extras" or
-- "missing"), naming types not caught yet while the catchesNames
-- setting is on. caught, total, done (every counted type caught), count
-- ("25 of 46 types caught"), countOf ("of 46 types caught", to go after
-- the number; nil once done), next (the next trophy step, in words), fill
-- (0–1) and ticks (each trophy step but the last, 0–1 along the bar);
-- group and show, the menus: title, label ("Show: All"), options ({ id,
-- label, picked, and for show count: the tiles it shows }) and, on show,
-- names ({ label, value }, the setting); sections, each { title, sub
-- (the zones, or "Not counted"), count ("8 / 12", "2 caught" or nil),
-- counted and got (the counted types and how many are caught; nil when
-- it doesn't count), done, none ("Nothing caught here yet" for New on
-- Forever with nothing in it) and tiles }; empty ({ title, text }, while
-- the Crew has caught nothing), filtered ({ title, text }, when show
-- leaves nothing); recentTitle; and recent (up to 3 first catches from
-- the last 3 days, newest first: itemId, name, first, caught ("caught",
-- between who and the item) and when ("Feralas · 5h ago")). A tile, a
-- type or an unlisted catch: id, itemId, name (English, or "Item 123"
-- for an unlisted one, for while the game hasn't the item), caught,
-- named (its name may show), fresh (first caught in the last 3 days),
-- extra, unlisted, first (as catches()) and tooltip: unnamed ("???", the
-- name while it can't show), note, extra, firstBy ("First caught by") and
-- first, when ("2 days ago · Feralas"), crew ("The Crew has caught") and
-- count, also ("Also caught by Tor and you"), none, hint (how to show
-- names) and where ("Where: Level 30–45, Level 40–55"), each nil when it
-- doesn't apply. A section's count is over all its tiles, not only those
-- Show leaves. See docs/design/catches.md.
function Core:catchesTab(group, show)
  local own = self.ledger:own()
  local playing = own and own.characters and own.characters[self.ledger:playing() or ""]
  return ns.Catches.tab(self:catches(), {
    group = group,
    show = show,
    names = self:setting("catchesNames"),
    now = self.now(),
    level = playing and playing.level,
  })
end

-- The panel's rows, ready to render, sorted by order: "online" (default),
-- "level" or "name". Your own row comes first. Each row is a Member whose
-- Characters weren't all unseen for 30 days: memberId, displayName, own,
-- online, lastSeen, sinceSeen (seconds since lastSeen), onAlt (playing a Character other than the Main),
-- mainSet (the Main was chosen, rather than the most recently played),
-- altsCanPlay, via (display name of the Member whose message brought their
-- record, if not their own) and alts, plus the shown Character: the one
-- being played while online, else the Main. A Character, shown or alt, has
-- guid, name (the first name), fullName ("First Last" on Forever, else
-- name), classFilename, level, xp, maxXp, zone, deaths, money (copper,
-- nil if its client never shared it), professions (nil if its client never
-- shared them, else up to 5 { skillLine, name, icon, skill, max, secondary,
-- rank ("Apprentice" to "Artisan", from max), full (skill at max), capped
-- (skill at Professions.CAP) }, main professions first), mapId, x, y and
-- instance (where last seen; see mapPins()), lastPlayed, sinceSeen,
-- lastSeenText (Last seen in words: "5m ago"; on a row "online" while
-- online, and nil on your own), playing (being played right now), main and
-- canPlay (within Core.CAN_PLAY_LEVELS of the Character you play). Each
-- row also has status, the finished right-hand text ("by the fire" and
-- "asleep · 5m ago" with the Camp on, else lastSeenText; nil on your own),
-- and each other Member's row section, the label of the Roster section it
-- sits in ("BY THE FIRE" and "ASLEEP IN CAMP" when sorted Online first with
-- the Camp on, else "CREW").
function Core:rows(order)
  return ns.Camp.wordRows(ns.Roster.rows(self.ledger, self.now(), order), self:setting("camp"), order)
end

-- The Professions tab: professions, a { skillLine, name, icon, secondary,
-- had (some Character shown has it) } for each of the twelve (main ones by
-- name, then cooking, fishing and first aid) and any other a Character shown
-- has, after its kind; and members, a row per Member the Roster shows (as
-- rows(order): yours first), or sorted by the profession with skill line
-- sortBy (yours still first, then best skill in it). A member has memberId,
-- own, displayName, known (false if none of their Characters' clients ever
-- shared professions) and cells: per profession, false for none, or the
-- best skill among their Characters (skill, max, rank, full, capped) and
-- characters, each Character who has it (name, fullName, classFilename, alt, skill,
-- max, rank, full, capped), best first.
function Core:professions(order, sortBy)
  return ns.Professions.tab(ns.Roster.rows(self.ledger, self.now(), order), sortBy)
end

-- The Together tab: the Crew's Characters and the game's dungeons on one
-- level line, ready to lay out (docs/design/together.md), or nil before
-- you play a Character. measure(text, font) gives a text's width in pixels
-- in Skin's "small" or "tiny" font; without it widths are estimated.
-- selected is the memberIds picked on the line (see selectTogether). The
-- Show menu's choices are the together* settings.
-- Positions are pixels from level 1's left edge, in Core.TOGETHER_LAYOUT's
-- geometry: as (the Character you play: name, classFilename, level, alt),
-- hidden ("3 alts, 2 offline hidden", or nil), selected (the picked memberIds Core knows), clear ("Clear" while any
-- are picked, else nil), show (the Show menu: label, sections of { title,
-- options: key (the setting), label, value }, key { title, items of
-- { kind, text } } and help), empty (with only near your level on: text,
-- action, setting (what the action turns off) and spans of { left, right } with nothing in a lane; else nil),
-- width, you (your level's x), band ({ left, right, text } for can play),
-- ticks (per level: level, x, big, number, you), groups (a group per level
-- of the Characters shown: level, x, label, alt, own, online,
-- classFilename, count, more, row (1 nearest the axis, nil when only the
-- dot shows), labelX, labelWidth, memberIds (the other Members a click
-- picks), faded, and characters: memberId, member ("You" for yours), name,
-- fullName, classFilename, level, alt, online, own, canPlay and apart), bars (a
-- dungeon each, or the raids' one: name, kind ("dungeon",
-- "attunement" or "raids"), forever (new in WoW: Forever), from, to,
-- fits, count, dots (class of each Member who fits, up to 4), moreDots, x,
-- width, lane (1 nearest the axis; every bar has one), shared, faded and
-- tooltip: title,
-- detail, forever, raids (name, detail, forever), you, fits, fitters
-- (memberId, member, name, fullName, classFilename, level, online, far), none and
-- almost), and lanes (how many lanes the bars take).
function Core:together(measure, selected)
  return ns.Together.view(ns.Roster.rows(self.ledger, self.now()), measure, {
    selected = selected,
    filters = {
      offline = self:setting("togetherOffline"),
      alts = self:setting("togetherAlts"),
      near = self:setting("togetherNear"),
      attunements = self:setting("togetherAttunements"),
      raids = self:setting("togetherRaids"),
    },
  })
end

-- Picking friends on the Together line: selected (memberIds picked so
-- far), memberIds (a clicked label's or dot's, its group's memberIds) and
-- add (shift held) give the new selection. Clicking what's picked clears
-- it; your own dot (no memberIds) changes nothing.
Core.selectTogether = ns.Together.select

-- The world map's pins: one per other Member the panel shows whose shown
-- Character (being played while online, else the Main) has a known spot,
-- unsorted. A pin has memberId, displayName, name, fullName, classFilename, level,
-- mapId, x and y (0–1 on that map), zone, instance (the instance's name
-- while inside one, the spot then being the last one outside), online,
-- sinceSeen (seconds since the Member was last seen) and lastSeenText (as
-- rows() words it).
function Core:mapPins()
  local pins = {}
  for _, row in ipairs(ns.Roster.rows(self.ledger, self.now())) do
    if not row.own and row.mapId and row.x and row.y then
      pins[#pins + 1] = {
        memberId = row.memberId,
        displayName = row.displayName,
        name = row.name,
        fullName = row.fullName,
        classFilename = row.classFilename,
        level = row.level,
        mapId = row.mapId,
        x = row.x,
        y = row.y,
        zone = row.zone,
        instance = row.instance,
        online = row.online,
        sinceSeen = row.sinceSeen,
        lastSeenText = row.lastSeenText,
      }
    end
  end
  return pins
end

-- The Camp: the Crew as a campsite `columns` art pixels wide (the band's
-- width in art pixels, which only UI knows), or nil while the Camp setting
-- is off. Positions are art pixels from the fire's centre, in
-- Core.CAMP_LAYOUT's geometry: { columns, actors, graves, tent, more }.
-- actors are every Member the Roster shows, you first, as many as fit:
-- { memberId, pose ("seated" or "asleep"), label ("You" or the display
-- name), classFilename (of the Character the Roster shows), x (the
-- figure's left edge), width (the figure's), labelWidth (room for the name
-- above it), spark (max level in the last day), you }. graves are { memberId,
-- x, flower (anyone paid Respects) }, a death each in the last day; tent is
-- { x } when there's room; more counts the Members that didn't fit, nil
-- when all did, and moreText words it ("+2 more"). Derived on read: no record changes and nothing is sent.
-- See docs/design/camp.md.
function Core:camp(columns)
  if not self:setting("camp") then return nil end
  local now = self.now()
  return ns.Camp.view(ns.Roster.rows(self.ledger, now), self.log:since(now - ns.Camp.RECENT), now, columns)
end

-- Counts for the title and minimap button: online, members, canPlay (online
-- Members whose Character being played can play with you), hidden
-- (Characters unseen for Core.HIDE_AFTER_DAYS) and spares (others'
-- open Spares one of your Characters is high enough level for), and
-- header, the panel header's finished count ("1 of 4 online", or "2 of 5
-- by the fire", you counted, with the Camp on).
function Core:summary()
  local summary = ns.Roster.summary(self.ledger, self.now())
  summary.spares = self.spareLife:usableCount()
  summary.header = ns.Camp.header(summary, self:setting("camp"))
  return summary
end

-- Whether someone went online or offline since last checked.
local function onlineChanged(self)
  local online = ns.Roster.online(self.ledger, self.now())
  local differs = false
  for id in pairs(online) do
    if not self.online[id] then differs = true end
  end
  for id in pairs(self.online) do
    if not online[id] then differs = true end
  end
  self.online = online
  return differs
end

-- Fires changed if someone went online or offline since last checked.
local function checkOnline(self)
  if onlineChanged(self) then self.listener("changed") end
end

-- Sync has settled after an initial login: While you were away goes out
-- if the popup is on and there's anything unseen, which is then seen. The
-- summary is { members, count, noticed }: a Member has memberId,
-- displayName, main and classFilename (their Main), time (latest
-- activity), characters (a row per Character with events, the Main's
-- first: name, main, from, level, deaths, new, maxLevel, and the cheer and
-- respects buttons, each nil when it doesn't apply), highlights ({ kind,
-- text } for max level, joined and left) and welcome. A button is { key,
-- reacted }, the key for react(). noticed is Your Crew noticed, newest
-- first: { text, reaction, time } per own entry with unseen Reactions.
-- goals is the Crew goals reached ({ text, time }), and spares the
-- Spare notices, then the Gives, each newest first: { kind
-- ("claimed", "given" or "gave"), text, time }. catches is the line of
-- others' new types you haven't been told of ({ kind = "catches", text
-- }, if any), then the rare finds missed, newest first ({ kind, text,
-- time, icon, cheer }). With the Camp on, camp is
-- the Camp at Core.CAMP_LAYOUT.awayColumns without the tent, each actor
-- with gained (its Main's, as the scoreboard words it, nil with nothing
-- gained) and highlight (max level), and intro is in the Camp's voice.
local function awaySummary(self)
  if not self:isAwayPopupOn() then return end
  local view, told = self:catches(), self.db.catchTypesTold
  local newTypesLine = told and ns.Catches.newTypesLine(view, told)
  -- With none saved yet (the first login with this), it's a silent baseline.
  self.db.catchTypesTold = ns.Catches.markTold(told or {}, view)
  local summary = self.log:takeSummary(self.spareLife:takeNews(), newTypesLine)
  if not summary then return end
  if self:setting("camp") then
    local now = self.now()
    summary.camp, summary.intro = ns.Camp.away(ns.Roster.rows(self.ledger, now),
      self.log:since(now - ns.Camp.RECENT), now, summary)
  end
  self.listener("awaySummary", summary)
  self.listener("changed")
end

-- Called once a second. Core decides what is due.
function Core:tick()
  -- Counts the second played.
  if self.playTracker:tick() then self.playTimesDue = true end
  sharePlayTimes(self)
  self.gossip:tick()
  if self.log:tick() then awaySummary(self) end
  if self.db.crew and self.crewGoals:tick() then
    -- A Crew's first sync: what it has isn't news to you, as for its goals.
    self.db.catchTypesTold = self.db.catchTypesTold or ns.Catches.markTold({}, self:catches())
    self.listener("changed")
  end
  if self.db.crew then self.spareLife:tick() end
  checkOnline(self)
end

-- The Goals tab: a row per Crew goal track (Crew levels, Everyone at level
-- N, Crew deaths, Every profession in the Crew, Crew skill, Everyone a
-- Journeyman): { track, title, rung (the next one, nil when complete),
-- value and goal (the progress bar, value out of goal; nil when complete),
-- unit, complete, reached (how many rungs it has reached), last ({ rung,
-- time, date ("3 Nov"), label }: the highest reached, or nil) }. For Everyone at level N and Everyone a Journeyman, value counts the
-- Members at the next rung, out of every Member. Every profession in the
-- Crew also has professions: the twelve as { skillLine, name, icon, lit }.
-- No Member is named.
function Core:goals()
  local rows = self.crewGoals:rows()
  for _, row in ipairs(rows) do
    if row.last then row.last.date = ns.Text.shortDate(row.last.time, self.utcOffset) end
  end
  return rows
end

-- The Goals tab's trophies: every Crew goal rung reached and every
-- instance the Crew has cleared, newest first on the shelf, the cabinet's
-- dungeon and raid grids and goal rungs by track, with the latest win and
-- how many others were reached since the tab was last opened (see
-- Goals:trophies).
-- Each trophy also has date, its time as a short local date: "3 Nov".
-- Call openGoals() first, so that count holds through a visit.
function Core:trophies()
  local trophies = self.crewGoals:trophies()
  for _, trophy in ipairs(trophies.shelf) do trophy.date = ns.Text.shortDate(trophy.time, self.utcOffset) end
  return trophies
end

-- The Goals tab is shown: call it on every draw, before trophies(). It
-- starts a visit if none is open.
function Core:openGoals()
  self.crewGoals:open()
end

-- The Goals tab was left (another tab, or the panel hidden).
function Core:leaveGoals()
  self.crewGoals:leave()
end

-- The Feed tab: { days = { { daysAgo, time, title, entries } }, unseen },
-- newest first, where unseen counts others' entries and Reactions to your
-- own not yet shown, and a day's title is "TODAY", "YESTERDAY" or "MONDAY
-- 02 NOVEMBER", in local time. An entry has kind ("ding", "death",
-- "newCharacter", "maxLevel", "joined", "left", "newProfession",
-- "professionSkill", "professionMaxed", "rareFind" (the Crew's first catch
-- of a rare type; icon and edge are the item's) or "goal": a Crew goal reached,
-- with no memberId), time, memberId, guid (for Character events), text,
-- from (the level before a ding or max level, or the skill before a
-- profession milestone), level, count (deaths), skillLine, profession (its
-- name), milestone and icon (for profession kinds), own, seen (false while
-- it has unseen Reactions), highlight (the news: max level, joined, a Crew
-- goal, a profession maxed) and new (New in the open Feed visit; see
-- openFeed()). And for Reactions: reaction ("cheer", "respects" or
-- "welcome", nil for left), key (for react()), reactors ({ memberId, name,
-- you }, in the order they reacted, name "You" for you), reacted (you
-- have) and canReact (not yours, and it has a key).
function Core:feed()
  return self.log:view(self.utcOffset)
end

-- The When tab, in the viewer's local time: grid (7 days from Monday, each
-- 24 hours from 00:00), max (the most a cell can hold), empty (every cell
-- 0), and the rules for the wording: weeks (how many are kept), usually
-- (weeks played to usually play) and minutes (to count as played). Without
-- memberId, the Crew: each cell counts the Members your Roster shows who
-- usually play then, out of max. With one, that
-- Member's weeks played (0–4) per hour, displayName, collectingSince (when
-- they started, while under a week ago) and noData (their BFF shares no
-- Play times); nil for a Member the Roster doesn't show. And the words:
-- title (the Crew, "You" or the Member's name), intro (what the grid
-- shows) and note (no data, collecting since, or nothing to show; nil
-- when there's nothing to say).
function Core:playTimes(memberId)
  local now = self.now()
  local PlayTimes = ns.PlayTimes
  local rows = ns.Roster.rows(self.ledger, now)
  local function view(values, max)
    return {
      grid = PlayTimes.grid(values, self.utcOffset),
      max = max,
      empty = PlayTimes.isEmpty(values),
      weeks = PlayTimes.WEEKS,
      usually = PlayTimes.USUALLY,
      minutes = PlayTimes.PLAYED_MINUTES,
    }
  end

  if memberId == nil then
    local summaries = {}
    for _, row in ipairs(rows) do
      summaries[#summaries + 1] = self.ledger:record(row.memberId).playTimes
    end
    local result = view(PlayTimes.usuallyPlaying(summaries, now), #rows)
    result.title = "The Crew"
    result.intro = ("How many of the %d Members usually play each hour: in %d of the last %d weeks. Your local time.")
      :format(result.max, result.usually, result.weeks)
    if result.empty then
      result.note = ("Nobody usually plays at any hour yet. It takes %d weeks of play to show."):format(result.usually)
    end
    return result
  end

  for _, row in ipairs(rows) do
    if row.memberId == memberId then
      local summary = self.ledger:record(memberId).playTimes
      local since = summary and summary.since
      local result = view(PlayTimes.weeksPlayed(summary, now), PlayTimes.WEEKS)
      result.memberId = memberId
      result.displayName = row.displayName
      result.own = row.own == true
      result.noData = summary == nil
      result.collectingSince = since and now - since < PlayTimes.WEEK and since or nil
      local name = result.own and "You" or row.displayName or "?"
      result.title = name
      result.intro = ("How many of the last %d weeks %s played each hour. Your local time.")
        :format(result.weeks, result.own and "you" or name)
      if result.noData then
        result.note = ("%s's BFF doesn't share Play times yet."):format(name)
      elseif result.collectingSince then
        result.note = ("Collecting since %s: less than a week of data so far.")
          :format(ns.Text.shortDate(result.collectingSince, self.utcOffset))
      elseif result.empty then
        result.note = ("No hour played for %d minutes or more in the last %d weeks.")
          :format(result.minutes, result.weeks)
      end
      return result
    end
  end
  return nil
end

-- How many of others' Feed entries, and Reactions to your own, haven't
-- been shown yet.
function Core:unseen()
  return self.log:unseen()
end

-- Reacts to someone else's Feed entry, with a key from feed() or the
-- summary. It goes into your record and out with your next DATA, so it
-- works in combat and offline. Ignores your own entries, Removed Members,
-- entries that can't be reacted to, and those you already reacted to.
-- Returns true, or false and "reacted" when you already had.
function Core:react(key)
  local reason
  key, reason = self.log:react(key)
  if not key then return false, reason end
  self.ledger:addReaction(key)
  self.gossip:ownChanged("now")
  self.listener("changed")
  return true
end

-- The Spares tab: { crew, yours, unseen, claims, maxClaims, open,
-- maxOpen }. crew is other Members' open Spares, newest first: {
-- ownerId, owner (display name), id, item (the item string to resolve),
-- link (the game's link, nil until cached), level (required), time
-- (posted), expires (seconds left), usable (one of your Characters is
-- high enough level), winner ({ memberId, name, character, you }, nil
-- without Claims), claims (how many), claimed (you have), claimCharacter
-- (yours is for), canClaim and state (the Claim state in words) }. yours
-- is your own, open or Given, newest first: { id, item, link, level,
-- time, expires, winner, claims, given ({ memberId, name, character }
-- once Given), canGive, canWithdraw, state }. unseen counts notices not
-- yet shown, claims and open your open Claims and Spares, out of
-- maxClaims and maxOpen. Each row also comes worded: info (the line under
-- the item: who posted it or how long is left, and the Claim state),
-- primary and secondary (the buttons shown: { label, enabled } for Claim
-- or Give, { label } for Withdraw; nil when not shown), highlight (a
-- winning Claim of yours, a Claim on yours, or your item gone) and dimmed
-- (none of your Characters is high enough level, or yours was Given).
-- claimFor lists your Characters a Claim can be for, Main first: { guid,
-- label ("Jaina (30)") }.
function Core:spares()
  local view = self.spareLife:view()
  local claimFor = {}
  local own = ns.Roster.rows(self.ledger, self.now())[1]
  if own and own.own then
    local characters = { own }
    for _, alt in ipairs(own.alts) do characters[#characters + 1] = alt end
    for _, character in ipairs(characters) do
      local entry = { guid = character.guid, label = ("%s (%d)"):format(character.name, character.level) }
      if character.main then table.insert(claimFor, 1, entry) else claimFor[#claimFor + 1] = entry end
    end
  end
  view.claimFor = claimFor
  return view
end

-- An own write that others should get now.
local function ownWrite(self)
  self.gossip:ownChanged("now")
  self.listener("changed")
end

-- Offers an item to the Crew: an item link (or item string), the level it
-- needs and, optionally, what the bags say about it: { guid (its item
-- GUID), isBound (C_Item.IsBound), bindType (14th return of
-- C_Item.GetItemInfo) }. An item that can't be traded is refused. The
-- GUID is kept for the Character being played (see spareItems) and
-- never goes in the record. Returns the Spare's id, or nil and
-- "noCrew", "invalidItem", "bound", "questItem", "accountBound" or
-- "tooMany" (20 open already).
function Core:postSpare(link, level, inBags)
  local id, reason = self.spareLife:post(link, level, inBags)
  if id then ownWrite(self) end
  return id, reason
end

-- The item GUIDs of the open Spares the Character being played
-- posted, { [id] = itemGuid }, so the game side can tell when an item
-- has left the bags.
function Core:spareItems()
  return self.spareLife:items()
end

-- Withdraws an own open Spare. Returns true, or nil and "unknown".
function Core:withdrawSpare(id)
  local ok, reason = self.spareLife:withdraw(id)
  if ok then ownWrite(self) end
  return ok, reason
end

-- Gives an own open Spare to the winning Claim's Character, which
-- is final: every client shows that recipient from then on. It's for
-- after you've mailed the item, which BFF can't see. expected is the winner's Member id as you were shown
-- it, if any, so an earlier Claim arriving meanwhile isn't Given to
-- unseen. Returns true, or nil and "unknown", "noClaim" or
-- "winnerChanged".
function Core:giveSpare(id, expected)
  local ok, reason = self.spareLife:give(id, expected)
  if ok then ownWrite(self) end
  return ok, reason
end

-- The bags have settled (BAG_UPDATE_DELAYED): checks where the item of
-- each open Spare the Character being played posted is
-- (docs/adr/0004). Never call it before the first BAG_UPDATE_DELAYED of a
-- session: until then the bags read as empty. A gone item is noted on
-- your tab (row.gone); at the first check after a real login one with no
-- Claim is withdrawn, and the listener hears ("spareGone", { action
-- = "withdrawn", id, item, link }), and for one with a Claim, ({ action =
-- "ask", id, item, link, winner }), to ask whether to Give or withdraw it.
function Core:bagsUpdated()
  if self.spareLife:bagsUpdated(function() ownWrite(self) end) then self.listener("changed") end
end

-- Claims another Member's open Spare for one of your Characters by
-- GUID, by default the one being played. It goes into your record and
-- out with your next DATA, so it works in combat and offline. Returns
-- true, or nil and "own", "unknown", "claimed", "tooManyClaims"
-- (20 open) or "unknownCharacter".
function Core:claimSpare(owner, id, guid)
  local ok, reason = self.spareLife:claim(owner, id, guid)
  if ok then ownWrite(self) end
  return ok, reason
end

-- Withdraws your Claim, until the Spare is Given. Returns true, or
-- nil and "notClaimed" or "given".
function Core:withdrawClaim(owner, id)
  local ok, reason = self.spareLife:withdrawClaim(owner, id)
  if ok then ownWrite(self) end
  return ok, reason
end

-- How many Spare notices haven't been shown yet, for the sidebar.
function Core:unseenSpares()
  return self.spareLife:unseen()
end

-- The Spares tab was opened: every notice is seen.
function Core:sparesSeen()
  if self.spareLife:markAllSeen() then self.listener("changed") end
end

-- The Feed tab is shown: call it on every draw, before reading feed().
-- It starts a Feed visit if none is open, and every entry and Reaction
-- unseen now is New in feed() until leaveFeed(), and is seen.
function Core:openFeed()
  if self.log:open() then self.listener("changed") end
end

-- The Feed tab was left (another tab, or the panel hidden): the visit
-- ends, and nothing is New.
function Core:leaveFeed()
  self.log:leave()
end

-- Settings: the local preferences, one list of them. Each has its key, the
-- Settings page's section and label (finished text), its kind ("toggle"
-- for on/off, "sound" or "position"), its default, and how it's saved in
-- db, as earlier versions saved it so nothing needs migrating. Adding an
-- on/off setting with a section here puts it on the Settings page; the
-- Together tab's Show menu choices have none, and show only in that menu.
-- Display name isn't one: it's part of your Member record. See
-- docs/design/settings-and-release.md.

-- The table a setting is saved in: db itself, or one inside it.
local function savedIn(db, parent)
  if not parent then return db end
  db[parent] = db[parent] or {}
  return db[parent]
end

-- On/off, saved as field = true while off and nil while on.
local function offFlag(field, parent)
  return {
    read = function(db) return not savedIn(db, parent)[field] end,
    write = function(db, on) savedIn(db, parent)[field] = not on or nil end,
  }
end

-- On/off, saved as field = true while on and nil while off.
local function onFlag(field, parent)
  return {
    read = function(db) return savedIn(db, parent)[field] == true end,
    write = function(db, on) savedIn(db, parent)[field] = on and true or nil end,
  }
end

-- A value saved as nil while it's the default.
local function nilAsDefault(field, default)
  return {
    read = function(db)
      local value = db[field]
      if value == nil then return default end
      return value
    end,
    write = function(db, value)
      if value == default then value = nil end
      db[field] = value
    end,
  }
end

-- A screen position, saved as { x, y } or nil; read as a copy, so two
-- reads are the same when their x and y are.
local function screenPosition(field)
  return {
    read = function(db)
      local saved = db[field]
      return saved and { x = saved.x, y = saved.y } or nil
    end,
    write = function(db, value)
      db[field] = value and value.x and { x = value.x, y = value.y } or nil
    end,
    same = function(a, b)
      if a == nil or b == nil then return a == b end
      return a.x == b.x and a.y == b.y
    end,
  }
end

-- The panel's size limits and the size it opens at, in UI units.
Core.PANEL_MIN_WIDTH, Core.PANEL_MIN_HEIGHT = 460, 380
Core.PANEL_WIDTH, Core.PANEL_HEIGHT = 640, 520
Core.PANEL_MAX_WIDTH, Core.PANEL_MAX_HEIGHT = 900, 800

local function round(value)
  return math.floor(value + 0.5)
end

local function clamp(value, low, high)
  return math.max(low, math.min(high, value))
end

-- The panel's size and position, saved as { width, height, left, top } in
-- whole UI units (left and top from the screen's bottom left), or nil for
-- the default size, centred. The size is kept within the panel's limits;
-- staying on screen is panelPlace()'s, since the screen can change.
local function windowPlace(field)
  return {
    read = function(db)
      local saved = db[field]
      return saved and { width = saved.width, height = saved.height, left = saved.left, top = saved.top } or nil
    end,
    write = function(db, value)
      if not (value and value.width) then
        db[field] = nil
        return
      end
      db[field] = {
        width = clamp(round(value.width), Core.PANEL_MIN_WIDTH, Core.PANEL_MAX_WIDTH),
        height = clamp(round(value.height), Core.PANEL_MIN_HEIGHT, Core.PANEL_MAX_HEIGHT),
        left = round(value.left),
        top = round(value.top),
      }
    end,
    same = function(a, b)
      if a == nil or b == nil then return a == b end
      return a.width == b.width and a.height == b.height and a.left == b.left and a.top == b.top
    end,
  }
end

-- The toast sound's default: the name UI plays it by.
Core.DEFAULT_TOAST_SOUND = "UI_BNET_TOAST"

local SHARING = "Sharing"
local NOTIFICATIONS = "Notifications and display"
local TOASTS = "Toasts"

local SETTINGS = {
  {
    key = "paused", section = SHARING, kind = "toggle",
    label = "Appear offline: send nothing, so your Crew sees you as offline",
    saved = onFlag("paused"),
  },
  {
    key = "chatLines", section = NOTIFICATIONS, kind = "toggle",
    label = "Chat message for live events",
    saved = offFlag("chatLinesOff"),
  },
  {
    key = "awayPopup", section = NOTIFICATIONS, kind = "toggle",
    label = "Show While you were away on login",
    saved = offFlag("awayPopupOff"),
  },
  -- LibDBIcon reads hide from the button's own table (minimapIcon()).
  {
    key = "minimap", section = NOTIFICATIONS, kind = "toggle",
    label = "Show minimap button",
    saved = offFlag("hide", "minimap"),
  },
  -- The Camp (camp()), and its wording in rows(), summary() and the rest.
  {
    key = "camp", section = NOTIFICATIONS, kind = "toggle",
    label = "Show the Camp",
    saved = offFlag("campOff"),
  },
  -- The panel's size and position (panelPlace()); the page shows a reset.
  {
    key = "panelPlace", section = NOTIFICATIONS, kind = "panelPlace",
    label = "Reset BFF window",
    saved = windowPlace("panelPlace"),
  },
  {
    key = "toasts", section = TOASTS, kind = "toggle",
    label = "Show toasts for live events",
    saved = offFlag("toastsOff"),
  },
  -- The name UI plays it by, or "none".
  {
    key = "toastSound", section = TOASTS, kind = "sound",
    label = "Sound",
    saved = nilAsDefault("toastSound", Core.DEFAULT_TOAST_SOUND),
  },
  -- The centre of the first toast, as { x, y } from the screen's bottom
  -- left; nil for the default.
  {
    key = "toastPosition", section = TOASTS, kind = "position",
    label = "Move toasts",
    saved = screenPosition("toastPosition"),
  },
  -- The Together tab's Show menu (together().show), saved in db.together.
  { key = "togetherOffline", kind = "toggle", saved = offFlag("offlineOff", "together") },
  { key = "togetherAlts", kind = "toggle", saved = onFlag("alts", "together") },
  { key = "togetherNear", kind = "toggle", saved = onFlag("near", "together") },
  { key = "togetherAttunements", kind = "toggle", saved = offFlag("attunementsOff", "together") },
  { key = "togetherRaids", kind = "toggle", saved = onFlag("raids", "together") },
  -- The Catches tab's names of types not caught yet (catchesTab()), saved
  -- in db.catches.
  { key = "catchesNames", kind = "toggle", saved = onFlag("names", "catches") },
}

local SETTING = {}
for _, setting in ipairs(SETTINGS) do SETTING[setting.key] = setting end

local function settingFor(key)
  local setting = SETTING[key]
  if not setting then error(("Core: no setting %q"):format(tostring(key)), 3) end
  return setting
end

-- What Core itself does when a setting changes, by key.
local ON_CHANGE = {
  -- Pause sharing: send nothing, still receive, and appear offline.
  paused = function(self, paused) self.gossip:setPaused(paused) end,
}

-- A setting's current value, by key.
function Core:setting(key)
  return settingFor(key).saved.read(self.db)
end

-- Sets a setting by key. A real change is saved and fires
-- settingChanged(key, value); setting the value it already has fires
-- nothing.
function Core:setSetting(key, value)
  local saved = settingFor(key).saved
  local before = saved.read(self.db)
  saved.write(self.db, value)
  local after = saved.read(self.db)
  if (saved.same or rawequal)(before, after) then return end
  local onChange = ON_CHANGE[key]
  if onChange then onChange(self, after) end
  self.listener("settingChanged", key, after)
end

-- The Settings page, ready to render: sections in order, { title,
-- settings }, each setting { key, kind, label, value }. Settings with no
-- section (the Together tab's Show menu) aren't on it.
function Core:settings()
  local sections, byTitle = {}, {}
  for _, setting in ipairs(SETTINGS) do
    local section = setting.section and byTitle[setting.section]
    if setting.section and not section then
      section = { title = setting.section, settings = {} }
      byTitle[setting.section] = section
      sections[#sections + 1] = section
    end
    if section then
      section.settings[#section.settings + 1] = {
        key = setting.key,
        kind = setting.kind,
        label = setting.label,
        value = self:setting(setting.key),
      }
    end
  end
  return sections
end

-- The named settings, over setting() and setSetting().

-- Chat message for live events: on by default.
function Core:setChatLines(on) self:setSetting("chatLines", on) end
function Core:isChatLinesOn() return self:setting("chatLines") end

-- Show While you were away on login: on by default.
function Core:setAwayPopup(on) self:setSetting("awayPopup", on) end
function Core:isAwayPopupOn() return self:setting("awayPopup") end

-- Toasts for live events: on by default.
function Core:setToasts(on) self:setSetting("toasts", on) end
function Core:isToastsOn() return self:setting("toasts") end

-- The toast sound: the name UI plays it by, or "none". Nil goes back to
-- the default.
function Core:setToastSound(name) self:setSetting("toastSound", name) end
function Core:toastSound() return self:setting("toastSound") end

-- Where toasts appear: the centre of the first toast, as x and y from the
-- screen's bottom left. Nil x goes back to the default, where this returns
-- nil.
function Core:setToastPosition(x, y)
  self:setSetting("toastPosition", x and { x = x, y = y } or nil)
end

function Core:toastPosition()
  local position = self:setting("toastPosition")
  if not position then return nil end
  return position.x, position.y
end

-- The panel's size and position as the player left it, by its top left
-- corner in UI units from the screen's bottom left. Account-wide, so it
-- opens the same on every Character.
function Core:setPanelPlace(width, height, left, top)
  self:setSetting("panelPlace", { width = width, height = height, left = left, top = top })
end

-- Back to the default size, centred.
function Core:resetPanelPlace()
  self:setSetting("panelPlace", nil)
end

-- Where the panel opens on a screen this big (UI units): { width, height,
-- left, top }, shrunk to fit the screen and moved onto it. Left and top
-- are nil while it hasn't been moved or resized, for centred.
function Core:panelPlace(screenWidth, screenHeight)
  local saved = self:setting("panelPlace")
  if not saved then
    return { width = math.min(Core.PANEL_WIDTH, screenWidth), height = math.min(Core.PANEL_HEIGHT, screenHeight) }
  end
  local width = math.min(saved.width, screenWidth)
  local height = math.min(saved.height, screenHeight)
  return {
    width = width,
    height = height,
    left = clamp(saved.left, 0, screenWidth - width),
    top = clamp(saved.top, height, screenHeight),
  }
end

-- Pause sharing: send nothing, still receive, and appear offline. Kept
-- across reloads and logouts.
function Core:setPaused(paused) self:setSetting("paused", paused) end
function Core:isPaused() return self:setting("paused") end

-- Show minimap button: on by default.
function Core:setMinimapShown(shown) self:setSetting("minimap", shown) end
function Core:isMinimapShown() return self:setting("minimap") end

-- The minimap button's saved table, handed to LibDBIcon, which keeps the
-- button's position and the minimap setting's hide flag in it.
-- Account-wide, like every setting.
function Core:minimapIcon()
  return savedIn(self.db, "minimap")
end

-- Your display name, or nil until one is set.
function Core:displayName()
  return self.ledger:displayName()
end

-- The Roster footer's status lines, in priority order.
local LEAVING = "Leaving the Crew. It finishes once BFF's channel is reachable."
local PAUSED = "You appear offline: the others don't see you. Change it in Settings."
local WAITING = "Waiting for your Crew. Members show up when they or someone who has seen them is online."

-- The Crew: code, channel and password, leaving while a leave hasn't
-- reached the link yet, alone while no other Member is known, and status:
-- the Roster footer's line, the first that applies of leaving, appearing
-- offline (Pause sharing) and waiting for the Crew (alone), else nil. Nil
-- when not in a Crew.
function Core:crew()
  local saved = self.db.crew
  if not saved then return nil end
  local channel, password = ns.CrewCode.channel(saved.code)
  local alone = not self.ledger:knowsOthers()
  local status
  if saved.leaving then
    status = LEAVING
  elseif self:isPaused() then
    status = PAUSED
  elseif alone then
    status = WAITING
  end
  return {
    code = saved.code,
    channel = channel,
    password = password,
    leaving = saved.leaving,
    alone = alone,
    status = status,
  }
end

local MIN_NAME, MAX_NAME = 2, 16

-- The trimmed name, or nil if it isn't 2–16 UTF-8 characters.
local function validName(name)
  if type(name) ~= "string" then return nil end
  name = name:match("^%s*(.-)%s*$")
  -- Count every byte that doesn't continue a UTF-8 character.
  local length = #name:gsub("[\128-\191]", "")
  if length < MIN_NAME or length > MAX_NAME then return nil end
  return name
end

-- Without a name, keeps the one already set.
local function nameOrCurrent(self, displayName)
  if displayName == nil then return self.ledger:displayName() end
  return validName(displayName)
end

-- Joining (not starting) makes your own joined entry, for Welcomes.
local function enter(self, code, displayName, joining)
  self.ledger:writeOwn({ displayName = displayName, left = false, joinedAt = self.now() })
  sendOwnNow(self)
  self.crewGoals:clear()
  self.db.catchTypesTold = nil
  self.db.crew = { code = code }
  if joining then self.log:ownJoined() end
  self.listener("crewChanged")
  updateLink(self)
  return self:crew()
end

-- Starts a Crew with a new code. Returns crew(), or nil and "inCrew" or
-- "invalidName".
function Core:startCrew(displayName)
  if self.db.crew then return nil, "inCrew" end
  local name = nameOrCurrent(self, displayName)
  if not name then return nil, "invalidName" end
  return enter(self, ns.CrewCode.generate(self.random), name)
end

-- Joins the Crew a typed code names. Joining the Crew you're in does
-- nothing, and cancels a leave that hasn't finished. Returns crew(), or nil
-- and "invalidCode", "inCrew" or "invalidName".
function Core:joinCrew(code, displayName)
  code = ns.CrewCode.normalise(code)
  if not code then return nil, "invalidCode" end
  local current = self.db.crew
  if current and current.code ~= code then return nil, "inCrew" end
  local name = nameOrCurrent(self, displayName)
  if not name then return nil, "invalidName" end
  if not current then return enter(self, code, name, true) end

  if current.leaving then
    current.leaving = nil
    self.ledger:writeOwn({ displayName = name, left = false })
    sendOwnNow(self)
  end
  return self:crew()
end

-- Sets your display name. Returns true, or nil and "invalidName".
function Core:setDisplayName(displayName)
  local name = validName(displayName)
  if not name then return nil, "invalidName" end
  if name ~= self.ledger:displayName() then
    self.ledger:writeOwn({ displayName = name })
    sendOwnNow(self)
    self.listener("changed")
  end
  return true
end

-- Set as Main: one of your own Characters by GUID, or nil for the most
-- recently played. Returns true, or nil and "unknownCharacter".
function Core:setMain(guid)
  if guid ~= nil then
    local own = self.ledger:own()
    if not (own and type(guid) == "string" and own.characters[guid]) then
      return nil, "unknownCharacter"
    end
  end
  if self.ledger:writeOwn({ main = guid or false }) then
    sendOwnNow(self)
    self.listener("changed")
  end
  return true
end

-- Remove: hides a Member from your own view only, and stops relaying them.
-- Returns true, or nil and "unknownMember".
function Core:removeMember(id)
  if not self.ledger:remove(id) then return nil, "unknownMember" end
  self.gossip:forget(id)
  self.log:dropMember(id)
  self.spareLife:memberRemoved()
  self.online[id] = nil
  checkGoals(self, true)
  self.listener("changed")
  return true
end

-- Re-adds a removed Member: a DIGEST without them goes out, and whoever
-- holds them replies with DATA. Returns true, or nil and "unknownMember".
function Core:readdMember(id)
  if not self.ledger:readd(id) then return nil, "unknownMember" end
  self.gossip:askAround()
  self.listener("changed")
  return true
end

-- The removed Members, by display name: memberId and displayName.
function Core:removed()
  local removed = {}
  for id, member in self.ledger:removed() do
    removed[#removed + 1] = { memberId = id, displayName = member.displayName }
  end
  table.sort(removed, function(a, b)
    local x, y = (a.displayName or ""):lower(), (b.displayName or ""):lower()
    if x ~= y then return x < y end
    return a.memberId < b.memberId
  end)
  return removed
end

-- Hands the tombstone to the link, then forgets the Crew. Your own record
-- stays, so rejoining resumes where you left off. The Crew is forgotten
-- before sending, so a link that reacts to the send can't finish it twice.
local function finishLeaving(self)
  self.db.crew = nil
  updateLink(self)
  self.gossip:sendNow({ type = "DATA", records = { self.ledger:tombstone() } })
  self.ledger:forgetOthers()
  self.ledger:clearReactions()
  self.spareLife:clear()
  self.log:clear()
  self.crewGoals:clear()
  self.db.catchTypesTold = nil
  self.online = {}
  self.listener("crewChanged")
  self.listener("notice", "leftCrew")
end

-- Leaves the Crew: marks your record left, and finishes once the link is
-- up, even after a logout. Returns true, or nil and "noCrew".
function Core:leaveCrew()
  local crew = self.db.crew
  if not crew then return nil, "noCrew" end
  if crew.leaving then return true end
  crew.leaving = true
  self.ledger:writeOwn({ left = true })
  if self.linkUp then finishLeaving(self) else self.listener("changed") end
  return true
end

-- The incoming half of the link port. Every up() sends a fresh DIGEST, plus
-- own DATA if the own record changed while the link was down.
function Core:up()
  self.linkUp = true
  if self.db.crew and self.db.crew.leaving then
    finishLeaving(self)
  else
    updateLink(self)
  end
end

function Core:down()
  self.linkUp = false
  updateLink(self)
end

-- A Character of this name left the channel, i.e. logged out: its Member
-- shows offline right away.
function Core:gone(name)
  if type(name) ~= "string" then return end
  self.gossip:peerGone(name)
  if self.ledger:wentAway(name) then checkOnline(self) end
end

-- A send to the Character of this name failed: they may have missed it, so
-- they get a DIGEST of their own shortly after. Sync with everyone else
-- carries on.
function Core:sendFailed(name)
  if type(name) == "string" then self.gossip:sendFailed(name) end
end

local function dataReceived(self, records, from)
  local changed = false
  for _, record in ipairs(records) do
    local kept, before = self.ledger:merge(record, from)
    if self.trace then
      self.trace(("receive DATA from %s · ok · %s"):format(traceName(self, from),
        traceReceived(self, record, kept)))
    end
    if kept then
      changed = true
      self.log:dataMerged()
      self.crewGoals:dataMerged()
      local entries, reactions = self.log:recordChanged(before, record)
      announce(self, entries, reactions, self.spareLife:recordChanged(before, record))
      -- A Member first seen, leaving or back, or professions first shared,
      -- change who counts.
      if ns.Goals.countedChanged(before, record) then checkGoals(self, true) end
    end
    if type(record) == "table" and type(record.id) == "string" and type(record.version) == "number" then
      self.gossip:recordSeen(record.id, record.version)
    end
  end
  if changed then
    checkGoals(self)
    -- Caught with you online: nothing to tell you at your next login.
    local told = self.db.catchTypesTold
    if told then ns.Catches.markTold(told, self:catches(), self.sessionStart) end
  end
  return changed
end

-- A message from the link. Your own, echoed back by the channel, and
-- anything arriving outside a Crew are dropped.
function Core:received(message)
  if type(message) ~= "string" or not self.db.crew then return end
  local decoded, reason = ns.Codec.decode(message)
  if self.trace and reason then
    self.trace(("receive · %s · %d B"):format(reason, #message))
  end
  if reason == "newer" then
    if not self.toldOutOfDate then
      self.toldOutOfDate = true
      self.listener("notice", "outOfDate")
    end
    return
  end
  if type(decoded) ~= "table" or type(decoded.from) ~= "string" then
    if self.trace and not reason then self.trace(("receive · invalid (no sender) · %d B"):format(#message)) end
    return
  end
  if decoded.from == self.ledger:memberId() then
    if self.trace then self.trace(("receive %s from you · ignored"):format(tostring(decoded.type))) end
    return
  end

  self.ledger:heard(decoded.from)
  local changed = false
  if decoded.type == "DIGEST" and type(decoded.versions) == "table" then
    local partial = decoded.partial == true
    if self.trace then
      self.trace(("receive DIGEST from %s · ok%s · %s"):format(traceName(self, decoded.from),
        partial and " (more in turn)" or "", traceVersions(self, decoded.versions)))
    end
    self.gossip:digestReceived(decoded.versions, partial, decoded.turns == true)
  elseif decoded.type == "DATA" and type(decoded.records) == "table" then
    changed = dataReceived(self, decoded.records, decoded.from)
  elseif self.trace then
    self.trace(("receive %s from %s · ignored (unknown)"):format(tostring(decoded.type), traceName(self, decoded.from)))
  end
  if onlineChanged(self) or changed then self.listener("changed") end
end
