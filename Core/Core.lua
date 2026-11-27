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

local REPAIRED_BY = { serverId = "server ID", name = "name" }

local function repairText(repaired)
  if not repaired then return nil end
  local how = repaired.swapped and "%s and %s swapped (by %s)" or "%s moved to %s (by %s)"
  return how:format(repaired.from, repaired.to, REPAIRED_BY[repaired.by])
end

local function traceRuleset(self, what)
  if self.trace then self.trace(("ruleset %s %s"):format(self.rulesetKey, what)) end
end

local function traceOpening(self)
  if not self.trace then return end
  for _, line in ipairs(self.openingLines) do self.trace(line) end
  self.openingLines = {}
end

function Core:setTrace(trace)
  self.trace = type(trace) == "function" and trace or nil
  traceOpening(self)
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

local function refreshMembers(self)
  self.online = ns.Roster.online(self.ledger, self.now())
  self.known = knownMembers(self.ledger)
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

local LANTERNS = 2
local SAVED_TITLE = "Saved for your Crew"
local SAVED_WAITING = "They sit here once you hear from one of them."
local SAVED_HINT = "Click to invite in chat. Right-click for the code."
local INVITE = "Join my Crew in BFF: /bff join %s"

local function savedSeats(self)
  local crew = self.db.crew
  if not crew or crew.leaving or self.ledger:knowsOthers() then return nil end
  if crew.joined then return { tooltip = { title = SAVED_TITLE, lines = { SAVED_WAITING } } } end
  return {
    code = crew.code,
    invite = INVITE:format(crew.code),
    tooltip = {
      title = SAVED_TITLE,
      lines = { "Friends join with /bff join " .. crew.code },
      hint = SAVED_HINT,
    },
  }
end

local function ownRowOf(rows)
  for _, row in ipairs(rows) do
    if row.own then return { row } end
  end
  return {}
end

local function walkInOf(self, view, rows, arrangeAlone)
  local id = self.db.crew and self.db.crew.walkIn
  if not id then return nil end
  return ns.Camp.walkIn(view, id, arrangeAlone and arrangeAlone(ownRowOf(rows)))
end

local function aloneByTheFire(self)
  local crew = self.db.crew
  return crew ~= nil and not crew.leaving and not self.ledger:knowsOthers() and self:setting("camp")
end

local function strayWanted(self)
  local own = self.ledger:own()
  return aloneByTheFire(self) and own ~= nil and ns.Look.pet(own.look) == nil
end

local function mourning(self)
  local own = self.ledger:own()
  return self.mourning and own ~= nil and ns.Look.pet(own.look) ~= nil
end

local function strayRows(self, rows)
  local visit = strayWanted(self) and self.stray:visiting()
  if not visit then return nil end
  for _, row in ipairs(rows) do
    if row.own then row.pet = visit.key end
  end
  return visit
end

local function markStray(view, visit)
  if not visit then return end
  local found
  for _, seat in ipairs(view.lanternSeats or {}) do
    if seat.pet == visit.key then found = seat end
  end
  if not found then return end
  found.stray = true
  view.stray = ns.Stray.describe(visit)
end

local function noteWalkIn(self, records)
  for _, record in ipairs(records) do
    local id = type(record) == "table" and record.id
    local known = id and id ~= self.ledger:memberId() and self.ledger:record(id)
    if known and not known.left then
      self.db.crew.walkIn = id
      return
    end
  end
end

local function sendBeforeOwn(self)
  if not self.locate then return nil end
  return function()
    local location = self.where:read()
    local changed = self.ledger:locate(location)
    local own = self.ledger:own()
    if not changed and own and self.where:sentSince(own.version) then self.ledger:touch() end
    self.where:dataSent(location)
  end
end

