local _, ns = ...

local Doing = {}
Doing.__index = Doing
ns.Doing = Doing

local ORDER = { "flying", "auction", "vendor", "fighting", "afk", "resting" }
local KNOWN = {}
for _, state in ipairs(ORDER) do KNOWN[state] = true end

local FORMS = { wolf = "now", bear = "now", cat = "now", moonkin = "now", travel = "held", seal = "held" }
local TRAVEL_HOLD = 30
local FORM_EXPIRES = 150

local FIGHTING_HOLD = 20
local EVERY_MIN = 15
local EVERY_PER_MEMBER = 5
local REFRESH = 2 * 60
local EXPIRES = 5 * 60
local QUEST_FOR = 90
local LARGE_CREW = 12
assert(QUEST_FOR > EVERY_PER_MEMBER * (LARGE_CREW - 1), "a quest must outlast the gap between DOINGs")

function Doing.new(now)
  return setmetatable({
    now = now,
    facts = {},
    formSince = -math.huge,
    sentForm = nil,
    fightingUntil = -math.huge,
    sent = false,
    sentAt = -math.huge,
    unheard = false,
    questAt = nil,
    noted = nil,
    notedForm = nil,
    heardFrom = {},
  }, Doing)
end

function Doing:set(facts)
  local was, wasForm = self.facts.combat, self.facts.form
  self.facts = {
    combat = facts.combat == true, vendor = facts.vendor == true, auction = facts.auction == true,
    afk = facts.afk == true, resting = facts.resting == true, flying = facts.flying == true,
    form = FORMS[facts.form] and facts.form or nil,
  }
  if was and not self.facts.combat then self.fightingUntil = self.now() + FIGHTING_HOLD end
  if self.facts.form ~= wasForm then self.formSince = self.now() end
end

function Doing:form()
  return self.facts.form
end

local function tellable(self)
  local form = self.facts.form
  if not form then return nil end
  local since = self.formSince
  if FORMS[form] == "held" then
    since = since + TRAVEL_HOLD
    if self.now() < since then return nil end
  end
  return form, since
end

function Doing:fighting()
  return self.facts.combat or self.now() < self.fightingUntil
end

function Doing:state()
  local facts = self.facts
  local on = {
    flying = facts.flying, auction = facts.auction, vendor = facts.vendor, afk = facts.afk, resting = facts.resting,
    fighting = self:fighting(),
  }
  for _, state in ipairs(ORDER) do
    if on[state] then return state end
  end
  return nil
end

function Doing:noteState()
  local state, form = self:state(), self.facts.form
  if state == self.noted and form == self.notedForm then return false end
  self.noted, self.notedForm = state, form
  return true
end

function Doing:questHandedIn()
  self.questAt = self.now()
end

function Doing:newcomer()
  self.unheard = true
end

function Doing:tick(talking, othersOnline)
  local now = self.now()
  if self.questAt and now - self.questAt > QUEST_FOR then self.questAt = nil end
  if not talking or othersOnline <= 0 then return nil end
  local state = self:state()
  local form, formSince = tellable(self)
  local due = state ~= self.sent or self.questAt ~= nil
    or (form ~= nil and (form ~= self.sentForm or formSince > self.sentAt))
    or ((state ~= nil or form ~= nil) and (self.unheard or now - self.sentAt >= REFRESH))
  if not due or now - self.sentAt < math.max(EVERY_MIN, EVERY_PER_MEMBER * othersOnline) then return nil end
  local quest = self.questAt ~= nil or nil
  self.sent, self.sentForm, self.sentAt, self.unheard, self.questAt = state, form, now, false, nil
  return { type = "DOING", doing = state, form = form, quest = quest, at = now }
end

function Doing:heard(from, message)
  if type(message.at) ~= "number" then return false end
  local held = self.heardFrom[from]
  if held and held.at > message.at then return false end
  self.heardFrom[from] = { doing = KNOWN[message.doing] and message.doing or nil,
    form = FORMS[message.form] and message.form or nil, at = message.at, heardAt = self.now() }
  return true, message.quest == true
end

function Doing:of(memberId)
  local held = self.heardFrom[memberId]
  if held and self.now() - held.heardAt < EXPIRES then return held.doing end
  return nil
end

function Doing:formOf(memberId)
  local held = self.heardFrom[memberId]
  if held and self.now() - held.heardAt < FORM_EXPIRES then return held.form end
  return nil
end

function Doing:expire()
  local now, ended = self.now(), false
  for id, held in pairs(self.heardFrom) do
    if held.form and now - held.heardAt >= FORM_EXPIRES then
      ended = true
      held.form = nil
    end
    if now - held.heardAt >= EXPIRES then
      ended = ended or held.doing ~= nil
      self.heardFrom[id] = nil
    end
  end
  return ended
end

function Doing:forget(memberId)
  self.heardFrom[memberId] = nil
end

function Doing:clear()
  self.heardFrom = {}
end
