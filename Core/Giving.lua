-- Giving: the Hand-me-downs tab's state, worked out from the Ledger's
-- records. Each Hand-me-down is in its owner's record and each Claim in
-- its claimer's; this finds the Claims every held record makes on a
-- Hand-me-down and shows the earliest as winning, until the owner's Give
-- names the recipient instead (docs/adr/0003). Removed Members aren't
-- held, so their Hand-me-downs and Claims are gone too; Left ones are
-- skipped. Also keeps the notices: the owner hears when a Claim becomes
-- the winning one, and the winning claimer when it's Given, each with a
-- seen flag like Reactions. See docs/design/hand-me-downs.md.

local _, ns = ...

local Giving = {}
Giving.__index = Giving
ns.Giving = Giving

local HandMeDowns = ns.HandMeDowns

local DAY = 24 * 60 * 60
-- Notices are kept this long, and at most this many.
local KEEP_FOR = 30 * DAY
local KEEP_MAX = 50
-- Claims expire on their own (30 days); the winners are checked this
-- often so one moving up that way is silent.
local QUIET_CHECK_EVERY = 60

-- db is the whole saved table; Giving keeps `handMeDownNews` (the
-- notices, oldest first) and `handMeDownWinners` (the winning Member id
-- last told of, per own Hand-me-down id). itemLink(itemString) is the
-- game's link for an item string, or nil while it isn't cached.
function Giving.new(db, ledger, now, itemLink)
  db.handMeDownNews = db.handMeDownNews or {}
  db.handMeDownWinners = db.handMeDownWinners or {}
  return setmetatable({
    db = db,
    ledger = ledger,
    now = now,
    itemLink = itemLink or function() return nil end,
    lastQuietCheck = now(),
  }, Giving)
end

local function memberName(self, record)
  if not record then return "Someone" end
  if record.displayName then return record.displayName end
  local main = ns.Roster.main(record, self.now())
  return main and main.name or "Someone"
end

local function characterName(record, guid)
  local character = record and record.characters and record.characters[guid]
  return character and character.name or "?"
end

-- The item's link for the texts, "an item" until the game has it.
local function linkText(self, item)
  return self.itemLink(HandMeDowns.itemLink(item)) or "an item"
end

-- Whether a Member's record counts: held, not Left, not Removed.
local function shown(self, record)
  return record ~= nil and not record.left and not self.ledger:isRemoved(record.id)
end

-- The Claims every counted record makes on one Hand-me-down, as
-- { memberId, guid, time }. The owner's own never count.
local function claimsOn(self, owner, id)
  local now = self.now()
  local list = {}
  for memberId, record in self.ledger:records() do
    if memberId ~= owner and shown(self, record) then
      for _, claim in ipairs(HandMeDowns.claimsIn(record)) do
        if claim.owner == owner and claim.id == id and now - claim.time <= HandMeDowns.KEEP_FOR then
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

-- A Hand-me-down by owner and id, as in HandMeDowns.inRecord, while its
-- owner counts. Nil otherwise.
local function find(self, owner, id)
  local record = self.ledger:record(owner)
  if not shown(self, record) then return nil end
  for _, handMeDown in ipairs(HandMeDowns.inRecord(record)) do
    if handMeDown.id == id then return handMeDown, record end
  end
  return nil
end

-- The winning Claim on a Hand-me-down, { memberId, guid, time }, and how
-- many Claims there are.
local function winnerOf(self, owner, id)
  local claims = claimsOn(self, owner, id)
  return HandMeDowns.winner(claims), #claims
end

-- The own Claim on a Hand-me-down, as stored, or nil.
local function ownClaim(self, owner, id)
  for _, claim in ipairs(HandMeDowns.claimsIn(self.ledger:own())) do
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

-- How many own Hand-me-downs are open.
function Giving:openCount()
  local count = 0
  for _, handMeDown in ipairs(HandMeDowns.inRecord(self.ledger:own())) do
    if HandMeDowns.isOpen(handMeDown, self.now()) then count = count + 1 end
  end
  return count
end

-- How many own Claims are open: their Hand-me-down still is.
function Giving:claimCount()
  local count = 0
  for _, claim in ipairs(HandMeDowns.claimsIn(self.ledger:own())) do
    local handMeDown = find(self, claim.owner, claim.id)
    if handMeDown and HandMeDowns.isOpen(handMeDown, self.now()) then count = count + 1 end
  end
  return count
end

-- An own open Hand-me-down by id, or nil.
function Giving:ownOpen(id)
  for _, handMeDown in ipairs(HandMeDowns.inRecord(self.ledger:own())) do
    if handMeDown.id == id and HandMeDowns.isOpen(handMeDown, self.now()) then return handMeDown end
  end
  return nil