local function bindSlot(self, slot, initialLogin)
  self.db = slot
  self.ledger = ns.Ledger.new(slot, self.now, self.random, initialLogin)
  self.feedState = ns.Feed.new(slot, self.ledger, self.now, self.maxLevel, initialLogin, self.itemLink, self.itemLook)
  self.spareLife = ns.Spares.new({
    db = slot,
    ledger = self.ledger,
    feed = self.feedState,
    now = self.now,
    listener = self.listener,
    initialLogin = initialLogin,
    itemLink = self.itemLink,
    findItem = self.findItem,
  })
  self.crewGoals = ns.Goals.new(slot, self.ledger, self.now, self.maxLevel)
  self.pocket = ns.Pocket.new({
    now = self.now,
    ledger = self.ledger,
    feed = self.feedState,
    goals = self.crewGoals,
    spares = self.spareLife,
    doings = self.doings,
    listener = self.listener,
    on = function() return self.db.crew ~= nil and self:setting("camp") and self:setting("pocketCamp") end,
    setting = function(key) return self:setting(key) end,
    season = function() return self:season() end,
    phase = function() return self:phase() end,
    spot = function(row) return shownSpot(self, row) end,
    saved = function() return savedSeats(self) end,
    walkIn = function(view, rows) return walkInOf(self, view, rows) end,
    stray = {
      rows = function(rows) return strayRows(self, rows) end,
      mark = markStray,
    },
  })
  self.stray = ns.Stray.new(slot, self.now, self.random)
  self.gossip = self.Gossip.new(self.ledger, self.now, self.random, function(message, to)
    sendMessage(self, message, to)
  end, sendBeforeOwn(self))
  self.gossip:setPaused(self:isPaused())
  self.playTracker = ns.PlayTimes.new(slot, self.now)
  self.playTimesDue = true
  if initialLogin or type(slot.channelMoves) ~= "table" then slot.channelMoves = { count = 0 } end
  refreshMembers(self)
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
    account = deps.db,
    now = deps.now,
    random = deps.random,
    link = deps.link,
    listener = deps.listener,
    initialLogin = deps.initialLogin == true,
    maxLevel = deps.maxLevel,
    utcOffset = type(deps.utcOffset) == "number" and deps.utcOffset or 0,
    daylight = type(deps.daylight) == "function" and deps.daylight or function() end,
    finalBosses = type(deps.finalBosses) == "table" and deps.finalBosses or ns.Clears.FINAL_BOSSES,
    itemLink = type(deps.itemLink) == "function" and deps.itemLink or nil,
    itemLook = type(deps.itemLook) == "function" and deps.itemLook or nil,
    findItem = type(deps.findItem) == "function" and deps.findItem or nil,
    locate = type(deps.locate) == "function" and deps.locate or nil,
    Gossip = type(deps.gossip) == "table" and deps.gossip or ns.Gossip,
    linkUp = false,
    upSince = nil,
    downSince = nil,
    doings = ns.Doing.new(deps.now),
  }, Core)
  self.sessionStart = deps.now()
  self.where = ns.Where.new(deps.now, self.locate)
  self.facts = ns.Slots.facts(deps.ruleset)
  local opened = ns.Slots.open(deps.db, self.facts, deps.random, deps.now())
  self.rulesetKey, self.rulesetEntry, self.rulesetRepair = opened.key, opened.entry, repairText(opened.repaired)
  self.openingLines = {}
  if self.rulesetRepair then self.openingLines[1] = "ruleset " .. self.rulesetRepair end
  if opened.placed then
    self.openingLines[#self.openingLines + 1] = ("ruleset %s placed the Crew saved before Rulesets here%s"):format(
      opened.key, opened.slot.provisional and " (provisional)" or "")
  end
  bindSlot(self, opened.slot, self.initialLogin)
  if opened.placed and self.facts.serverId then
    self.ledger:keepCharacters(ns.Slots.belongsHere(self.db, self.facts.serverId))
  end
  self.whatsNewState = ns.WhatsNew.new(self.account, deps.version, deps.changelog, fresh)
  self.generationFrom = "saved"
  self:raiseGeneration(true)
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

local PET_NEWS = { ding = "hop", maxLevel = "hop", rareFind = "fish" }

local function petCanCue(self)
  return aloneByTheFire(self) and self.feedState:isSettled()
end

local function petNews(self, entries)
  if not petCanCue(self) then return end
  for _, entry in ipairs(entries) do
    if entry.own and entry.kind == "death" then
      self.mourning = true
    elseif entry.own and PET_NEWS[entry.kind] then
      self.listener("petCue", PET_NEWS[entry.kind])
    end
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

local function leaveOtherSlots(self, guid)
  if self.leftOtherSlotsAs == guid then return end
  self.leftOtherSlotsAs = guid
  for _, slot in ipairs(ns.Slots.others(self.account, self.db)) do
    if type(slot.memberId) == "string" then
      ns.Ledger.new(slot, self.now, self.random):keepCharacters(function(other) return other ~= guid end)
    end
  end
end

