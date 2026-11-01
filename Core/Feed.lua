-- Feed: turns a record as it was and as it is now into Feed entries (ding,
-- death, new Character, max level, joined and left the Crew), and keeps the
-- account-wide log with its seen flags. A jump over skipped versions makes
-- at most one entry of each kind per Character, and the first sight of a
-- Member is a silent baseline, unless they joined the Crew after you. Also
-- attaches the Reactions Members' records carry to the entries they point
-- at, each with a seen flag on your own entries, and knows when sync has
-- settled after an initial login.
-- See docs/design/feed.md and docs/design/reactions.md.

local _, ns = ...

local Feed = {}
Feed.__index = Feed
ns.Feed = Feed

local Reactions = ns.Reactions

local DAY = 24 * 60 * 60
-- Entries are kept this long, and at most this many.
local KEEP_FOR = 30 * DAY
local KEEP_MAX = 200
-- Settled after this long with no new DATA, or at most this long after the
-- link came up.
local QUIET_FOR = 10
local SETTLE_WITHIN = 30

-- For "a new Character: Jaina (Mage)". Core has no game strings.
local CLASS_NAMES = {
  DEATHKNIGHT = "Death Knight",
  DEMONHUNTER = "Demon Hunter",
}

local function className(classFilename)
  if not classFilename then return "?" end
  return CLASS_NAMES[classFilename] or classFilename:sub(1, 1) .. classFilename:sub(2):lower()
end

