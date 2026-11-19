local _, ns = ...

local Feed = {}
Feed.__index = Feed
ns.Feed = Feed

local Reactions = ns.Reactions
local Spares = ns.Spares

local DAY = 24 * 60 * 60
local KEEP_FOR = 30 * DAY
local KEEP_MAX = 200

local CLASS_NAMES = {
  DEATHKNIGHT = "Death Knight",
  DEMONHUNTER = "Demon Hunter",
}

local function className(classFilename)
  if not classFilename then return "?" end
  return CLASS_NAMES[classFilename] or classFilename:sub(1, 1) .. classFilename:sub(2):lower()
end

function Feed.new(db, ledger, now, maxLevel, initialLogin, itemLink, itemLook)
  db.feed = db.feed or {}
  db.feedJoins = db.feedJoins or {}
  return setmetatable({
    db = db,
    ledger = ledger,
    now = now,
    maxLevel = maxLevel,
    itemLink = itemLink or Spares.NO_LINK,
    itemLook = itemLook or function() return nil end,
    settle = ns.Settle.new(now, not initialLogin),
  }, Feed)
end

local function memberName(self, record)
  return ns.Roster.memberName(record, self.now())
end

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
    seen = own or nil,
  }
end

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

  local deaths = (character.deaths or 0) - (was.deaths or 0)
  if deaths > 0 then
    local times = deaths == 1 and "" or (" %d times"):format(deaths)
    local entry = newEntry("death", record, own,
      ("%s died%s"):format(subject(self, record, character, own), times), character)
    entry.count, entry.to = deaths, character.deaths
    list[#list + 1] = entry
  end

  for _, news in ipairs(ns.Professions.news(was.professions, character.professions)) do
    local who = subject(self, record, character, own)
    local text
    if news.kind == "newProfession" then
      text = ("%s picked up %s"):format(who, news.name)
    elseif news.kind == "professionMaxed" then
      text = ("%s maxed %s"):format(who, news.name)
    else
      text = ("%s reached %d %s"):format(who, news.milestone, news.name)
    end
    local entry = newEntry(news.kind, record, own, text, character)
    entry.skillLine, entry.profession, entry.icon = news.skillLine, news.name, news.icon
    entry.from, entry.milestone = news.from, news.milestone
    list[#list + 1] = entry
  end
end

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

local function find(self, key)
  local log = self.db.feed
  for i = #log, 1, -1 do
    if Reactions.matches(log[i], key) then return log[i] end
  end
  return nil
end

local function attachHeld(self, entry)
  if not Reactions.forKind(entry.kind) then return end
  for id, record in self.ledger:records() do
    for _, item in ipairs(Reactions.inRecord(record)) do
      if Reactions.matches(entry, item.key) then attach(entry, id, item.key, item.time, true) end
    end
  end
end

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

local function reactionsChanged(self, before, after)
  local news, attached = {}, {}
  if after.left then return news, attached end
  local had = {}
  for _, item in ipairs(Reactions.inRecord(before)) do had[Reactions.id(item.key)] = true end
  for _, item in ipairs(Reactions.inRecord(after)) do
    local entry = not had[Reactions.id(item.key)] and find(self, item.key)
    if entry then
      local reaction = attach(entry, after.id, item.key, item.time, before == nil or not entry.own)
      if reaction and not reaction.seen then news[#news + 1] = { entry = entry, reaction = reaction } end
      if reaction and before ~= nil then attached[#attached + 1] = { entry = entry, reaction = reaction } end
    end
  end
  return news, attached
end

local function joinedAfterYou(self, record)
  local own = self.ledger:own()
  local yours = own and own.joinedAt
  return record.joinedAt ~= nil and yours ~= nil and record.joinedAt > yours
end

local function crewEntry(self, kind, record)
  local verb = kind == "joined" and " joined the Crew" or " left the Crew"
  local entry = newEntry(kind, record, false, memberName(self, record) .. verb)
  if kind == "joined" then entry.joinedAt = record.joinedAt end
  return entry
end

local function hasGave(self, owner, id)
  for _, entry in ipairs(self.db.feed) do
    if entry.kind == "gave" and entry.memberId == owner and entry.spare == id then return true end
  end
  return false
end

local function gaveEntry(self, record, own, spare)
  local entry = newEntry("gave", record, own, nil)
  entry.time = own and self.now() or record.version
  entry.spare, entry.item, entry.recipient = spare.id, spare.item, spare.to
  if spare.to == self.ledger:memberId() then entry.seen = true end
  return entry
end

local function gaveEntries(self, before, after, list)
  for _, spare in ipairs(Spares.newlyGiven(before, after)) do
    if not hasGave(self, after.id, spare.id) then
      list[#list + 1] = gaveEntry(self, after, false, spare)
    end
  end
end

local function caughtText(who, item)
  return ("%s caught %s"):format(who, item)
end

local function rareEntries(self, had, record, own, list)
  local records = {}
  for _, held in self.ledger:records() do
    if not held.left then records[#records + 1] = held end
  end
  for _, rare in ipairs(ns.Catches.rareFinds(had, record, records)) do
    local character = rare.guid and record.characters[rare.guid]
    local who = character and subject(self, record, character, own)
      or own and "You" or memberName(self, record)
    local entry = newEntry("rareFind", record, own, caughtText(who, rare.name), character)
    entry.time = rare.time
    entry.catch, entry.itemId, entry.fish, entry.who = rare.id, rare.itemId, rare.name, who
    list[#list + 1] = entry
  end
end

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
    gaveEntries(self, before, after, list)
    rareEntries(self, ns.Catches.rareHeld(before), after, false, list)
  end
  return insert(self, list), reactionsChanged(self, before, after)
end

function Feed:ownJoined()
  local own = self.ledger:own()
  local entry = newEntry("joined", own, true, "You joined the Crew")
  entry.joinedAt = own.joinedAt
  return insert(self, { entry })
end

function Feed:ownChanged(was, guid)
  local list = {}
  local own = self.ledger:own()
  local first = was == nil and next(own.characters, next(own.characters)) == nil
  if not first then characterEntries(self, own, was, own.characters[guid], true, list) end
  return insert(self, list)
end

function Feed:ownGave(spare)
  if hasGave(self, self.ledger:memberId(), spare.id) then return {} end
  return insert(self, { gaveEntry(self, self.ledger:own(), true, spare) })
end

function Feed:ownCaught(had)
  local list = {}
  rareEntries(self, had, self.ledger:own(), true, list)
  return insert(self, list)
end

function Feed:goalsReached(reached)
  local list = {}
  for _, goal in ipairs(reached) do
    list[#list + 1] = { kind = "goal", time = self.now(), track = goal.track, rung = goal.rung, text = goal.text }
  end
  return insert(self, list)
end

function Feed:dropMember(id)
  local log = self.db.feed
  for i = #log, 1, -1 do
    if log[i].memberId == id then table.remove(log, i) end
  end
end

function Feed:clear()
  self.db.feed = {}
  self.db.feedJoins = {}
end

function Feed:markSeen(item)
  item.seen = true
end

local function shown(self, reaction)
  return not self.ledger:isRemoved(reaction.by)
end

local function unseenReactions(self, entry)
  local list = {}
  if not entry.own then return list end
  for _, reaction in ipairs(entry.reactions or {}) do
    if not reaction.seen and shown(self, reaction) then list[#list + 1] = reaction end
  end
  return list
end

local function markAllSeen(self)
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

function Feed:open()
  local visit = self.visit or {}
  self.visit = visit
  for _, entry in ipairs(self.db.feed) do
    if not entry.seen or #unseenReactions(self, entry) > 0 then visit[entry] = true end
  end
  return markAllSeen(self)
end

function Feed:leave()
  self.visit = nil
end

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

local function gaveText(self, entry)
  local giver = entry.own and "You" or reactorName(self, entry.memberId)
  local recipient = entry.recipient == self.ledger:memberId() and "you" or reactorName(self, entry.recipient)
  return ("%s gave %s %s"):format(giver, recipient, Spares.linkText(self.itemLink, entry.item))
end

local function lookOf(self, entry)
  return entry.kind == "rareFind" and self.itemLook(entry.itemId) or {}
end

local function textOf(self, entry)
  if entry.kind == "gave" then return gaveText(self, entry) end
  local look = lookOf(self, entry)
  if look.text then return caughtText(entry.who, look.text) end
  return entry.text
end

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

local function phrase(self, entry)
  local own = self.ledger:own()
  local character = own and entry.guid and own.characters[entry.guid]
  local main = own and ns.Roster.main(own, self.now())
  local alt = character ~= nil and main ~= nil and character.guid ~= main.guid
  return Reactions.phrase(entry, character, alt)
end

function Feed:news(item)
  local name = reactorName(self, item.reaction.by)
  local words = phrase(self, item.entry)
  return {
    text = Reactions.text({ name }, words),
    reaction = Reactions.forKind(item.entry.kind),
    name = name,
    phrase = words,
    entryKey = Reactions.id(Reactions.keyOf(item.entry)),
    memberId = item.reaction.by,
  }
end

function Feed:react(key)
  key = Reactions.validKey(key)
  if not key then return nil end
  local me = self.ledger:memberId()
  if key.memberId == me or self.ledger:isRemoved(key.memberId) then return nil end
  local entry = find(self, key)
  if not entry or entry.own then return nil end
  if hasReacted(self, entry) then return nil, "reacted" end
  local reaction = attach(entry, me, key, self.now(), true)
  return key, nil, { entry = entry, reaction = reaction }
end

function Feed:campReaction(item)
  local entry, reaction = item.entry, item.reaction
  local ledger = self.ledger
  if ledger:isRemoved(reaction.by) or ledger:isRemoved(entry.memberId) then return nil end
  local owner = ledger:record(entry.memberId)
  if not owner or owner.left then return nil end
  local kind = Reactions.forKind(entry.kind)
  local played = { kind = kind, memberId = entry.memberId }
  if kind == "respects" then
    for _, other in ipairs(entry.reactions) do
      if other ~= reaction and shown(self, other) then return nil end
    end
    played.grave = Reactions.id(Reactions.keyOf(entry))
  end
  return played
end

function Feed:linkUp()
  self.settle:up()
end

function Feed:linkDown()
  self.settle:down()
end

function Feed:dataMerged()
  self.settle:data()
end

function Feed:isSettled()
  return self.settle:isSettled()
end

function Feed:tick()
  local now = self.now()
  local log = self.db.feed
  while log[1] and (#log > KEEP_MAX or now - log[1].time > KEEP_FOR) do
    table.remove(log, 1)
  end
  return self.settle:tick()
end

local HIGHLIGHTED = { maxLevel = true, joined = true, goal = true, professionMaxed = true }

local MEMBER_NEWS = { maxLevel = true, joined = true, left = true, goal = true }
local TAGS = { joined = true, left = true }

local function button(self, entry)
  local key = entry and Reactions.keyOf(entry)
  if not key then return nil end
  return { key = key, reacted = hasReacted(self, entry) }
end

local function cheerRank(entry)
  if entry.kind == "maxLevel" then return 1000 end
  if entry.kind == "ding" then return entry.level end
  if entry.kind == "newCharacter" then return 0 end
  return nil
end

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
  if row.new then
    row.gained = "new"
  elseif row.from then
    row.gained = "+" .. (row.level - row.from)
  end
  row.cheer, row.respects = button(self, cheer), button(self, respects)
  return any and row or nil
end

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
    tags = {},
  }

  local byCharacter, characters = {}, {}
  for _, entry in ipairs(entries) do
    block.time = math.max(block.time, entry.time)
    if MEMBER_NEWS[entry.kind] then
      block.highlights[#block.highlights + 1] = { kind = entry.kind, text = entry.text }
    end
    if TAGS[entry.kind] then
      block.tags[#block.tags + 1] = { text = entry.kind, highlight = HIGHLIGHTED[entry.kind] == true }
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
    if row then
      if not row.main then
        row.label = "Alt " .. row.name
      elseif row.name ~= block.displayName then
        row.label = row.name
      end
      block.characters[#block.characters + 1] = row
    end
  end
  return block
end

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

function Feed:takeSummary(spares, newTypesLine)
  spares = spares or {}
  local byMember, ids, goals, gives, professions, catches, count = {}, {}, {}, {}, {}, {}, 0
  for _, entry in ipairs(self.db.feed) do
    if not entry.seen and ns.Professions.KINDS[entry.kind] then
      entry.seen = true
      count = count + 1
      table.insert(professions, 1, {
        kind = entry.kind, text = entry.text, time = entry.time, icon = entry.icon, cheer = button(self, entry),
        highlight = HIGHLIGHTED[entry.kind] == true,
      })
    elseif not entry.seen and entry.kind == "rareFind" then
      entry.seen = true
      count = count + 1
      table.insert(catches, 1, {
        kind = entry.kind, text = textOf(self, entry), time = entry.time, icon = lookOf(self, entry).icon,
        cheer = button(self, entry),
      })
    elseif not entry.seen and entry.kind == "goal" then
      entry.seen = true
      count = count + 1
      table.insert(goals, 1, { text = entry.text, time = entry.time })
    elseif not entry.seen and entry.kind == "gave" then
      entry.seen = true
      count = count + 1
      table.insert(gives, 1, { kind = "gave", text = gaveText(self, entry), time = entry.time })
    elseif not entry.seen then
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
  if newTypesLine then
    count = count + 1
    table.insert(catches, 1, { kind = "catches", text = newTypesLine })
  end
  local noticed = takeNoticed(self)
  if count == 0 and #noticed == 0 and #spares == 0 then return nil end
  for _, give in ipairs(gives) do spares[#spares + 1] = give end

  local members = {}
  for i, id in ipairs(ids) do members[i] = memberBlock(self, id, byMember[id]) end
  table.sort(members, function(a, b)
    if a.time ~= b.time then return a.time > b.time end
    return a.memberId < b.memberId
  end)
  return {
    members = members, goals = goals, spares = spares, professions = professions, catches = catches, count = count,
    noticed = noticed,
    intro = count == 1 and "1 thing happened while you were away."
      or ("%d things happened while you were away."):format(count),
    maxLevel = self.maxLevel,
  }
end

function Feed:describe(entry)
  local me = self.ledger:memberId()
  local reactors = {}
  for i, id in ipairs(reactorIds(self, entry)) do
    local you = id == me
    reactors[i] = { memberId = id, name = you and "You" or reactorName(self, id), you = you }
  end
  local key = Reactions.keyOf(entry)
  local look = lookOf(self, entry)
  return {
    kind = entry.kind,
    time = entry.time,
    memberId = entry.memberId,
    guid = entry.guid,
    text = textOf(self, entry),
    from = entry.from,
    level = entry.level,
    count = entry.count,
    skillLine = entry.skillLine,
    profession = entry.profession,
    milestone = entry.milestone,
    icon = look.icon or entry.icon,
    edge = look.edge,
    own = entry.own == true,
    seen = entry.seen == true and #unseenReactions(self, entry) == 0,
    highlight = HIGHLIGHTED[entry.kind] == true,
    new = self.visit ~= nil and self.visit[entry] == true,
    reaction = Reactions.forKind(entry.kind),
    key = key,
    reactors = reactors,
    reacted = hasReacted(self, entry),
    canReact = key ~= nil and not entry.own and not self.ledger:isRemoved(entry.memberId),
  }
end

function Feed:since(time)
  local list = {}
  local log = self.db.feed
  for i = #log, 1, -1 do
    if log[i].time < time then break end
    list[#list + 1] = self:describe(log[i])
  end
  return list
end

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
  for _, group in ipairs(days) do
    group.day = nil
    group.title = ns.Text.dayTitle(group.daysAgo, group.time, utcOffset)
  end
  return { days = days, unseen = self:unseen() }
end