function Core:updateOwn(character)
  self.character = character
  if type(character) == "table" then leaveOtherSlots(self, character.guid) end
  local versionChanged = self.whatsNewState.version ~= nil and self.ledger:writeOwn({ bff = self.whatsNewState.version })
  local changed, before = self.ledger:updateOwn(character)
  if versionChanged and not changed then self.gossip:ownChanged("later") end
  sharePlayTimes(self, changed)
  if changed then
    local entries = self.db.crew and self.feedState:ownChanged(before, character.guid) or {}
    self.pocket:animate(entries)
    petNews(self, entries)
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
    petNews(self, entries)
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
  local known = ns.Rares.byId(kill.npcId) ~= nil
  self.gossip:ownChanged(known and "now" or "later")
  if known and petCanCue(self) then self.listener("petCue", "star") end
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
  local saved = savedSeats(self)
  local function arrange(rows, entries, lanternCount)
    return ns.Camp.view(rows, entries, now, columns, { season = self:season(), phase = self:phase(),
      lanternCount = lanternCount, mourn = lanternCount and mourning(self) })
  end
  local rows = ns.Roster.rows(self.ledger, now)
  local stray = strayRows(self, rows)
  local view = arrange(rows, self.feedState:since(now - ns.Camp.RECENT), saved and LANTERNS)
  view.saved = view.lanternSeats and saved or nil
  view.walkIn = walkInOf(self, view, rows, function(own) return arrange(own, {}, LANTERNS) end)
  markStray(view, stray)
  return view
end

function Core:keepStray()
  local key, line = self.stray:keep()
  if not key then return nil end
  self:setLook({ pet = key })
  return line
end

function Core:strayNotNow()
  if self.stray:notNow() then self.listener("changed") end
end

function Core:panelClosed()
  if self.stray:wanderOff() then self.listener("changed") end
end

function Core:walkedIn()
  if self.db.crew then self.db.crew.walkIn = nil end
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

local function emptySummary(self)
  return { members = {}, goals = {}, spares = {}, professions = {}, catches = {}, noticed = {}, count = 0,
    maxLevel = self.maxLevel }
end

local function sendAway(self, summary)
  if self:setting("camp") then
    local now = self.now()
    local saved = savedSeats(self) ~= nil
    summary.camp, summary.intro = ns.Camp.away(ns.Roster.rows(self.ledger, now),
      self.feedState:since(now - ns.Camp.RECENT), now, summary,
      { season = self:season(), phase = self:phase(), lanternCount = saved and LANTERNS or nil,
        mourn = saved and mourning(self) })
  end
  self.listener("awaySummary", summary)
  self.listener("changed")
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
  if not summary and update then summary = emptySummary(self) end
  if not summary then return end
  summary.update = update
  sendAway(self, summary)
end

function Core:previewAwayUpdate(update)
  local summary = emptySummary(self)
  summary.update = update
  sendAway(self, summary)
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
  if self.stray:tick(strayWanted(self), self.doings:fighting()) then self.listener("changed") end
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
    saved = onFlag("paused"), inSlot = true,
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
    saved = offFlag("pocketCampOff"),
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

local ON_CHANGE = {
  paused = function(self, paused) self.gossip:setPaused(paused) end,
}

local function savedFor(self, setting)
  if setting.inSlot then return self.db end
  return self.account
end

function Core:setting(key)
  local setting = settingFor(key)
  return setting.saved.read(savedFor(self, setting))
end

function Core:setSetting(key, value)
  local setting = settingFor(key)
  local saved, db = setting.saved, savedFor(self, setting)
  local before = saved.read(db)
  saved.write(db, value)
  local after = saved.read(db)
  if (saved.same or rawequal)(before, after) then return end
  local onChange = ON_CHANGE[key]
  if onChange then onChange(self, after) end
  self.listener("settingChanged", key, after)
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
  return savedIn(self.account, "minimap")
end

function Core:ruleset()
  local entry = self.rulesetEntry
  local serverIds = {}
  for i, id in ipairs(entry.serverIds) do serverIds[i] = id end
  return {
    key = self.rulesetKey,
    realmName = self.facts.realmName,
    recordId = entry.recordId,
    faction = entry.faction,
    serverId = self.facts.serverId,
    serverIds = serverIds,
    name = entry.name,
    provisional = self.db.provisional == true,
    repair = self.rulesetRepair,
  }
end

local SEPARATE = "BFF keeps a separate Crew for each %s and faction."
local ASK = SEPARATE .. " It can't tell which one your Crew from before belongs to. Is this where your Crew is?"
local OFFER = "Your Crew on %s hasn't heard from anyone yet. If your friends play this faction, bring it here."

local function worldWord(self)
  return self.facts.realmName and "realm" or "Ruleset"
