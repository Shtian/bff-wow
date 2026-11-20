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

Core.CAN_PLAY_LEVELS = ns.Roster.CAN_PLAY
Core.reactionText = ns.Reactions.text
Core.HIDE_AFTER_DAYS = ns.Roster.HIDE_AFTER / (24 * 60 * 60)
Core.DUNGEONS = ns.Dungeons.DUNGEONS
Core.DUNGEONS_LAYOUT = ns.Dungeons.LAYOUT
Core.CAMP_LAYOUT = ns.Camp.LAYOUT
Core.SEASONS = ns.Camp.SEASONS
Core.HATS = ns.Look.HATS
Core.PETS = ns.Look.PETS
Core.FINAL_BOSSES = ns.Clears.FINAL_BOSSES

Core.grouped = ns.Text.grouped

function Core.goldText(money)
  if type(money) ~= "number" then return nil end
  return "Gold: " .. ns.Text.grouped(math.floor(money / 10000))
end

function Core:setTrace(trace)
  self.trace = type(trace) == "function" and trace or nil
end

local function traceName(self, id, displayName)
  if id == self.ledger:memberId() then return self:displayName() or id end
  local record = self.ledger:record(id)
  return displayName or (record and record.displayName) or tostring(id)
end

local function traceRecord(self, record)
  if type(record) ~= "table" then return "?" end
  return ("%s (%s) v%s"):format(traceName(self, record.id, record.displayName),
    tostring(record.id), tostring(record.version))
end

