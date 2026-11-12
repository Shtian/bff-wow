-- Doing: what each Member is doing right now, for the Pocket Camp: at a
-- vendor or the auction house, fighting, flying or resting. Like a WHERE
-- it's told as it happens and is no part of a record: a small DOING goes out when what
-- you're doing changes, { doing (nil for nothing), quest (true if a quest
-- was just handed in), at (your clock) }, one chunk, never DATA, so
-- DIGESTs don't start asking for it. What's heard is held in memory only
-- and runs out by itself, since the DOING that ends it can be lost. Older
-- BFFs ignore the unknown type. See docs/design/pocket-camp.md.

local _, ns = ...

local Doing = {}
Doing.__index = Doing
ns.Doing = Doing

-- What can be done, the one shown first when several are true.
local ORDER = { "flying", "auction", "vendor", "fighting", "resting" }
local KNOWN = {}
for _, state in ipairs(ORDER) do KNOWN[state] = true end

-- Fighting lasts this long past the end of combat, so pull after pull is
-- one spell of it.
local FIGHTING_HOLD = 20
-- The least time between DOINGs, and how much it grows per other Member
-- online, so a big Crew stays at about 12 whispers a minute.
local EVERY_MIN = 15
local EVERY_PER_MEMBER = 5
-- While something is being done, it's said again this often, and what's
-- heard runs out this long after it was last said.
local REFRESH = 2 * 60
local EXPIRES = 5 * 60
-- A quest handed in is only worth telling this long: longer than the
-- gap between DOINGs in a Crew of a dozen.
local QUEST_FOR = 90

-- now() is Core's clock.
function Doing.new(now)
  return setmetatable({
    now = now,
    -- What the game says is true now: combat, vendor, auction, resting, flying.
    facts = {},
    fightingUntil = -math.huge,
    -- What the last DOING said (false until this session has sent one,
    -- so the first says what you're doing even if that's nothing: the
    -- Crew may still hold what the session before said), and when it went
    -- out.
    sent = false,
    sentAt = -math.huge,
    -- Someone came online since, who hasn't heard it.
    unheard = false,
    -- When a quest was handed in that no DOING has told of yet.
    questAt = nil,
    -- What you were doing when noteState() last looked.
    noted = nil,
    -- memberId -> { doing, at (their clock), heardAt (yours) }.
    heardFrom = {},
  }, Doing)
end

-- What the game says you're doing: { combat, vendor, auction, resting,
-- flying }, each true or not.
function Doing:set(facts)
  local was = self.facts.combat
  self.facts = {
    combat = facts.combat == true, vendor = facts.vendor == true, auction = facts.auction == true,
    resting = facts.resting == true, flying = facts.flying == true,
  }
  if was and not self.facts.combat then self.fightingUntil = self.now() + FIGHTING_HOLD end
end

-- What you're doing now: the first of ORDER that's true, or nil.
function Doing:state()
  local facts = self.facts
  local on = {
    flying = facts.flying, auction = facts.auction, vendor = facts.vendor, resting = facts.resting,
    fighting = facts.combat or self.now() < self.fightingUntil,
  }
  for _, state in ipairs(ORDER) do
    if on[state] then return state end
  end
  return nil
end

-- Notes what you're doing now. Returns true if it isn't what it was the
-- last time this looked.
function Doing:noteState()
  local state = self:state()
  if state == self.noted then return false end
  self.noted = state
  return true
end

-- A quest was handed in: the next DOING says so, if it goes out soon.
function Doing:questHandedIn()
  self.questAt = self.now()
end

-- Someone came online: they haven't heard what you're doing.
function Doing:newcomer()
  self.unheard = true
end

-- Called once a second. talking says Gossip may talk and others how many
-- other Members are online. Returns a DOING to send to everyone, or nil.
function Doing:tick(talking, others)
  local now = self.now()
  if self.questAt and now - self.questAt > QUEST_FOR then self.questAt = nil end
  if not talking or others <= 0 then return nil end
  local state = self:state()
  local due = state ~= self.sent or self.questAt ~= nil
    or (state ~= nil and (self.unheard or now - self.sentAt >= REFRESH))
  if not due or now - self.sentAt < math.max(EVERY_MIN, EVERY_PER_MEMBER * others) then return nil end
  local quest = self.questAt ~= nil or nil
  self.sent, self.sentAt, self.unheard, self.questAt = state, now, false, nil
  return { type = "DOING", doing = state, quest = quest, at = now }
end

-- A DOING from the Member with this id. Returns whether it was kept, and
-- whether it tells of a quest handed in. A state this BFF doesn't know
-- counts as nothing.
function Doing:heard(from, message)
  if type(message.at) ~= "number" then return false end
  local held = self.heardFrom[from]
  if held and held.at > message.at then return false end
  self.heardFrom[from] = { doing = KNOWN[message.doing] and message.doing or nil, at = message.at,
    heardAt = self.now() }
  return true, message.quest == true
end

-- What the Member with this id was last heard doing, or nil.
function Doing:of(memberId)
  local held = self.heardFrom[memberId]
  if held and self.now() - held.heardAt < EXPIRES then return held.doing end
  return nil
end

-- Drops what has run out. Returns true if something being done ended.
function Doing:expire()
  local now, ended = self.now(), false
  for id, held in pairs(self.heardFrom) do
    if now - held.heardAt >= EXPIRES then
      ended = ended or held.doing ~= nil
      self.heardFrom[id] = nil
    end
  end
  return ended
end

-- A Member who was removed or went offline: what they did goes.
function Doing:forget(memberId)
  self.heardFrom[memberId] = nil
end

-- Leaving the Crew: everything heard goes.
function Doing:clear()
  self.heardFrom = {}
end