end

local function placeOf(crew, world)
  local where = crew.name or (crew.character and ("%s's %s"):format(crew.character, world)) or "another " .. world
  return crew.faction and ("%s (%s)"):format(where, crew.faction) or where
end

local function hintFor(crews, world)
  if #crews == 0 then return nil end
  local places = {}
  for i, crew in ipairs(crews) do places[i] = placeOf(crew, world) end
  local where = #crews == 1 and "Yours is on %s: log in a Character there to see it,"
    or "Yours are on %s: log in a Character there to see them,"
  return ("%s %s or start a new Crew on this %s, or join one."):format(
    SEPARATE:format(world), where:format(ns.Text.list(places)), world)
end

function Core:elsewhere()
  local found = ns.Slots.elsewhere(self.account, self.rulesetKey, self.now())
  local world = worldWord(self)
  return {
    hint = hintFor(found.crews, world),
    ask = found.ask and ASK:format(world) or nil,
    offer = found.offer and OFFER:format(placeOf(found.offer, world)) or nil,
  }
end

local function confirmRuleset(self)
  if not self.db.provisional then return end
  self.db.provisional = nil
  traceRuleset(self, "confirmed by a Member")
end

function Core:rulesetNamed(name)
  name = ns.Slots.facts({ name = name }).name
  local entry = self.rulesetEntry
  if not name or entry.name == name then return end
  entry.name = name
  traceRuleset(self, "named " .. name)
  self.listener("changed")
end

function Core:displayName()
  return self.ledger:displayName()
end

local LEAVING = "Leaving the Crew. It finishes once BFF's channel is reachable."
local PAUSED = "You appear offline: the others don't see you. Change it in Settings."
local WAITING = "Waiting for your Crew. Members show up when they or someone who has seen them is online."

local CAPPED = "The game won't let BFF into any channel for your Crew. Try again later."

function Core:crew()
  local saved = self.db.crew
  if not saved then return nil end
  local generation = saved.generation or 0
  local channel, password = ns.CrewCode.channel(saved.code, generation)
  local alone = not self.ledger:knowsOthers()
  local status, waiting
  if saved.leaving then
    status = LEAVING
  elseif self.channelCapped then
    status, waiting = CAPPED, alone or nil
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
    capped = self.channelCapped == true,
    generation = generation,
    generationFrom = self.generationFrom,
    moves = self.db.channelMoves.count,
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

local function switchSlot(self, slot, carryFrom)
  bindSlot(self, slot, false)
  if carryFrom then self.ledger:carryOwn(carryFrom) end
  self.linkFailed = nil
  self.channelCapped = nil
  self.toldOutOfDate = nil
  self.mourning = nil
  self.generationFrom = "saved"
  if self.whatsNewState.version then self.ledger:writeOwn({ bff = self.whatsNewState.version }) end
  if self.character then self.ledger:updateOwn(self.character) end
  updateLink(self)
end

local function leftCrewWith(self, code)
  local slot = ns.Slots.left(self.account, self.rulesetKey)
  local crew = slot and slot.crew
  return type(crew) == "table" and crew.code == code and crew or nil
end

local function enter(self, code, displayName, joining)
  local left = leftCrewWith(self, code)
  if left then
    switchSlot(self, ns.Slots.rejoin(self.account, self.rulesetKey))
  else
    ns.Slots.dropLeft(self.account, self.rulesetKey)
    self.crewGoals:clear()
  end
  self.db.catchTypesTold = nil
  local generation = left and left.generation or nil
  self.ledger:writeOwn({ displayName = displayName, left = false, joinedAt = self.now(), generation = generation or false })
  sendOwnNow(self)
  self.db.crew = { code = code, joined = joining or nil, generation = generation }
  self.generationFrom = "saved"
  self.linkFailed = nil
  self.channelCapped = nil
  if left then self:raiseGeneration(true) end
  if joining then self.feedState:ownJoined() end
  self.listener("crewChanged")
  updateLink(self)
  return self:crew()
end

local function cardAnswer(self, answer)
  if self.db.crew then return nil, "inCrew" end
  local result = answer()
  if not result then return nil, "notWaiting" end
  return result
end

local function takeSlot(self, slot, how)
  switchSlot(self, slot)
  if self.facts.serverId then self.ledger:keepCharacters(ns.Slots.belongsHere(self.db, self.facts.serverId)) end
  self:raiseGeneration(true)
  sendOwnNow(self)
  traceRuleset(self, how)
  self.listener("crewChanged")
  return self:crew()
