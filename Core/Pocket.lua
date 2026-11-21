local _, ns = ...

local Pocket = {}
Pocket.__index = Pocket
ns.Pocket = Pocket

local SPELL_FOR = 60
local BEDROLL_FOR = 10 * 60
local TROPHY_CUP_FOR = 60 * 60
local LANTERNS = 1

local ANIMATED = { ding = true, maxLevel = true, death = true, rareFind = true, goal = true }

function Pocket.new(deps)
  return setmetatable({
    now = deps.now,
    ledger = deps.ledger,
    feed = deps.feed,
    goals = deps.goals,
    spares = deps.spares,
    doings = deps.doings,
    listener = deps.listener,
    isOn = deps.on,
    setting = deps.setting,
    season = deps.season,
    phase = deps.phase,
    spot = deps.spot,
    saved = deps.saved,
    walkIn = deps.walkIn,
    trophiesSince = deps.feed:isSettled() and deps.now() or nil,
    fishing = {},
    working = {},
    bedrolls = {},
    poseSince = {},
    party = {},
    partyKey = nil,
  }, Pocket)
end

function Pocket:on()
  return self.isOn()
end

function Pocket:syncSettled()
  self.trophiesSince = self.now()
end

function Pocket:caught(id)
  self.fishing[id] = self.now() + SPELL_FOR
end

function Pocket:practised(id, before, after)
  local kind = ns.Professions.practised(before, after)
  if kind then self.working[id] = { kind = kind, ends = self.now() + SPELL_FOR } end
end

function Pocket:merged(before, record)
  if ns.Catches.total(record) > ns.Catches.total(before) then self:caught(record.id) end
  for guid, character in pairs(record.characters) do
    local was = before.characters[guid]
    if was then self:practised(record.id, was.professions, character.professions) end
  end
end

function Pocket:cameOnline(id)
  self.bedrolls[id] = nil
end

function Pocket:wentOffline(id)
  self.bedrolls[id] = self.now()
end

function Pocket:forget(id)
  self.fishing[id] = nil
  self.working[id] = nil
  self.bedrolls[id] = nil
end

function Pocket:clear()
  self.fishing = {}
  self.working = {}
  self.bedrolls = {}
end

local function text(value)
  return type(value) == "string" and value ~= "" and value or nil
end

