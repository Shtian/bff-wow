local _, ns = ...

local Camp = {}
ns.Camp = Camp

local DAY = 24 * 60 * 60

local LAYOUT = {
  fire = 9,
  seated = 12,
  asleep = 18,
  grave = 8,
  graveGap = 2,
  gap = 4,
  labelGap = 2,
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
  working = {
    mining = { fore = 5, aft = 0 },
    herbalism = { fore = 6, aft = 5 },
    skinning = { fore = 11, aft = 0 },
    alchemy = { fore = 5, aft = 0 },
    blacksmithing = { fore = 6, aft = 0 },
    enchanting = { fore = 6, aft = 0 },
    engineering = { fore = 7, aft = 0 },
    leatherworking = { fore = 7, aft = 0 },
    tailoring = { fore = 7, aft = 0 },
    cooking = { fore = 7, aft = 0 },
    firstAid = { fore = 7, aft = 6 },
  },
  formFore = 3,
  formAft = 3,
  formTrot = 4,
  doorway = 2,
  doorwayGap = 3,
  pet = 13,
  petGap = 1,
  tree = 11,
  pumpkin = 13,
  pole = 15,
  decorGap = 4,
  lantern = 18,
}
Camp.LAYOUT = LAYOUT

local DECOR = {
  tree = { width = LAYOUT.tree, gap = LAYOUT.decorGap },
  pumpkin = { width = LAYOUT.pumpkin, gap = LAYOUT.decorGap },
  pole = { width = LAYOUT.pole, gap = LAYOUT.decorGap },
}

Camp.SEASONS = {
  { key = "lunar", from = { 1, 22 }, to = { 2, 12 }, decor = {} },
  { key = "midsummer", from = { 6, 20 }, to = { 7, 5 }, decor = { "pole" } },
  { key = "autumn", from = { 10, 18 }, to = { 11, 1 }, decor = { "pumpkin" } },
  { key = "winter", from = { 12, 1 }, to = { 1, 2 }, decor = { "tree" } },
}
local SEASON = {}
for _, season in ipairs(Camp.SEASONS) do SEASON[season.key] = season end

local function dayOf(monthDay)
  return monthDay[1] * 100 + monthDay[2]
end

local function within(today, season)
  local from, to = dayOf(season.from), dayOf(season.to)
  if from <= to then return from <= today and today <= to end
  return today >= from or today <= to
end

function Camp.isSeason(key)
  return SEASON[key] ~= nil
end

function Camp.season(now, utcOffset)
  local today = dayOf({ ns.Text.monthDay(now, utcOffset or 0) })
  for _, season in ipairs(Camp.SEASONS) do
    if within(today, season) then return season.key end
  end
  return nil
end

local DAWN = 5 * 60 + 30
local DUSK = 21 * 60

function Camp.phase(isDay, hour, minute)
  if isDay ~= nil then return isDay and "day" or "night" end
  if type(hour) ~= "number" or type(minute) ~= "number" then return "night" end
  local clock = hour * 60 + minute
  return clock >= DAWN and clock < DUSK and "day" or "night"
end

Camp.RECENT = DAY
local MEMBER_GRAVES = 2
local GRAVES = 4

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

