-- Camp: the Crew as a small pixel campsite, worked out from Roster's rows
-- and Feed's entries, placed so the UI only draws it. Who is there, seated
-- by the fire or asleep, the graves recent deaths leave, the flowers
-- Respects put on them and the spark over a fresh max level. Also the
-- Pocket Camp, the cut-down one kept on screen: the fire, the online
-- Members, with what each is doing, and bedrolls for those who just went
-- offline. Pure and stateless: tested through
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
-- Pocket Camp is `pocketRows` high and from `pocketColumns` (its usual
-- width, three seats each side) to `pocketMaxColumns` wide, in steps of
-- `pocketStep` (one more seat each side); a flying figure's griffin takes
-- `griffinFore` more towards the fire and `griffinAft` away from it, and a
-- doorway reaches `doorway` past the first and last figure standing in it.
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
  pocketMaxColumns = 304,
  pocketStep = 32,
  pocketRows = 34,
  griffinFore = 8,
  griffinAft = 6,
  doorway = 2,
}
Camp.LAYOUT = LAYOUT

-- Graves and sparks last this long; each Member has at most `MEMBER_GRAVES`
-- graves, the Camp `GRAVES`.
Camp.RECENT = DAY
local MEMBER_GRAVES = 2
local GRAVES = 4

-- Online Members, you first, in Roster's order; then sleepers, most
-- recent Last seen first. With onlineOnly, only those of the sleepers in
-- the set `sleepers` (if given).
local function candidates(rows, onlineOnly, sleepers)
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
  for _, row in ipairs(asleep) do
    if not onlineOnly or (sleepers and sleepers[row.memberId]) then seated[#seated + 1] = row end
  end
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
-- out sleepers and graves, but those in the set options.sleepers, which
-- take the room the online Members leave and aren't counted in more if
-- they don't fit; options.moreText words the count of who
-- didn't fit (default "+%d more"), options.room(row) gives the room a
-- row's figure needs beyond itself: towards the fire, and away from it,
-- and options.together(row) a key that rows next to each other share when
-- they should sit side by side: they're placed on one side if they fit
-- there, else one by one, and split is then true.
-- Returns { columns, actors, graves, tent, more, split }; see Core:camp().
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
  local list = candidates(rows, options.onlineOnly, options.sleepers)
  local function keyOf(row)
    return options.together and (row.own or row.online) and options.together(row) or nil
  end
  local function roomOf(row)
    if options.room then return options.room(row) end
  end
  -- Rows that sit together, from the first of them: on the roomier side
  -- if they all fit there, or the other. Where each went: row to { x, side }.
  local placed = {}
  local function placeTogether(first)
    local key = keyOf(list[first])
    local last = first
    while key and list[last + 1] and keyOf(list[last + 1]) == key do last = last + 1 end
    if last == first then return end
    for _, tried in ipairs({ roomier(left, right) }) do
      local copy = { sign = tried.sign, used = tried.used, limit = tried.limit }
      local xs = {}
      for j = first, last do
        local fore, aft = roomOf(list[j])
        xs[#xs + 1] = placeOn(copy, LAYOUT.seated, 0, fore, aft)
      end
      if #xs == last - first + 1 then
        tried.used = copy.used
        for j = first, last do placed[list[j]] = { x = xs[j - first + 1], side = tried } end
        return
      end
    end
    view.split = true
  end
  for index, row in ipairs(list) do
    local key = keyOf(row)
    if key and not placed[row] and (index == 1 or keyOf(list[index - 1]) ~= key) then placeTogether(index) end
    local seated = row.own or row.online
    local figure = seated and LAYOUT.seated or LAYOUT.asleep
    local own = not options.onlineOnly and graves[row.memberId] or {}
    local fore, aft = roomOf(row)
    local x, graveXs, side
    if placed[row] then
      x, graveXs, side = placed[row].x, {}, placed[row].side
    else
      -- A slot that won't fit with its graves may fit without them.
      local first, second = roomier(left, right)
      for _, count in ipairs({ #own, 0 }) do
        for _, tried in ipairs({ first, second }) do
          if not x then
            x, graveXs = placeOn(tried, figure, count, fore, aft)
            side = x and tried
          end
        end
        if x then break end
      end
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
    elseif seated or not options.onlineOnly then
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

-- A Pocket Camp width in art pixels, the nearest of its steps: from
-- LAYOUT.pocketColumns, in steps of pocketStep, up to pocketMaxColumns.
-- Anything but a number is the usual width.
function Camp.pocketWidth(columns)
  local low, high, step = LAYOUT.pocketColumns, LAYOUT.pocketMaxColumns, LAYOUT.pocketStep
  if type(columns) ~= "number" then return low end
  columns = math.max(low, math.min(high, columns))
  return low + math.floor((columns - low) / step + 0.5) * step
end

-- How many seated figures fit in a Pocket Camp `columns` art pixels wide,
-- both sides of the fire. A flying figure takes more.
function Camp.pocketSeats(columns)
  local room = math.floor(columns / 2) - LAYOUT.margin - LAYOUT.fire + LAYOUT.gap
  return 2 * math.max(0, math.floor(room / (LAYOUT.seated + LAYOUT.gap)))
end

-- Which of Roster's rows (others') show a Character in your group:
-- Member id to true. party is the game's group, { guid, name, lastName }
-- per unit (Core:group()). A unit is matched by GUID, else by name
-- ignoring case: the first name, and the last name too when both sides
-- have one.
function Camp.grouped(rows, party)
  local found = {}
  for _, row in ipairs(rows) do
    if not row.own then
      local name = row.name and row.name:lower()
      local lastName = row.fullName and row.fullName ~= row.name and row.fullName:sub(#row.name + 2):lower() or nil
      for _, unit in ipairs(party or {}) do
        local match
        if unit.guid and row.guid then
          match = unit.guid == row.guid
        else
          match = unit.name ~= nil and unit.name:lower() == name
            and (not unit.lastName or not lastName or unit.lastName:lower() == lastName)
        end
        if match then found[row.memberId] = true end
      end
    end
  end
  return found
end

-- The online rows (you first) in the Pocket Camp's order: you, your group
-- (in Roster's order), then the rest; and any who are adventuring in the
-- same instance are pulled up after the first of them, so they sit
-- together. The others' rows follow as they were.
local function together(rows, poses, group)
  local online, offline = {}, {}
  for _, row in ipairs(rows) do
    if row.own or row.online then online[#online + 1] = row else offline[#offline + 1] = row end
  end
  local function rank(row)
    if row.own then return 0 end
    return group[row.memberId] and 1 or 2
  end
  local ranked = {}
  for r = 0, 2 do
    for _, row in ipairs(online) do
      if rank(row) == r then ranked[#ranked + 1] = row end
    end
  end
  local function place(row)
    return poses[row.memberId] == "adventuring" and row.instance or nil
  end
  local ordered, taken = {}, {}
  for i, row in ipairs(ranked) do
    if not taken[row] then
      taken[row] = true
      ordered[#ordered + 1] = row
      local instance = place(row)
      for j = i + 1, instance and #ranked or 0 do
        local other = ranked[j]
        if not taken[other] and place(other) == instance then
          taken[other] = true
          ordered[#ordered + 1] = other
        end
      end
    end
  end
  for _, row in ipairs(offline) do ordered[#ordered + 1] = row end
  return ordered
end

-- The doorways the adventuring actors stand in: next to each other on one
-- side, in the same instance, they share one. Each is { x, width,
-- instance, raid }, reaching LAYOUT.doorway past its first and last
-- figure, and each such actor's doorway is its index.
local function doorways(actors)
  local list = {}
  local sorted = {}
  for _, actor in ipairs(actors) do
    if actor.pose == "adventuring" then sorted[#sorted + 1] = actor end
  end
  table.sort(sorted, function(a, b) return a.x < b.x end)
  local previous
  for _, actor in ipairs(sorted) do
    local door = previous and list[previous.doorway]
    if door and door.instance == actor.instance and previous.x + previous.width + LAYOUT.gap == actor.x then
      door.width = actor.x + actor.width + LAYOUT.doorway - door.x
    else
      list[#list + 1] = {
        x = actor.x - LAYOUT.doorway, width = actor.width + 2 * LAYOUT.doorway,
        instance = actor.instance, raid = actor.raid,
      }
    end
    -- Sorted by x, so a doorway's actors are always the latest ones.
    actor.doorway = #list
    previous = actor
  end
  return list
end

-- The Pocket Camp: the fire and the online Members, you first, as many as
-- fit, LAYOUT.pocketRows high. It's the narrowest of its widths (from
-- LAYOUT.pocketColumns in steps of pocketStep, up to maxColumns) that
-- everyone fits, or maxColumns if they don't. doing is what they're
-- up to, each by Member id: said (what they last said they're doing, as
-- Doing gives it), fishing (true while fishing) and working ("crafting"
-- or "gathering" while at a profession). Each actor is as in view(), with
-- pose (see Core:pocketCamp()), instance (its name, while in one), raid
-- (true if that's a raid), status (the pose in words) and row (the
-- Member's Roster row, for the tooltip over the figure). A flying figure
-- takes its griffin's room. Members that didn't fit are counted in more
-- ("+2"). group (Member id to true: Camp.grouped) are in your party or
-- raid: they sit right after you, marked group. Members adventuring in
-- the same instance sit side by side, in a doorway they share (doorways,
-- and each one's doorway: see doorways()); it grows to keep them together
-- if it can. bedrolls (Member id to when they were seen going offline)
-- are the Members asleep in a bedroll: after every online Member, as many
-- as fit at the width those need, never counted in more; pose "asleep",
-- status "asleep · 4m". tooltip lists who is doing what: { title, lines }.
function Camp.pocket(rows, entries, now, doing, bedrolls, maxColumns, group)
  group = group or {}
  local poses = {}
  for _, row in ipairs(rows) do poses[row.memberId] = poseOf(row, doing) end
  rows = together(rows, poses, group)
  local options = {
    tent = false, onlineOnly = true, moreText = "+%d", sleepers = bedrolls,
    room = function(row)
      if poses[row.memberId] == "flying" then return LAYOUT.griffinFore, LAYOUT.griffinAft end
    end,
    together = function(row)
      if poses[row.memberId] == "adventuring" then return row.instance end
    end,
  }
  local columns = LAYOUT.pocketColumns
  local view = Camp.view(rows, entries, now, columns, options)
  while (view.more or view.split) and columns + LAYOUT.pocketStep <= (maxColumns or LAYOUT.pocketColumns) do
    columns = columns + LAYOUT.pocketStep
    view = Camp.view(rows, entries, now, columns, options)
  end
  view.rows = LAYOUT.pocketRows
  view.graves = nil
  local byMember = {}
  for _, row in ipairs(rows) do byMember[row.memberId] = row end
  local lines = {}
  for i, actor in ipairs(view.actors) do
    actor.row = byMember[actor.memberId]
    if actor.pose == "asleep" then
      -- Under a minute it's too soon to say how long.
      local since = now - bedrolls[actor.memberId]
      actor.status = since < 60 and "asleep" or "asleep · " .. ns.Text.ago(since)
    else
      actor.pose = poses[actor.memberId]
      actor.instance = actor.row.instance
      actor.group = group[actor.memberId]
      if actor.pose == "adventuring" then
        actor.raid = RAIDS[actor.instance] or nil
        actor.status = "in " .. actor.instance
      else
        actor.status = STATUS[actor.pose]
      end
    end
    lines[i] = ("%s: %s"):format(actor.label, actor.status)
  end
  view.split = nil
  view.doorways = doorways(view.actors)
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
