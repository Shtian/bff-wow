-- Spares: the whole Spare lifecycle, behind the interface Core delegates
-- to. Posting, withdrawing and Giving your own, making and withdrawing
-- Claims on others', when each ends, who wins (docs/adr/0003), what
-- happens when a posted item leaves the bags (docs/adr/0004), the Spares
-- tab's rows, the Roster's count, and the notices with their seen flags.
--
-- Each Spare is in its owner's record and each Claim in its claimer's;
-- the Ledger stores and sends them, and asks this module, through the
-- pruner handed over at setup, which have ended. Removed Members aren't
-- held, so their Spares and Claims are gone too; Left ones are skipped.
-- The owner hears when a Claim becomes the winning one, and the winning
-- claimer when it's Given. Your own Gives go into the Feed from here;
-- the Feed asks newlyGiven for others'. The stateless rules are in
-- SpareRules. See docs/design/spares.md.

local _, ns = ...

local Spares = {}
Spares.__index = Spares
ns.Spares = Spares

local Rules = ns.SpareRules

local DAY = 24 * 60 * 60
-- Notices are kept this long, and at most this many.
local KEEP_FOR = 30 * DAY
local KEEP_MAX = 50
-- Claims expire on their own (30 days); the winners are checked this
-- often so one moving up that way is silent.
local QUIET_CHECK_EVERY = 60

-- The trimmed item string from an item link, or nil when it isn't an item.
-- For Bags, which finds the item a link names.
Spares.itemString = Rules.itemString

-- The Spares Given in the after record that weren't in before (nil on
-- first sight counts as none), as { id, item, level, time, to, guid }. For
-- the Feed's gave entries.
Spares.newlyGiven = Rules.newlyGiven

-- An item's link for a text, from itemLink(itemString), or "an item" until
-- the game has it.
Spares.linkText = Rules.linkText

-- itemLink for a client that can't resolve items: never cached.
Spares.NO_LINK = Rules.NO_LINK

-- deps: db (the whole saved table), ledger, feed, now(), listener (Core's,
-- for spareGone), initialLogin, itemLink(itemString) (optional: the game's
-- link, nil while it isn't cached) and findItem(itemGuid) (optional: where
-- a posted item is, see Bags.findItem).
--
-- Keeps in db: `spareNews` (the notices, oldest first), `spareWinners`
-- (the winning Member id last told of, per own Spare id), `nextSpare` (the
-- next own Spare id) and `spareItems` (per Character GUID, the item GUID
-- of each own open Spare it posted; never sent).
function Spares.new(deps)
  local db = deps.db
  db.spareNews = db.spareNews or {}
  db.spareWinners = db.spareWinners or {}
  local self = setmetatable({
    db = db,
    ledger = deps.ledger,
    feed = deps.feed,
    now = deps.now,
    listener = deps.listener,
    itemLink = deps.itemLink or Rules.NO_LINK,
    findItem = deps.findItem,
    lastQuietCheck = deps.now(),
    -- Own Spare ids whose item has left the bags this session.
    goneItems = {},
    -- Whether the check that may end Spares is still to come: the
    -- first after a real login, never after a /reload (buyback survives it).
    loginCheckDue = deps.initialLogin == true,
  }, Spares)
  self.ledger:pruneWith(function(record, now) self:prune(record, now) end)
  return self
end

local function memberName(self, record)
  return ns.Roster.memberName(record, self.now())
end

local function characterName(record, guid)
  local character = record and record.characters and record.characters[guid]
  return character and character.name or "?"
end

-- Whether a Member's record counts: held, not Left, not Removed.
local function shown(self, record)
  return record ~= nil and not record.left and not self.ledger:isRemoved(record.id)
end

-- A Spare by owner and id, as in SpareRules.inRecord, while its owner
-- counts (your own always does). Nil otherwise.
local function find(self, owner, id)
  local record = self.ledger:record(owner)
  if owner ~= self.ledger:memberId() and not shown(self, record) then return nil end
  for _, spare in ipairs(Rules.inRecord(record)) do
    if spare.id == id then return spare, record end
  end
  return nil
end

-- A Spare by owner and id while it's open: its owner counts, it isn't
-- Given and it's under 30 days old. Nil otherwise. The one place that
-- decides whether a Spare is open.
local function openSpare(self, owner, id)
  local spare = find(self, owner, id)
  if spare and Rules.isOpen(spare, self.now()) then return spare end
  return nil
end

-- The index of the first stored item in list that matches, or nil.
local function indexOf(list, matches)
  for index, item in ipairs(list or {}) do
    if matches(item) then return index end
  end
  return nil
end