-- db is the whole saved table; Feed keeps `feed` (the log, oldest first)
-- and `feedJoins` (the joinedAt last seen per Member, so re-adding a
-- Member doesn't announce their join again). Only an initial login waits
-- for sync to settle.
function Feed.new(db, ledger, now, maxLevel, initialLogin)
  db.feed = db.feed or {}
  db.feedJoins = db.feedJoins or {}
  return setmetatable({
    db = db,
    ledger = ledger,
    now = now,
    maxLevel = maxLevel,
    settled = not initialLogin,
    -- When the link first came up in a Crew, and when DATA last changed
    -- something.
    upSince = nil,
    lastData = nil,
  }, Feed)
end

local function memberName(self, record)
  if record.displayName then return record.displayName end
  local main = ns.Roster.main(record, self.now())
  return main and main.name or "Someone"
end

-- Who an event happened to: "Ana", "Ana's Alt Jaina", "You" or "Your Alt
-- Jaina". The Main is the one the panel shows.
local function subject(self, record, character, own)
  local main = ns.Roster.main(record, self.now())
  local alt = main ~= nil and character.guid ~= main.guid
  if own then return alt and "Your Alt " .. character.name or "You" end
  local name = memberName(self, record)
  return alt and ("%s's Alt %s"):format(name, character.name) or name
end

local function newEntry(kind, record, own, text, character)
  return {
    kind = kind,
    time = record.version,
    memberId = record.id,
    guid = character and character.guid,
    text = text,
    own = own or nil,
    -- Your own events are never news to you.
    seen = own or nil,
  }
end

-- The entries for one Character, from how it was (nil if new) to how it is.
local function characterEntries(self, record, was, character, own, list)
  if not was then
    local owner = own and "You have" or memberName(self, record) .. " has"
    local entry = newEntry("newCharacter", record, own,
      ("%s a new Character: %s (%s)"):format(owner, character.name, className(character.classFilename)),
      character)
    entry.level = character.level
    list[#list + 1] = entry
    return
  end

  local level, from = character.level, was.level
  -- A level above your own max level means you're behind on a patch.
  if level > from and level <= self.maxLevel then
    local entry
    if level == self.maxLevel then
      entry = newEntry("maxLevel", record, own,
        subject(self, record, character, own) .. " reached max level!", character)
    else
      entry = newEntry("ding", record, own,
        ("%s dinged %d"):format(subject(self, record, character, own), level), character)
    end
    entry.from, entry.level = from, level
    list[#list + 1] = entry
  end

  -- A count that went down is a crash that lost a session's deaths.
  local deaths = (character.deaths or 0) - (was.deaths or 0)
  if deaths > 0 then
    local times = deaths == 1 and "" or (" %d times"):format(deaths)
    local entry = newEntry("death", record, own,
      ("%s died%s"):format(subject(self, record, character, own), times), character)
    -- The death total reached keys Reactions (docs/adr/0002).
    entry.count, entry.to = deaths, character.deaths
    list[#list + 1] = entry
  end
end

-- Attaches a Reaction by the Member id `by` to an entry: { by, n, time,
-- seen }, kept in the order they were made. Returns it, or nil when it was
-- already there or is the owner's own.
local function attach(entry, by, key, time, seen)
  if by == entry.memberId then return nil end
  local list = entry.reactions or {}
  for _, reaction in ipairs(list) do
    if reaction.by == by and reaction.n == key.n then return nil end
  end
  local reaction = { by = by, n = key.n, time = time, seen = seen or nil }
  local at = #list + 1
  while at > 1 and list[at - 1].time > time do at = at - 1 end
  table.insert(list, at, reaction)
  entry.reactions = list
  return reaction
end

-- The newest entry a key falls on, or nil.
local function find(self, key)
  local log = self.db.feed
  for i = #log, 1, -1 do
    if Reactions.matches(log[i], key) then return log[i] end
  end
  return nil
end

-- A new entry takes the Reactions to it already in held records, so it
-- doesn't matter which record arrived first. They aren't news.
local function attachHeld(self, entry)
  if not Reactions.forKind(entry.kind) then return end
  for id, record in self.ledger:records() do
    for _, item in ipairs(Reactions.inRecord(record)) do
      if Reactions.matches(entry, item.key) then attach(entry, id, item.key, item.time, true) end
    end
  end
end

-- Keeps the log oldest first by time; equal times keep arrival order.
local function insert(self, entries)
  local log = self.db.feed
  for _, entry in ipairs(entries) do
    local at = #log + 1
    while at > 1 and log[at - 1].time > entry.time do at = at - 1 end
    table.insert(log, at, entry)
    attachHeld(self, entry)
  end
  return entries
end

-- The Reactions in after that weren't in before, attached to the entries
-- they point at. A Reaction whose entry isn't in the log is ignored. Only
-- those to your own entries can be news, and never on first sight.
-- Returns the news as { entry, reaction }.
local function reactionsChanged(self, before, after)
  local news = {}
  if after.left then return news end
  local had = {}
  for _, item in ipairs(Reactions.inRecord(before)) do had[Reactions.id(item.key)] = true end
  for _, item in ipairs(Reactions.inRecord(after)) do
    local entry = not had[Reactions.id(item.key)] and find(self, item.key)
    if entry then
      local reaction = attach(entry, after.id, item.key, item.time, before == nil or not entry.own)
      if reaction and not reaction.seen then news[#news + 1] = { entry = entry, reaction = reaction } end
    end
  end
  return news
end

local function joinedAfterYou(self, record)
  local own = self.ledger:own()
  local yours = own and own.joinedAt
  return record.joinedAt ~= nil and yours ~= nil and record.joinedAt > yours
end

local function crewEntry(self, kind, record)
  local verb = kind == "joined" and " joined the Crew" or " left the Crew"
  local entry = newEntry(kind, record, false, memberName(self, record) .. verb)
  -- joinedAt keys Welcomes (docs/adr/0002).
  if kind == "joined" then entry.joinedAt = record.joinedAt end
  return entry
end

-- Someone else's record was kept: before is the copy held until now (nil
-- on first sight) and after the new one. Returns the new entries, and the
-- new Reactions to your own entries as { entry, reaction }.
function Feed:recordChanged(before, after)
  local list = {}
  local joins = self.db.feedJoins
  local announced = joins[after.id]
  joins[after.id] = after.joinedAt

  if before == nil then
    if not after.left and joinedAfterYou(self, after) and after.joinedAt ~= announced then
      list[1] = crewEntry(self, "joined", after)
    end
  elseif after.left then
    if not before.left then list[1] = crewEntry(self, "left", after) end
  elseif before.left then
    list[1] = crewEntry(self, "joined", after)
  else
    for guid, character in pairs(after.characters) do
      characterEntries(self, after, before.characters[guid], character, false, list)
    end
  end
  return insert(self, list), reactionsChanged(self, before, after)
end

-- You joined a Crew: your own joined entry, which Welcomes attach to.
function Feed:ownJoined()
  local own = self.ledger:own()
  local entry = newEntry("joined", own, true, "You joined the Crew")
  entry.joinedAt = own.joinedAt
  return insert(self, { entry })
end

-- The Character being played changed: was is how it was (nil if new), and
-- guid names it in the own record. Your first Character ever is a silent
-- baseline. Returns the new entries.
function Feed:ownChanged(was, guid)
  local list = {}
  local own = self.ledger:own()
  local first = was == nil and next(own.characters, next(own.characters)) == nil
  if not first then characterEntries(self, own, was, own.characters[guid], true, list) end
  return insert(self, list)
end

-- Drops a Removed Member's entries.
function Feed:dropMember(id)
  local log = self.db.feed
  for i = #log, 1, -1 do
    if log[i].memberId == id then table.remove(log, i) end
  end
end

-- Leaving the Crew wipes the log.
function Feed:clear()
  self.db.feed = {}
  self.db.feedJoins = {}
end

-- Marks an entry, or a Reaction, seen.
function Feed:markSeen(item)
  item.seen = true
end

-- Whether a Reaction counts: a Removed Member's are hidden.
local function shown(self, reaction)
  return not self.ledger:isRemoved(reaction.by)
end

-- The unseen Reactions to an entry. Only your own entries have any.
local function unseenReactions(self, entry)
  local list = {}
  if not entry.own then return list end
  for _, reaction in ipairs(entry.reactions or {}) do
    if not reaction.seen and shown(self, reaction) then list[#list + 1] = reaction end
  end
  return list
end

-- Marks every entry and Reaction seen. Returns true if any wasn't.
function Feed:markAllSeen()
  local any = false
  for _, entry in ipairs(self.db.feed) do
    if not entry.seen then
      entry.seen = true
      any = true
    end
    for _, reaction in ipairs(unseenReactions(self, entry)) do
      reaction.seen = true
      any = true
    end
  end
  return any
end

-- How many entries and Reactions haven't been seen.
function Feed:unseen()
  local count = 0
  for _, entry in ipairs(self.db.feed) do
    if not entry.seen then count = count + 1 end
    count = count + #unseenReactions(self, entry)
  end
  return count
end

local function reactorName(self, id)
  local record = self.ledger:record(id)
  return record and memberName(self, record) or "Someone"
end

-- The Members who reacted to an entry, each once, in the order they did.
local function reactorIds(self, entry)
  local ids, counted = {}, {}
  for _, reaction in ipairs(entry.reactions or {}) do
    if shown(self, reaction) and not counted[reaction.by] then
      counted[reaction.by] = true
      ids[#ids + 1] = reaction.by
    end
  end
  return ids
end

local function hasReacted(self, entry)
  local me = self.ledger:memberId()
  for _, reaction in ipairs(entry.reactions or {}) do
    if reaction.by == me then return true end
  end
  return false
end

-- What Reactions to your own entry did, after the names: "cheered your ding
-- to 30".
local function phrase(self, entry)
  local own = self.ledger:own()
  local character = own and entry.guid and own.characters[entry.guid]
  local main = own and ns.Roster.main(own, self.now())
  local alt = character ~= nil and main ~= nil and character.guid ~= main.guid
  return Reactions.phrase(entry, character, alt)
end

-- A Reaction to your own entry as news, for the chat line and the toast:
-- { text, reaction, name, phrase, entryKey, memberId }. Toasts merge news
-- with the same entryKey.
function Feed:news(item)
  local name = reactorName(self, item.reaction.by)
  local words = phrase(self, item.entry)
  return {
    text = Reactions.text({ name }, words),
    reaction = Reactions.forKind(item.entry.kind),
    name = name,
    phrase = words,
    -- A Reaction only lands on an entry that has a key.
    entryKey = Reactions.id(Reactions.keyOf(item.entry)),
    memberId = item.reaction.by,
  }
end

-- Your Reaction to someone else's entry. Ignores your own entries, Removed
-- Members, entries that can't be reacted to or aren't in the log, and
-- entries you already reacted to. Returns the key to store, or nil.
function Feed:react(key)
  key = Reactions.validKey(key)
  if not key then return nil end
  local me = self.ledger:memberId()
  if key.memberId == me or self.ledger:isRemoved(key.memberId) then return nil end
  local entry = find(self, key)
  if not entry or entry.own or hasReacted(self, entry) then return nil end
  attach(entry, me, key, self.now(), true)
  return key
end

-- The link came up in a Crew: settling starts, if it hasn't.
function Feed:linkUp()
  self.upSince = self.upSince or self.now()
end

-- The link went down before settling: a half-synced summary is never
-- shown, so settling starts over at the next up().
function Feed:linkDown()
  if self.settled then return end
  self.upSince, self.lastData = nil, nil
end

-- DATA changed a record.
function Feed:dataMerged()
  self.lastData = self.now()
end

function Feed:isSettled()
  return self.settled
end

-- Called once a second: prunes the log, and settles once sync has gone
-- quiet. Returns true on the tick it settles.
function Feed:tick()
  local now = self.now()
  local log = self.db.feed
  while log[1] and (#log > KEEP_MAX or now - log[1].time > KEEP_FOR) do
    table.remove(log, 1)
  end

  if self.settled or not self.upSince then return false end
  local quietSince = math.max(self.upSince, self.lastData or self.upSince)
  if now - quietSince >= QUIET_FOR or now - self.upSince >= SETTLE_WITHIN then
    self.settled = true
    return true
  end
  return false
end

-- Entries shown in the summary on their own highlighted line.
local HIGHLIGHT = { maxLevel = true, joined = true, left = true }

-- A Reaction button in the summary: { key, reacted }, or nil.
local function button(self, entry)
  local key = entry and Reactions.keyOf(entry)
  if not key then return nil end
  return { key = key, reacted = hasReacted(self, entry) }
end

-- The entry a row's Cheer goes to: max level, else the highest ding, else
-- a new Character.
local function cheerRank(entry)
  if entry.kind == "maxLevel" then return 1000 end
  if entry.kind == "ding" then return entry.level end
  if entry.kind == "newCharacter" then return 0 end
  return nil
end

-- One Character's row in a Member's block: { name, main, from, level,
-- deaths, new, maxLevel, cheer, respects }. The level range runs from the
-- lowest "before" to the highest "after" (max level counts towards it), a
-- new Character has its level but no from, and deaths add up. Cheer is
-- keyed to the highest level and Respects to the highest death total. Nil
-- when the Character has none of these.
local function characterRow(self, entries, character, isMain)
  local row = {
    name = character and character.name or "?",
    main = isMain or nil,
  }
  local any = false
  local cheer, respects
  for _, entry in ipairs(entries) do
    local rank = cheerRank(entry)
    if rank and (not cheer or rank > cheerRank(cheer)) then cheer = entry end
    if entry.kind == "death" and (not respects or (entry.to or 0) > (respects.to or 0)) then
      respects = entry
    end
    if entry.kind == "ding" or entry.kind == "maxLevel" then
      row.from = math.min(row.from or entry.from, entry.from)
      row.level = math.max(row.level or entry.level, entry.level)
      if entry.kind == "maxLevel" then row.maxLevel = true end
      any = true
    elseif entry.kind == "death" then
      row.deaths = (row.deaths or 0) + entry.count
      any = true
    elseif entry.kind == "newCharacter" then
      row.new = true
      row.level = math.max(row.level or entry.level, entry.level)
      any = true
    end
  end
  if row.new then row.from = nil end
  row.cheer, row.respects = button(self, cheer), button(self, respects)
  return any and row or nil
end

-- One Member's block: a row per Character with events, the Main's first,
-- then the rest by latest activity, and a Welcome when they joined.
local function memberBlock(self, id, entries)
  local record = self.ledger:record(id)
  local main = record and ns.Roster.main(record, self.now())
  local block = {
    memberId = id,
    displayName = record and memberName(self, record) or "Someone",
    main = main and main.name,
    classFilename = main and main.classFilename,
    time = 0,
    characters = {},
    highlights = {},
  }

  local byCharacter, characters = {}, {}
  for _, entry in ipairs(entries) do
    block.time = math.max(block.time, entry.time)
    if HIGHLIGHT[entry.kind] then
      block.highlights[#block.highlights + 1] = { kind = entry.kind, text = entry.text }
    end
    if entry.kind == "joined" then block.welcome = button(self, entry) or block.welcome end
    if entry.guid then
      local forCharacter = byCharacter[entry.guid]
      if not forCharacter then
        forCharacter = { guid = entry.guid, time = 0 }
        byCharacter[entry.guid] = forCharacter
        characters[#characters + 1] = forCharacter
      end
      forCharacter[#forCharacter + 1] = entry
      forCharacter.time = math.max(forCharacter.time, entry.time)
    end
  end

  local mainGuid = main and main.guid
  table.sort(characters, function(a, b)
    if (a.guid == mainGuid) ~= (b.guid == mainGuid) then return a.guid == mainGuid end
    if a.time ~= b.time then return a.time > b.time end
    return a.guid < b.guid
  end)
  for _, forCharacter in ipairs(characters) do
    local character = record and record.characters[forCharacter.guid]
    local row = characterRow(self, forCharacter, character, forCharacter.guid == mainGuid)
    if row then block.characters[#block.characters + 1] = row end
  end
  return block
end

-- Your Crew noticed: a line per own entry with unseen Reactions, naming
-- everyone who reacted to it, newest first: { text, reaction, time }.
-- Marks them seen.
local function takeNoticed(self)
  local lines = {}
  for _, entry in ipairs(self.db.feed) do
    local unseen = unseenReactions(self, entry)
    if #unseen > 0 then
      local time = 0
      for _, reaction in ipairs(unseen) do
        reaction.seen = true
        time = math.max(time, reaction.time)
      end
      local names = {}
      for i, id in ipairs(reactorIds(self, entry)) do names[i] = reactorName(self, id) end
      lines[#lines + 1] = {
        text = Reactions.text(names, phrase(self, entry)),
        reaction = Reactions.forKind(entry.kind),
        time = time,
      }
    end
  end
  table.sort(lines, function(a, b)
    if a.time ~= b.time then return a.time > b.time end
    return a.text < b.text
  end)
  return lines
end

-- While you were away: the unseen entries from other Members, one block
-- per Member, most recent activity first, and the unseen Reactions to your
-- own, as { members, count, noticed }. Marks them seen. Nil when there are
-- none.
function Feed:takeSummary()
  local byMember, ids, count = {}, {}, 0
  for _, entry in ipairs(self.db.feed) do
    if not entry.seen then
      entry.seen = true
      count = count + 1
      local memberEntries = byMember[entry.memberId]
      if not memberEntries then
        memberEntries = {}
        byMember[entry.memberId] = memberEntries
        ids[#ids + 1] = entry.memberId
      end
      memberEntries[#memberEntries + 1] = entry
    end
  end
  local noticed = takeNoticed(self)
  if count == 0 and #noticed == 0 then return nil end

  local members = {}
  for i, id in ipairs(ids) do members[i] = memberBlock(self, id, byMember[id]) end
  table.sort(members, function(a, b)
    if a.time ~= b.time then return a.time > b.time end
    return a.memberId < b.memberId
  end)
  return { members = members, count = count, noticed = noticed }
end

-- An entry as handed out: a fresh table UI may keep. Seen is false while
-- it has unseen Reactions. reaction is the one that applies, key what
-- react() takes, reactors who reacted ({ memberId, name, you }), reacted
-- whether you have, and canReact whether you can at all.
function Feed:describe(entry)
  local me = self.ledger:memberId()
  local reactors = {}
  for i, id in ipairs(reactorIds(self, entry)) do
    reactors[i] = { memberId = id, name = reactorName(self, id), you = id == me }
  end
  local key = Reactions.keyOf(entry)
  return {
    kind = entry.kind,
    time = entry.time,
    memberId = entry.memberId,
    guid = entry.guid,
    text = entry.text,
    from = entry.from,
    level = entry.level,
    count = entry.count,
    own = entry.own == true,
    seen = entry.seen == true and #unseenReactions(self, entry) == 0,
    reaction = Reactions.forKind(entry.kind),
    key = key,
    reactors = reactors,
    reacted = hasReacted(self, entry),
    canReact = key ~= nil and not entry.own and not self.ledger:isRemoved(entry.memberId),
  }
end

-- The log newest first, grouped by day (utcOffset shifts day boundaries
-- to local time): { days = { { daysAgo, time, entries } }, unseen }.
function Feed:view(utcOffset)
  local today = math.floor((self.now() + utcOffset) / DAY)
  local days = {}
  local log = self.db.feed
  for i = #log, 1, -1 do
    local entry = log[i]
    local day = math.floor((entry.time + utcOffset) / DAY)
    local group = days[#days]
    if not group or group.day ~= day then
      group = { day = day, daysAgo = today - day, time = entry.time, entries = {} }
      days[#days + 1] = group
    end
    group.entries[#group.entries + 1] = self:describe(entry)
  end
  for _, group in ipairs(days) do group.day = nil end
  return { days = days, unseen = self:unseen() }
end