local function news(entries, now)
  local graves, sparks, total = {}, {}, 0
  for _, entry in ipairs(entries) do
    if entry.memberId and now - entry.time < Camp.RECENT then
      if entry.kind == "maxLevel" then sparks[entry.memberId] = true end
      if entry.kind == "death" then
        local list = graves[entry.memberId] or {}
        graves[entry.memberId] = list
        local flower = #entry.reactors > 0 or nil
        local key = entry.key and ns.Reactions.id(entry.key)
        for _ = 1, entry.count or 1 do
          if #list < MEMBER_GRAVES and total < GRAVES then
            list[#list + 1] = { flower = flower, key = key }
            total = total + 1
          end
        end
      end
    end
  end
  return graves, sparks
end

local function placeOn(side, figure, graveCount, fore, aft, pet, gap)
  aft = aft or 0
  local petRoom = pet and LAYOUT.petGap + LAYOUT.pet or 0
  local width = figure + aft + petRoom + graveCount * (LAYOUT.graveGap + LAYOUT.grave)
  local start = (side.used == 0 and LAYOUT.fire or side.used + (gap or LAYOUT.gap)) + (fore or 0)
  if start + width > side.limit then return nil end
  side.used = start + width
  local x
  if side.sign > 0 then x = start else x = -start - figure end
  local petX
  if pet and side.sign > 0 then
    petX = x + figure + aft + LAYOUT.petGap
  elseif pet then
    petX = x - aft - LAYOUT.petGap - LAYOUT.pet
  end
  local graveXs = {}
  for i = 1, graveCount do
    local offset = figure + petRoom + (i - 1) * (LAYOUT.graveGap + LAYOUT.grave) + LAYOUT.graveGap
    if side.sign > 0 then
      graveXs[i] = x + offset
    else
      graveXs[i] = x - offset + figure - LAYOUT.grave
    end
  end
  return x, graveXs, petX
end

local function roomier(left, right)
  if right.used < left.used then return right, left end
  return left, right
end

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
    actor.labelWidth = math.max(actor.width, math.floor(2 * math.min(centre - before, after - centre)) - LAYOUT.labelGap)
  end
end

local function yourSide(actors)
  for _, actor in ipairs(actors) do
    if actor.you then return actor.x < 0 and -1 or 1 end
  end
  return nil
end

local function yourPet(rows, options)
  for _, row in ipairs(rows) do
    if row.own and not (options.noPet and options.noPet(row)) then return row.pet end
  end
  return nil
end

local function lanternSeats(rows, actors, left, right, options)
  local list = {}
  for _ = 1, options.lanternCount or 0 do
    local side = roomier(left, right)
    local x = placeOn(side, LAYOUT.lantern, 0)
    if x then list[#list + 1] = { x = x, side = side.sign } end
  end
  if not list[1] then return nil end
  local side, bed = yourSide(actors), list[1]
  for _, seat in ipairs(list) do
    if seat.side == side and bed.side ~= side then bed = seat end
  end
  bed.pet = yourPet(rows, options)
  for _, seat in ipairs(list) do seat.side = nil end
  return list
end

local function mourner(view, leftEdge, rightEdge)
  local you, bed
  for _, actor in ipairs(view.actors) do
    if actor.you then you = actor.memberId end
  end
  for _, seat in ipairs(view.lanternSeats or {}) do
    if seat.pet then bed = seat end
  end
  local grave
  for _, each in ipairs(view.graves) do
    if not grave and each.memberId == you then grave = each end
  end
  if not (bed and grave) then return nil end
  local x = grave.x < 0 and grave.x - LAYOUT.petGap - LAYOUT.pet or grave.x + LAYOUT.grave + LAYOUT.petGap
  x = math.max(-leftEdge + LAYOUT.margin, math.min(rightEdge - LAYOUT.margin - LAYOUT.pet, x))
  local key = bed.pet
  bed.pet = nil
  return { key = key, x = x }
end

local function arrange(rows, entries, now, columns, options, petted)
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
    if options.together and (row.own or row.online) then return options.together(row) end
  end
  local function roomOf(row)
    if options.room then return options.room(row) end
  end
  local withPets = {}
  local function petOf(row)
    if row.own and options.lanternCount then return nil end
    if row.pet and not (options.noPet and options.noPet(row)) then return row.pet end
  end
  local placed = {}
  local function placeTogether(first)
    local key, gap = keyOf(list[first])
    local last = first
    while key and list[last + 1] and keyOf(list[last + 1]) == key do last = last + 1 end
    if last == first then return end
    for _, tried in ipairs({ roomier(left, right) }) do
      local copy = { sign = tried.sign, used = tried.used, limit = tried.limit }
      local spots = {}
      for j = first, last do
        local fore, aft = roomOf(list[j])
        local x, _, petX = placeOn(copy, LAYOUT.seated, 0, fore, aft, petted[list[j].memberId], j > first and gap or nil)
        spots[#spots + 1] = x and { x = x, petX = petX, side = tried } or nil
      end
      if #spots == last - first + 1 then
        tried.used = copy.used
        for j = first, last do placed[list[j]] = spots[j - first + 1] end
        return
      end
    end
    local side = roomier(left, right)
    for j = first, last do
      local fore, aft = roomOf(list[j])
      local x, _, petX = placeOn(side, LAYOUT.seated, 0, fore, aft, petted[list[j].memberId], j > first and gap or nil)
      if not x then break end
      placed[list[j]] = { x = x, petX = petX, side = side }
    end
    view.splits = view.splits or {}
    view.splits[key] = last - first + 1
  end
  for index, row in ipairs(list) do
    local key = (keyOf(row))
    if key and not placed[row] and (index == 1 or keyOf(list[index - 1]) ~= key) then placeTogether(index) end
    local seated = row.own or row.online
    local figure = seated and LAYOUT.seated or LAYOUT.asleep
    local own = not options.onlineOnly and graves[row.memberId] or {}
    local fore, aft = roomOf(row)
    local pet = petOf(row)
    local x, graveXs, side, petX
    if placed[row] then
      x, graveXs, side, petX = placed[row].x, {}, placed[row].side, placed[row].petX
    else
      local first, second = roomier(left, right)
      for _, count in ipairs({ #own, 0 }) do
        for _, tried in ipairs({ first, second }) do
          if not x then
            x, graveXs, petX = placeOn(tried, figure, count, fore, aft, petted[row.memberId])
            side = x and tried
          end
        end
        if x then break end
      end
    end
    if x then
      if pet then withPets[#withPets + 1] = row.memberId end
      view.actors[#view.actors + 1] = {
        memberId = row.memberId,
        pose = seated and "seated" or "asleep",
        label = row.own and "You" or row.displayName or row.name,
        classFilename = row.classFilename,
        hat = row.hat,
        pet = petX and { key = pet, x = petX } or nil,
        x = x,
        width = figure,
        side = side.sign,
        spark = sparks[row.memberId],
        you = row.own or nil,
      }
      for i, graveX in ipairs(graveXs) do
        view.graves[#view.graves + 1] = { memberId = row.memberId, x = graveX, flower = own[i].flower, key = own[i].key }
      end
    elseif seated or not options.onlineOnly then
      more = more + 1
    end
  end
  view.more = more > 0 and more or nil
  view.moreText = view.more and (options.moreText or "+%d more"):format(more) or nil
  view.lanternSeats = lanternSeats(rows, view.actors, left, right, options)
  view.mourner = options.mourn and mourner(view, leftEdge, rightEdge) or nil

  if options.tent ~= false then
    local side = roomier(left, right)
    local x = placeOn(side, LAYOUT.tent, 0)
    if x then view.tent = { x = x } end
  end
  local season = SEASON[options.season]
  view.season = season and season.key
  view.phase = options.phase
  local decor = season and (options.tent == false or view.tent) and season.decor or {}
  for _, key in ipairs(decor) do
    local x = placeOn(roomier(left, right), DECOR[key].width, 0, nil, nil, nil, DECOR[key].gap)
    if x then
      view.decor = view.decor or {}
      view.decor[#view.decor + 1] = { key = key, x = x }
    end
  end
  labelRoom(view.actors, leftEdge, rightEdge)
  for _, actor in ipairs(view.actors) do actor.side = nil end
  return view, withPets
end

local function seats(view)
  local parts = { view.more or 0, view.tent and "tent" or "" }
  for _, actor in ipairs(view.actors) do parts[#parts + 1] = actor.memberId end
  for _, grave in ipairs(view.graves) do parts[#parts + 1] = grave.memberId end
  return table.concat(parts, " ")
end

function Camp.view(rows, entries, now, columns, options)
  options = options or {}
  local base, withPets = arrange(rows, entries, now, columns, options, {})
  local wanted = seats(base)
  for count = #withPets, 1, -1 do
    local petted = {}
    for i = 1, count do petted[withPets[i]] = true end
    local view = arrange(rows, entries, now, columns, options, petted)
    if seats(view) == wanted then
      view.petsLeftOut = count < #withPets and #withPets - count or nil
      return view
    end
  end
  base.petsLeftOut = #withPets > 0 and #withPets or nil
  return base
end

local STATUS = {
  seated = "by the fire", fishing = "fishing", crafting = "crafting",
  mining = "mining", herbalism = "picking herbs", skinning = "skinning",
  alchemy = "brewing potions", blacksmithing = "smithing", enchanting = "enchanting", engineering = "tinkering",
  leatherworking = "working leather", tailoring = "tailoring", cooking = "cooking", firstAid = "making bandages",
  fighting = "fighting", vendor = "at a vendor", auction = "at the auction house", resting = "resting",
  afk = "away", flying = "flying",
}

local FORM_STATUS = {
  wolf = "a ghost wolf", bear = "in bear form", cat = "in cat form", travel = "in travel form",
  seal = "in aquatic form", moonkin = "in moonkin form",
}
local TROTS = { wolf = true, travel = true }
local FORM_POSES = { seated = true, fighting = true }

local GROUP = {}

local RAIDS = {}
for _, dungeon in ipairs(ns.Dungeons.DUNGEONS) do
  if dungeon.kind == "raid" then RAIDS[dungeon.name] = true end
end

local SAID_FIRST = { flying = true, auction = true, vendor = true }
for work in pairs(ns.Professions.WORK_STATES) do SAID_FIRST[work] = true end

local function poseOf(row, doing)
  local id = row.memberId
  local said = not row.instance and doing.said[id] or nil
  if SAID_FIRST[said] then return said end
  if doing.fishing[id] then return "fishing" end
  if doing.working[id] then return doing.working[id] end
  if row.instance then return "adventuring" end
  return said or "seated"
end

local function withTime(status, seconds)
  return seconds < 60 and status or status .. " · " .. ns.Text.ago(seconds)
end

function Camp.poseKeys(rows, doing)
  local keys = {}
  for _, row in ipairs(rows) do
    if row.own or row.online then
      local pose = poseOf(row, doing)
      keys[row.memberId] = pose == "adventuring" and pose .. ":" .. row.instance or pose
    end
  end
  return keys
end

function Camp.pocketWidth(columns)
  local low, high, step = LAYOUT.pocketColumns, LAYOUT.pocketMaxColumns, LAYOUT.pocketStep
  if type(columns) ~= "number" then return low end
  columns = math.max(low, math.min(high, columns))
  return low + math.floor((columns - low) / step + 0.5) * step
end

function Camp.pocketSeats(columns)
  local room = math.floor(columns / 2) - LAYOUT.margin - LAYOUT.fire + LAYOUT.gap
  return 2 * math.max(0, math.floor(room / (LAYOUT.seated + LAYOUT.gap)))
end

function Camp.grouped(rows, party)
  local found = {}
  for _, row in ipairs(rows) do
    local fullName = not row.own and row.fullName and row.fullName:lower()
    for _, unit in ipairs(fullName and party or {}) do
      local match
      if unit.guid and row.guid then
        match = unit.guid == row.guid
      else
        match = unit.name ~= nil
          and (unit.lastName and unit.name .. " " .. unit.lastName or unit.name):lower() == fullName
      end
      if match then found[row.memberId] = true end
    end
  end
  return found
end

local function seatingOrder(rows, group, doorwayOf)
  local you, ranks, offline = nil, { {}, {} }, {}
  for _, row in ipairs(rows) do
    if row.own then
      you = row
    elseif row.online then
      local rank = group[row.memberId] and ranks[1] or ranks[2]
      rank[#rank + 1] = row
    else
      offline[#offline + 1] = row
    end
  end
  local ordered = { you }
  local yours = you and doorwayOf(you)
  for _, rank in ipairs(ranks) do
    local count = {}
    for _, row in ipairs(rank) do
      local key = doorwayOf(row)
      if key then count[key] = (count[key] or 0) + 1 end
    end
    local taken = {}
    local function take(wanted)
      for _, row in ipairs(rank) do
        if not taken[row] and wanted(row) then
          taken[row] = true
          ordered[#ordered + 1] = row
          local key = doorwayOf(row)
          for _, other in ipairs(rank) do
            if key and not taken[other] and doorwayOf(other) == key then
              taken[other] = true
              ordered[#ordered + 1] = other
            end
          end
        end
      end
    end
    take(function(row) return yours ~= nil and doorwayOf(row) == yours end)
    take(function(row) return doorwayOf(row) ~= nil and count[doorwayOf(row)] > 1 end)
    take(function() return true end)
  end
  for _, row in ipairs(offline) do ordered[#ordered + 1] = row end
  return ordered
end

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
    local apart = previous and actor.x - previous.x - previous.width
    if door and door.instance == actor.instance and (apart == LAYOUT.doorwayGap or apart == LAYOUT.gap) then
      door.width = actor.x + actor.width + LAYOUT.doorway - door.x
    else
      list[#list + 1] = {
        x = actor.x - LAYOUT.doorway, width = actor.width + 2 * LAYOUT.doorway,
        instance = actor.instance, raid = actor.raid,
      }
    end
    actor.doorway = #list
    previous = actor
  end
  return list
end

local function doorwaySeats(columns)
  local room = math.floor(columns / 2) - LAYOUT.margin - LAYOUT.fire
  if room < LAYOUT.seated then return 0 end
  return 1 + math.floor((room - LAYOUT.seated) / (LAYOUT.seated + LAYOUT.doorwayGap))
end

function Camp.pocket(rows, entries, now, doing, bedrolls, maxColumns, group, shown)
  group = group or {}
  shown = shown or {}
  local poses, forms = {}, {}
  for _, row in ipairs(rows) do
    local id = row.memberId
    poses[id] = poseOf(row, doing)
    local form = doing.form and doing.form[id]
    if FORM_POSES[poses[id]] and FORM_STATUS[form] then forms[id] = form end
  end
  local outside = true
  for _, row in ipairs(rows) do
    if row.own and poses[row.memberId] == "adventuring" then outside = false end
  end
  local function seatKey(row)
    if poses[row.memberId] == "adventuring" then return row.instance end
    if outside and (row.own or group[row.memberId]) then return GROUP end
  end
  rows = seatingOrder(rows, group, seatKey)
  local options = {
    tent = false, onlineOnly = true, moreText = "+%d", sleepers = bedrolls, season = shown.season, phase = shown.phase,
    lanternCount = shown.lanternCount,
    room = function(row)
      local pose = poses[row.memberId]
      if pose == "flying" then return LAYOUT.griffinFore, LAYOUT.griffinAft end
      local working = LAYOUT.working[pose]
      if working then return working.fore, working.aft end
      local form = forms[row.memberId]
      if form then return LAYOUT.formFore, LAYOUT.formAft + (TROTS[form] and LAYOUT.formTrot or 0) end
    end,
    together = function(row)
      local key = seatKey(row)
      return key, key ~= GROUP and LAYOUT.doorwayGap or nil
    end,
    noPet = function(row) return poses[row.memberId] == "adventuring" end,
  }
  local function wanted(view, columns)
    for key, count in pairs(view.splits or {}) do
      if key ~= GROUP and count <= doorwaySeats(LAYOUT.pocketMaxColumns) then return true end
    end
    return view.more and columns + LAYOUT.pocketStep <= (maxColumns or LAYOUT.pocketColumns)
  end
  local columns = LAYOUT.pocketColumns
  local view = Camp.view(rows, entries, now, columns, options)
  while wanted(view, columns) and columns + LAYOUT.pocketStep <= LAYOUT.pocketMaxColumns do
    columns = columns + LAYOUT.pocketStep
    view = Camp.view(rows, entries, now, columns, options)
  end
  local room = math.min(maxColumns or LAYOUT.pocketColumns, LAYOUT.pocketMaxColumns)
  local wider = columns
  while view.petsLeftOut and wider + LAYOUT.pocketStep <= room do
    wider = wider + LAYOUT.pocketStep
    local tried = Camp.view(rows, entries, now, wider, options)
    if (tried.petsLeftOut or 0) < view.petsLeftOut then view = tried end
  end
  view.rows = LAYOUT.pocketRows
  view.graves = nil
  local byMember = {}
  for _, row in ipairs(rows) do byMember[row.memberId] = row end
  local lines = {}
  for i, actor in ipairs(view.actors) do
    actor.row = byMember[actor.memberId]
    if actor.pose == "asleep" then
      actor.status = withTime("asleep", now - bedrolls[actor.memberId])
    else
      actor.pose = poses[actor.memberId]
      actor.instance = actor.row.instance
      actor.group = group[actor.memberId]
      actor.form = forms[actor.memberId]
      actor.trots = actor.form and TROTS[actor.form] or nil
      if actor.pose == "adventuring" then
        actor.raid = RAIDS[actor.instance] or nil
        actor.status = "in " .. actor.instance
      elseif actor.form and actor.pose == "seated" then
        actor.status = FORM_STATUS[actor.form]
      elseif actor.pose == "seated" and actor.row.quiet then
        actor.status = STATUS.seated .. " · quiet"
      else
        actor.status = STATUS[actor.pose]
      end
      local began = actor.pose ~= "seated" and doing.since and doing.since[actor.memberId]
      if began and now - began >= 60 then
        actor.since = now - began
        actor.status = withTime(actor.status, actor.since)
      end
    end
    actor.onAlt = shown.alts ~= false and actor.row.onAlt or nil
    lines[i] = ("%s%s: %s"):format(actor.label, actor.onAlt and " (on alt)" or "", actor.status)
  end
  view.splits = nil
  view.doorways = doorways(view.actors)
  view.tooltip = { title = "Pocket Camp", lines = lines }
  return view
end

function Camp.wordRows(rows, on, order)
  local split = on and (order == nil or order == "online")
  for _, row in ipairs(rows) do
    if row.own then
      row.status = nil
    elseif on then
      row.status = row.quiet and "by the fire · quiet" or row.online and "by the fire" or "asleep · " .. row.lastSeenText
    else
      row.status = row.lastSeenText
    end
    if not row.own then
      row.section = split and (row.online and "BY THE FIRE" or "ASLEEP IN CAMP") or "CREW"
    end
  end
  return rows
end

function Camp.header(summary, on)
  if on then
    return ("%d of %d by the fire"):format(summary.online + 1, summary.members + 1)
  end
  return ("%d of %d online"):format(summary.online, summary.members)
end

function Camp.away(rows, entries, now, summary, shown)
  local view = Camp.view(rows, entries, now, LAYOUT.awayColumns,
    { tent = false, season = shown.season, phase = shown.phase, lanternCount = shown.lanternCount, mourn = shown.mourn })
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

function Camp.walkIn(view, memberId, alone)
  for _, actor in ipairs(view.actors) do
    if actor.memberId == memberId then
      return { memberId = memberId, seats = alone and alone.lanternSeats or {} }
    end
  end
  return nil
end
