-- Away: the While you were away popup from the Feed decision (#14), in the
-- Skin's flat look. Your Crew noticed comes first: a line per entry of
-- yours others reacted to, then Crew goals reached, in gold, then
-- Spares: Claims on yours, what was sent to you and Gives. Then Core's
-- summary as a scoreboard, Members by
-- most recent activity: a row per Character with its level now, a bar for
-- the jump (gold when it reached max level), levels gained, deaths, and
-- Cheer and Respects buttons. The Member's name sits on their first row,
-- with joined or left beside it, and a Welcome by joined. Dismiss and Open
-- Feed. App shows it once out of combat. See docs/design/feed.md and
-- docs/design/reactions.md.

local _, ns = ...

local Away = {}
ns.Away = Away

local Skin = ns.Skin

local WIDTH = 400
local INSET = 14
local INTRO = 30
local HEADINGS = 18
local BUTTONS = 46
local ICON = 14
local ROW = 26
local NOTICED_TITLE = 18
local NOTICED_LINE = 22
local NOTICED_GAP = 12
-- The Reaction buttons, in a column at the right of each row.
local REACT = 18
local REACT_GAP = 4
local REACT_COLUMN = 2 * REACT + REACT_GAP + 8
-- A row with the Character's name under the Member's.
local TALL_ROW = 38
-- Columns, as x from the left of the scoreboard and from its right.
local LEVEL_X = 136
local BAR = 90
local DEATHS_RIGHT = REACT_COLUMN
local GAINED_RIGHT = DEATHS_RIGHT + 30
-- The names stop short of the level column.
local NAME_WIDTH = LEVEL_X - 8
local GAINED = Skin.ONLINE
local STAR = "|T" .. Skin.FEED_ICONS.maxLevel .. ":12|t"
local SKULL = "|T" .. Skin.FEED_ICONS.death .. ":12|t"
local GOAL = "|T" .. Skin.FEED_ICONS.goal .. ":14|t"

local frame
local rows = {}
local lines = {}
local goalLines = {}
local spareLines = {}

local hex = Skin.hex

local function classHex(classFilename)
  local color = classFilename and RAID_CLASS_COLORS[classFilename]
  if color then return hex({ color.r, color.g, color.b }) end
  return hex(Skin.TEXT)
end

-- A column heading, placed by show(): x is from the left, or from the
-- right when negative.
local function heading(text, x)
  local label = Skin.label(frame, "tiny", Skin.DIM)
  label:SetText(text)
  label.x = x
  if x < 0 then label:SetJustifyH("RIGHT") end
  frame.headings[#frame.headings + 1] = label
  return label
end

local function create()
  frame = Skin.window("BFFAway", WIDTH, "While you were away")
  frame:SetPoint("CENTER", 0, 120)

  frame.noticed = Skin.label(frame, "tiny", Skin.DIM)
  frame.noticed:SetText("YOUR CREW NOTICED")
  frame.goals = Skin.label(frame, "tiny", Skin.DIM)
  frame.goals:SetText("CREW GOALS")
  frame.spares = Skin.label(frame, "tiny", Skin.DIM)
  frame.spares:SetText("SPARES")
  frame.intro = Skin.label(frame, "small", Skin.MUTED)

  frame.headings = {}
  heading("LEVEL", INSET + LEVEL_X)
  heading("GAINED", -INSET - GAINED_RIGHT)
  heading(SKULL, -INSET - DEATHS_RIGHT)

  local open = Skin.button(frame, "Open Feed", function()
    frame:Hide()
    ns.Panel.show("feed")
  end, true)
  open:SetPoint("BOTTOMRIGHT", -INSET, INSET)
  local dismiss = Skin.button(frame, "Dismiss", function() frame:Hide() end)
  dismiss:SetPoint("RIGHT", open, "LEFT", -8, 0)
end

-- A Reaction button's click: reacts with the key it was drawn with, and
-- shows it done once it is.
local function react(button)
  if not button.key or button.done then return end
  local ok, reason = ns.core:react(button.key)
  button:SetReaction(button.reaction, ok or reason == "reacted")
end

-- Draws a Reaction button from a summary button ({ key, reacted }), or
-- hides it.
local function drawButton(button, reaction, data)
  button:SetShown(data ~= nil)
  if not data then return end
  button.key = data.key
  button:SetReaction(reaction, data.reacted)
end

-- A scoreboard row: the Member (on their first row) and the Character on
-- the left, then level and bar, levels gained, deaths and Reactions.
local function row(index)
  local item = rows[index]
  if item then return item end
  item = CreateFrame("Frame", nil, frame)
  item.edge = Skin.edge(item, "TOP", Skin.LINE)
  item.icon = item:CreateTexture(nil, "ARTWORK")
  item.icon:SetSize(ICON, ICON)
  item.member = Skin.label(item, "text")
  item.member:SetPoint("LEFT", item.icon, "RIGHT", 6, 0)
  item.member:SetWidth(NAME_WIDTH - ICON - 6)
  item.member:SetWordWrap(false)
  item.character = Skin.label(item, "small", Skin.MUTED)
  item.character:SetWidth(NAME_WIDTH)
  item.character:SetWordWrap(false)
  item.level = Skin.label(item, "text")
  item.track = Skin.fill(item, { 1, 1, 1, 0.08 }, "ARTWORK")
  item.track:ClearAllPoints()
  item.track:SetSize(BAR, 4)
  item.before = Skin.fill(item, Skin.MUTED, "ARTWORK", 1)
  item.before:ClearAllPoints()
  item.gain = Skin.fill(item, GAINED, "ARTWORK", 1)
  item.gain:ClearAllPoints()
  item.gained = Skin.label(item, "text")
  item.gained:SetJustifyH("RIGHT")
  item.gained:SetPoint("RIGHT", -GAINED_RIGHT, 0)
  item.deaths = Skin.label(item, "text", Skin.DIM)
  item.deaths:SetJustifyH("RIGHT")
  item.deaths:SetPoint("RIGHT", -DEATHS_RIGHT, 0)
  item.respects = Skin.reactionButton(item, REACT, react)
  item.respects:SetPoint("RIGHT", 0, 0)
  item.cheer = Skin.reactionButton(item, REACT, react)
  item.cheer:SetPoint("RIGHT", item.respects, "LEFT", -REACT_GAP, 0)
  item.welcome = Skin.reactionButton(item, REACT, react)
  rows[index] = item
  return item
end

-- The level column: the level now (gold with a star at max level) over a
-- bar from 0 to max level, the part before in grey and the jump in green,
-- or gold at max level. A dash for a Character that only died.
local function drawLevel(item, character, maxLevel)
  local shown = character.level ~= nil
  item.track:SetShown(shown)
  item.before:Hide()
  item.gain:Hide()
  item.level:ClearAllPoints()
  if not shown then
    item.level:SetText(character.deaths and hex(Skin.DIM) .. "-|r" or "")
    item.level:SetPoint("LEFT", LEVEL_X, 0)
    return
  end

  item.level:SetText(character.maxLevel and hex(Skin.GOLD) .. character.level .. "|r " .. STAR
    or tostring(character.level))
  item.level:SetPoint("BOTTOMLEFT", item, "LEFT", LEVEL_X, -1)
  item.track:SetPoint("TOPLEFT", item, "LEFT", LEVEL_X, -3)

  local scale = BAR / math.max(maxLevel, character.level)
  local from = character.from or 0
  if from > 0 then
    item.before:SetPoint("TOPLEFT", item.track)
    item.before:SetSize(from * scale, 4)
    item.before:Show()
  end
  local color = character.maxLevel and Skin.GOLD or GAINED
  item.gain:SetColorTexture(color[1], color[2], color[3])
  item.gain:SetPoint("TOPLEFT", item.track, "TOPLEFT", from * scale, 0)
  item.gain:SetSize(math.max(2, (character.level - from) * scale), 4)
  item.gain:Show()
end

-- Draws one row and returns its height. character is nil for a Member
-- with no Character rows (joined or left only).
local function drawRow(item, member, character, first, maxLevel)
  item.edge:SetShown(first)
  item.icon:SetShown(first and member.classFilename ~= nil)
  item.member:SetShown(first)
  if first then
    item.icon:SetAtlas("classicon-" .. (member.classFilename or ""):lower())
    local tags = {}
    for _, highlight in ipairs(member.highlights) do
      if highlight.kind ~= "maxLevel" then tags[#tags + 1] = highlight.kind end
    end
    local text = classHex(member.classFilename) .. member.displayName .. "|r"
    if #tags > 0 then text = text .. "  " .. hex(Skin.GOLD) .. table.concat(tags, ", ") .. "|r" end
    item.member:SetText(text)
  end
  -- The Welcome sits just after the gold joined tag.
  drawButton(item.welcome, "welcome", first and member.welcome or nil)
  if first and member.welcome then
    item.welcome:ClearAllPoints()
    local width = math.min(item.member:GetStringWidth(), item.member:GetWidth())
    item.welcome:SetPoint("LEFT", item.member, "LEFT", width + 6, 0)
  end
  drawButton(item.cheer, "cheer", character and character.cheer)
  drawButton(item.respects, "respects", character and character.respects)

  -- The Character's name, unless it is the Member's own name on their Main.
  local name
  if character and not (character.main and character.name == member.displayName) then
    name = character.main and character.name or "Alt " .. character.name
  end
  item.character:SetText(name or "")
  item.character:SetShown(name ~= nil)

  local height = (first and name) and TALL_ROW or ROW
  item:SetHeight(height)
  item.icon:ClearAllPoints()
  item.character:ClearAllPoints()
  if first and name then
    item.icon:SetPoint("TOPLEFT", 0, -6)
    item.character:SetPoint("TOPLEFT", item.member, "BOTTOMLEFT", 0, -2)
  else
    item.icon:SetPoint("LEFT", 0, 0)
    item.character:SetPoint("LEFT", 0, 0)
  end

  drawLevel(item, character or {}, maxLevel)
  if character and character.new then
    item.gained:SetText(hex(Skin.GOLD) .. "new|r")
  elseif character and character.from then
    item.gained:SetText(hex(GAINED) .. "+" .. (character.level - character.from) .. "|r")
  else
    item.gained:SetText("")
  end
  item.deaths:SetText(character and character.deaths or "")
  item:Show()
  return height
end

-- A line in Your Crew noticed or Crew goals: an icon and the text.
local function line(pool, index)
  local item = pool[index]
  if item then return item end
  item = Skin.label(frame, "text")
  item:SetWordWrap(false)
  pool[index] = item
  return item
end

-- A section of one-line items under a title (Your Crew noticed, Crew
-- goals), from y down, with a line per text from the pool. Returns the y
-- below it.
local function drawSection(title, texts, pool, y)
  title:SetShown(#texts > 0)
  for i = #texts + 1, #pool do pool[i]:Hide() end
  if #texts == 0 then return y end
  y = y - 10
  title:SetPoint("TOPLEFT", INSET, y)
  y = y - NOTICED_TITLE
  for i, text in ipairs(texts) do
    local item = line(pool, i)
    item:ClearAllPoints()
    item:SetPoint("TOPLEFT", INSET, y)
    item:SetPoint("RIGHT", -INSET, 0)
    item:SetText(text)
    item:Show()
    y = y - NOTICED_LINE
  end
  return y - NOTICED_GAP
end

-- Your Crew noticed: each with its Reaction's icon.
local function drawNoticed(noticed, y)
  local texts = {}
  for i, notice in ipairs(noticed) do
    texts[i] = Skin.reactionGlyph(notice.reaction, 14) .. "  " .. notice.text
  end
  return drawSection(frame.noticed, texts, lines, y)
end

-- Crew goals reached, in gold.
local function drawGoals(goals, y)
  local texts = {}
  for i, goal in ipairs(goals) do
    texts[i] = GOAL .. "  " .. Skin.hex(Skin.GOLD) .. goal.text .. "|r"
  end
  return drawSection(frame.goals, texts, goalLines, y)
end

-- Spare notices and Gives, each with its kind's icon.
local function drawSpares(notices, y)
  local texts = {}
  for i, notice in ipairs(notices) do
    texts[i] = "|T" .. Skin.FEED_ICONS[notice.kind] .. ":14|t  " .. notice.text
  end
  return drawSection(frame.spares, texts, spareLines, y)
end

-- Shows the summary from Core's awaySummary: { members, goals,
-- spares, count, noticed }. With no Member news, only Your Crew
-- noticed, Crew goals and Spares show.
function Away.show(summary)
  if not frame then create() end
  local y = drawNoticed(summary.noticed or {}, -Skin.HEADER_HEIGHT)
  y = drawGoals(summary.goals or {}, y)
  y = drawSpares(summary.spares or {}, y)

  local scoreboard = #summary.members > 0
  frame.intro:SetShown(scoreboard)
  for _, label in ipairs(frame.headings) do label:SetShown(scoreboard) end
  if scoreboard then
    frame.intro:SetText(summary.count == 1 and "1 thing happened while you were away."
      or ("%d things happened while you were away."):format(summary.count))
    frame.intro:ClearAllPoints()
    frame.intro:SetPoint("TOPLEFT", INSET, y - 10)
    for _, label in ipairs(frame.headings) do
      label:ClearAllPoints()
      label:SetPoint(label.x < 0 and "TOPRIGHT" or "TOPLEFT", label.x, y - INTRO)
    end
    y = y - INTRO - HEADINGS
  end

  local maxLevel = GetMaxLevelForPlayerExpansion()
  local index = 0
  for _, member in ipairs(summary.members) do
    local characters = member.characters
    for i = 1, math.max(#characters, 1) do
      index = index + 1
      local item = row(index)
      item:ClearAllPoints()
      item:SetPoint("TOPLEFT", INSET, y)
      item:SetPoint("TOPRIGHT", -INSET, y)
      y = y - drawRow(item, member, characters[i], i == 1, maxLevel)
    end
  end
  for i = index + 1, #rows do rows[i]:Hide() end

  frame:SetHeight(-y + BUTTONS)
  frame:Show()
end