local function traceVersions(self, versions)
  local items = {}
  for id, version in pairs(versions) do
    items[#items + 1] = ("%s v%s"):format(traceName(self, id), tostring(version))
  end
  table.sort(items)
  return table.concat(items, ", ")
end

local function sentLine(self, message, size, to)
  if message.type == "DIGEST" and type(message.versions) == "table" then
    local count = 0
    for _ in pairs(message.versions) do count = count + 1 end
    return ("send DIGEST%s · %d versions%s · %d B · %s"):format(to and (" to " .. to) or "", count,
      message.partial and " (more in turn)" or "", size, traceVersions(self, message.versions))
  end
  if message.type == "WHERE" then return ("send WHERE · %d B"):format(size) end
  if message.type == "DOING" then
    return ("send DOING · %s%s · %d B"):format(message.doing or "nothing",
      message.form and (" · " .. message.form) or "", size)
  end
  local records = {}
  for i, record in ipairs(type(message.records) == "table" and message.records or {}) do
    records[i] = traceRecord(self, record)
  end
  return ("send %s · %d B · %s"):format(tostring(message.type), size, table.concat(records, ", "))
end

local function traceReceived(self, record, kept)
  local line = traceRecord(self, record) .. (kept and " · merged" or " · not merged")
  if type(record) == "table" and type(record.version) == "number" then
    line = line .. (" · late %ds"):format(math.max(0, self.now() - record.version))
  end
  return line
end

local function sendMessage(self, message, to)
  message.from = self.ledger:memberId()
  local encoded = ns.Codec.encode(message)
  if self.trace then self.trace(sentLine(self, message, #encoded, to)) end
  self.link.send(encoded, to)
end

local function knownMembers(ledger)
  local known = {}
  for id in ledger:records() do known[id] = true end
  return known
end

local function shownSpot(self, row)
  local record = self.ledger:record(row.memberId)
  local live = record and self.where:spot(row.memberId, row.guid, record.version)
  if live then return { mapId = live.mapId, x = live.x, y = live.y } end
  if row.mapId and row.x and row.y then
    return { mapId = row.mapId, x = row.x, y = row.y, instance = row.instance }
  end
  return nil
end

function Core.new(deps)
  for name, kind in pairs(required) do
    if type(deps[name]) ~= kind then
      error(("Core.new: %s must be a %s"):format(name, kind), 2)
    end
  end
  if type(deps.link.send) ~= "function" then
    error("Core.new: link.send must be a function", 2)
  end

  local fresh = next(deps.db) == nil
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
    daylight = type(deps.daylight) == "function" and deps.daylight or function() end,
    finalBosses = type(deps.finalBosses) == "table" and deps.finalBosses or ns.Clears.FINAL_BOSSES,
    linkUp = false,
    upSince = nil,
    downSince = nil,
    doings = ns.Doing.new(deps.now),
  }, Core)
  local itemLink = type(deps.itemLink) == "function" and deps.itemLink or nil
  local itemLook = type(deps.itemLook) == "function" and deps.itemLook or nil
  self.feedState = ns.Feed.new(deps.db, self.ledger, deps.now, deps.maxLevel, self.initialLogin, itemLink, itemLook)
  self.sessionStart = deps.now()
  self.spareLife = ns.Spares.new({
    db = deps.db,
    ledger = self.ledger,
    feed = self.feedState,
    now = deps.now,
    listener = deps.listener,
    initialLogin = self.initialLogin,
    itemLink = itemLink,
    findItem = type(deps.findItem) == "function" and deps.findItem or nil,
  })
  self.crewGoals = ns.Goals.new(deps.db, self.ledger, deps.now, deps.maxLevel)
  local locate = type(deps.locate) == "function" and deps.locate or nil
  self.where = ns.Where.new(deps.now, locate)
  self.pocket = ns.Pocket.new({
    now = deps.now,
    ledger = self.ledger,
    feed = self.feedState,
    goals = self.crewGoals,
    spares = self.spareLife,
    doings = self.doings,
    listener = deps.listener,
    on = function() return self.db.crew ~= nil and self:setting("camp") and self:setting("pocketCamp") end,
    setting = function(key) return self:setting(key) end,
    season = function() return self:season() end,
    phase = function() return self:phase() end,
    spot = function(row) return shownSpot(self, row) end,
  })
  local Gossip = type(deps.gossip) == "table" and deps.gossip or ns.Gossip
  self.gossip = Gossip.new(self.ledger, deps.now, deps.random, function(message, to)
    sendMessage(self, message, to)
  end, locate and function()
    local location = self.where:read()
    local changed = self.ledger:locate(location)
    local own = self.ledger:own()
    if not changed and own and self.where:sentSince(own.version) then self.ledger:touch() end
    self.where:dataSent(location)
  end)
  self.gossip:setPaused(self:isPaused())
  self.playTracker = ns.PlayTimes.new(deps.db, deps.now)
  self.playTimesDue = true
  self.online = ns.Roster.online(self.ledger, deps.now())
  self.known = knownMembers(self.ledger)
  self.whatsNewState = ns.WhatsNew.new(deps.db, deps.version, deps.changelog, fresh)
  self.bffVersionOf = function(id)
    local record = self.ledger:record(id)
    return record and record.bff
  end
  return self
end

local HEAR_ALL_WITHIN = 2 * 60
local DEAF_AFTER = ns.Roster.ONLINE_FOR - HEAR_ALL_WITHIN

local function deaf(self, now)
  return self.upSince == nil or (self.downSince ~= nil and now - self.downSince >= DEAF_AFTER)
end

local function hearsEveryone(self, now)
  return self.upSince ~= nil and self.downSince == nil and now - self.upSince >= HEAR_ALL_WITHIN
end

local function updateLink(self)
  local up = self.linkUp and self.db.crew ~= nil
  local now = self.now()
  if up then
    if not self.upSince or deaf(self, now) then self.upSince = now end
    self.downSince = nil
  elseif self.upSince then
    self.downSince = self.downSince or now
  end
  if up then self.feedState:linkUp() else self.feedState:linkDown() end
  if up then self.crewGoals:linkUp() else self.crewGoals:linkDown() end
  self.gossip:setLink(up)
end

local function outlets(self)
  return { chat = self:isChatLinesOn(), toast = self:isToastsOn() }
end

local function liveEntry(self, entry)
  local described = self.feedState:describe(entry)
  if described.memberId and described.kind ~= "rareFind" and self:setting("camp") then
    for _, row in ipairs(ns.Roster.rows(self.ledger, self.now())) do
      if row.memberId == described.memberId then described.figure, described.hat = row.classFilename, row.hat end
    end
  end
  return described
end

local function playReaction(self, item)
  local played = self:setting("camp") and self.feedState:campReaction(item)
  if played then self.listener("campReaction", played) end
end

local function playReactions(self, attached)
  if not self.feedState:isSettled() then return end
  for _, item in ipairs(attached) do playReaction(self, item) end
end

local function announce(self, entries, reactions, notices)
  if not self.feedState:isSettled() then return end
  self.pocket:animate(entries)
  local to = outlets(self)
  if not (to.chat or to.toast) then return end
  for _, entry in ipairs(entries) do
    if not entry.seen then
      self.feedState:markSeen(entry)
      self.listener("feedEntry", liveEntry(self, entry), to)
    end
  end
  for _, item in ipairs(reactions or {}) do
    self.feedState:markSeen(item.reaction)
    self.listener("reaction", self.feedState:news(item), to)
  end
  for _, news in ipairs(notices or {}) do
    self.spareLife:markSeen(news)
    self.listener("spare", self.spareLife:describe(news), to)
  end
end

local function checkGoals(self, quiet)
  if not self.db.crew then return end
  local reached = self.crewGoals:check(quiet)
  if #reached > 0 then announce(self, self.feedState:goalsReached(reached)) end
end

local function writePlayTimes(self)
  if not (self.playTimesDue and self.ledger:own()) then return false end
  self.playTimesDue = false
  return self.ledger:setPlayTimes(self.playTracker:summary())
end

local function sharePlayTimes(self, otherChange)
  if writePlayTimes(self) and not otherChange then
    self.gossip:ownChanged("later")
    self.listener("changed")
  end
end

local function sendOwnNow(self)
  self.gossip:ownChanged("now")
end

function Core:updateOwn(character)
  local versionChanged = self.whatsNewState.version ~= nil and self.ledger:writeOwn({ bff = self.whatsNewState.version })
  local changed, before = self.ledger:updateOwn(character)
  if versionChanged and not changed then self.gossip:ownChanged("later") end
  sharePlayTimes(self, changed)
  if changed then
    local entries = self.db.crew and self.feedState:ownChanged(before, character.guid) or {}
    self.pocket:animate(entries)
    local after = self.ledger:own().characters[character.guid]
    if before then self.pocket:practised(self.ledger:memberId(), before.professions, after.professions) end
    self.gossip:ownChanged(#entries > 0 and "now" or ns.Gossip.urgency(before, character))
    checkGoals(self, ns.Goals.professionsFirstKnown(before, self.ledger:own().characters[character.guid]))
    self.listener("changed")
  end
end

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

function Core:doing(facts)
  self.doings:set(type(facts) == "table" and facts or {})
  if self.doings:noteState() and self.pocket:on() then self.listener("changed") end
end

function Core:group(party)
  self.pocket:group(party)
end

function Core:questHandedIn()
  if not self.db.crew then return end
  self.doings:questHandedIn()
  self.pocket:animateMember("quest", self.ledger:memberId())
end

function Core:caught(loot)
  if not self.ledger:own() then return false end
  local now, character = self.now(), self.ledger:playing()
  local had = ns.Catches.rareHeld(self.ledger:own())
  local changed = self.ledger:changeOwn(function(record) return ns.Catches.add(record, loot, now, character) end)
  if changed then
    local entries = self.db.crew and self.feedState:ownCaught(had) or {}
    self.pocket:caught(self.ledger:memberId())
    self.pocket:animate(entries)
    self.gossip:ownChanged(#entries > 0 and "now" or "later")
    checkGoals(self)
    self.listener("changed")
  end
  return changed
end

function Core:rareKilled(kill)
  if not self.ledger:own() then return false, "noRecord" end
  local now, character = self.now(), self.ledger:playing()
  local changed, reason
  self.ledger:changeOwn(function(record)
    changed, reason = ns.Rares.add(record, kill, now, character)
    return changed
  end)
  if not changed then return false, reason end
  self.gossip:ownChanged(ns.Rares.byId(kill.npcId) and "now" or "later")
  checkGoals(self)
  self.listener("changed")
  return true
end

function Core:catches()
  local records = {}
  for _, record in self.ledger:records() do
    if not record.left then records[#records + 1] = record end
  end
  return ns.Catches.collect(records, self.ledger:memberId(), self.now())
end

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

function Core:rows(order)
  return ns.Camp.wordRows(ns.Roster.rows(self.ledger, self.now(), order), self:setting("camp"), order)
end

function Core:professions(order, sortBy)
  return ns.Professions.tab(ns.Roster.rows(self.ledger, self.now(), order), sortBy)
end

function Core:dungeons(measure, selected)
  return ns.Dungeons.view(ns.Roster.rows(self.ledger, self.now()), measure, {
    selected = selected,
    filters = {
      offline = self:setting("dungeonsOffline"),
      alts = self:setting("dungeonsAlts"),
      near = self:setting("dungeonsNear"),
      attunements = self:setting("dungeonsAttunements"),
      raids = self:setting("dungeonsRaids"),
    },
  })
end

Core.selectDungeons = ns.Dungeons.select

function Core:mapPins()
  local pins = {}
  if not self:setting("mapPins") then return pins end
  local campOn = self:setting("camp")
  local size = self:setting("mapPinSize")
  for _, row in ipairs(ns.Roster.rows(self.ledger, self.now())) do
    local spot = not row.own and shownSpot(self, row)
    if spot then
      pins[#pins + 1] = {
        memberId = row.memberId,
        displayName = row.displayName,
        name = row.name,
        fullName = row.fullName,
        classFilename = row.classFilename,
        level = row.level,
        mapId = spot.mapId,
        x = spot.x,
        y = spot.y,
        zone = row.zone,
        instance = spot.instance,
        figure = campOn and row.classFilename or nil,
        size = size,
        online = row.online,
        sinceSeen = row.sinceSeen,
        lastSeenText = row.lastSeenText,
      }
    end
  end
  return pins
end

function Core:season()
  if not (self:setting("camp") and self:setting("seasons")) then return nil end
  if self.forcedSeason ~= nil then return self.forcedSeason or nil end
  return ns.Camp.season(self.now(), self.utcOffset)
end

function Core:forceSeason(key)
  if not (key == "off" or key == "auto" or ns.Camp.isSeason(key)) then return false end
  if key == "off" then
    self.forcedSeason = false
  elseif key == "auto" then
    self.forcedSeason = nil
  else
    self.forcedSeason = key
  end
  self.listener("changed")
  return true
end

local PHASES = { day = true, night = true }

function Core:phase()
  if not (self:setting("camp") and self:setting("dayNight")) then return nil end
  if self.forcedPhase then return self.forcedPhase end
  return ns.Camp.phase(self.daylight())
end

function Core:forcePhase(key)
  if not (key == "auto" or PHASES[key]) then return false end
  self.forcedPhase = PHASES[key] and key or nil
  self.listener("changed")
  return true
end

function Core:daylightChanged()
  self.listener("changed")
end

function Core:camp(columns)
  if not self:setting("camp") then return nil end
  local now = self.now()
  return ns.Camp.view(ns.Roster.rows(self.ledger, now), self.feedState:since(now - ns.Camp.RECENT), now, columns,
    { season = self:season(), phase = self:phase() })
end

function Core:pocketCamp()
  return self.pocket:view()
end

function Core:rosterCounts()
  local counts = ns.Roster.counts(self.ledger, self.now())
  counts.spares = self.spareLife:usableCount()
  counts.header = ns.Camp.header(counts, self:setting("camp"))
  return counts
end

local function onlineChanged(self)
  local now = self.now()
  local online = ns.Roster.online(self.ledger, now)
  local differs = false
  local arrived = {}
  for id in pairs(online) do
    if not self.online[id] then
      differs = true
      if id ~= self.ledger:memberId() then self.doings:newcomer() end
      self.pocket:cameOnline(id)
      if self.known[id] then arrived[#arrived + 1] = id end
    end
  end
  for id in pairs(self.online) do
    if not online[id] then
      differs = true
      self.doings:forget(id)
      local record = self.ledger:record(id)
      if not deaf(self, now) and record and not record.left then
        self.pocket:wentOffline(id)
      end
    end
  end
  self.online = online
  self.known = knownMembers(self.ledger)
  if self.feedState:isSettled() and hearsEveryone(self, now) then
    for _, id in ipairs(arrived) do self.pocket:animateMember("arrive", id) end
  end
  return differs
end

local function checkOnline(self)
  if onlineChanged(self) then self.listener("changed") end
end

local function tellNewerBff(self)
  if not (self.db.crew and self.feedState:isSettled()) then return end
  local line = self.whatsNewState:takeNewerBffLine(ns.Roster.rows(self.ledger, self.now()), self.bffVersionOf)
  if line then self.listener("newerBff", line) end
end

local function awaySummary(self)
  if not self:isAwayPopupOn() then
    self.whatsNewState:takeAwayLine()
    return
  end
  local view, told = self:catches(), self.db.catchTypesTold
  local newTypesLine = told and ns.Catches.newTypesLine(view, told)
  self.db.catchTypesTold = ns.Catches.markTold(told or {}, view)
  local summary = self.feedState:takeSummary(self.spareLife:takeNews(), newTypesLine)
  local update = self.whatsNewState:takeAwayLine()
  if not summary and update then
    summary = { members = {}, goals = {}, spares = {}, professions = {}, catches = {}, noticed = {}, count = 0,
      maxLevel = self.maxLevel }
  end
  if not summary then return end
  summary.update = update
  if self:setting("camp") then
    local now = self.now()
    summary.camp, summary.intro = ns.Camp.away(ns.Roster.rows(self.ledger, now),
      self.feedState:since(now - ns.Camp.RECENT), now, summary, self:season(), self:phase())
  end
  self.listener("awaySummary", summary)
  self.listener("changed")
end

local function offerTip(self)
  local tip = self:tip()
  local offered = self.db.tipsOffered
  if not tip or (offered and offered[tip.key]) then return end
  self.db.tipsOffered = offered or {}
  self.db.tipsOffered[tip.key] = true
  self.listener("tip", tip)
end

local function audience(self)
  local talking = self.gossip.open == true and not (self.db.crew and self.db.crew.leaving)
  local others = 0
  for id in pairs(self.online) do
    if id ~= self.ledger:memberId() then others = others + 1 end
  end
  return talking, others
end

local function shareWhere(self)
  local talking, others = audience(self)
  local own = self.ledger:own()
  local message = self.where:tick(talking, others, self.ledger:playing(), own and own.version)
  if message then sendMessage(self, message) end
end

local function shareDoing(self)
  local message = self.doings:tick(audience(self))
  if message then sendMessage(self, message) end
end

function Core:tick()
  if self.playTracker:tick() then self.playTimesDue = true end
  sharePlayTimes(self)
  self.gossip:tick()
  shareWhere(self)
  shareDoing(self)
  if self.feedState:tick() then
    self.pocket:syncSettled()
    awaySummary(self)
    tellNewerBff(self)
  end
  if self.db.crew and self.crewGoals:tick() then
    self.db.catchTypesTold = self.db.catchTypesTold or ns.Catches.markTold({}, self:catches())
    self.listener("changed")
  end
  if self.db.crew then self.spareLife:tick() end
  offerTip(self)
  self.pocket:tick()
  checkOnline(self)
end

function Core:goals()
  local rows = self.crewGoals:rows()
  for _, row in ipairs(rows) do
    if row.last then row.last.date = ns.Text.shortDate(row.last.time, self.utcOffset) end
  end
  return rows
end

function Core:trophies()
  local trophies = self.crewGoals:trophies()
  for _, trophy in ipairs(trophies.shelf) do trophy.date = ns.Text.shortDate(trophy.time, self.utcOffset) end
  return trophies
end

function Core:openTrophies()
  self.crewGoals:open()
end

function Core:leaveTrophies()
  self.crewGoals:leave()
end

function Core:feed()
  return self.feedState:view(self.utcOffset)
end

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
      result.note = ("After %d weeks of play, the hours the Crew usually plays show up here."):format(result.usually)
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

function Core:unseen()
  return self.feedState:unseen()
end

function Core:react(key)
  local reason, attached
  key, reason, attached = self.feedState:react(key)
  if not key then return false, reason end
  self.ledger:addReaction(key)
  self.gossip:ownChanged("now")
  self.listener("changed")
  if ns.Reactions.forKind(key.kind) ~= "cheer" then playReaction(self, attached) end
  return true
end

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

local function ownWrite(self)
  self.gossip:ownChanged("now")
  self.listener("changed")
end

-- WoW: bindType is the 14th return of C_Item.GetItemInfo.
function Core:postSpare(link, level, inBags)
  local id, reason = self.spareLife:post(link, level, inBags)
  if id then ownWrite(self) end
  return id, reason
end

function Core:spareItems()
  return self.spareLife:items()
end

function Core:withdrawSpare(id)
  local ok, reason = self.spareLife:withdraw(id)
  if ok then ownWrite(self) end
  return ok, reason
end

function Core:giveSpare(id, expected)
  local ok, reason = self.spareLife:give(id, expected)
  if ok then ownWrite(self) end
  return ok, reason
end

-- WoW: the bags read as empty until the first BAG_UPDATE_DELAYED of a session.
function Core:bagsUpdated()
  if self.spareLife:bagsUpdated(function() ownWrite(self) end) then self.listener("changed") end
end

function Core:claimSpare(owner, id, guid)
  local ok, reason = self.spareLife:claim(owner, id, guid)
  if ok then ownWrite(self) end
  return ok, reason
end

function Core:withdrawClaim(owner, id)
  local ok, reason = self.spareLife:withdrawClaim(owner, id)
  if ok then ownWrite(self) end
  return ok, reason
end

function Core:unseenSpares()
  return self.spareLife:unseen()
end

function Core:sparesSeen()
  if self.spareLife:markAllSeen() then self.listener("changed") end
end

function Core:openFeed()
  if self.feedState:open() then self.listener("changed") end
end

function Core:leaveFeed()
  self.feedState:leave()
end

function Core:hasNewChanges()
  return self.whatsNewState:hasNew()
end

function Core:openWhatsNew()
  if self.whatsNewState:open() then self.listener("changed") end
end

function Core:leaveWhatsNew()
  self.whatsNewState:leave()
end

function Core:whatsNew()
  return self.whatsNewState:view(ns.Roster.rows(self.ledger, self.now()), self.bffVersionOf)
end

local function savedIn(db, parent)
  if not parent then return db end
  db[parent] = db[parent] or {}
  return db[parent]
end

local function offFlag(field, parent)
  return {
    read = function(db) return not savedIn(db, parent)[field] end,
    write = function(db, on) savedIn(db, parent)[field] = not on or nil end,
  }
end

local function onFlag(field, parent)
  return {
    read = function(db) return savedIn(db, parent)[field] == true end,
    write = function(db, on) savedIn(db, parent)[field] = on and true or nil end,
  }
end

local function oneOf(field, choices, default)
  local known = {}
  for _, choice in ipairs(choices) do known[choice.key] = true end
  local function valid(value)
    if known[value] then return value end
    return default
  end
  return {
    read = function(db) return valid(db[field]) end,
    write = function(db, value)
      value = valid(value)
      db[field] = value ~= default and value or nil
    end,
  }
end

local function combatChoice(hideField, fadeField)
  return {
    read = function(db)
      if db[hideField] == true then return "hide" end
      if db[fadeField] == true then return "fade" end
      return "stay"
    end,
    write = function(db, value)
      db[hideField] = value == "hide" or nil
      db[fadeField] = value == "fade" or nil
    end,
  }
end

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

local function percent(field, default, low, high)
  low, high = low or 0, high or 100
  return {
    read = function(db)
      local value = db[field]
      if type(value) ~= "number" then return default end
      return math.max(low, math.min(high, value))
    end,
    write = function(db, value)
      if type(value) ~= "number" then value = default end
      value = math.max(low, math.min(high, math.floor(value + 0.5)))
      if value == default then value = nil end
      db[field] = value
    end,
  }
end

Core.PANEL_MIN_WIDTH, Core.PANEL_MIN_HEIGHT = 460, 460
Core.PANEL_WIDTH, Core.PANEL_HEIGHT = 640, 520
Core.PANEL_MAX_WIDTH, Core.PANEL_MAX_HEIGHT = 900, 800

local function round(value)
  return math.floor(value + 0.5)
end

local function clamp(value, low, high)
  return math.max(low, math.min(high, value))
end

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

Core.DEFAULT_TOAST_SOUND = "UI_BNET_TOAST"
Core.MAP_PIN_SIZES = {
  { key = "small", label = "Small" },
  { key = "medium", label = "Medium" },
  { key = "large", label = "Large" },
}

Core.POCKET_CAMP_COMBAT = {
  { key = "stay", label = "Stay" },
  { key = "fade", label = "Fade" },
  { key = "hide", label = "Hide" },
}

Core.POCKET_CAMP_MIN_SCALE, Core.POCKET_CAMP_MAX_SCALE = 50, 300

Core.pocketCampWidth = ns.Camp.pocketWidth
Core.pocketCampSeats = ns.Camp.pocketSeats

local function pocketWidth(field)
  return {
    read = function(db) return ns.Camp.pocketWidth(db[field]) end,
    write = function(db, value)
      value = ns.Camp.pocketWidth(value)
      if value == ns.Camp.LAYOUT.pocketColumns then value = nil end
      db[field] = value
    end,
  }
end

local SHARING = "Sharing"
local NOTIFICATIONS = "Notifications and display"
local TOASTS = "Toasts"
local POCKET_CAMP = "Pocket Camp"
local POCKET_CAMP_SHOWN = "Shown in the Pocket Camp"

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
  {
    key = "minimap", section = NOTIFICATIONS, kind = "toggle",
    label = "Show minimap button",
    -- WoW: LibDBIcon keeps the button's position and its hide flag in this table.
    saved = offFlag("hide", "minimap"),
  },
  {
    key = "camp", section = NOTIFICATIONS, kind = "toggle",
    label = "Show the Camp",
    saved = offFlag("campOff"),
  },
  {
    key = "seasons", section = NOTIFICATIONS, kind = "toggle", needs = "camp",
    label = "Seasonal decorations",
    saved = offFlag("seasonsOff"),
  },
  {
    key = "dayNight", section = NOTIFICATIONS, kind = "toggle", needs = "camp",
    label = "Day and night",
    saved = offFlag("dayNightOff"),
  },
  {
    key = "mapPins", section = NOTIFICATIONS, kind = "toggle",
    label = "Show your Crew on the world map",
    saved = offFlag("mapPinsOff"),
  },
  {
    key = "mapPinSize", section = NOTIFICATIONS, kind = "choice",
    label = "Map pin size", needs = "mapPins",
    choices = Core.MAP_PIN_SIZES,
    saved = oneOf("mapPinSize", Core.MAP_PIN_SIZES, "medium"),
  },
  {
    key = "panelPlace", section = NOTIFICATIONS, kind = "panelPlace",
    label = "BFF window size and position", button = "Reset",
    saved = windowPlace("panelPlace"),
  },
  {
    key = "toasts", section = TOASTS, kind = "toggle",
    label = "Show toasts for live events",
    saved = offFlag("toastsOff"),
  },
  {
    key = "toastSound", section = TOASTS, kind = "sound",
    label = "Sound",
    saved = nilAsDefault("toastSound", Core.DEFAULT_TOAST_SOUND),
  },
  {
    key = "toastPosition", section = TOASTS, kind = "position",
    label = "Where toasts appear", button = "Move",
    saved = screenPosition("toastPosition"),
  },
  {
    key = "pocketCamp", section = POCKET_CAMP, kind = "toggle",
    label = "Show the Pocket Camp",
    saved = onFlag("pocketCamp"),
  },
  {
    key = "pocketCampOpacity", section = POCKET_CAMP, kind = "percent",
    label = "Backdrop opacity",
    saved = percent("pocketCampOpacity", 60),
  },
  {
    key = "pocketCampLocked", section = POCKET_CAMP, kind = "toggle",
    label = "Lock its position and size",
    saved = onFlag("pocketCampLocked"),
  },
  {
    key = "pocketCampCombat", section = POCKET_CAMP, kind = "choice",
    label = "In combat",
    choices = Core.POCKET_CAMP_COMBAT,
    saved = combatChoice("pocketCampCombatHide", "pocketCampCombatFades"),
  },
  {
    key = "pocketCampCombatFade", section = POCKET_CAMP, kind = "percent",
    label = "Fade to", shownWhen = { key = "pocketCampCombat", value = "fade" },
    saved = percent("pocketCampCombatFadeTo", 25),
  },
  {
    key = "pocketCampAlts", section = POCKET_CAMP_SHOWN, kind = "toggle", needs = "pocketCamp",
    label = "ALT over a Member playing an alt",
    saved = offFlag("pocketCampAltsOff"),
  },
  {
    key = "pocketCampSpares", section = POCKET_CAMP_SHOWN, kind = "toggle", needs = "pocketCamp",
    label = "A crate by the fire for unseen Spare notices",
    saved = offFlag("pocketCampSparesOff"),
  },
  { key = "pocketCampPosition", kind = "position", saved = screenPosition("pocketCampPosition") },
  {
    key = "pocketCampScale", kind = "percent",
    saved = percent("pocketCampScale", 100, Core.POCKET_CAMP_MIN_SCALE, Core.POCKET_CAMP_MAX_SCALE),
  },
  { key = "pocketCampColumns", kind = "columns", saved = pocketWidth("pocketCampColumns") },
  { key = "dungeonsOffline", kind = "toggle", saved = offFlag("offlineOff", "together") },
  { key = "dungeonsAlts", kind = "toggle", saved = onFlag("alts", "together") },
  { key = "dungeonsNear", kind = "toggle", saved = onFlag("near", "together") },
  { key = "dungeonsAttunements", kind = "toggle", saved = offFlag("attunementsOff", "together") },
  { key = "dungeonsRaids", kind = "toggle", saved = onFlag("raids", "together") },
  { key = "catchesNames", kind = "toggle", saved = onFlag("names", "catches") },
}

local SETTING = {}
for _, setting in ipairs(SETTINGS) do SETTING[setting.key] = setting end

local function settingFor(key)
  local setting = SETTING[key]
  if not setting then error(("Core: no setting %q"):format(tostring(key)), 3) end
  return setting
end

local TIPS = {
  {
    key = "pocketCamp", setting = "pocketCamp", needs = "camp",
    title = "New: the Pocket Camp",
    text = "Keep your Crew on screen. The Pocket Camp shows the fire and who's by it while you play. "
      .. "You can turn it on or off any time in Settings.",
  },
}

local TIP = {}
for _, tip in ipairs(TIPS) do TIP[tip.key] = tip end

local function answerTip(self, tip)
  self.db.tipsAnswered = self.db.tipsAnswered or {}
  self.db.tipsAnswered[tip.key] = true
end

local ON_CHANGE = {
  paused = function(self, paused) self.gossip:setPaused(paused) end,
}

function Core:setting(key)
  return settingFor(key).saved.read(self.db)
end

function Core:setSetting(key, value)
  local saved = settingFor(key).saved
  local before = saved.read(self.db)
  saved.write(self.db, value)
  local after = saved.read(self.db)
  if (saved.same or rawequal)(before, after) then return end
  local onChange = ON_CHANGE[key]
  if onChange then onChange(self, after) end
  for _, tip in ipairs(TIPS) do
    if tip.setting == key and after == true then answerTip(self, tip) end
  end
  self.listener("settingChanged", key, after)
end

function Core:tip()
  if not self.db.crew then return nil end
  local answered = self.db.tipsAnswered or {}
  for _, tip in ipairs(TIPS) do
    if not answered[tip.key] and not self:setting(tip.setting) and (not tip.needs or self:setting(tip.needs)) then
      return { key = tip.key, title = tip.title, text = tip.text, accept = "Turn on", dismiss = "No thanks" }
    end
  end
  return nil
end

function Core:acceptTip(key)
  local tip = TIP[key]
  if not tip then return false end
  answerTip(self, tip)
  self:setSetting(tip.setting, true)
  self.listener("changed")
  return true
end

function Core:dismissTip(key)
  local tip = TIP[key]
  if not tip then return false end
  answerTip(self, tip)
  self.listener("changed")
  return true
end

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
        choices = setting.choices,
        needs = setting.needs,
        button = setting.button,
        hidden = setting.shownWhen and self:setting(setting.shownWhen.key) ~= setting.shownWhen.value or nil,
      }
    end
  end
  return sections
end

function Core:setChatLines(on) self:setSetting("chatLines", on) end
function Core:isChatLinesOn() return self:setting("chatLines") end

function Core:setAwayPopup(on) self:setSetting("awayPopup", on) end
function Core:isAwayPopupOn() return self:setting("awayPopup") end

function Core:setToasts(on) self:setSetting("toasts", on) end
function Core:isToastsOn() return self:setting("toasts") end

function Core:setToastSound(name) self:setSetting("toastSound", name) end
function Core:toastSound() return self:setting("toastSound") end

Core.UNVEIL_SOUND = "UI_LEGENDARY_LOOT_TOAST"
function Core:unveilSound()
  if self:toastSound() == "none" then return nil end
  return Core.UNVEIL_SOUND
end

function Core:setToastPosition(x, y)
  self:setSetting("toastPosition", x and { x = x, y = y } or nil)
end

function Core:toastPosition()
  local position = self:setting("toastPosition")
  if not position then return nil end
  return position.x, position.y
end

function Core:setPocketCampPosition(x, y)
  self:setSetting("pocketCampPosition", x and { x = x, y = y } or nil)
end

function Core:setPocketCampScale(scale)
  self:setSetting("pocketCampScale", scale and scale * 100 or nil)
end

function Core:setPocketCampColumns(columns)
  self:setSetting("pocketCampColumns", columns)
end

function Core:setPanelPlace(width, height, left, top)
  self:setSetting("panelPlace", { width = width, height = height, left = left, top = top })
end

function Core:resetPanelPlace()
  self:setSetting("panelPlace", nil)
end

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

function Core:setPaused(paused) self:setSetting("paused", paused) end
function Core:isPaused() return self:setting("paused") end

function Core:setMinimapShown(shown) self:setSetting("minimap", shown) end
function Core:isMinimapShown() return self:setting("minimap") end

function Core:minimapIcon()
  return savedIn(self.db, "minimap")
end

function Core:displayName()
  return self.ledger:displayName()
end

local LEAVING = "Leaving the Crew. It finishes once BFF's channel is reachable."
local PAUSED = "You appear offline: the others don't see you. Change it in Settings."
local WAITING = "Waiting for your Crew. Members show up when they or someone who has seen them is online."

function Core:crew()
  local saved = self.db.crew
  if not saved then return nil end
  local channel, password = ns.CrewCode.channel(saved.code)
  local alone = not self.ledger:knowsOthers()
  local status, waiting
  if saved.leaving then
    status = LEAVING
  elseif self:isPaused() then
    status = PAUSED
  elseif alone then
    status, waiting = WAITING, true
  end
  return {
    code = saved.code,
    channel = channel,
    password = password,
    leaving = saved.leaving,
    alone = alone,
    joined = saved.joined == true,
    status = status,
    waiting = waiting,
  }
end

local MIN_NAME, MAX_NAME = 2, 16

local function utf8Length(s)
  return #s:gsub("[\128-\191]", "")
end

local function validName(name)
  if type(name) ~= "string" then return nil end
  name = name:match("^%s*(.-)%s*$")
  local length = utf8Length(name)
  if length < MIN_NAME or length > MAX_NAME then return nil end
  return name
end

local function nameOrCurrent(self, displayName)
  if displayName == nil then return self.ledger:displayName() end
  return validName(displayName)
end

local function enter(self, code, displayName, joining)
  self.ledger:writeOwn({ displayName = displayName, left = false, joinedAt = self.now() })
  sendOwnNow(self)
  self.crewGoals:clear()
  self.db.catchTypesTold = nil
  self.db.crew = { code = code, joined = joining or nil }
  if joining then self.feedState:ownJoined() end
  self.listener("crewChanged")
  updateLink(self)
  return self:crew()
end

function Core:startCrew(displayName)
  if self.db.crew then return nil, "inCrew" end
  local name = nameOrCurrent(self, displayName)
  if not name then return nil, "invalidName" end
  return enter(self, ns.CrewCode.generate(self.random), name)
end

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

local function ownLook(self)
  local own = self.ledger:own()
  local look = own and own.look
  return ns.Look.hat(look), ns.Look.pet(look)
end

function Core:look()
  local hat, pet = ownLook(self)
  return { hat = hat, hatLabel = ns.Look.hatLabel(hat), pet = pet, petLabel = ns.Look.petLabel(pet) }
end

local function chosenKey(key)
  return key ~= "none" and key or nil
end

function Core:setLook(look)
  if type(look) ~= "table" then return nil, "unknownHat" end
  if look.hat ~= nil and not ns.Look.knownHat(look.hat) then return nil, "unknownHat" end
  if look.pet ~= nil and not ns.Look.knownPet(look.pet) then return nil, "unknownPet" end
  local oldHat, oldPet = ownLook(self)
  local hat, pet = oldHat, oldPet
  if look.hat ~= nil then hat = chosenKey(look.hat) end
  if look.pet ~= nil then pet = chosenKey(look.pet) end
  if hat ~= oldHat or pet ~= oldPet then
    self.ledger:writeOwn({ look = (hat or pet) and { hat = hat, pet = pet } or false })
    sendOwnNow(self)
    self.listener("changed")
  end
  return true
end

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

function Core:removeMember(id)
  if not self.ledger:remove(id) then return nil, "unknownMember" end
  self.gossip:forget(id)
  self.where:forget(id)
  self.feedState:dropMember(id)
  self.spareLife:memberRemoved()
  self.online[id] = nil
  self.pocket:forget(id)
  self.doings:forget(id)
  checkGoals(self, true)
  self.listener("changed")
  return true
end

function Core:readdMember(id)
  if not self.ledger:readd(id) then return nil, "unknownMember" end
  self.gossip:askAround()
  self.listener("changed")
  return true
end

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

local function finishLeaving(self)
  self.db.crew = nil
  updateLink(self)
  self.gossip:sendNow({ type = "DATA", records = { self.ledger:tombstone() } })
  self.ledger:forgetOthers()
  self.ledger:clearReactions()
  self.spareLife:clear()
  self.feedState:clear()
  self.crewGoals:clear()
  self.db.catchTypesTold = nil
  self.online = {}
  self.pocket:clear()
  self.doings:clear()
  self.listener("crewChanged")
  self.listener("notice", "leftCrew")
end

function Core:leaveCrew()
  local crew = self.db.crew
  if not crew then return nil, "noCrew" end
  if crew.leaving then return true end
  crew.leaving = true
  self.ledger:writeOwn({ left = true })
  if self.linkUp then finishLeaving(self) else self.listener("changed") end
  return true
end

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

-- WoW: a Character leaving the channel has logged out.
function Core:gone(name)
  if type(name) ~= "string" then return end
  self.gossip:peerGone(name)
  if self.ledger:wentAway(name) then checkOnline(self) end
end

-- WoW: some clients get no channel member list, so a whisper can come from a
-- Character not seen in the channel.
function Core:fromKnownMember(message)
  if type(message) ~= "string" or not self.db.crew then return false end
  local decoded = ns.Codec.decode(message)
  local id = type(decoded) == "table" and decoded.from
  return type(id) == "string" and id ~= self.ledger:memberId()
    and self.ledger:record(id) ~= nil and not self.ledger:isRemoved(id)
end

function Core:sendFailed(name)
  if type(name) == "string" then self.gossip:sendFailed(name) end
end

local function dataReceived(self, records, from, whispered)
  local changed = false
  for _, record in ipairs(records) do
    local kept, before = self.ledger:merge(record, from)
    if self.trace then
      self.trace(("receive DATA from %s · ok · %s"):format(traceName(self, from),
        traceReceived(self, record, kept)))
    end
    if kept then
      changed = true
      self.feedState:dataMerged()
      self.crewGoals:dataMerged()
      if before and not record.left and self.feedState:isSettled() then self.pocket:merged(before, record) end
      local entries, reactions, attached = self.feedState:recordChanged(before, record)
      announce(self, entries, reactions, self.spareLife:recordChanged(before, record))
      playReactions(self, attached)
      if ns.Goals.countedChanged(before, record) then checkGoals(self, true) end
    end
    if type(record) == "table" and type(record.id) == "string" and type(record.version) == "number" then
      self.gossip:recordSeen(record.id, record.version, record.id == from or not whispered)
    end
  end
  if changed then
    checkGoals(self)
    tellNewerBff(self)
    local told = self.db.catchTypesTold
    if told then ns.Catches.markTold(told, self:catches(), self.sessionStart) end
  end
  return changed
end

-- WoW: the channel echoes your own messages back to you.
function Core:received(message, from)
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
  if decoded.type == "WHERE" then
    local kept = not self.ledger:isRemoved(decoded.from) and self.where:heard(decoded.from, decoded)
    if self.trace then
      self.trace(("receive WHERE from %s · %s"):format(traceName(self, decoded.from), kept and "ok" or "ignored"))
    end
    if kept then self.listener("moved") end
  elseif decoded.type == "DOING" then
    local kept, quest = false, false
    if not self.ledger:isRemoved(decoded.from) then kept, quest = self.doings:heard(decoded.from, decoded) end
    if self.trace then
      self.trace(("receive DOING from %s · %s"):format(traceName(self, decoded.from), kept and "ok" or "ignored"))
    end
    if kept and self.pocket:on() then
      changed = true
      if quest and self.feedState:isSettled() then self.pocket:animateMember("quest", decoded.from) end
    end
  elseif decoded.type == "DIGEST" and type(decoded.versions) == "table" then
    local partial = decoded.partial == true
    if self.trace then
      self.trace(("receive DIGEST from %s · ok%s · %s"):format(traceName(self, decoded.from),
        partial and " (more in turn)" or "", traceVersions(self, decoded.versions)))
    end
    self.gossip:digestReceived(decoded.versions, partial, decoded.turns == true, from)
  elseif decoded.type == "DATA" and type(decoded.records) == "table" then
    changed = dataReceived(self, decoded.records, decoded.from, type(from) == "string")
  elseif self.trace then
    self.trace(("receive %s from %s · ignored (unknown)"):format(tostring(decoded.type), traceName(self, decoded.from)))
  end
  if onlineChanged(self) or changed then self.listener("changed") end
end
