local _, ns = ...

local Away = {}
ns.Away = Away

local Skin = ns.Skin

local WIDTH = 400
local CAMP_WIDTH = 440
local INSET = 14
local INTRO_TOP = 16
local INTRO = 30
local HEADINGS = 18
local BUTTON = 24
local FOOTER_GAP = 18
local CHANGE_TOP = 2
local SUBTEXT_TOP = 4
local SUBTEXT_GAP = 1
local ICON = 14
local ROW = 26
local SECTION_TOP = 12
local NOTICED_TITLE = 16
local NOTICED_LINE = 20
local NOTICED_GAP = 4
local REACT = 18
local REACT_GAP = 4
local REACT_COLUMN = 2 * REACT + REACT_GAP + 8
local SMALL_BUTTON = 20
local MORE_ROW_TOP = 8
local BAND_BOTTOM = 12
local TALL_ROW = 38
local LEVEL_X = 136
local BAR = 90
local DEATHS_RIGHT = REACT_COLUMN
local GAINED_RIGHT = DEATHS_RIGHT + 30
local NAME_WIDTH = LEVEL_X - 8
local GAINED = Skin.ONLINE
local STAR = "|T" .. Skin.FEED_ICONS.maxLevel .. ":12|t"
local SKULL = "|T" .. Skin.FEED_ICONS.death .. ":12|t"
local GOAL = Skin.iconGlyph(Skin.FEED_PICTURES.goal, 14)

local frame
local rows = {}
local lines = {}
local goalLines = {}
local spareLines = {}
local professionLines = {}
local catchLines = {}
local updateLines = {}

local hex = Skin.hex

local function classHex(classFilename)
  local color = classFilename and RAID_CLASS_COLORS[classFilename]
  if color then return hex({ color.r, color.g, color.b }) end
  return hex(Skin.TEXT)
end

