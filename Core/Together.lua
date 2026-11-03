-- Together: the Together tab, worked out from Roster's rows. The Crew's
-- Characters and the game's dungeons on one level line, placed and worded
-- so the UI only lays them out. Pure and stateless: tested through
-- Core:together(). See docs/design/together.md.

local _, ns = ...

local Together = {}
ns.Together = Together

-- The game's dungeons, by the level they start at. kind is "dungeon",
-- "attunement" or "raid"; forever marks the ones new in WoW: Forever (from
-- Blizzard's "Explore the New Dungeons of World of Warcraft: Forever", Oct
-- 20 2026). Classic ranges are the usual recommended ones; the two new
-- raids' levels aren't published yet and are assumed to be 60.
local DUNGEONS = {
  { name = "Ragefire Chasm", from = 13, to = 18, where = "Orgrimmar" },
  { name = "Hall of Thanes", from = 13, to = 18, where = "beneath Ironforge", forever = true },
  { name = "Ruins of Lordaeron", from = 15, to = 20, where = "Tirisfal Glades", forever = true },
  { name = "Wailing Caverns", from = 17, to = 24, where = "The Barrens" },
  { name = "The Deadmines", from = 17, to = 26, where = "Westfall" },
  { name = "Shadowfang Keep", from = 22, to = 30, where = "Silverpine Forest" },
  { name = "Blackfathom Deeps", from = 24, to = 32, where = "Ashenvale" },
  { name = "The Stockade", from = 24, to = 32, where = "Stormwind City" },
  { name = "Excavation Site", from = 24, to = 29, where = "Wetlands", forever = true },
  { name = "SM Graveyard", from = 28, to = 38, where = "Scarlet Monastery, Tirisfal Glades" },
  { name = "City of Dalaran", from = 28, to = 33, where = "Alterac Mountains (needs an attunement)", forever = true },
  { name = "Gnomeregan", from = 29, to = 38, where = "Dun Morogh" },
  { name = "SM Library", from = 29, to = 39, where = "Scarlet Monastery, Tirisfal Glades" },
  { name = "Razorfen Kraul", from = 30, to = 40, where = "The Barrens" },
  { name = "SM Armory", from = 32, to = 42, where = "Scarlet Monastery, Tirisfal Glades" },
  { name = "SM Cathedral", from = 35, to = 45, where = "Scarlet Monastery, Tirisfal Glades" },
  { name = "The Drowned City", from = 35, to = 40, where = "off Stranglethorn", forever = true },
  { name = "Razorfen Downs", from = 40, to = 50, where = "The Barrens" },
  { name = "Krol'dok Stronghold", from = 40, to = 45, where = "Riverglades", forever = true },
  { name = "Uldaman", from = 42, to = 52, where = "Badlands" },
  { name = "Zul'Farrak", from = 44, to = 54, where = "Tanaris" },
  { name = "Maraudon", from = 46, to = 55, where = "Desolace" },
  { name = "Alcaz Prison", from = 48, to = 53, where = "Dustwallow Marsh", forever = true },
  { name = "Sunken Temple", from = 50, to = 60, where = "Swamp of Sorrows" },
  { name = "Blackrock Depths", from = 52, to = 60, where = "Blackrock Mountain" },
  { name = "Lower Blackrock Spire", from = 55, to = 60, where = "Blackrock Mountain" },
  { name = "Blackmaw Hold", from = 55, to = 60, where = "Azshara", forever = true },
  { name = "Onyxia attunement", from = 55, to = 60, where = "a quest chain for Onyxia's Lair", kind = "attunement" },
  { name = "Dire Maul", from = 56, to = 60, where = "Feralas" },
  { name = "Scholomance", from = 58, to = 60, where = "Western Plaguelands" },
  { name = "Stratholme", from = 58, to = 60, where = "Eastern Plaguelands" },
  { name = "Upper Blackrock Spire", from = 58, to = 60, where = "Blackrock Mountain" },
  { name = "Shaper's Terrace", from = 58, to = 60, where = "Un'Goro Crater", forever = true },
  { name = "Molten Core", from = 60, to = 60, where = "Blackrock Mountain", kind = "raid", size = 40 },
  { name = "Onyxia's Lair", from = 60, to = 60, where = "Dustwallow Marsh", kind = "raid", size = 40 },
  { name = "Zul'Gurub", from = 60, to = 60, where = "Stranglethorn Vale", kind = "raid", size = 20 },
  { name = "The Barrow Deeps", from = 60, to = 60, where = "Mount Hyjal", kind = "raid", size = 10, forever = true },
  { name = "Hyjal Summit", from = 60, to = 60, where = "Mount Hyjal", kind = "raid", size = 20, forever = true },
}
for i, dungeon in ipairs(DUNGEONS) do
  dungeon.kind = dungeon.kind or "dungeon"
  dungeon.forever = dungeon.forever == true
  dungeon.index = i