end

-- Who an own Hand-me-down would go to now: { memberId, guid, time }, or nil.
function Giving:winnerOf(id)
  return (winnerOf(self, self.ledger:memberId(), id))
end

-- Whether you may Claim another Member's Hand-me-down for a Character
-- (default the one being played). Returns the GUID, or nil and "own",
-- "unknown" (not held, ended, or its owner Removed or Left), "claimed",
-- "tooMany" or "unknownCharacter".
function Giving:canClaim(owner, id, guid)
  if owner == self.ledger:memberId() then return nil, "own" end
  local handMeDown = type(owner) == "string" and find(self, owner, id)
  if not handMeDown or not HandMeDowns.isOpen(handMeDown, self.now()) then return nil, "unknown" end
  if ownClaim(self, owner, id) then return nil, "claimed" end
  if self:claimCount() >= HandMeDowns.MAX_CLAIMS then return nil, "tooMany" end
  guid = guid or self.ledger.playingGuid
  local own = self.ledger:own()
  if type(guid) ~= "string" or not (own and own.characters[guid]) then return nil, "unknownCharacter" end
  return guid
end

-- Whether you may withdraw your Claim. Returns true, or nil and "unknown"
-- (no such Claim) or "given".
function Giving:canWithdrawClaim(owner, id)
  if not ownClaim(self, owner, id) then return nil, "unknown" end
  local handMeDown = find(self, owner, id)
  if handMeDown and handMeDown.to then return nil, "given" end
  return true
end

-- A row of "From the Crew": another Member's open Hand-me-down.
local function crewRow(self, record, handMeDown, highest)
  local owner, id = record.id, handMeDown.id
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
  local item = HandMeDowns.itemLink(handMeDown.item)
  return {
    ownerId = owner,
    owner = memberName(self, record),
    id = id,
    item = item,
    link = self.itemLink(item),
    level = handMeDown.level,
    time = handMeDown.time,
    expires = handMeDown.time + HandMeDowns.KEEP_FOR - self.now(),
    usable = highest >= handMeDown.level,
    winner = winner and who(self, winner.memberId, winner.guid),
    claims = count,
    claimed = mine ~= nil,
    claimCharacter = mine and characterName(self.ledger:own(), mine.guid),
    canClaim = mine == nil,
    state = state,
  }
end

-- A row of "Yours": an own Hand-me-down, open or Given.
local function yourRow(self, handMeDown)
  local id = handMeDown.id
  local winner, count = winnerOf(self, self.ledger:memberId(), id)
  local given = handMeDown.to and who(self, handMeDown.to, handMeDown.guid)
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
  local item = HandMeDowns.itemLink(handMeDown.item)
  return {
    id = id,
    item = item,
    link = self.itemLink(item),
    level = handMeDown.level,
    time = handMeDown.time,
    expires = handMeDown.time + HandMeDowns.KEEP_FOR - self.now(),
    winner = winner and who(self, winner.memberId, winner.guid),
    claims = count,
    given = given,
    canGive = winner ~= nil,
    canWithdraw = given == nil,
    state = state,
  }
end

local function newestFirst(a, b)
  if a.time ~= b.time then return a.time > b.time end
  if (a.ownerId or "") ~= (b.ownerId or "") then return (a.ownerId or "") < (b.ownerId or "") end
  return a.id > b.id
end