local function heading(text, x)
  local label = Skin.label(frame, "label", Skin.DIM)
  label:SetText(text)
  label.x = x
  if x < 0 then label:SetJustifyH("RIGHT") end
  frame.headings[#frame.headings + 1] = label
  return label
end

local function create()
  frame = Skin.window("BFFAway", WIDTH, "While you were away")
  frame:SetPoint("CENTER", 0, 120)
  frame.camp = ns.CampScene.new(frame, { gains = true })
  frame.camp:SetPoint("TOPLEFT", 1, -Skin.HEADER_HEIGHT)
  frame.camp:SetPoint("TOPRIGHT", -1, -Skin.HEADER_HEIGHT)
  Skin.edge(frame.camp, "BOTTOM", Skin.LINE, "OVERLAY")

  frame.noticed = Skin.label(frame, "label", Skin.DIM)
  frame.noticed:SetText("YOUR CREW NOTICED")
  frame.goals = Skin.label(frame, "label", Skin.DIM)
  frame.goals:SetText("CREW GOALS")
  frame.spares = Skin.label(frame, "label", Skin.DIM)
  frame.spares:SetText("SPARES")
  frame.professions = Skin.label(frame, "label", Skin.DIM)
  frame.professions:SetText("PROFESSIONS")
  frame.catches = Skin.label(frame, "label", Skin.DIM)
  frame.catches:SetText("CATCHES")
  frame.updateBand = Skin.fill(frame, Skin.RAISED, "BACKGROUND", 2)
  frame.updateBand.edge = frame:CreateTexture(nil, "BORDER")
  frame.updateBand.edge:SetColorTexture(Skin.LINE[1], Skin.LINE[2], Skin.LINE[3], Skin.LINE[4] or 1)
  frame.updateBand.edge:SetHeight(1)
  frame.updateBand.edge:SetPoint("TOPLEFT", frame.updateBand, "BOTTOMLEFT")
  frame.updateBand.edge:SetPoint("TOPRIGHT", frame.updateBand, "BOTTOMRIGHT")
  frame.update = Skin.label(frame, "label", Skin.DIM)
  frame.more = Skin.label(frame, "small", Skin.MUTED)
  frame.whatsNew = Skin.button(frame, "What's new", function()
    frame:Hide()
    ns.Panel.show("whatsnew")
  end)
  frame.whatsNew.label:SetFontObject(Skin.fonts.small)
  frame.whatsNew:SetSize(frame.whatsNew.label:GetStringWidth() + 16, SMALL_BUTTON)
  frame.intro = Skin.label(frame, "heading", Skin.TEXT)

  frame.headings = {}
  heading("LEVEL", INSET + LEVEL_X)
  heading("GAINED", -INSET - GAINED_RIGHT)
  heading(SKULL, -INSET - DEATHS_RIGHT)

  frame.open = Skin.button(frame, "Open Feed", function()
    frame:Hide()
    ns.Panel.show(frame.opens)
  end, true)
  frame.open:SetPoint("BOTTOMRIGHT", -INSET, INSET)
  local dismiss = Skin.button(frame, "Dismiss", function() frame:Hide() end)
  dismiss:SetPoint("RIGHT", frame.open, "LEFT", -8, 0)
end

local function react(button)
  if not button.key or button.done then return end
  local ok, reason = ns.core:react(button.key)
  button:SetReaction(button.reaction, ok or reason == "reacted")
  if ok and button.reaction == "cheer" then
    frame.camp:Hop(button.key.memberId)
    ns.Panel.cheered(button.key.memberId)
  end
end

local function drawButton(button, reaction, data)
  button:SetShown(data ~= nil)
  if not data then return end
  button.key = data.key
  button:SetReaction(reaction, data.reacted)
end

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
  item.track = Skin.fill(item, Skin.TRACK, "ARTWORK")
  item.track:ClearAllPoints()
  item.track:SetSize(BAR, 4)
  item.before = Skin.fill(item, Skin.BAR, "ARTWORK", 1)
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

  item.level:SetText(character.maxLevel and character.level .. " " .. STAR or tostring(character.level))
  item.level:SetPoint("BOTTOMLEFT", item, "LEFT", LEVEL_X, -1)
  item.track:SetPoint("TOPLEFT", item, "LEFT", LEVEL_X, -3)

  local scale = BAR / math.max(maxLevel, character.level)
  local from = character.from or 0
  if from > 0 then
    item.before:SetPoint("TOPLEFT", item.track)
    item.before:SetSize(from * scale, 4)
    item.before:Show()
  end
  item.gain:SetColorTexture(GAINED[1], GAINED[2], GAINED[3])
  item.gain:SetPoint("TOPLEFT", item.track, "TOPLEFT", from * scale, 0)
  item.gain:SetSize(math.max(2, (character.level - from) * scale), 4)
  item.gain:Show()
end

local function drawRow(item, member, character, first, maxLevel)
  item.edge:SetShown(first)
  item.icon:SetShown(first and member.classFilename ~= nil)
  item.member:SetShown(first)
  if first then
    item.icon:SetAtlas("classicon-" .. (member.classFilename or ""):lower())
    local tags = {}
    for i, tag in ipairs(member.tags) do
      tags[i] = hex(tag.highlight and Skin.GOLD or Skin.MUTED) .. tag.text .. "|r"
    end
    local text = classHex(member.classFilename) .. member.displayName .. "|r"
    if #tags > 0 then text = text .. "  " .. table.concat(tags, ", ") end
    item.member:SetText(text)
  end
  drawButton(item.welcome, "welcome", first and member.welcome or nil)
  if first and member.welcome then
    item.welcome:ClearAllPoints()
    local width = math.min(item.member:GetStringWidth(), item.member:GetWidth())
    item.welcome:SetPoint("LEFT", item.member, "LEFT", width + 6, 0)
  end
  drawButton(item.cheer, "cheer", character and character.cheer)
  drawButton(item.respects, "respects", character and character.respects)

  local name = character and character.label
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
  local gained = character and character.gained
  item.gained:SetText(gained and hex(GAINED) .. gained .. "|r" or "")
  item.deaths:SetText(character and character.deaths or "")
  item:Show()
  return height
end

local function line(pool, index)
  local item = pool[index]
  if item then return item end
  item = Skin.label(frame, "text")
  item:SetWordWrap(false)
  pool[index] = item
  return item
end

local function drawSection(title, texts, pool, y)
  title:SetShown(#texts > 0)
  for i = #texts + 1, #pool do pool[i]:Hide() end
  if #texts == 0 then return y end
  y = y - SECTION_TOP
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

local function drawNoticed(noticed, y)
  local texts = {}
  for i, notice in ipairs(noticed) do
    texts[i] = Skin.reactionGlyph(notice.reaction, 14) .. "  " .. notice.text
  end
  return drawSection(frame.noticed, texts, lines, y)
end

local function drawGoals(goals, y)
  local texts = {}
  for i, goal in ipairs(goals) do
    texts[i] = GOAL .. "  " .. Skin.hex(Skin.GOLD) .. goal.text .. "|r"
  end
  return drawSection(frame.goals, texts, goalLines, y)
end

local function drawSpares(notices, y)
  local texts = {}
  for i, notice in ipairs(notices) do
    texts[i] = "|T" .. Skin.FEED_ICONS[notice.kind] .. ":14|t  " .. notice.text
  end
  return drawSection(frame.spares, texts, spareLines, y)
end

local function cheerLine(pool, index)
  local item = pool[index]
  if item then return item end
  item = CreateFrame("Frame", nil, frame)
  item:SetHeight(NOTICED_LINE)
  item.text = Skin.label(item, "text")
  item.text:SetWordWrap(false)
  item.text:SetPoint("LEFT", 0, 0)
  item.text:SetPoint("RIGHT", -(REACT + 8), 0)
  item.cheer = Skin.reactionButton(item, REACT, react)
  item.cheer:SetPoint("RIGHT", 0, 0)
  pool[index] = item
  return item
end

local function drawCheerLines(title, news, pool, y)
  title:SetShown(#news > 0)
  for i = #news + 1, #pool do pool[i]:Hide() end
  if #news == 0 then return y end
  y = y - SECTION_TOP
  title:SetPoint("TOPLEFT", INSET, y)
  y = y - NOTICED_TITLE
  for i, item in ipairs(news) do
    local entry = cheerLine(pool, i)
    entry:ClearAllPoints()
    entry:SetPoint("TOPLEFT", INSET, y)
    entry:SetPoint("TOPRIGHT", -INSET, y)
    local text = item.highlight and hex(Skin.GOLD) .. item.text .. "|r" or item.text
    local icon = item.icon or Skin.FEED_PICTURES[item.kind]
    entry.text:SetText(Skin.iconGlyph(icon, 14) .. "  " .. text)
    drawButton(entry.cheer, "cheer", item.cheer)
    entry:Show()
    y = y - NOTICED_LINE
  end
  return y - NOTICED_GAP
end

local function updateLine(index)
  local item = updateLines[index]
  if item then return item end
  item = Skin.label(frame, "text", Skin.TEXT)
  item:SetWordWrap(true)
  updateLines[index] = item
  return item
end

local function drawBand(top, bottom)
  local band = frame.updateBand
  band:SetShown(top ~= nil)
  band.edge:SetShown(top ~= nil)
  if not top then return end
  band:ClearAllPoints()
  band:SetPoint("TOPLEFT", 1, top)
  band:SetPoint("TOPRIGHT", -1, top)
  band:SetHeight(top - bottom)
end

local function drawChanges(changes, y)
  for i = #changes + 1, #updateLines do updateLines[i]:Hide() end
  for i, text in ipairs(changes) do
    if i == 2 then y = y - SUBTEXT_TOP end
    local item = updateLine(i)
    item:SetFontObject(Skin.fonts[i == 1 and "text" or "small"])
    item:SetWidth(frame:GetWidth() - 2 * INSET)
    item:SetText(text)
    item:ClearAllPoints()
    item:SetPoint("TOPLEFT", INSET, y)
    item:Show()
    y = y - item:GetStringHeight() - SUBTEXT_GAP
  end
  return y
end

local function drawMore(more, y, withButton)
  frame.more:SetShown(more ~= nil)
  frame.more:SetText(more or "")
  frame.more:ClearAllPoints()
  frame.whatsNew:ClearAllPoints()
  if not withButton then
    if not more then return y end
    frame.more:SetPoint("TOPLEFT", INSET, y - SUBTEXT_TOP)
    return y - SUBTEXT_TOP - frame.more:GetStringHeight() - SUBTEXT_GAP
  end
  y = y - MORE_ROW_TOP
  frame.whatsNew:SetPoint("TOPRIGHT", -INSET, y)
  frame.more:SetPoint("LEFT", frame, "TOPLEFT", INSET, y - SMALL_BUTTON / 2)
  return y - SMALL_BUTTON
end

local function drawUpdate(update, y, updateOnly)
  local banded = update ~= nil and not updateOnly
  frame.update:SetShown(update ~= nil)
  frame.whatsNew:SetShown(banded)
  if not update then
    drawChanges({}, y)
    drawMore(nil, y, false)
    drawBand(nil)
    return y
  end

  local top = y
  y = y - SECTION_TOP
  Skin.color(frame.update, banded and Skin.MUTED or Skin.DIM)
  frame.update:SetText(update.title)
  frame.update:ClearAllPoints()
  frame.update:SetPoint("TOPLEFT", INSET, y)
  y = drawChanges(update.lines, y - NOTICED_TITLE - CHANGE_TOP)
  y = drawMore(update.more, y, banded)
  if not banded then
    drawBand(nil)
    return y
  end
  y = y - BAND_BOTTOM
  drawBand(top, y)
  return y
end

local function onlyUpdate(summary)
  if not summary.update or #summary.members > 0 then return false end
  for _, key in ipairs({ "noticed", "goals", "spares", "professions", "catches" }) do
    if #(summary[key] or {}) > 0 then return false end
  end
  return true
end

function Away.campReaction(reaction)
  if frame and frame:IsShown() then frame.camp:React(reaction) end
end

function Away.petCue(kind)
  if frame and frame:IsShown() then frame.camp:PetCue(kind) end
end

function Away.show(summary)
  if not frame then create() end
  local top = -Skin.HEADER_HEIGHT
  frame:SetWidth(summary.camp and CAMP_WIDTH or WIDTH)
  if summary.camp then
    local _, height = frame.camp:Measure(CAMP_WIDTH - 2, ns.CampScene.BAND_ROWS)
    frame.camp:SetHeight(height)
    top = top - height
  end
  frame.camp:Draw(summary.camp)
  local updateOnly = onlyUpdate(summary)
  local y = drawUpdate(summary.update, top, updateOnly)
  frame.opens = updateOnly and "whatsnew" or "feed"
  frame.open:SetText(updateOnly and "What's new" or "Open Feed")
  y = drawNoticed(summary.noticed or {}, y)
  y = drawGoals(summary.goals or {}, y)
  y = drawSpares(summary.spares or {}, y)
  y = drawCheerLines(frame.professions, summary.professions or {}, professionLines, y)
  y = drawCheerLines(frame.catches, summary.catches or {}, catchLines, y)

  local scoreboard = #summary.members > 0
  frame.intro:SetShown(scoreboard)
  for _, label in ipairs(frame.headings) do label:SetShown(scoreboard) end
  if scoreboard then
    frame.intro:SetText(summary.intro)
    frame.intro:ClearAllPoints()
    frame.intro:SetPoint("TOPLEFT", INSET, y - INTRO_TOP)
    for _, label in ipairs(frame.headings) do
      label:ClearAllPoints()
      label:SetPoint(label.x < 0 and "TOPRIGHT" or "TOPLEFT", label.x, y - INTRO_TOP - INTRO)
    end
    y = y - INTRO_TOP - INTRO - HEADINGS
  end

  local maxLevel = summary.maxLevel
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

  frame:SetHeight(-y + FOOTER_GAP + BUTTON + INSET)
  frame:Show()
end