end
Together.DUNGEONS = DUNGEONS

-- The raids, shown together as one "Raids 5" entry at 60 when the Show
-- menu's Raids is on.
local RAID_LIST = {}
for _, dungeon in ipairs(DUNGEONS) do
  if dungeon.kind == "raid" then RAID_LIST[#RAID_LIST + 1] = dungeon end
end
local RAIDS = {
  name = ("Raids %d"):format(#RAID_LIST),
  short = "Raids",
  from = 60,
  to = 60,
  kind = "raids",
  forever = false,
  index = #DUNGEONS + 1,
  raids = RAID_LIST,
}

-- "Only near your level": dungeons whose range comes within this many
-- levels of you.
local NEAR = 10

-- The line's geometry, in pixels: a level's width, the room left of level
-- 1 and right of the top level, the label rows above the axis and the
-- dungeon lanes below it, and the gaps kept between neighbours in a row or
-- a lane. UI reads the same table to lay the line out.
local LAYOUT = {
  levels = 60,
  level = 24,
  left = 16,
  right = 90,
  rows = 4,
  lanes = 5,
  rowGap = 6,
  laneGap = 3,
  -- A label's name is cut at this width.
  nameWidth = 96,
  -- A bar shows at most this many Member dots, then "+N".
  dots = 4,
  dot = 8,
}
Together.LAYOUT = LAYOUT

local CAN_PLAY = ns.Roster.CAN_PLAY

local function xOf(level)
  return LAYOUT.left + (level - 1) * LAYOUT.level
end

-- Text widths, when the UI doesn't hand in its own measure: roughly Arial
-- Narrow's.
local function estimate(text, font)
  return #text * (font == "tiny" and 5 or 6)
end

local function plural(count, one, many)
  return count == 1 and one or many
end

-- "Ann", "Ann and Bob", "Ann, Bob and Cleo", "Ann, Bob and 2 more".
local function listJoin(names, max)
  max = max or 3
  if #names <= 1 then return names[1] or "" end
  if #names <= max then
    return table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names]
  end
  return table.concat(names, ", ", 1, max - 1) .. " and " .. (#names - max + 1) .. " more"
end

-- The Roster's rule: within CAN_PLAY levels of the Character you play.
local function canPlay(level, yourLevel)
  return math.abs(level - yourLevel) <= CAN_PLAY
end

-- "can play", "4 ahead" or "10 behind", from you.
local function apart(level, yourLevel)
  local gap = level - yourLevel
  if canPlay(level, yourLevel) then return "can play" end
  return ("%d %s"):format(math.abs(gap), gap > 0 and "ahead" or "behind")
end

-- The Members, from Roster's rows (yours first): each with its name and
-- every Character the Roster shows, the shown one first. played marks the
-- Character being played while online.
local function membersOf(rows)
  local members = {}
  for _, row in ipairs(rows) do
    local member = { id = row.memberId, own = row.own == true, online = row.online == true, characters = {} }
    local function add(character, shown)
      member.characters[#member.characters + 1] = {
        member = member,
        name = character.name,
        classFilename = character.classFilename,
        level = character.level,
        main = character.main == true,
        played = shown and row.online == true,
        shown = shown,
      }
      if character.main then member.name = row.displayName or character.name end
    end
    add(row, true)
    for _, alt in ipairs(row.alts) do add(alt, false) end
    member.name = member.name or row.displayName or row.name
    members[#members + 1] = member
  end
  return members
end

-- The Member's Character closest to level (that passes the test, if one is
-- given), or nil. A tie goes to the one shown first.
local function closest(member, level, test)
  local best, bestGap
  for _, character in ipairs(member.characters) do
    if not test or test(character) then
      local gap = math.abs(character.level - level)
      if not best or gap < bestGap then best, bestGap = character, gap end
    end
  end
  return best
end

-- Whether a Character shows on the line, under the Show menu's filters:
-- yours while played; others' Main and the Character they're playing.
-- Alts show only with filters.alts, offline Members' Characters only with
-- filters.offline.
local function visible(character, filters)
  local member = character.member
  if member.own then return character.shown or filters.alts end
  if not filters.offline and not member.online then return false end
  return character.main or character.played or filters.alts
end

local function fits(level, dungeon)
  return level >= dungeon.from and level <= dungeon.to
end

-- Friends: a group per level, its Characters you first, then whoever is
-- online, then Mains.
local function before(a, b)
  if a.member.own ~= b.member.own then return a.member.own end
  if a.played ~= b.played then return a.played end
  if a.main ~= b.main then return a.main end
  if a.member.name ~= b.member.name then return a.member.name < b.member.name end
  return a.name < b.name
end

local function describeCharacter(character, yourLevel)
  local own = character.member.own
  return {
    memberId = character.member.id,
    member = own and "You" or character.member.name,
    name = character.name,
    classFilename = character.classFilename,
    level = character.level,
    alt = not character.main,
    online = character.played,
    own = own,
    canPlay = not own and canPlay(character.level, yourLevel),
    apart = not own and apart(character.level, yourLevel) or nil,
  }
end

local function buildGroups(members, yourLevel, measure, filters, chosen)
  local byLevel, levels = {}, {}
  for _, member in ipairs(members) do
    for _, character in ipairs(member.characters) do
      if visible(character, filters) then
        local level = character.level
        if not byLevel[level] then
          byLevel[level] = {}
          levels[#levels + 1] = level
        end
        table.insert(byLevel[level], character)
      end
    end
  end
  table.sort(levels)

  local groups = {}
  for _, level in ipairs(levels) do
    local pins = byLevel[level]
    table.sort(pins, before)
    local lead = pins[1]
    local group = {
      level = level,
      x = xOf(level),
      label = lead.member.own and "You" or lead.member.name,
      alt = not lead.main,
      own = lead.member.own,
      classFilename = lead.classFilename,
      count = #pins,
      more = #pins - 1,
      online = false,
      characters = {},
      memberIds = {},
      faded = chosen.any,
    }
    local seen = {}
    for i, character in ipairs(pins) do
      group.characters[i] = describeCharacter(character, yourLevel)
      if character.played then group.online = true end
      local member = character.member
      if not member.own and not seen[member.id] then
        seen[member.id] = true
        group.memberIds[#group.memberIds + 1] = member.id
      end
      if member.own or chosen[member.id] then group.faded = false end
    end
    group.labelWidth = math.min(measure(group.label, "small"), LAYOUT.nameWidth) + 4
      + measure(tostring(level), "tiny")
      + (group.alt and measure("alt", "tiny") + 10 or 0)
      + (group.more > 0 and measure("+" .. group.more, "small") + 4 or 0) + 8
    groups[#groups + 1] = group
  end
  return groups
end

-- Is [from, to) clear of everything in spans, gap pixels apart?
local function free(spans, from, to, gap)
  for _, span in ipairs(spans) do
    if not (to + gap <= span[1] or from >= span[2] + gap) then return false end
  end
  return true
end

-- Labels go in the rows above the axis, row 1 nearest it: yours first,
-- then online friends, then the nearest to your level. A label that finds
-- no room leaves just its dot.
local function placeLabels(groups, yourLevel)
  local order = {}
  for i, group in ipairs(groups) do order[i] = group end
  table.sort(order, function(a, b)
    if a.own ~= b.own then return a.own end
    if a.online ~= b.online then return a.online end
    local gapA, gapB = math.abs(a.level - yourLevel), math.abs(b.level - yourLevel)
    if gapA ~= gapB then return gapA < gapB end
    return a.level < b.level
  end)
  local rows = {}
  for row = 1, LAYOUT.rows do rows[row] = {} end
  for _, group in ipairs(order) do
    local from = group.x - 5
    for row = 1, LAYOUT.rows do
      if free(rows[row], from, from + group.labelWidth, LAYOUT.rowGap) then
        table.insert(rows[row], { from, from + group.labelWidth })
        group.row, group.labelX = row, from
        break
      end
    end
  end
end

local function rangeText(dungeon)
  if dungeon.from == dungeon.to then return tostring(dungeon.from) end
  return ("%d–%d"):format(dungeon.from, dungeon.to)
end

local KINDS = { dungeon = "Dungeon", attunement = "Attunement", raid = "Raid" }

-- A dungeon's tooltip and the Members who fit it: each other Member with a
-- Character in its range, the one closest to your level, online first.
local function describeDungeon(dungeon, others, yourLevel)
  local fitters = {}
  local almost = {}
  for _, member in ipairs(others) do
    local character = closest(member, yourLevel, function(c) return fits(c.level, dungeon) end)
    if character then
      fitters[#fitters + 1] = character
    else
      local short = closest(member, dungeon.from, function(c)
        return c.level < dungeon.from and c.level >= dungeon.from - CAN_PLAY
      end)
      if short then almost[#almost + 1] = short end
    end
  end
  table.sort(fitters, function(a, b)
    if a.played ~= b.played then return a.played end
    local gapA, gapB = math.abs(a.level - yourLevel), math.abs(b.level - yourLevel)
    if gapA ~= gapB then return gapA < gapB end
    return a.member.name < b.member.name
  end)
  table.sort(almost, function(a, b)
    if a.level ~= b.level then return a.level > b.level end
    return a.member.name < b.member.name
  end)

  local youFit = fits(yourLevel, dungeon)
  local you
  if youFit then
    you = "You fit"
  elseif yourLevel < dungeon.from then
    local need = dungeon.from - yourLevel
    you = ("You need %d more %s"):format(need, plural(need, "level", "levels"))
  else
    you = "You've outlevelled it"
  end

  local tooltip = {
    title = dungeon.name,
    detail = dungeon.where and ("%s · %s · %s"):format(KINDS[dungeon.kind], rangeText(dungeon), dungeon.where),
    forever = dungeon.forever and "New in WoW: Forever" or nil,
    you = you,
    fits = youFit,
    fitters = {},
    none = #fitters == 0 and "No friend fits it yet" or nil,
  }
  for i, character in ipairs(fitters) do
    local gap = math.abs(character.level - yourLevel)
    tooltip.fitters[i] = {
      memberId = character.member.id,
      member = character.member.name,
      name = character.name,
      classFilename = character.classFilename,
      level = character.level,
      online = character.played,
      far = gap > CAN_PLAY and ("fits, but %d levels from you"):format(gap) or nil,
    }
  end
  if dungeon.raids then
    tooltip.title = "Raids at 60"
    tooltip.raids = {}
    for i, raid in ipairs(dungeon.raids) do
      tooltip.raids[i] = {
        name = raid.name,
        detail = ("%d-player · %s"):format(raid.size, raid.where),
        forever = raid.forever,
      }
    end
  end
  if #almost > 0 then
    local parts = {}
    for i, character in ipairs(almost) do
      parts[i] = ("%s (%d short)"):format(character.member.name, dungeon.from - character.level)
    end
    tooltip.almost = "Almost: " .. table.concat(parts, ", ")
  end
  return fitters, tooltip
end

-- The dungeons the Show menu's filters leave on the line: every dungeon,
-- the attunement while Attunements is on, one entry for the raids while
-- Raids is on; with Only near your level, those within NEAR levels of you.
local function shownDungeons(filters, yourLevel)
  local list = {}
  for _, dungeon in ipairs(DUNGEONS) do
    if dungeon.kind == "dungeon" or (dungeon.kind == "attunement" and filters.attunements) then
      list[#list + 1] = dungeon
    end
  end
  if filters.raids then list[#list + 1] = RAIDS end
  if not filters.near then return list end
  local near = {}
  for _, dungeon in ipairs(list) do
    if dungeon.to >= yourLevel - NEAR and dungeon.from <= yourLevel + NEAR then near[#near + 1] = dungeon end
  end
  return near
end

-- Whether you and every chosen Member (any of their Characters) fit it.
local function sharedBy(dungeon, yourLevel, chosen)
  if #chosen == 0 or not fits(yourLevel, dungeon) then return false end
  for _, member in ipairs(chosen) do
    if not closest(member, yourLevel, function(c) return fits(c.level, dungeon) end) then return false end
  end
  return true
end

-- Bars below the axis for the dungeons shown, placed in the lanes most
-- relevant first: ones you fit, then by how many Members fit. The rest
-- fold into "+N here" chips near their level. While friends are chosen,
-- the ones you all fit are shared and the rest faded.
local function buildBars(dungeons, others, yourLevel, measure, chosen)
  local bars = {}
  for _, dungeon in ipairs(dungeons) do
    local fitters, tooltip = describeDungeon(dungeon, others, yourLevel)
    local dots = {}
    for i = 1, math.min(#fitters, LAYOUT.dots) do dots[i] = fitters[i].classFilename end
    local moreDots = math.max(#fitters - LAYOUT.dots, 0)
    -- The raids' entry starts a little left of 60, for its diamond.
    local raids = dungeon.kind == "raids"
    local content = measure(dungeon.name, "small") + 10
      + (dungeon.forever and measure("NEW", "tiny") + 10 or 0)
      + (#dots > 0 and #dots * LAYOUT.dot + 6 or 0)
      + (moreDots > 0 and measure("+" .. moreDots, "tiny") + 4 or 0)
      + (raids and 12 or 0)
    local shared = sharedBy(dungeon, yourLevel, chosen)
    bars[#bars + 1] = {
      name = dungeon.name,
      short = dungeon.short or dungeon.name,
      kind = dungeon.kind,
      forever = dungeon.forever,
      from = dungeon.from,
      to = dungeon.to,
      index = dungeon.index,
      fits = tooltip.fits,
      count = #fitters,
      dots = dots,
      moreDots = moreDots,
      x = xOf(dungeon.from) - (raids and 6 or 0),
      width = math.max((dungeon.to - dungeon.from) * LAYOUT.level, content),
      tooltip = tooltip,
      shared = shared,
      faded = #chosen > 0 and not shared,
    }
  end

  local order = {}
  for i, bar in ipairs(bars) do order[i] = bar end
  table.sort(order, function(a, b)
    if a.fits ~= b.fits then return a.fits end
    if a.count ~= b.count then return a.count > b.count end
    return a.index < b.index
  end)
  local lanes = {}
  for lane = 1, LAYOUT.lanes do lanes[lane] = {} end
  local placed, over = {}, {}
  for _, bar in ipairs(order) do
    for lane = 1, LAYOUT.lanes do
      if free(lanes[lane], bar.x, bar.x + bar.width, LAYOUT.laneGap) then
        table.insert(lanes[lane], { bar.x, bar.x + bar.width })
        bar.lane = lane
        break
      end
    end
    if bar.lane then
      placed[#placed + 1] = bar
    else
      over[#over + 1] = bar
    end
  end
  table.sort(placed, function(a, b) return a.index < b.index end)
  table.sort(over, function(a, b) return a.index < b.index end)

  -- Chips: the overflow, grouped by starting level (within CAN_PLAY of a
  -- chip's first), each placed in the first room found at or right of
  -- its level, lowest lane first. A chip with no room joins the one before
  -- (or, before any is placed, the next).
  local groups = {}
  for _, bar in ipairs(over) do
    local last = groups[#groups]
    if last and bar.from - last.from <= CAN_PLAY then
      table.insert(last.items, bar)
    else
      groups[#groups + 1] = { from = bar.from, items = { bar } }
    end
  end
  local chips, waiting = {}, {}
  local farthest = xOf(LAYOUT.levels) + LAYOUT.right
  for i, group in ipairs(groups) do
    for _, bar in ipairs(group.items) do waiting[#waiting + 1] = bar end
    local width = measure(("+%d here"):format(#waiting), "small") + 12
    -- Up to 6 levels right of the group; the last group, with no chip
    -- placed yet, looks as far as the line goes, so nothing is lost.
    local steps = (i == #groups and #chips == 0) and math.huge or 12
    local x, lane
    local step = 0
    while not lane and step <= steps and xOf(group.from) + step * LAYOUT.level / 2 + width <= farthest do
      local at = xOf(group.from) + step * LAYOUT.level / 2
      for l = LAYOUT.lanes, 1, -1 do
        if free(lanes[l], at, at + width, LAYOUT.laneGap) then
          x, lane = at, l
          break
        end
      end
      step = step + 1
    end
    if lane then
      table.insert(lanes[lane], { x, x + width })
      chips[#chips + 1] = { x = x, width = width, lane = lane, items = waiting }
      waiting = {}
    elseif #chips > 0 then
      for _, bar in ipairs(waiting) do table.insert(chips[#chips].items, bar) end
      waiting = {}
    end
  end
  for _, chip in ipairs(chips) do
    chip.text = ("+%d here"):format(#chip.items)
    chip.title = ("%d more here"):format(#chip.items)
    chip.shared = false
    for _, item in ipairs(chip.items) do
      item.detail = rangeText(item) .. (item.count > 0 and (" · %d fit"):format(item.count) or "")
      if item.shared then chip.shared = true end
    end
    chip.faded = #chosen > 0 and not chip.shared
  end
  return placed, chips
end

local function segment(text, style)
  return { text = text, style = style or "text" }
end

-- A Member's name, shortened to its first word when long.
local function shortName(name)
  if #name > 14 then return name:match("^%S+") or name end
  return name
end

-- The answer line while friends are chosen: whether you can all play, and
-- the dungeons shown that you all fit.
local function chosenAnswer(chosen, yourLevel, bars, chips)
  local names, far, allNear = { "You" }, {}, true
  for _, member in ipairs(chosen) do
    names[#names + 1] = shortName(member.name)
    local character = closest(member, yourLevel)
    if not canPlay(character.level, yourLevel) then
      allNear = false
      local gap = character.level - yourLevel
      far[#far + 1] = ("%s is %d %s"):format(shortName(member.name), math.abs(gap), gap > 0 and "ahead" or "behind")
    end
  end
  local first = { segment(listJoin(names, 4)) }
  if allNear then
    first[1].text = first[1].text .. " "
    first[2] = segment("can play", "highlight")
  end

  local shared = {}
  local function add(bar)
    if bar.shared then shared[#shared + 1] = bar end
  end
  for _, bar in ipairs(bars) do add(bar) end
  for _, chip in ipairs(chips) do
    for _, item in ipairs(chip.items) do add(item) end
  end
  table.sort(shared, function(a, b) return a.index < b.index end)

  local second
  if #shared > 0 then
    local list = {}
    for i, bar in ipairs(shared) do list[i] = bar.short end
    second = { segment("Together: ", "muted"), segment(table.concat(list, ", ")) }
  else
    second = { segment(("No dungeon fits you %s yet · %s"):format(#chosen == 1 and "both" or "all",
      #far > 0 and table.concat(far, ", ") or "Quest together"), "muted") }
  end
  return { first, second }
end

-- The answer line: who can play with you, and the best dungeon together.
local function answer(others, yourLevel)
  if #others == 0 then
    return {
      { segment("You're the only one in the Crew so far.", "muted") },
      { segment("Share your Crew code from Settings to bring friends in.", "muted") },
    }
  end

  local can, nearest = {}, nil
  for _, member in ipairs(others) do
    local character = closest(member, yourLevel)
    local gap = math.abs(character.level - yourLevel)
    if canPlay(character.level, yourLevel) then can[#can + 1] = character end
    if not nearest or gap < math.abs(nearest.level - yourLevel)
      or (gap == math.abs(nearest.level - yourLevel) and member.name < nearest.member.name) then
      nearest = character
    end
  end

  if #can == 0 then
    local gap = nearest.level - yourLevel
    local who = nearest.main and nearest.member.name
      or ("%s's alt %s"):format(nearest.member.name, nearest.name)
    return {
      { segment(("Nobody is within %d levels of you."):format(CAN_PLAY), "muted") },
      { segment(("Nearest: %s, %d %s."):format(who, math.abs(gap), gap > 0 and "ahead" or "behind"), "muted") },
    }
  end

  table.sort(can, function(a, b)
    if a.member.online ~= b.member.online then return a.member.online end
    local gapA, gapB = math.abs(a.level - yourLevel), math.abs(b.level - yourLevel)
    if gapA ~= gapB then return gapA < gapB end
    return a.member.name < b.member.name
  end)

  local first
  if #can > 3 then
    local online = 0
    for _, character in ipairs(can) do
      if character.member.online then online = online + 1 end
    end
    first = {
      segment(("%d friends "):format(#can)),
      segment("can play", "highlight"),
      segment(" with you"),
      segment((" · %d online now"):format(online), "muted"),
    }
  else
    local names = {}
    for i, character in ipairs(can) do
      names[i] = shortName(character.member.name) .. (character.main and "" or " (alt)")
    end
    first = { segment(listJoin(names) .. " "), segment("can play", "highlight"), segment(" with you") }
  end

  -- The dungeon you fit that the most of them fit (with a Character that
  -- can play with you), online first.
  local best = {}
  for _, dungeon in ipairs(DUNGEONS) do
    if dungeon.kind == "dungeon" and fits(yourLevel, dungeon) then
      local with, online = {}, 0
      for _, character in ipairs(can) do
        local fitting = closest(character.member, yourLevel, function(c)
          return fits(c.level, dungeon) and canPlay(c.level, yourLevel)
        end)
        if fitting then
          with[#with + 1] = character.member
          if character.member.online then online = online + 1 end
        end
      end
      if #with > 0 then best[#best + 1] = { dungeon = dungeon, with = with, online = online } end
    end
  end
  table.sort(best, function(a, b)
    if #a.with ~= #b.with then return #a.with > #b.with end
    if a.online ~= b.online then return a.online > b.online end
    return a.dungeon.index < b.dungeon.index
  end)

  local second
  if best[1] then
    local names = {}
    for i, member in ipairs(best[1].with) do names[i] = shortName(member.name) end
    second = {
      segment("Best together: ", "muted"),
      segment(best[1].dungeon.name),
      segment(" with " .. (#names > 2 and ("%d friends"):format(#names) or listJoin(names)), "muted"),
    }
    if best[2] then second[#second + 1] = segment(" · also " .. best[2].dungeon.name, "muted") end
  else
    second = { segment("No dungeon fits you together yet. Quest together.", "muted") }
  end
  return { first, second }
end

-- The Show menu: its options with their current values, the key and the
-- help line.
local function showMenu(filters)
  local function option(key, field, label, sub)
    return { key = key, label = label, sub = sub, value = filters[field] }
  end
  return {
    label = "Show",
    sections = {
      { title = "FRIENDS", options = {
        option("togetherOffline", "offline", "Offline friends"),
        option("togetherAlts", "alts", "Alts", "Mains and played Characters always show"),
      } },
      { title = "DUNGEONS", options = {
        option("togetherNear", "near", ("Only near your level (±%d)"):format(NEAR)),
        option("togetherAttunements", "attunements", "Attunements"),
        option("togetherRaids", "raids", "Raids"),
      } },
    },
    key = {
      title = "KEY",
      items = {
        { kind = "fits", text = "Fits your level" },
        { kind = "attunement", text = "Attunement" },
        { kind = "forever", text = "New in WoW: Forever" },
        { kind = "fitters", text = "Friends who fit it" },
      },
    },
    help = "Drag or scroll to move along the levels. Click a friend to see where you fit together.",
  }
end

-- The stretches of the line, from 0 to width, with nothing in a lane.
local function emptySpans(bars, chips, width)
  local taken = {}
  for _, bar in ipairs(bars) do taken[#taken + 1] = { bar.x, bar.x + bar.width } end
  for _, chip in ipairs(chips) do taken[#taken + 1] = { chip.x, chip.x + chip.width } end
  table.sort(taken, function(a, b) return a[1] < b[1] end)
  local spans, from = {}, 0
  for _, span in ipairs(taken) do
    if span[1] > from then spans[#spans + 1] = { left = from, right = span[1] } end
    from = math.max(from, span[2])
  end
  if from < width then spans[#spans + 1] = { left = from, right = width } end
  return spans
end

-- "3 alts, 2 offline hidden", or nil when nothing is. Offline Members
-- hidden by the filter count once each; Alts count among the rest.
local function hiddenNote(others, filters)
  local alts, offline = 0, 0
  for _, member in ipairs(others) do
    if not filters.offline and not member.online then
      offline = offline + 1
    else
      for _, character in ipairs(member.characters) do
        if not visible(character, filters) then alts = alts + 1 end
      end
    end
  end
  local parts = {}
  if alts > 0 then parts[#parts + 1] = ("%d %s"):format(alts, plural(alts, "alt", "alts")) end
  if offline > 0 then parts[#parts + 1] = ("%d offline"):format(offline) end
  if #parts == 0 then return nil end
  return table.concat(parts, ", ") .. " hidden"
end

-- Picking friends on the line: clicking a label or dot picks the Members
-- in it (memberIds), shift-clicking (add) adds them, and clicking what's
-- already picked clears it. No Members (your own dot) changes nothing.
-- Returns the new list of memberIds.
function Together.select(selected, memberIds, add)
  local result = {}
  for i, id in ipairs(selected) do result[i] = id end
  if #memberIds == 0 then return result end
  local picked = {}
  for _, id in ipairs(selected) do picked[id] = true end
  local same = #selected == #memberIds
  for _, id in ipairs(memberIds) do
    if not picked[id] then same = false end
  end
  if same then return {} end
  if not add then
    result = {}
    picked = {}
  end
  for _, id in ipairs(memberIds) do
    if not picked[id] then
      picked[id] = true
      result[#result + 1] = id
    end
  end
  return result
end

-- The Together tab from Roster's rows (yours first), or nil before you
-- play a Character. measure(text, font) is how wide a text is in pixels
-- in the font named ("small" or "tiny", as Skin's); without one, widths
-- are estimated. options: filters (the Show menu's offline, alts, near,
-- attunements and raids) and selected (memberIds picked on the line).
function Together.view(rows, measure, options)
  local own = rows[1]
  if not own or not own.own then return nil end
  measure = measure or estimate
  local filters = options.filters
  local yourLevel = own.level

  local members = membersOf(rows)
  local others, byId = {}, {}
  for _, member in ipairs(members) do
    if not member.own then
      others[#others + 1] = member
      byId[member.id] = member
    end
  end

  -- The chosen Members, as a list and by id; any is set while there are some.
  local chosen, selected = {}, {}
  for _, id in ipairs(options.selected or {}) do
    local member = byId[id]
    if member and not chosen[id] then
      chosen[id] = true
      chosen[#chosen + 1] = member
      selected[#selected + 1] = id
    end
  end
  chosen.any = #chosen > 0

  local groups = buildGroups(members, yourLevel, measure, filters, chosen)
  placeLabels(groups, yourLevel)
  local bars, chips = buildBars(shownDungeons(filters, yourLevel), others, yourLevel, measure, chosen)

  local ticks = {}
  for level = 1, LAYOUT.levels do
    local big = level == 1 or level % 5 == 0
    ticks[level] = {
      level = level,
      x = xOf(level),
      big = big,
      number = big or level == yourLevel,
      you = level == yourLevel,
    }
  end

  local width = xOf(LAYOUT.levels) + LAYOUT.right
  return {
    as = { name = own.name, classFilename = own.classFilename, level = yourLevel, alt = own.onAlt == true },
    hidden = hiddenNote(others, filters),
    answer = chosen.any and chosenAnswer(chosen, yourLevel, bars, chips) or answer(others, yourLevel),
    selected = selected,
    clear = chosen.any and "Clear" or nil,
    show = showMenu(filters),
    empty = filters.near and {
      text = "No dungeons shown at these levels",
      action = "Show all levels",
      setting = "togetherNear",
      spans = emptySpans(bars, chips, width),
    } or nil,
    width = width,
    you = xOf(yourLevel),
    band = {
      left = xOf(yourLevel - CAN_PLAY) - LAYOUT.level / 2,
      right = xOf(yourLevel + CAN_PLAY) + LAYOUT.level / 2,
      text = "can play",
    },
    ticks = ticks,
    groups = groups,
    bars = bars,
    chips = chips,
  }
end