end

function Core:placeCrewHere()
  return cardAnswer(self, function()
    local slot = ns.Slots.placeHere(self.account, self.rulesetKey, self.now())
    return slot and takeSlot(self, slot, "placed the Crew saved before Rulesets here (asked)")
  end)
end

function Core:bringCrewHere()
  return cardAnswer(self, function()
    local slot = ns.Slots.bringHere(self.account, self.rulesetKey, self.random)
    return slot and takeSlot(self, slot, "brought the Crew over from the other faction")
  end)
end

function Core:startFresh()
  return cardAnswer(self, function()
    if not ns.Slots.decline(self.account, self.rulesetKey, self.now()) then return false end
    traceRuleset(self, "started fresh, leaving the Crew saved before Rulesets")
    self.listener("crewChanged")
    return true
  end)
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
  local crew = self.db.crew
  if self.linkUp then self.gossip:sendNow({ type = "DATA", records = { self.ledger:tombstone() } }) end
  self.spareLife:clear()
  crew.leaving, crew.left = nil, true
  local joinFailure = self.db.joinFailure
  switchSlot(self, ns.Slots.leave(self.account, self.rulesetKey, self.random), self.ledger)
  self.db.joinFailure = joinFailure
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
  if self.linkUp or self.linkFailed or self.channelCapped then finishLeaving(self) else self.listener("changed") end
  return true
end

local function moveTo(self, generation, from)
  self.db.crew.generation = generation
  self.generationFrom = from
  self.channelCapped = nil
  self.ledger:writeOwn({ generation = generation })
  sendOwnNow(self)
  if self.trace then self.trace(("channel generation %d (%s)"):format(generation, from)) end
end

function Core:raiseGeneration(quiet)
  local crew = self.db.crew
  if not crew then return false end
  local highest, from = self.ledger:highestGeneration()
  if highest <= (crew.generation or 0) then return false end
  moveTo(self, highest, ("%s's record"):format(self.ledger:record(from).displayName or from))
  if not quiet then self.listener("crewChanged") end
  return true
end

Core.MAX_MOVES = 5

function Core:channelBroken()
  local crew = self.db.crew
  if not crew then return end
  local moves = self.db.channelMoves
  if moves.count >= Core.MAX_MOVES then
    if self.trace then self.trace(("channel broken, not moving: %d moves this session already"):format(moves.count)) end
    self.channelCapped = true
    if crew.leaving then
      finishLeaving(self)
      return
    end
    if not moves.told then
      moves.told = true
      self.listener("notice", "noChannel")
    end
    self.listener("changed")
    return
  end
  moves.count = moves.count + 1
  moveTo(self, (crew.generation or 0) + 1, "moved this session")
  self.listener("crewChanged")
end

local JOIN_FAILURES = { wrongPassword = true, tooManyChannels = true }

function Core:joinFailed(kind)
  local crew = self.db.crew
  if not crew or not JOIN_FAILURES[kind] then return end
  self.linkFailed = true
  self.db.joinFailure = { kind = kind, at = self.now() }
  if crew.leaving then
    finishLeaving(self)
  else
    self.listener("notice", kind)
  end
end

function Core:joinFailure()
  local saved = self.db.joinFailure
  if type(saved) ~= "table" or not JOIN_FAILURES[saved.kind] or type(saved.at) ~= "number" then return nil end
  return { kind = saved.kind, at = saved.at }
end

function Core:up()
  self.linkUp = true
  self.linkFailed = nil
  self.db.joinFailure = nil
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
  local alone = self.db.crew ~= nil and not self.ledger:knowsOthers()
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
    self:raiseGeneration()
    if alone then noteWalkIn(self, records) end
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
    confirmRuleset(self)
    local partial = decoded.partial == true
    if self.trace then
      self.trace(("receive DIGEST from %s · ok%s · %s"):format(traceName(self, decoded.from),
        partial and " (more in turn)" or "", traceVersions(self, decoded.versions)))
    end
    self.gossip:digestReceived(decoded.versions, partial, decoded.turns == true, from)
  elseif decoded.type == "DATA" and type(decoded.records) == "table" then
    confirmRuleset(self)
    changed = dataReceived(self, decoded.records, decoded.from, type(from) == "string")
  elseif self.trace then
    self.trace(("receive %s from %s · ignored (unknown)"):format(tostring(decoded.type), traceName(self, decoded.from)))
  end
  if onlineChanged(self) or changed then self.listener("changed") end
end
