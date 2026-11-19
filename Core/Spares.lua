local _, ns = ...

local Spares = {}
Spares.__index = Spares
ns.Spares = Spares

local Rules = ns.SpareRules

local DAY = 24 * 60 * 60
local KEEP_FOR = 30 * DAY
local KEEP_MAX = 50
local QUIET_CHECK_EVERY = 60

Spares.itemString = Rules.itemString

Spares.newlyGiven = Rules.newlyGiven

-- WoW: the game has no link for an item until the client has cached it.
Spares.linkText = Rules.linkText

Spares.NO_LINK = Rules.NO_LINK

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
    goneItems = {},
    -- WoW: the vendor buyback list survives a /reload, not a logout.
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

local function shown(self, record)
  return record ~= nil and not record.left and not self.ledger:isRemoved(record.id)
end

local function find(self, owner, id)
  local record = self.ledger:record(owner)
  if owner ~= self.ledger:memberId() and not shown(self, record) then return nil end
  for _, spare in ipairs(Rules.inRecord(record)) do
    if spare.id == id then return spare, record end
  end
  return nil
end

local function openSpare(self, owner, id)
  local spare = find(self, owner, id)
  if spare and Rules.isOpen(spare, self.now()) then return spare end
  return nil
end

local function indexOf(list, matches)
  for index, item in ipairs(list or {}) do
    if matches(item) then return index end
  end
  return nil
end

local function ownSpares(self)
  return Rules.inRecord(self.ledger:own())
end

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

local function winnerOf(self, owner, id)
  local claims = claimsOn(self, owner, id)
  return Rules.winner(claims), #claims
end

local function ownClaim(self, owner, id)
  for _, claim in ipairs(Rules.claimsIn(self.ledger:own())) do
    if claim.owner == owner and claim.id == id then return claim end
  end
  return nil
end

local function highestLevel(self)
  local own = self.ledger:own()
  local highest = 0
  for _, character in pairs(own and own.characters or {}) do
    highest = math.max(highest, character.level)
  end
  return highest
end

local function openCount(self)
  local count, me = 0, self.ledger:memberId()
  for _, spare in ipairs(ownSpares(self)) do
    if openSpare(self, me, spare.id) then count = count + 1 end
  end
  return count
end

local function claimCount(self)
  local count = 0
  for _, claim in ipairs(Rules.claimsIn(self.ledger:own())) do
    if openSpare(self, claim.owner, claim.id) then count = count + 1 end
  end
  return count
end

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

function Spares:prune(record, now)
  if record.spares then Rules.prune(record.spares, now) end
  if record.claims then
    Rules.pruneClaims(record.claims, now, function(owner, id) return openSpare(self, owner, id) ~= nil end)
  end
  forgetItems(self)
end

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
  local ownerName = memberName(self, record)
  local usable = highest >= spare.level
  return {
    ownerId = owner,
    owner = ownerName,
    id = id,
    item = item,
    link = self.itemLink(item),
    level = spare.level,
    time = spare.time,
    expires = spare.time + Rules.KEEP_FOR - self.now(),
    usable = usable,
    winner = winner and who(self, winner.memberId, winner.guid),
    claims = count,
    claimed = mine ~= nil,
    claimCharacter = mine and characterName(self.ledger:own(), mine.guid),
    canClaim = mine == nil,
    state = state,
    info = ("%s · %s"):format(ownerName, state),
    primary = mine == nil and { label = "Claim", enabled = true } or nil,
    secondary = mine ~= nil and { label = "Withdraw" } or nil,
    highlight = winner ~= nil and winner.memberId == me,
    dimmed = not usable,
  }
end

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
  local expires = spare.time + Rules.KEEP_FOR - self.now()
  local gone = (not given and self.goneItems[id]) or nil
  local info
  if gone then
    info = "This item has left your bags · " .. state
  elseif given then
    info = state
  else
    info = ("%s · %s"):format(expires > 0 and ns.Text.ago(expires) .. " left" or "ending", state)
  end
  return {
    id = id,
    item = item,
    link = self.itemLink(item),
    level = spare.level,
    time = spare.time,
    expires = expires,
    winner = winner and who(self, winner.memberId, winner.guid),
    claims = count,
    given = given,
    canGive = winner ~= nil,
    canWithdraw = given == nil,
    gone = gone,
    state = state,
    info = info,
    primary = not given and { label = "Give", enabled = winner ~= nil } or nil,
    secondary = not given and { label = "Withdraw" } or nil,
    highlight = winner ~= nil or gone == true,
    dimmed = given ~= nil,
  }
end

local function newestFirst(a, b)
  if a.time ~= b.time then return a.time > b.time end
  if (a.ownerId or "") ~= (b.ownerId or "") then return (a.ownerId or "") < (b.ownerId or "") end
  return a.id > b.id
end

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

local function yourRows(self)
  local rows, now = {}, self.now()
  for _, spare in ipairs(ownSpares(self)) do
    if spare.to or Rules.isOpen(spare, now) then rows[#rows + 1] = yourRow(self, spare) end
  end
  table.sort(rows, newestFirst)
  return rows
end

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

function Spares:usableCount()
  local count = 0
  for _, row in ipairs(crewRows(self)) do
    if row.usable then count = count + 1 end
  end
  return count
end

local function addNews(self, news)
  news.time = self.now()
  local list = self.db.spareNews
  list[#list + 1] = news
  return news
end

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
  return self.ledger:changeOwn(function(record)
    local id = Rules.nextId(record.spares, self.db.nextSpare)
    self.db.nextSpare = id + 1
    record.spares = record.spares or {}
    record.spares[#record.spares + 1] = Rules.item(id, item, level, self.now())
    local itemGuid = inBags.guid
    if type(itemGuid) == "string" and itemGuid ~= "" and character then
      self.db.spareItems = self.db.spareItems or {}
      self.db.spareItems[character] = self.db.spareItems[character] or {}
      self.db.spareItems[character][id] = itemGuid
    end
    return id
  end)
end

function Spares:items()
  forgetItems(self)
  local list = {}
  local items, playing = self.db.spareItems, self.ledger:playing()
  for id, itemGuid in pairs(items and playing and items[playing] or {}) do
    list[id] = itemGuid
  end
  return list
end

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

function Spares:memberRemoved()
  check(self, true)
end

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

function Spares:markSeen(news)
  news.seen = true
end

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

function Spares:unseen()
  local count = 0
  for _, news in ipairs(self.db.spareNews) do
    if not news.seen then count = count + 1 end
  end
  return count
end

function Spares:clear()
  self.ledger:changeOwn(function(record)
    record.spares, record.claims = nil, nil
    return false
  end)
  self.db.spareItems = nil
  self.db.spareNews = {}
  self.db.spareWinners = {}
end

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