-- Every other counted Member's open Hand-me-downs, as rows.
local function crewRows(self)
  local rows, now, highest = {}, self.now(), highestLevel(self)
  local me = self.ledger:memberId()
  for id, record in self.ledger:records() do
    if id ~= me and shown(self, record) then
      for _, handMeDown in ipairs(HandMeDowns.inRecord(record)) do
        if HandMeDowns.isOpen(handMeDown, now) then rows[#rows + 1] = crewRow(self, record, handMeDown, highest) end
      end
    end
  end
  table.sort(rows, newestFirst)
  return rows
end

-- The tab: { crew, yours, unseen, claims, maxClaims, open, maxOpen }.
function Giving:view()
  local yours, now = {}, self.now()
  for _, handMeDown in ipairs(HandMeDowns.inRecord(self.ledger:own())) do
    if handMeDown.to or HandMeDowns.isOpen(handMeDown, now) then yours[#yours + 1] = yourRow(self, handMeDown) end
  end
  table.sort(yours, newestFirst)
  return {
    crew = crewRows(self),
    yours = yours,
    unseen = self:unseen(),
    claims = self:claimCount(),
    maxClaims = HandMeDowns.MAX_CLAIMS,
    open = self:openCount(),
    maxOpen = HandMeDowns.MAX_OPEN,
  }
end

-- Other Members' open Hand-me-downs one of your Characters is high enough
-- level for, for the Roster.
function Giving:usableCount()
  local count = 0
  for _, row in ipairs(crewRows(self)) do
    if row.usable then count = count + 1 end
  end
  return count
end

local function addNews(self, news)
  news.time = self.now()
  local list = self.db.handMeDownNews
  list[#list + 1] = news
  return news
end

-- Works out who wins each own open Hand-me-down. A winner that changed
-- to a Member is news to you, unless quiet (first sight of a Member,
-- removing one, Claims expiring). Returns the news.
function Giving:check(quiet)
  local news, open = {}, {}
  local winners = self.db.handMeDownWinners
  local me = self.ledger:memberId()
  for _, handMeDown in ipairs(HandMeDowns.inRecord(self.ledger:own())) do
    if HandMeDowns.isOpen(handMeDown, self.now()) then
      local id = handMeDown.id
      open[id] = true
      local winner = winnerOf(self, me, id)
      local memberId = winner and winner.memberId
      if memberId ~= winners[id] then
        winners[id] = memberId
        if memberId and not quiet then
          news[#news + 1] = addNews(self, {
            kind = "claimed", memberId = memberId, guid = winner.guid, id = id, item = handMeDown.item,
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

-- Someone else's record was kept: before is the copy held until now (nil
-- on first sight) and after the new one. A Hand-me-down newly Given to
-- you is news, and so is a Claim becoming the winning one on yours; on
-- first sight neither is. Returns the news.
function Giving:recordChanged(before, after)
  local news = {}
  local me = self.ledger:memberId()
  if before ~= nil and not after.left then
    local had = {}
    for _, handMeDown in ipairs(HandMeDowns.inRecord(before)) do
      if handMeDown.to then had[handMeDown.id] = true end
    end
    for _, handMeDown in ipairs(HandMeDowns.inRecord(after)) do
      if handMeDown.to == me and not had[handMeDown.id] then
        news[#news + 1] = addNews(self, {
          kind = "given", memberId = after.id, guid = handMeDown.guid, id = handMeDown.id, item = handMeDown.item,
        })
      end
    end
  end
  for _, item in ipairs(self:check(before == nil)) do news[#news + 1] = item end
  return news
end

-- A notice as handed out, for the chat line, the toast and While you were
-- away: { kind ("claimed" or "given"), text, time, opens }. opens is the
-- panel tab a click on its toast opens.
function Giving:describe(news)
  local text
  local record = self.ledger:record(news.memberId)
  if news.kind == "claimed" then
    text = ("%s claimed %s for %s"):format(memberName(self, record), linkText(self, news.item),
      characterName(record, news.guid))
  else
    text = ("%s sent you %s. Check %s's mailbox."):format(memberName(self, record), linkText(self, news.item),
      characterName(self.ledger:own(), news.guid))
  end
  return { kind = news.kind, text = text, time = news.time, opens = "handMeDowns" }
end

function Giving:markSeen(news)
  news.seen = true
end

-- The unseen notices, newest first, as describe() gives them. Marks them
-- seen.
function Giving:takeNews()
  local lines = {}
  for _, news in ipairs(self.db.handMeDownNews) do
    if not news.seen then
      news.seen = true
      table.insert(lines, 1, self:describe(news))
    end
  end
  return lines
end

-- Marks every notice seen. Returns true if any wasn't.
function Giving:markAllSeen()
  local any = false
  for _, news in ipairs(self.db.handMeDownNews) do
    if not news.seen then
      news.seen = true
      any = true
    end
  end
  return any
end

function Giving:unseen()
  local count = 0
  for _, news in ipairs(self.db.handMeDownNews) do
    if not news.seen then count = count + 1 end
  end
  return count
end

-- Leaving the Crew forgets the notices and winners.
function Giving:clear()
  self.db.handMeDownNews = {}
  self.db.handMeDownWinners = {}
end

-- Called once a second: prunes the notices, and now and then works out
-- the winners quietly, so a Claim expiring isn't news.
function Giving:tick()
  local now = self.now()
  local list = self.db.handMeDownNews
  while list[1] and (#list > KEEP_MAX or now - list[1].time > KEEP_FOR) do
    table.remove(list, 1)
  end
  if now - self.lastQuietCheck >= QUIET_CHECK_EVERY then
    self.lastQuietCheck = now
    self:check(true)
  end
end
