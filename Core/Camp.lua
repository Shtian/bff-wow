-- Camp: the Crew as a small pixel campsite, worked out from Roster's rows
-- and Feed's entries, placed so the UI only draws it. Who is there, seated
-- by the fire or asleep, the graves recent deaths leave, the flowers
-- Respects put on them and the spark over a fresh max level. Also the
-- Pocket Camp, the cut-down one kept on screen: the fire and the online
-- Members, with what each is doing. Pure and stateless: tested through
-- Core:camp() and Core:pocketCamp(). See docs/design/camp.md and
-- docs/design/pocket-camp.md.

local _, ns = ...

local Camp = {}
ns.Camp = Camp

local DAY = 24 * 60 * 60

-- The Camp's geometry, in art pixels. x runs from the fire's centre,
-- negative to the left. The fire's logs keep `fire` clear on each side,
-- a figure is `seated` or `asleep` wide, a grave `grave` wide with
-- `graveGap` before it, `gap` sits between neighbours and `margin` inside
-- each edge of the band. The tent, `tent` wide, only shows when there's
-- room. UI reads the same table to draw it. The panel's band is between
-- `minColumns` and `maxColumns` wide; the popup's is `awayColumns`. The
-- Pocket Camp is always `pocketColumns` wide and `pocketRows` high; a
-- flying figure's griffin takes `griffinFore` more towards the fire and
-- `griffinAft` away from it.
local LAYOUT = {
  fire = 9,
  seated = 12,
  asleep = 18,
  grave = 8,
  graveGap = 2,
  gap = 4,
  margin = 2,
  tent = 36,
  minColumns = 128,
  maxColumns = 375,
  awayColumns = 120,
  pocketColumns = 112,
  pocketRows = 34,
  griffinFore = 8,
  griffinAft = 6,
}
Camp.LAYOUT = LAYOUT

-- Graves and sparks last this long; each Member has at most `MEMBER_GRAVES`
-- graves, the Camp `GRAVES`.
Camp.RECENT = DAY
local MEMBER_GRAVES = 2
local GRAVES = 4