-- The own Spares as in SpareRules.inRecord.
local function ownSpares(self)
  return Rules.inRecord(self.ledger:own())
end

-- The Claims every counted record makes on one Spare, as
-- { memberId, guid, time }. The owner's own never count.
local function claimsOn(self, owner, id)
  local now = self.now()
  local list = {}
  for memberId, record in self.ledger:records() do
    if memberId ~= owner and shown(self, record) then
      for _, claim in ipairs(Rules.claimsIn(record)) do
        if claim.owner == owner and claim.id == id and now - claim.time <= Rules.KEEP_FOR then
          list[#list + 1] = { memberId = memberId, guid = claim.guid, time = claim.time }
        end
      end
    end
  end
  return list
end

-- A Member and Character for the UI: { memberId, name, character, you }.
local function who(self, memberId, guid)
  local record = self.ledger:record(memberId)
  local me = memberId == self.ledger:memberId()
  return {
    memberId = memberId,
    name = me and "You" or memberName(self, record),
    character = characterName(record, guid),
    you = me,
  }
end

-- The winning Claim on a Spare, { memberId, guid, time }, and how
-- many Claims there are.
local function winnerOf(self, owner, id)
  local claims = claimsOn(self, owner, id)
  return Rules.winner(claims), #claims
end

-- The own Claim on a Spare, as read from the record, or nil.
local function ownClaim(self, owner, id)
  for _, claim in ipairs(Rules.claimsIn(self.ledger:own())) do
    if claim.owner == owner and claim.id == id then return claim end
  end
  return nil
end

-- The highest level among your own Characters, 0 with none.
local function highestLevel(self)
  local own = self.ledger:own()
  local highest = 0
  for _, character in pairs(own and own.characters or {}) do
    highest = math.max(highest, character.level)
  end
  return highest
end

-- How many own Spares are open.
local function openCount(self)
  local count, me = 0, self.ledger:memberId()
  for _, spare in ipairs(ownSpares(self)) do
    if openSpare(self, me, spare.id) then count = count + 1 end
  end
  return count
end

-- How many own Claims are open: their Spare still is.
local function claimCount(self)
  local count = 0
  for _, claim in ipairs(Rules.claimsIn(self.ledger:own())) do
    if openSpare(self, claim.owner, claim.id) then count = count + 1 end
  end
  return count
end

-- Forgets the item GUIDs of own Spares that are no longer open:
-- withdrawn, Given or past their 30 days.
local function forgetItems(self)
  local items = self.db.spareItems
  if not items then return end
  local me = self.ledger:memberId()
  for character, list in pairs(items) do
    for id in pairs(list) do
      if not openSpare(self, me, id) then list[id] = nil end
    end
    if next(list) == nil then items[character] = nil end
  end
  if next(items) == nil then self.db.spareItems = nil end
end

-- The Ledger's pruner, on every write of the own record: drops its Spares
-- 30 days after posting and its Claims once their Spare has ended, and
-- forgets the item GUIDs of own Spares that ended.
function Spares:prune(record, now)
  if record.spares then Rules.prune(record.spares, now) end
  if record.claims then
    Rules.pruneClaims(record.claims, now, function(owner, id) return openSpare(self, owner, id) ~= nil end)
  end
  forgetItems(self)
end

-- A row of "From the Crew": another Member's open Spare.
local function crewRow(self, record, spare, highest)
  local owner, id = record.id, spare.id
  local winner, count = winnerOf(self, owner, id)
  local mine = ownClaim(self, owner, id)
  local me = self.ledger:memberId()
  local state
  if not winner then
    state = "No claims yet"
  elseif winner.memberId == me then
    state = "You claimed it for " .. characterName(self.ledger:own(), winner.guid)
  else
    state = memberName(self, self.ledger:record(winner.memberId)) .. " claimed it first"
    if mine then state = state .. " (you claimed it for " .. characterName(self.ledger:own(), mine.guid) .. ")" end
  end
  local item = Rules.fullItemString(spare.item)
  return {
    ownerId = owner,
    owner = memberName(self, record),
    id = id,
    item = item,
    link = self.itemLink(item),
    level = spare.level,
    time = spare.time,
    expires = spare.time + Rules.KEEP_FOR - self.now(),
    usable = highest >= spare.level,
    winner = winner and who(self, winner.memberId, winner.guid),
    claims = count,
    claimed = mine ~= nil,
    claimCharacter = mine and characterName(self.ledger:own(), mine.guid),
    canClaim = mine == nil,
    state = state,
  }
end

-- A row of "Yours": an own Spare, open or Given.
local function yourRow(self, spare)
  local id = spare.id
  local winner, count = winnerOf(self, self.ledger:memberId(), id)
  local given = spare.to and who(self, spare.to, spare.guid)
  local state
  if given then
    state = ("Given to %s (%s)"):format(given.name, given.character)
    winner = nil
  elseif winner then
    local claimer = who(self, winner.memberId, winner.guid)
    state = ("%s claimed it for %s"):format(claimer.name, claimer.character)
    if count > 1 then state = state .. (" (%d Claims)"):format(count) end
  else
    state = "No claims yet"
  end
  local item = Rules.fullItemString(spare.item)
  return {
    id = id,
    item = item,
    link = self.itemLink(item),
    level = spare.level,
    time = spare.time,
    expires = spare.time + Rules.KEEP_FOR - self.now(),
    winner = winner and who(self, winner.memberId, winner.guid),
    claims = count,
    given = given,
    canGive = winner ~= nil,
    canWithdraw = given == nil,
    gone = (not given and self.goneItems[id]) or nil,
    state = state,
  }
end

-- Rows newest first; ties by owner, then the later id first.
local function newestFirst(a, b)
  if a.time ~= b.time then return a.time > b.time end
  if (a.ownerId or "") ~= (b.ownerId or "") then return (a.ownerId or "") < (b.ownerId or "") end
  return a.id > b.id
end

-- Every other counted Member's open Spares, as rows.
local function crewRows(self)
  local rows, now, highest = {}, self.now(), highestLevel(self)
  local me = self.ledger:memberId()
  for id, record in self.ledger:records() do
    if id ~= me and shown(self, record) then
      for _, spare in ipairs(Rules.inRecord(record)) do
        if Rules.isOpen(spare, now) then rows[#rows + 1] = crewRow(self, record, spare, highest) end
      end
    end
  end
  table.sort(rows, newestFirst)
  return rows
end

-- The own Spares, open or Given, as rows.
local function yourRows(self)
  local rows, now = {}, self.now()
  for _, spare in ipairs(ownSpares(self)) do
    if spare.to or Rules.isOpen(spare, now) then rows[#rows + 1] = yourRow(self, spare) end
  end
  table.sort(rows, newestFirst)
  return rows
end

-- The tab: { crew, yours, unseen, claims, maxClaims, open, maxOpen }, as
-- Core:spares() describes it.
function Spares:view()
  return {
    crew = crewRows(self),
    yours = yourRows(self),
    unseen = self:unseen(),
    claims = claimCount(self),
    maxClaims = Rules.MAX_CLAIMS,
    open = openCount(self),
    maxOpen = Rules.MAX_OPEN,
  }
end

-- Other Members' open Spares one of your Characters is high enough
-- level for, for the Roster.
function Spares:usableCount()
  local count = 0
  for _, row in ipairs(crewRows(self)) do
    if row.usable then count = count + 1 end
  end
  return count
end

-- Keeps a notice, made now and unseen. Returns it.
local function addNews(self, news)
  news.time = self.now()
  local list = self.db.spareNews
  list[#list + 1] = news
  return news
end

-- Works out who wins each own open Spare. A winner that changed
-- to a Member is news to you, unless quiet (first sight of a Member,
-- removing one, Claims expiring, your own writes). Returns the news.
local function check(self, quiet)
  local news, open = {}, {}
  local winners = self.db.spareWinners
  local me = self.ledger:memberId()
  for _, spare in ipairs(ownSpares(self)) do
    if openSpare(self, me, spare.id) then
      local id = spare.id
      open[id] = true
      local winner = winnerOf(self, me, id)
      local memberId = winner and winner.memberId
      if memberId ~= winners[id] then
        winners[id] = memberId
        if memberId and not quiet then
          news[#news + 1] = addNews(self, {
            kind = "claimed", memberId = memberId, guid = winner.guid, id = id, item = spare.item,
          })
        end
      end
    end
  end
  for id in pairs(winners) do
    if not open[id] then winners[id] = nil end
  end
  return news
end

-- Offers an item to the Crew: an item link (or item string), the level it
-- needs and, optionally, what the bags say about it ({ guid, isBound,
-- bindType }). Returns the Spare's id, or nil and "noCrew",
-- "invalidItem", "bound", "questItem", "accountBound" or "tooMany".
function Spares:post(link, level, inBags)
  if not self.db.crew then return nil, "noCrew" end
  local item = Rules.itemString(link)
  if not item then return nil, "invalidItem" end
  inBags = type(inBags) == "table" and inBags or {}
  local ok, reason = Rules.tradeable(inBags.isBound, inBags.bindType)
  if not ok then return nil, reason end
  if openCount(self) >= Rules.MAX_OPEN then return nil, "tooMany" end
  level = type(level) == "number" and level >= 0 and math.floor(level) or 0
  local character = self.ledger:playing()
  -- The id is never reused, even after leaving, nor after the counter is
  -- lost while the record still holds higher ids.
  return self.ledger:changeOwn(function(record)
    local id = Rules.nextId(record.spares, self.db.nextSpare)
    self.db.nextSpare = id + 1
    record.spares = record.spares or {}
    record.spares[#record.spares + 1] = Rules.item(id, item, level, self.now())
    -- The item GUID is kept for the Character being played, outside
    -- the record, so it never leaves this client.
    local itemGuid = inBags.guid
    if type(itemGuid) == "string" and itemGuid ~= "" and character then
      self.db.spareItems = self.db.spareItems or {}
      self.db.spareItems[character] = self.db.spareItems[character] or {}
      self.db.spareItems[character][id] = itemGuid
    end
    return id
  end)
end

-- The item GUIDs of the open Spares the Character being played
-- posted: { [id] = itemGuid }.
function Spares:items()
  forgetItems(self)
  local list = {}
  local items, playing = self.db.spareItems, self.ledger:playing()
  for id, itemGuid in pairs(items and playing and items[playing] or {}) do
    list[id] = itemGuid
  end
  return list
end

-- Withdraws an own open Spare. Returns true, or nil and "unknown".
function Spares:withdraw(id)
  if not openSpare(self, self.ledger:memberId(), id) then return nil, "unknown" end
  self.ledger:changeOwn(function(record)
    local index = indexOf(record.spares, function(item) return item.i == id end)
    if index then table.remove(record.spares, index) end
    return index ~= nil
  end)
  check(self, true)
  return true
end

-- Gives an own open Spare to the winning Claim's Character, which is
-- final: it stays in the record, so every client sees the recipient,
-- until its 30 days run out. Makes your own gave entry. expected is the
-- winner's Member id as you were shown it, if any. Returns true, or nil
-- and "unknown", "noClaim" or "winnerChanged".
function Spares:give(id, expected)
  local spare = openSpare(self, self.ledger:memberId(), id)
  if not spare then return nil, "unknown" end
  local winner = winnerOf(self, self.ledger:memberId(), id)
  if not winner then return nil, "noClaim" end
  if expected ~= nil and winner.memberId ~= expected then return nil, "winnerChanged" end
  self.ledger:changeOwn(function(record)
    local index = indexOf(record.spares, function(item) return item.i == id end)
    if index then record.spares[index].r, record.spares[index].c = winner.memberId, winner.guid end
    return index ~= nil
  end)
  self.feed:ownGave({ id = id, item = spare.item, to = winner.memberId, guid = winner.guid })
  check(self, true)
  return true
end

-- The bags have settled: checks where the item of each open Spare the
-- Character being played posted is (docs/adr/0004). A gone item is noted
-- on its row; at the first check after a real login one with no Claim is
-- withdrawn and one with a Claim asked about, each told to the listener as
-- spareGone, after wrote() for each withdrawal (Core sends the own record
-- then). Returns whether the tab changed otherwise.
function Spares:bagsUpdated(wrote)
  if not (self.findItem and self.ledger:playing()) then return false end
  local isNextLogin = self.loginCheckDue
  self.loginCheckDue = false
  local rows, changed = {}, false
  for _, row in ipairs(yourRows(self)) do rows[row.id] = row end
  for id, itemGuid in pairs(self:items()) do
    local row = rows[id]
    local isOpen = row ~= nil and openSpare(self, self.ledger:memberId(), id) ~= nil
    local hasClaim = isOpen and row.winner ~= nil
    local inInventory, isEquipped = self.findItem(itemGuid)
    local action = Rules.itemCheck(isOpen, hasClaim, inInventory, isEquipped, isNextLogin)
    local isGone = action == "note" or action == "ask"
    if isGone ~= (self.goneItems[id] == true) then
      self.goneItems[id] = isGone or nil
      changed = true
    end
    if action == "withdraw" then
      self:withdraw(id)
      wrote()
      self.listener("spareGone", { action = "withdrawn", id = id, item = row.item, link = row.link })
    elseif action == "ask" then
      self.listener("spareGone", { action = "ask", id = id, item = row.item, link = row.link, winner = row.winner })
    end
  end
  return changed
end

-- Claims another Member's open Spare for one of your Characters by
-- GUID, by default the one being played. Returns true, or nil and "own",
-- "unknown" (not held, ended, or its owner Removed or Left), "claimed",
-- "tooManyClaims" or "unknownCharacter".
function Spares:claim(owner, id, guid)
  if owner == self.ledger:memberId() then return nil, "own" end
  if type(owner) ~= "string" or not openSpare(self, owner, id) then return nil, "unknown" end
  if ownClaim(self, owner, id) then return nil, "claimed" end
  if claimCount(self) >= Rules.MAX_CLAIMS then return nil, "tooManyClaims" end
  guid = guid or self.ledger:playing()
  local own = self.ledger:own()
  if type(guid) ~= "string" or not (own and own.characters[guid]) then return nil, "unknownCharacter" end
  self.ledger:changeOwn(function(record)
    record.claims = record.claims or {}
    record.claims[#record.claims + 1] = Rules.claim(owner, id, guid, self.now())
    return true
  end)
  return true
end

-- Withdraws your Claim, until the Spare is Given. Returns true, or nil
-- and "notClaimed" or "given".
function Spares:withdrawClaim(owner, id)
  if not ownClaim(self, owner, id) then return nil, "notClaimed" end
  local spare = find(self, owner, id)
  if spare and spare.to then return nil, "given" end
  self.ledger:changeOwn(function(record)
    local index = indexOf(record.claims, function(item) return item.m == owner and item.i == id end)
    if index then table.remove(record.claims, index) end
    return index ~= nil
  end)
  return true
end

-- Someone else's record was kept: before is the copy held until now (nil
-- on first sight) and after the new one. A Spare newly Given to
-- you is news, and so is a Claim becoming the winning one on yours; on
-- first sight neither is. Returns the news.
function Spares:recordChanged(before, after)
  local news = {}
  local me = self.ledger:memberId()
  if before ~= nil and not after.left then
    for _, spare in ipairs(Rules.newlyGiven(before, after)) do
      if spare.to == me then
        news[#news + 1] = addNews(self, {
          kind = "given", memberId = after.id, guid = spare.guid, id = spare.id, item = spare.item,
        })
      end
    end
  end
  for _, item in ipairs(check(self, before == nil)) do news[#news + 1] = item end
  return news
end

-- A Member was Removed: their Claims stop counting, quietly.
function Spares:memberRemoved()
  check(self, true)
end

-- A notice as handed out, for the chat line, the toast and While you were
-- away: { kind ("claimed" or "given"), text, time, opens }. opens is the
-- panel tab a click on its toast opens.
function Spares:describe(news)
  local text
  local record = self.ledger:record(news.memberId)
  if news.kind == "claimed" then
    text = ("%s claimed %s for %s"):format(memberName(self, record),
      Rules.linkText(self.itemLink, news.item), characterName(record, news.guid))
  else
    text = ("%s sent you %s. Check %s's mailbox."):format(memberName(self, record),
      Rules.linkText(self.itemLink, news.item), characterName(self.ledger:own(), news.guid))
  end
  return { kind = news.kind, text = text, time = news.time, opens = "spares" }
end

-- Marks a notice seen, as Core does when it fires.
function Spares:markSeen(news)
  news.seen = true
end

-- The unseen notices, newest first, as describe() gives them. Marks them
-- seen.
function Spares:takeNews()
  local lines = {}
  for _, news in ipairs(self.db.spareNews) do
    if not news.seen then
      news.seen = true
      table.insert(lines, 1, self:describe(news))
    end
  end
  return lines
end

-- Marks every notice seen. Returns true if any wasn't.
function Spares:markAllSeen()
  local any = false
  for _, news in ipairs(self.db.spareNews) do
    if not news.seen then
      news.seen = true
      any = true
    end
  end
  return any
end

-- How many notices haven't been seen.
function Spares:unseen()
  local count = 0
  for _, news in ipairs(self.db.spareNews) do
    if not news.seen then count = count + 1 end
  end
  return count
end

-- Leaving the Crew clears the own Spares and Claims (not a write, like
-- clearing Reactions), the item GUIDs, the notices and the winners.
function Spares:clear()
  self.ledger:changeOwn(function(record)
    record.spares, record.claims = nil, nil
    return false
  end)
  self.db.spareItems = nil
  self.db.spareNews = {}
  self.db.spareWinners = {}
end

-- Called once a second in a Crew: prunes the notices, and now and then
-- works out the winners quietly, so a Claim expiring isn't news.
function Spares:tick()
  local now = self.now()
  local list = self.db.spareNews
  while list[1] and (#list > KEEP_MAX or now - list[1].time > KEEP_FOR) do
    table.remove(list, 1)
  end
  if now - self.lastQuietCheck >= QUIET_CHECK_EVERY then
    self.lastQuietCheck = now
    check(self, true)
  end
end