function Pocket:group(party)
  local units, keys = {}, {}
  for _, unit in ipairs(type(party) == "table" and party or {}) do
    if type(unit) == "table" then
      local guid, name, lastName = text(unit.guid), text(unit.name), text(unit.lastName)
      if guid or name then
        units[#units + 1] = { guid = guid, name = name, lastName = lastName }
        keys[#keys + 1] = ("%s/%s/%s"):format(guid or "", name or "", lastName or "")
      end
    end
  end
  table.sort(keys)
  local key = table.concat(keys, "\n")
  if key == self.partyKey then return end
  self.party = units
  self.partyKey = key
  if self:on() then self.listener("changed") end
end

local function doingOf(self, rows, now)
  local doing = { said = {}, form = {}, fishing = {}, working = {} }
  for _, row in ipairs(rows) do
    local id = row.memberId
    if row.own then
      doing.said[id], doing.form[id] = self.doings:state(), self.doings:form()
    else
      doing.said[id], doing.form[id] = self.doings:of(id), self.doings:formOf(id)
    end
  end
  for id, ends in pairs(self.fishing) do
    if ends > now then doing.fishing[id] = true end
  end
  for id, work in pairs(self.working) do
    if work.ends > now then doing.working[id] = work.kind end
  end
  local keys, since = ns.Camp.poseKeys(rows, doing), {}
  for id, key in pairs(keys) do
    local held = self.poseSince[id]
    if not held or held.key ~= key then
      held = { key = key, at = now }
      self.poseSince[id] = held
    end
    since[id] = held.at
  end
  for id in pairs(self.poseSince) do
    if not keys[id] then self.poseSince[id] = nil end
  end
  doing.since = since
  return doing
end

local function pocketView(self)
  local now = self.now()
  local rows = ns.Roster.rows(self.ledger, now)
  local doing = doingOf(self, rows, now)
  local bedrolls = {}
  for id, since in pairs(self.bedrolls) do
    if now - since < BEDROLL_FOR then bedrolls[id] = since end
  end
  local saved = self.saved()
  local shown = { alts = self.setting("pocketCampAlts"), season = self.season(), phase = self.phase(),
    lanternCount = saved and LANTERNS }
  local view = ns.Camp.pocket(rows, self.feed:since(now - ns.Camp.RECENT), now, doing, bedrolls,
    self.setting("pocketCampColumns"), ns.Camp.grouped(rows, self.party), shown)
  view.saved = view.lanternSeats and saved or nil
  view.walkIn = self.walkIn(view, rows)
  return view
end

local function expire(self)
  local now, ended = self.now(), false
  for id, ends in pairs(self.fishing) do
    if ends <= now then
      self.fishing[id] = nil
      ended = true
    end
  end
  for id, work in pairs(self.working) do
    if work.ends <= now then
      self.working[id] = nil
      ended = true
    end
  end
  for id, since in pairs(self.bedrolls) do
    if now - since >= BEDROLL_FOR then
      self.bedrolls[id] = nil
      ended = true
    end
  end
  return ended
end

local function notePoses(self)
  if not self:on() then
    self.poseSince = {}
    return
  end
  local now = self.now()
  doingOf(self, ns.Roster.rows(self.ledger, now), now)
end

function Pocket:tick()
  local ended = expire(self)
  ended = self.doings:expire() or ended
  ended = self.doings:noteState() or ended
  if ended and self:on() then self.listener("changed") end
  notePoses(self)
end

function Pocket:animateMember(kind, memberId)
  if not self:on() then return end
  for _, actor in ipairs(pocketView(self).actors) do
    if actor.memberId == memberId and actor.pose ~= "asleep" then
      self.listener("pocketCampAnimation", { kind = kind, memberId = memberId })
    end
  end
end

function Pocket:animate(entries)
  if not self:on() then return end
  for _, entry in ipairs(entries) do
    if entry.kind == "goal" then
      self.listener("pocketCampAnimation", { kind = "goal" })
    elseif ANIMATED[entry.kind] then
      self:animateMember(entry.kind, entry.memberId)
    end
  end
end

local function sessionTrophies(self)
  if not self.trophiesSince then return nil end
  local now = self.now()
  local list = {}
  for _, trophy in ipairs(self.goals:trophies().shelf) do
    local age = now - trophy.time
    if not trophy.quiet and trophy.time >= self.trophiesSince and age < TROPHY_CUP_FOR then
      list[#list + 1] = {
        name = trophy.title .. ": " .. trophy.label,
        ago = age < 60 and "just now" or ns.Text.since(age),
      }
    end
  end
  return list[1] and list or nil
end

local function trophiesTooltip(trophies)
  local lines = {}
  for i, trophy in ipairs(trophies) do lines[i] = trophy.name .. " · " .. trophy.ago end
  if #trophies == 1 then
    return { title = "A Trophy reached", lines = lines, hint = "Click to see it in Trophies." }
  end
  return { title = #trophies .. " Trophies reached", lines = lines, hint = "Click to see them in Trophies." }
end

local function sparesTooltip(spares)
  if spares == 1 then return { title = "1 Spare notice", hint = "Click to see it in Spares." } end
  return { title = spares .. " Spare notices", hint = "Click to see them in Spares." }
end

function Pocket:view()
  if not self:on() then return nil end
  local setting = self.setting
  local view = pocketView(self)
  view.opacity = setting("pocketCampOpacity") / 100
  view.locked = setting("pocketCampLocked")
  view.inCombat = setting("pocketCampCombat")
  view.combatFade = setting("pocketCampCombatFade") / 100
  view.position = setting("pocketCampPosition")
  view.scale = setting("pocketCampScale") / 100
  view.maxColumns = setting("pocketCampColumns")
  view.tooltip.hint = view.locked and "Click to open BFF." or "Click to open BFF. Drag to move."
  local spares = setting("pocketCampSpares") and self.spares:unseen() or 0
  if spares > 0 then
    view.spares = spares
    view.sparesTooltip = sparesTooltip(spares)
  end
  view.trophies = sessionTrophies(self)
  view.trophiesTooltip = view.trophies and trophiesTooltip(view.trophies)
  for _, actor in ipairs(view.actors) do
    local row = actor.row
    if row and not row.own and actor.pose ~= "asleep" then
      local spot = self.spot(row)
      actor.menu = { fullName = row.fullName, mapId = spot and spot.mapId }
    end
  end
  return view
end