-- Online Members, you first, in Roster's order; then sleepers, most
-- recent Last seen first, unless onlineOnly.
local function candidates(rows, onlineOnly)
  local seated, asleep = {}, {}
  for _, row in ipairs(rows) do
    if row.own or row.online then
      seated[#seated + 1] = row
    else
      asleep[#asleep + 1] = row
    end
  end
  table.sort(asleep, function(a, b)
    if a.lastSeen ~= b.lastSeen then return a.lastSeen > b.lastSeen end
    return a.memberId < b.memberId
  end)
  if onlineOnly then return seated end
  for _, row in ipairs(asleep) do seated[#seated + 1] = row end
  return seated
end

-- The recent news per Member: graves (newest first, a death entry counting
-- as its deaths, capped per Member and in all) and sparks.
local function news(entries, now)
  local graves, sparks, total = {}, {}, 0
  -- entries come newest first.
  for _, entry in ipairs(entries) do
    if entry.memberId and now - entry.time < Camp.RECENT then
      if entry.kind == "maxLevel" then sparks[entry.memberId] = true end
      if entry.kind == "death" then
        local list = graves[entry.memberId] or {}
        graves[entry.memberId] = list
        local flower = #entry.reactors > 0 or nil
        for _ = 1, entry.count or 1 do
          if #list < MEMBER_GRAVES and total < GRAVES then
            list[#list + 1] = { flower = flower }
            total = total + 1
          end
        end
      end
    end
  end
  return graves, sparks
end

-- Places a slot (a figure and its graves) on one side of the fire, if it
-- fits. A side is { sign, used, limit }; the figure is nearest the fire,
-- its graves outward. fore and aft (default 0) keep that much more clear
-- of the figure towards the fire and away from it.
local function placeOn(side, figure, graveCount, fore, aft)
  local width = figure + (aft or 0) + graveCount * (LAYOUT.graveGap + LAYOUT.grave)
  local start = (side.used == 0 and LAYOUT.fire or side.used + LAYOUT.gap) + (fore or 0)
  if start + width > side.limit then return nil end
  side.used = start + width
  local x
  if side.sign > 0 then x = start else x = -start - figure end
  local graveXs = {}
  for i = 1, graveCount do
    local offset = figure + (i - 1) * (LAYOUT.graveGap + LAYOUT.grave) + LAYOUT.graveGap
    if side.sign > 0 then
      graveXs[i] = x + offset
    else
      graveXs[i] = x - offset + figure - LAYOUT.grave
    end
  end
  return x, graveXs
end

-- The side with the most room left: the one used least, ties to the left.
local function roomier(left, right)
  if right.used < left.used then return right, left end
  return left, right
end

-- Each actor's label room: twice the distance from its centre to the
-- nearer of the midpoints with its neighbours (the fire counting as one at
-- 0, the band's edges as the outer ones), less the gap.
local function labelRoom(actors, left, right)
  local sorted = {}
  for i, actor in ipairs(actors) do sorted[i] = actor end
  table.sort(sorted, function(a, b) return a.x < b.x end)
  for i, actor in ipairs(sorted) do
    local centre = actor.x + actor.width / 2
    local before, after = -left, right
    local prev, nextOne = sorted[i - 1], sorted[i + 1]
    if prev then before = (prev.x + prev.width / 2 + centre) / 2 end
    if nextOne then after = (nextOne.x + nextOne.width / 2 + centre) / 2 end
    if centre > 0 and (not prev or prev.x + prev.width / 2 < 0) then before = math.max(before, 0) end
    if centre < 0 and (not nextOne or nextOne.x + nextOne.width / 2 > 0) then after = math.min(after, 0) end
    actor.labelWidth = math.max(actor.width, math.floor(2 * math.min(centre - before, after - centre)) - LAYOUT.gap)
  end
end

-- The Camp at `columns` art pixels wide, from Roster's rows (yours first)
-- and Feed's entries (newest first, as Feed:describe gives them), at time
-- now. options.tent false leaves the tent out; options.onlineOnly leaves
-- out sleepers and graves, and options.moreText words the count of who
-- didn't fit (default "+%d more"), and options.room(row) gives the room a
-- row's figure needs beyond itself: towards the fire, and away from it.
-- Returns { columns, actors, graves, tent, more }; see Core:camp().
function Camp.view(rows, entries, now, columns, options)
  options = options or {}
  columns = math.max(1, math.floor(columns))
  local leftEdge = math.floor(columns / 2)
  local rightEdge = columns - leftEdge
  local left = { sign = -1, used = 0, limit = leftEdge - LAYOUT.margin }
  local right = { sign = 1, used = 0, limit = rightEdge - LAYOUT.margin }
  local graves, sparks = news(entries, now)

  local view = { columns = columns, actors = {}, graves = {} }
  local more = 0
  for _, row in ipairs(candidates(rows, options.onlineOnly)) do
    local seated = row.own or row.online
    local figure = seated and LAYOUT.seated or LAYOUT.asleep
    local own = not options.onlineOnly and graves[row.memberId] or {}
    local fore, aft
    if options.room then fore, aft = options.room(row) end
    -- A slot that won't fit with its graves may fit without them.
    local first, second = roomier(left, right)
    local x, graveXs, side
    for _, count in ipairs({ #own, 0 }) do
      for _, tried in ipairs({ first, second }) do
        if not x then
          x, graveXs = placeOn(tried, figure, count, fore, aft)
          side = x and tried
        end
      end
      if x then break end
    end
    if x then
      view.actors[#view.actors + 1] = {
        memberId = row.memberId,
        pose = seated and "seated" or "asleep",
        label = row.own and "You" or row.displayName or row.name,
        classFilename = row.classFilename,
        x = x,
        width = figure,
        side = side.sign,
        spark = sparks[row.memberId],
        you = row.own or nil,
      }
      for i, graveX in ipairs(graveXs) do
        view.graves[#view.graves + 1] = { memberId = row.memberId, x = graveX, flower = own[i].flower }
      end
    else
      more = more + 1
    end
  end
  view.more = more > 0 and more or nil
  view.moreText = view.more and (options.moreText or "+%d more"):format(more) or nil

  if options.tent ~= false then
    local side = roomier(left, right)
    local x = placeOn(side, LAYOUT.tent, 0)
    if x then view.tent = { x = x } end
  end
  labelRoom(view.actors, leftEdge, rightEdge)
  for _, actor in ipairs(view.actors) do actor.side = nil end
  return view
end

-- A pose in words, but "adventuring", which names its instance.
local STATUS = {
  seated = "by the fire", fishing = "fishing", crafting = "crafting", gathering = "gathering",
  fighting = "fighting", vendor = "at a vendor", auction = "at the auction house", resting = "resting",
  afk = "away", flying = "flying",
}

-- The instances that are raids, by name.
local RAIDS = {}
for _, dungeon in ipairs(ns.Together.DUNGEONS) do
  if dungeon.kind == "raid" then RAIDS[dungeon.name] = true end
end

-- What a row's Member is shown doing. In an instance (the record says
-- so, and it's newer than anything said before going in) it's that,
-- unless a spell of fishing or of a profession is on. Elsewhere what they
-- said they chose to do (flying, the auction house, a vendor) comes
-- first, then such a spell, fighting, away, resting, and by the fire.
local function poseOf(row, doing)
  local id = row.memberId
  local said = not row.instance and doing.said[id] or nil
  if said == "flying" or said == "auction" or said == "vendor" then return said end
  if doing.fishing[id] then return "fishing" end
  if doing.working[id] then return doing.working[id] end
  if row.instance then return "adventuring" end
  return said or "seated"
end

-- The Pocket Camp: the fire and the online Members, you first, as many as
-- fit, at LAYOUT.pocketColumns by LAYOUT.pocketRows. doing is what they're
-- up to, each by Member id: said (what they last said they're doing, as
-- Doing gives it), fishing (true while fishing) and working ("crafting"
-- or "gathering" while at a profession). Each actor is as in view(), with
-- pose (see Core:pocketCamp()), instance (its name, while in one), raid
-- (true if that's a raid), status (the pose in words) and row (the
-- Member's Roster row, for the tooltip over the figure). A flying figure
-- takes its griffin's room. Members that didn't fit are counted in more
-- ("+2"). tooltip lists who is doing what: { title, lines }.
function Camp.pocket(rows, entries, now, doing)
  local poses = {}
  for _, row in ipairs(rows) do poses[row.memberId] = poseOf(row, doing) end
  local view = Camp.view(rows, entries, now, LAYOUT.pocketColumns, {
    tent = false, onlineOnly = true, moreText = "+%d",
    room = function(row)
      if poses[row.memberId] == "flying" then return LAYOUT.griffinFore, LAYOUT.griffinAft end
    end,
  })
  view.rows = LAYOUT.pocketRows
  view.graves = nil
  local byMember = {}
  for _, row in ipairs(rows) do byMember[row.memberId] = row end
  local lines = {}
  for i, actor in ipairs(view.actors) do
    actor.row = byMember[actor.memberId]
    actor.instance = actor.row.instance
    actor.pose = poses[actor.memberId]
    if actor.pose == "adventuring" then
      actor.raid = RAIDS[actor.instance] or nil
      actor.status = "in " .. actor.instance
    else
      actor.status = STATUS[actor.pose]
    end
    lines[i] = ("%s: %s"):format(actor.label, actor.status)
  end
  view.tooltip = { title = "Pocket Camp", lines = lines }
  return view
end

-- The Camp's wording on Roster's rows (as Roster.rows gives them, in
-- `order`), in place: each row's status (right-hand text: "by the fire",
-- "asleep · 5m ago", or with the Camp off its Last seen), and each other
-- Member's section label ("BY THE FIRE" and "ASLEEP IN CAMP" under Online
-- first with the Camp on, else "CREW").
function Camp.wordRows(rows, on, order)
  local split = on and (order == nil or order == "online")
  for _, row in ipairs(rows) do
    if row.own then
      row.status = nil
    elseif on then
      row.status = row.online and "by the fire" or "asleep · " .. row.lastSeenText
    else
      row.status = row.lastSeenText
    end
    if not row.own then
      row.section = split and (row.online and "BY THE FIRE" or "ASLEEP IN CAMP") or "CREW"
    end
  end
  return rows
end

-- The panel header's count: "2 of 5 by the fire", you counted, with the
-- Camp on; else "1 of 4 online", others only.
function Camp.header(summary, on)
  if on then
    return ("%d of %d by the fire"):format(summary.online + 1, summary.members + 1)
  end
  return ("%d of %d online"):format(summary.online, summary.members)
end

-- While you were away in the Camp's voice: the Camp at the popup's width
-- without the tent, each actor tagged with what their Main gained
-- (gained, as the scoreboard words it, and highlight for max level) from
-- the summary's member blocks, and the intro.
function Camp.away(rows, entries, now, summary)
  local view = Camp.view(rows, entries, now, LAYOUT.awayColumns, { tent = false })
  local byMember = {}
  for _, member in ipairs(summary.members) do byMember[member.memberId] = member end
  for _, actor in ipairs(view.actors) do
    local member = byMember[actor.memberId]
    local main = member and member.characters[1]
    if main and main.main and main.gained then
      actor.gained = main.gained
      actor.highlight = main.maxLevel or nil
    end
  end
  local count = summary.count
  local intro = count == 1 and "The fire kept burning. 1 thing happened in camp."
    or ("The fire kept burning. %d things happened in camp."):format(count)
  return view, intro
end
