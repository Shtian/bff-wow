-- Panel: the BFF window, in the Skin's flat look. Without a Crew it shows
-- the setup view (display name, Start or Join); in one, a sidebar with
-- Roster, Feed, Goals, When, Spares, Professions, Together and Settings. The Roster has your own row pinned on top,
-- then a row per Member with expandable Alts, a sort menu, a tooltip and
-- right-click menu per Character, and a footer with the hidden count,
-- removed Members and the Crew code. The Feed is a timeline
-- of Core's entries by day, an icon per kind, who reacted to each and a
-- button to react, and marks them seen while open. Goals is a trophy
-- cabinet of the Crew goals reached, drawn by GoalsTab. When is a heatmap of the week in local time: how many
-- Members usually play each hour, or one Member's weeks played, picked
-- from a menu. Spares lists other Members' open ones with Claim
-- and Withdraw-claim buttons, dimmed when none of your Characters is high
-- enough level, then your own with their winning Claim and Give and
-- Withdraw. Professions is a grid of all twelve professions, a row per
-- Member and a tile each with their best Character's skill, sortable by a
-- profession. Together is a level line of friends and dungeons, drawn by
-- TogetherTab. A grip in the bottom right corner resizes the window, and
-- Core keeps its size and position; views lay out to the current width
-- and redraw when a resize ends. While Core has a Camp (camp()), its band
-- runs across the window under the header, above the sidebar and every
-- tab, drawn by CampScene; Roster rows show a small seated figure in place
-- of the class icon, and a Cheer makes a seated friend hop. It never sees
-- a Member record.

local _, ns = ...

local Panel = {}
ns.Panel = Panel

local Skin = ns.Skin

-- The window's size is the player's (Core's panelPlace()), between
-- Core's limits; views read it as they draw.
local SIDEBAR = 124
-- Small enough to stay clear of the Roster footer's Removed and the
-- Together tab's overview strip.
local GRIP = 12
local HEADER = Skin.HEADER_HEIGHT
local NAV_HEIGHT = 30
local NAV_CHIP_X = 6
local NAV_CHIP_Y = 2
local NAV_CHIP_RADIUS = 2
-- The Roster footer's small labels (Crew code, Hidden, Removed) share one
-- bottom line, so they line up with each other and the code box.
local CODE_LINE = 15
local ROW_HEIGHT = 44
local ALT_HEIGHT = 20
local SECTION = 26
local INSET = 12
-- Buttons inside rows and headings, and the pickers that open a menu.
-- Window actions keep Skin.button's 24.
local SMALL_BUTTON = 20
local FEED_ENTRY = 38
local REACT = 20
local FEED_DAY = 26
-- The timeline's line runs through the middle of the entry pictures.
local NODE = 26
local NEW_DOT = 6
local LINE_X = INSET + NODE / 2 - 1
-- Last seen goes stale, so the open panel redraws this often.
local REDRAW_EVERY = 30
-- Under this high, the Camp band is its short one.
local CAMP_SMALL_UNDER = 460
local SCROLL_STEP = 40

local TITLE = "Best Friends in Forever"
local FEED_EMPTY_TITLE = "Nothing yet"
local FEED_EMPTY = "Dings, deaths and new Characters show up here."
-- The stretch of timeline behind an empty Feed's one node.
local FEED_EMPTY_LINE = 120
-- The setup view's block, centred in the window: Display name across it,
-- Start and Join in two columns below.
local SETUP_WIDTH = 320
local SETUP_COLUMN = 150
local SETUP_COLUMNS_Y = -72
-- The When grid: a cell per hour, a row per day. It grows to fill the view,
-- so the cell and row sizes are its least; the legend's swatches stay at them.
local WHEN_CELL = 11
local WHEN_ROW = 18
local WHEN_DAYS = 30
-- The grid's top, under the picker and the intro's room.
local WHEN_TOP = -INSET - SMALL_BUTTON - 8 - 36
-- What the grid leaves below it: the legend, two lines of note and an inset.
local WHEN_BELOW = 74
local DAY_NAMES = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" }
-- Spares: a row per item, under a section heading.
local SPARE_ROW = 44
local SPARE_ICON = 28
local SPARE_BUTTON = 58
local SPARE_SECTION = 28
local SPARES_NONE = "No Spares from the Crew right now."
local SPARES_DROP = "Drop an item from your bags here to offer it to your Crew."
local SPARES_HOW = "Offer an item: drop it on the slot above, or type /bff spares add and shift-click it into the chat box. Mail it to the winner, then Give it."
local QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"
-- Professions: a row per Member, a column per profession, a tile each.
local PROFESSION_HEAD = 26
local PROFESSION_ICON = 16
local PROFESSION_NAME = 82
local PROFESSION_NAME_MAX = 140
local PROFESSION_TILE = 18
local PROFESSION_GAP = 1
-- The gap before cooking, fishing and first aid, with a hairline in it.
local PROFESSION_DIVIDER = 6
local PROFESSION_ROW = 25
local PROFESSION_BAR = 2

local GOLD = Skin.GOLD
local MUTED = Skin.MUTED
local DIM = Skin.DIM
local TEXT = Skin.TEXT
local ONLINE = Skin.ONLINE
local ERROR = { 1, 0.42, 0.42 }

local SORTS = { { "online", "Online first" }, { "level", "Level" }, { "name", "Name" } }

local core
local frame
-- The Camp band, and its height now (0 while there's no Camp).
local camp
local campHeight = 0
local setup
local nav
local section
local rosterView
local feedView
local goalsView
local whenView
local sparesView
local professionsView
local footer
local rowFrames = {}
local altFrames = {}
-- What the UI itself remembers: the tab, the sort and which Members show
-- Alts. Which Feed entries are New is Core's (openFeed, leaveFeed).
local tab = "roster"
-- The When tab's Member, or nil for the Crew.
local whenMember
local order = "online"
local expanded = {}

local classColor = Skin.classColor

-- The content's width right of the sidebar, at the window's current size.
local function contentWidth()
  return frame:GetWidth() - SIDEBAR - 1
end

local function contentHeight()
  return frame:GetHeight() - HEADER - campHeight - 1
end

-- A scroll view's width: the content less the thumb's gutter.
local function listWidth()
  return contentWidth() - 6
end

local function className(classFilename)
  return LOCALIZED_CLASS_NAMES_MALE[classFilename] or classFilename or ""
end

-- Whisper and Invite, guarded since Midnight moved some chat functions.
local function whisper(name)
  local sendTell = ChatFrameUtil and ChatFrameUtil.SendTell or ChatFrame_SendTell
  if sendTell then sendTell(name) end
end

local function invite(name)
  if C_PartyInfo and C_PartyInfo.InviteUnit then C_PartyInfo.InviteUnit(name) end
end

StaticPopupDialogs.BFF_REMOVE_MEMBER = {
  text = "Remove %s? Only you stop seeing them; the rest of the Crew still does.",
  button1 = YES,
  button2 = NO,
  OnAccept = function(_, memberId) core:removeMember(memberId) end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
}

-- The tooltip goes beside the panel, level with the row under the mouse,
-- on whichever side has room. ANCHOR_RIGHT on a row near the top of the
-- screen put it in the screen's corner.
local TOOLTIP_ROOM = 280
local function placeBeside(owner)
  GameTooltip:SetOwner(owner, "ANCHOR_NONE")
  local y = owner:GetTop() - frame:GetTop()
  if frame:GetRight() + TOOLTIP_ROOM > UIParent:GetRight() then
    GameTooltip:SetPoint("TOPRIGHT", frame, "TOPLEFT", -6, y)
  else
    GameTooltip:SetPoint("TOPLEFT", frame, "TOPRIGHT", 6, y)
  end
end

-- The Character under the mouse: owner.row is its Member's row, and
-- owner.character the Character (the row itself for the shown one).
local function showTooltip(owner)
  local row, character = owner.row, owner.character
  if not row then return end
  placeBeside(owner)
  GameTooltip:AddLine(character.name, classColor(character.classFilename))
  GameTooltip:AddLine(("Level %d %s %s"):format(character.level, className(character.classFilename),
    character.main and "(Main)" or "(Alt)"), 1, 1, 1)
  GameTooltip:AddLine(row.own and "Your Character" or ("%s's Character"):format(row.displayName or "?"), 1, 1, 1)
  if character.zone then GameTooltip:AddLine(character.zone) end
  if character.maxXp and character.maxXp > 0 then
    GameTooltip:AddLine(("XP %d%%"):format(math.floor(100 * (character.xp or 0) / character.maxXp)), MUTED[1], MUTED[2], MUTED[3])
  end
  GameTooltip:AddLine(("Deaths: %d"):format(character.deaths or 0), MUTED[1], MUTED[2], MUTED[3])
  local gold = ns.Core.goldText(character.money)
  if gold then GameTooltip:AddLine(gold, MUTED[1], MUTED[2], MUTED[3]) end
  -- A line per profession: icon, name and rank, then skill/max, gold at
  -- 300/300. None when the Character's client never shared them.
  for _, profession in ipairs(character.professions or {}) do
    local icon = profession.icon and Skin.iconGlyph(profession.icon, 14) .. " " or ""
    local rank = profession.rank and (" %s%s|r"):format(Skin.hex(DIM), profession.rank) or ""
    local skill = profession.full and profession.capped and GOLD or MUTED
    GameTooltip:AddDoubleLine(icon .. profession.name .. rank, ("%d/%d"):format(profession.skill, profession.max),
      TEXT[1], TEXT[2], TEXT[3], skill[1], skill[2], skill[3])
  end
  if character.playing then
    GameTooltip:AddLine(row.own and "Playing now" or "Online now", ONLINE[1], ONLINE[2], ONLINE[3])
  else
    GameTooltip:AddLine("Last seen " .. character.lastSeenText, MUTED[1], MUTED[2], MUTED[3])
  end
  if not row.online and row.via then
    GameTooltip:AddLine("Heard via " .. row.via, MUTED[1], MUTED[2], MUTED[3])
  end
  if character.canPlay then
    GameTooltip:AddLine(("Within %d levels of you: can play together"):format(ns.Core.CAN_PLAY_LEVELS),
      GOLD[1], GOLD[2], GOLD[3])
  end
  GameTooltip:Show()
end

local function hideTooltip()
  GameTooltip:Hide()
end

-- Others' Characters: Whisper and Invite while being played, and Remove.
-- Your own: Set as Main, or back to the most recently played.
local function showMenu(owner)
  local row, character = owner.row, owner.character
  if not row then return end
  MenuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateTitle(character.name)
    if row.own then
      local setMain = root:CreateButton("Set as Main", function() core:setMain(character.guid) end)
      setMain:SetEnabled(not (character.main and row.mainSet))
      if row.mainSet then
        root:CreateButton("Main: most recently played", function() core:setMain(nil) end)
      end
    else
      root:CreateButton("Whisper", function() whisper(character.name) end):SetEnabled(character.playing)
      root:CreateButton("Invite", function() invite(character.name) end):SetEnabled(character.playing)
      local name = row.displayName or character.name
      root:CreateButton(("When does %s play?"):format(name), function() Panel.showWhen(row.memberId) end)
      root:CreateButton(("Remove %s..."):format(name), function()
        StaticPopup_Show("BFF_REMOVE_MEMBER", name, nil, row.memberId)
      end)
    end
  end)
end

local function createTag(parent)
  local tag = Skin.label(parent, "small", MUTED)
  tag:Hide()
  return tag
end

-- Lays tags out left to right after `anchor`, showing those with text.
local function placeTags(anchor, tags)
  for _, tag in ipairs(tags) do
    if tag:GetText() ~= "" then
      tag:ClearAllPoints()
      tag:SetPoint("LEFT", anchor, "RIGHT", 6, 0)
      tag:Show()
      anchor = tag
    else
      tag:Hide()
    end
  end
end

local function setTag(tag, text, color)
  tag:SetText(text or "")
  if text then Skin.color(tag, color) end
end

local function characterButton(height)
  local button = CreateFrame("Button", nil, rosterView.content)
  button:SetHeight(height)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  Skin.fill(button, Skin.HOVER, "HIGHLIGHT")
  button:SetScript("OnEnter", showTooltip)
  button:SetScript("OnLeave", hideTooltip)
  return button
end

local function onRowClick(button, mouse)
  if mouse == "RightButton" then
    showMenu(button)
  elseif #button.row.alts > 0 then
    expanded[button.row.memberId] = not expanded[button.row.memberId]
    Panel.refresh()
  end
end

-- A round status dot with a ring in the window's colour, so it reads on
-- top of a class icon.
local function createDot(parent, size)
  local ring = parent:CreateTexture(nil, "OVERLAY", nil, 1)
  ring:SetSize(size + 4, size + 4)
  ring:SetColorTexture(Skin.WINDOW[1], Skin.WINDOW[2], Skin.WINDOW[3], 1)
  Skin.round(parent, ring)
  local dot = parent:CreateTexture(nil, "OVERLAY", nil, 2)
  dot:SetSize(size, size)
  dot:SetPoint("CENTER", ring)
  dot:SetColorTexture(1, 1, 1, 1)
  Skin.round(parent, dot)
  dot.ring = ring
  return dot
end

local function setDot(dot, online)
  Skin.color(dot, online and ONLINE or Skin.OFFLINE)
end

local function createRow()
  local row = characterButton(ROW_HEIGHT)
  row:SetScript("OnClick", onRowClick)

  row.ownBackground = Skin.fill(row, { GOLD[1], GOLD[2], GOLD[3], 0.05 })

  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(28, 28)
  row.icon:SetPoint("TOPLEFT", INSET, -7)
  -- The Camp's seated figure, in the class icon's place.
  row.figure = ns.CampScene.figure(row)
  row.figure:SetPoint("BOTTOM", row.icon, "BOTTOM", 0, 1)
  row.dot = createDot(row, 8)
  row.dot.ring:SetPoint("CENTER", row.icon, "BOTTOMRIGHT", -1, 1)

  row.name = Skin.label(row, "body")
  row.name:SetPoint("TOPLEFT", INSET + 38, -6)
  row.level = Skin.badge(row)
  row.level:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
  row.member = createTag(row)
  row.onAlt = createTag(row)
  row.canPlay = createTag(row)

  row.zone = Skin.label(row, "small", MUTED)
  row.zone:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)

  row.seen = Skin.label(row, "small")
  row.seen:SetJustifyH("RIGHT")
  row.seen:SetPoint("TOPRIGHT", -INSET, -8)
  row.more = Skin.label(row, "small")
  row.more:SetJustifyH("RIGHT")
  row.more:SetPoint("TOPRIGHT", row.seen, "BOTTOMRIGHT", 0, -3)

  row.xp = CreateFrame("StatusBar", nil, row)
  row.xp:SetPoint("BOTTOMLEFT", INSET + 38, 4)
  row.xp:SetPoint("BOTTOMRIGHT", -INSET, 4)
  row.xp:SetHeight(2)
  row.xp:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
  Skin.fill(row.xp, Skin.TRACK)

  rowFrames[#rowFrames + 1] = row
  return row
end

local function drawRow(row, data)
  row.row, row.character = data, data
  row.ownBackground:SetShown(data.own)
  setDot(row.dot, data.online)
  row.icon:SetAtlas("classicon-" .. (data.classFilename or ""):lower())
  row.icon:SetShown(not camp:IsShown())
  if camp:IsShown() then row.figure:SetClass(data.classFilename) else row.figure:Hide() end
  row.name:SetText(data.name)
  row.name:SetTextColor(classColor(data.classFilename))
  row.level:SetText(data.level)
  setTag(row.member, data.own and "you" or data.displayName, MUTED)
  setTag(row.onAlt, data.onAlt and "on alt" or nil, MUTED)
  setTag(row.canPlay, data.canPlay and "can play" or nil, GOLD)
  placeTags(row.level, { row.member, row.onAlt, row.canPlay })
  row.zone:SetText(data.zone or "")

  row.seen:SetText(data.status or "")
  Skin.color(row.seen, data.online and ONLINE or DIM)
  if #data.alts > 0 then
    row.more:SetText(("%s%d more"):format(expanded[data.memberId] and "- " or "+ ", #data.alts))
    Skin.color(row.more, data.altsCanPlay and GOLD or MUTED)
  else
    row.more:SetText("")
  end

  local maxXp = data.maxXp or 0
  row.xp:SetMinMaxValues(0, math.max(maxXp, 1))
  row.xp:SetValue(maxXp > 0 and (data.xp or 0) or 0)
  row.xp:SetStatusBarColor(Skin.BAR[1], Skin.BAR[2], Skin.BAR[3], Skin.BAR[4])
  row.xp:SetShown(maxXp > 0)
  row:SetAlpha(data.online and 1 or 0.75)
  row:Show()
end

local function onAltClick(button, mouse)
  if mouse == "RightButton" then showMenu(button) end
end

local function createAlt()
  local alt = characterButton(ALT_HEIGHT)
  alt:SetScript("OnClick", onAltClick)
  alt.name = Skin.label(alt, "text")
  alt.name:SetPoint("LEFT", INSET + 38, 0)
  alt.level = Skin.badge(alt)
  alt.level:SetPoint("LEFT", alt.name, "RIGHT", 6, 0)
  alt.main = createTag(alt)
  alt.canPlay = createTag(alt)
  alt.right = Skin.label(alt, "small", DIM)
  alt.right:SetJustifyH("RIGHT")
  alt.right:SetPoint("RIGHT", -INSET, 0)
  altFrames[#altFrames + 1] = alt
  return alt
end

local function drawAlt(alt, row, data)
  alt.row, alt.character = row, data
  alt.name:SetText(data.name)
  alt.name:SetTextColor(classColor(data.classFilename))
  alt.level:SetText(data.level)
  setTag(alt.main, data.main and "main" or nil, MUTED)
  setTag(alt.canPlay, data.canPlay and "can play" or nil, GOLD)
  placeTags(alt.level, { alt.main, alt.canPlay })
  local zone = data.zone and data.zone .. " · " or ""
  alt.right:SetText(zone .. data.lastSeenText)
  alt:Show()
end

local function hideAll(lines, from)
  for i = from, #lines do lines[i]:Hide() end
end

-- Places a line across the Roster, at y from its top.
local function place(line, y)
  line:ClearAllPoints()
  line:SetPoint("TOPLEFT", rosterView.content, "TOPLEFT", 0, y)
  line:SetPoint("TOPRIGHT", rosterView.content, "TOPRIGHT", 0, y)
end

local function showSortMenu(owner)
  MenuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateTitle("Sort by")
    for _, sort in ipairs(SORTS) do
      root:CreateRadio(sort[2], function() return order == sort[1] end, function()
        order = sort[1]
        Panel.refresh()
      end)
    end
  end)
end

-- "CREW ———— 2 Spares for you [Sort: Online first]" between your
-- row and the Members'. Core names each row's section; the first carries
-- the sort and Spares, and any later one (ASLEEP IN CAMP) is a plain label
-- and line.
local function sectionLabel(parent)
  local label = Skin.label(parent, "label", DIM)
  label:SetPoint("LEFT", INSET, -2)
  return label
end

local function createSection()
  section = CreateFrame("Frame", nil, rosterView.content)
  section:SetHeight(SECTION)
  local label = sectionLabel(section)
  section.label = label

  section.sort = CreateFrame("Button", nil, section)
  section.sort:SetHeight(SMALL_BUTTON)
  section.sort:SetPoint("RIGHT", -INSET, -2)
  Skin.fill(section.sort, Skin.SECONDARY)
  Skin.border(section.sort, Skin.BORDER)
  Skin.fill(section.sort, Skin.HOVER, "HIGHLIGHT")
  section.sort.label = Skin.label(section.sort, "small", MUTED)
  section.sort.iconRoom = Skin.leadIcon(section.sort, "sort", MUTED)
  section.sort:SetScript("OnClick", showSortMenu)

  -- "2 Spares for you", which opens their tab.
  section.spares = CreateFrame("Button", nil, section)
  section.spares:SetHeight(18)
  section.spares:SetPoint("RIGHT", section.sort, "LEFT", -8, 0)
  section.spares.label = Skin.label(section.spares, "small", GOLD)
  section.spares.label:SetPoint("RIGHT")
  section.spares:SetScript("OnClick", function() Panel.show("spares") end)

  local line = section:CreateTexture(nil, "ARTWORK")
  line:SetColorTexture(Skin.LINE[1], Skin.LINE[2], Skin.LINE[3], Skin.LINE[4])
  line:SetHeight(1)
  line:SetPoint("LEFT", label, "RIGHT", 8, 0)
  section.line = line
end

local laterSections = {}

-- A later section's heading: the label, and the line to the right edge.
local function laterSection(index)
  local heading = laterSections[index]
  if heading then return heading end
  heading = CreateFrame("Frame", nil, rosterView.content)
  heading:SetHeight(SECTION)
  heading.label = sectionLabel(heading)
  local line = heading:CreateTexture(nil, "ARTWORK")
  line:SetColorTexture(Skin.LINE[1], Skin.LINE[2], Skin.LINE[3], Skin.LINE[4])
  line:SetHeight(1)
  line:SetPoint("LEFT", heading.label, "RIGHT", 8, 0)
  line:SetPoint("RIGHT", -INSET, 0)
  laterSections[index] = heading
  return heading
end

-- count is the open Spares you could use.
local function drawSection(count)
  if not section then createSection() end
  for _, sort in ipairs(SORTS) do
    if sort[1] == order then section.sort.label:SetText("Sort: " .. sort[2]) end
  end
  section.sort:SetWidth(section.sort.label:GetStringWidth() + section.sort.iconRoom + 16)
  section.spares.label:SetText(count == 1 and "1 Spare for you"
    or ("%d Spares for you"):format(count))
  section.spares:SetWidth(section.spares.label:GetStringWidth())
  section.spares:SetShown(count > 0)
  section.line:SetPoint("RIGHT", count > 0 and section.spares or section.sort, "LEFT", -8, 0)
end

-- The sidebar: Roster, Feed, Goals, When, Spares, Professions and Together on top, Settings and
-- the addon's version at the bottom, as plain labels. The selected one's
-- chip marks it.
local function navButton(label, onClick)
  local button = CreateFrame("Button", nil, frame.sidebar)
  button:SetHeight(NAV_HEIGHT)
  -- The selected tab and the hovered one get a light chip, inset from
  -- the sidebar's edges.
  button.selected = Skin.chip(button, { 1, 1, 1, 0.08 }, NAV_CHIP_X, NAV_CHIP_Y, NAV_CHIP_RADIUS)
  Skin.chip(button, { 1, 1, 1, 0.04 }, NAV_CHIP_X, NAV_CHIP_Y, NAV_CHIP_RADIUS, "HIGHLIGHT")
  button.label = Skin.label(button, "text", MUTED)
  button.label:SetPoint("LEFT", NAV_CHIP_X + 10, 0)
  button.label:SetText(label)
  button:SetScript("OnClick", onClick)
  return button
end

local function setSelected(button, selected)
  button.selected:SetShown(selected)
  Skin.color(button.label, selected and TEXT or MUTED)
end

local function createNav()
  nav = {}
  local function open(name)
    return function()
      tab = name
      Panel.refresh()
    end
  end
  nav.roster = navButton("Roster", open("roster"))
  nav.roster:SetPoint("TOPLEFT", 0, -8)
  nav.roster:SetPoint("TOPRIGHT", 0, -8)
  nav.feed = navButton("Feed", open("feed"))
  nav.feed:SetPoint("TOPLEFT", nav.roster, "BOTTOMLEFT")
  nav.feed:SetPoint("TOPRIGHT", nav.roster, "BOTTOMRIGHT")
  nav.feed.badge = Skin.badge(nav.feed, "tiny", { 0.1, 0.08, 0 }, GOLD)
  nav.feed.badge:SetPoint("RIGHT", -10, 0)
  nav.goals = navButton("Trophies", open("goals"))
  nav.goals:SetPoint("TOPLEFT", nav.feed, "BOTTOMLEFT")
  nav.goals:SetPoint("TOPRIGHT", nav.feed, "BOTTOMRIGHT")
  nav.when = navButton("Play Times", open("when"))
  nav.when:SetPoint("TOPLEFT", nav.goals, "BOTTOMLEFT")
  nav.when:SetPoint("TOPRIGHT", nav.goals, "BOTTOMRIGHT")
  nav.spares = navButton("Spare Items", open("spares"))
  nav.spares:SetPoint("TOPLEFT", nav.when, "BOTTOMLEFT")
  nav.spares:SetPoint("TOPRIGHT", nav.when, "BOTTOMRIGHT")
  nav.spares.badge = Skin.badge(nav.spares, "tiny", { 0.1, 0.08, 0 }, GOLD)
  nav.spares.badge:SetPoint("RIGHT", -10, 0)
  nav.professions = navButton("Professions", open("professions"))
  nav.professions:SetPoint("TOPLEFT", nav.spares, "BOTTOMLEFT")
  nav.professions:SetPoint("TOPRIGHT", nav.spares, "BOTTOMRIGHT")
  nav.together = navButton("Dungeons", open("together"))
  nav.together:SetPoint("TOPLEFT", nav.professions, "BOTTOMLEFT")
  nav.together:SetPoint("TOPRIGHT", nav.professions, "BOTTOMRIGHT")
  -- The panel steps aside so it doesn't cover the settings.
  nav.settings = navButton("Settings", function()
    if ns.Settings.open() then frame:Hide() end
  end)
  nav.settings:SetPoint("BOTTOMLEFT", 0, 22)
  nav.settings:SetPoint("BOTTOMRIGHT", 0, 22)
  nav.version = Skin.label(frame.sidebar, "tiny", DIM)
  nav.version:SetPoint("BOTTOMLEFT", NAV_CHIP_X + 10, 10)
  nav.version:SetText(ns.VERSION)
end

-- unseen counts the Feed's unseen entries, and sparesUnseen the
-- Spare notices not yet shown.
local function drawNav(unseen, sparesUnseen)
  if not nav then createNav() end
  setSelected(nav.roster, tab == "roster")
  setSelected(nav.feed, tab == "feed")
  setSelected(nav.goals, tab == "goals")
  setSelected(nav.when, tab == "when")
  setSelected(nav.spares, tab == "spares")
  setSelected(nav.professions, tab == "professions")
  setSelected(nav.together, tab == "together")
  setSelected(nav.settings, false)
  nav.feed.badge:SetText(unseen)
  nav.feed.badge:SetShown(unseen > 0 and tab ~= "feed")
  nav.spares.badge:SetText(sparesUnseen)
  nav.spares.badge:SetShown(sparesUnseen > 0 and tab ~= "spares")
end

-- A scroll frame that scrolls with the mouse wheel, with a thin thumb on
-- the right showing where you are. view.content is what scrolls.
local function updateThumb(view)
  local range = view:GetVerticalScrollRange()
  local thumb = view.thumb
  if range <= 0 then
    view:SetVerticalScroll(0)
    thumb:Hide()
    return
  end
  if view:GetVerticalScroll() > range then view:SetVerticalScroll(range) end
  local visible = view:GetHeight()
  local height = math.max(24, visible * visible / (visible + range))
  thumb:SetHeight(height)
  thumb:ClearAllPoints()
  thumb:SetPoint("TOPRIGHT", view, "TOPRIGHT", 4, -(visible - height) * view:GetVerticalScroll() / range)
  thumb:Show()
end

local function scroll(view, delta)
  local range = view:GetVerticalScrollRange()
  view:SetVerticalScroll(math.min(range, math.max(0, view:GetVerticalScroll() - delta * SCROLL_STEP)))
  updateThumb(view)
end

local function createScrollView()
  local view = CreateFrame("ScrollFrame", nil, frame.content)
  view:EnableMouseWheel(true)
  view:SetScript("OnMouseWheel", scroll)
  view.content = CreateFrame("Frame", nil, view)
  view.content:SetSize(listWidth(), 1)
  view:SetScrollChild(view.content)
  -- Rows anchor to the content, so they stretch with the window, live.
  view:SetScript("OnSizeChanged", function(self, width)
    self.content:SetWidth(width)
    updateThumb(self)
  end)
  view.thumb = view:CreateTexture(nil, "OVERLAY")
  view.thumb:SetColorTexture(1, 1, 1, 0.18)
  view.thumb:SetWidth(3)
  return view
end

-- The Feed: a timeline, newest first.
local function createFeedView()
  feedView = createScrollView()
  feedView:SetPoint("TOPLEFT")
  feedView:SetPoint("BOTTOMRIGHT", -6, 0)

  feedView.line = feedView.content:CreateTexture(nil, "BACKGROUND")
  feedView.line:SetColorTexture(1, 1, 1, 0.08)
  feedView.line:SetWidth(2)
  feedView.days = {}
  feedView.entries = {}

  -- An empty Feed: a short stretch of the timeline with one faint node,
  -- centred in the view, and what will show up beside it.
  local empty = CreateFrame("Frame", nil, feedView)
  empty:SetPoint("LEFT")
  empty:SetPoint("RIGHT")
  empty:SetHeight(FEED_EMPTY_LINE)
  local line = empty:CreateTexture(nil, "BACKGROUND")
  line:SetColorTexture(1, 1, 1, 1)
  Skin.color(line, Skin.TRACK)
  line:SetWidth(2)
  line:SetPoint("TOPLEFT", LINE_X, 0)
  line:SetPoint("BOTTOMLEFT", LINE_X, 0)
  local node = Skin.feedPicture(empty, NODE)
  node:SetPoint("LEFT", INSET, 0)
  node:SetPicture(Skin.FEED_PICTURES.ding)
  node.picture:SetDesaturated(true)
  node.picture:SetAlpha(0.5)
  local title = Skin.label(empty, "heading", TEXT)
  title:SetPoint("BOTTOMLEFT", node, "RIGHT", 10, 1)
  title:SetText(FEED_EMPTY_TITLE)
  local text = Skin.label(empty, "small", MUTED)
  text:SetPoint("TOPLEFT", node, "RIGHT", 10, -3)
  text:SetText(FEED_EMPTY)
  feedView.empty = empty
  feedView.emptyText = text
end

-- A day's label, like the Roster's CREW: on the window's colour so the
-- timeline's line stops behind it, with a hairline running to the right.
local function createFeedDay()
  local day = CreateFrame("Frame", nil, feedView.content)
  day:SetHeight(16)
  day.back = Skin.fill(day, { Skin.WINDOW[1], Skin.WINDOW[2], Skin.WINDOW[3], 1 })
  day.label = Skin.label(day, "label", DIM)
  day.label:SetPoint("LEFT", 4, 0)
  day.back:ClearAllPoints()
  day.back:SetPoint("TOPLEFT")
  day.back:SetPoint("BOTTOMLEFT")
  day.back:SetPoint("RIGHT", day.label, "RIGHT", 4, 0)
  local line = day:CreateTexture(nil, "ARTWORK")
  line:SetColorTexture(Skin.LINE[1], Skin.LINE[2], Skin.LINE[3], Skin.LINE[4])
  line:SetHeight(1)
  line:SetPoint("LEFT", day.label, "RIGHT", 8, 0)
  line:SetPoint("RIGHT")
  feedView.days[#feedView.days + 1] = day
  return day
end

-- An entry: the kind's picture on the line, the text, and the time under
-- it.
local function createFeedEntry()
  local entry = CreateFrame("Frame", nil, feedView.content)
  entry:SetHeight(FEED_ENTRY)
  local node = Skin.feedPicture(entry, NODE)
  node:SetPoint("TOPLEFT", INSET, -4)
  entry.node = node

  entry.text = Skin.label(entry, "text")
  entry.text:SetPoint("TOPLEFT", node, "TOPRIGHT", 10, -2)
  entry.text:SetPoint("RIGHT", -INSET - 36, 0)
  entry.text:SetWordWrap(false)
  -- New in this Feed visit: an unread dot in the margin, level with the
  -- picture's centre.
  entry.new = Skin.fill(entry, GOLD, "ARTWORK")
  entry.new:ClearAllPoints()
  entry.new:SetSize(NEW_DOT, NEW_DOT)
  entry.new:SetPoint("CENTER", node, "LEFT", -(NEW_DOT / 2 + 3), 0)
  Skin.round(entry, entry.new)
  entry.time = Skin.label(entry, "small", MUTED)
  entry.time:SetPoint("TOPLEFT", entry.text, "BOTTOMLEFT", 0, -2)
  entry.reactors = Skin.label(entry, "small", MUTED)
  entry.reactors:SetPoint("LEFT", entry.time, "RIGHT", 8, 0)
  entry.reactors:SetPoint("RIGHT", -INSET - 36, 0)
  entry.reactors:SetWordWrap(false)

  -- The Reaction button, always shown like a toast's.
  entry.react = Skin.reactionButton(entry, REACT, function(self)
    local data = self:GetParent().data
    if data and data.key and core:react(data.key) and data.reaction == "cheer" then
      Panel.cheered(data.memberId)
    end
  end)
  entry.react:SetPoint("TOPRIGHT", -INSET - 4, -4)
  feedView.entries[#feedView.entries + 1] = entry
  return entry
end

-- Who reacted, after the time: the Reaction's icon and their names, You
-- a step brighter than the others.
local function reactorsText(entry)
  if #entry.reactors == 0 then return "" end
  local names = {}
  for i, reactor in ipairs(entry.reactors) do
    names[i] = reactor.you and Skin.hex(TEXT) .. reactor.name .. "|r" or reactor.name
  end
  return Skin.reactionGlyph(entry.reaction, 12) .. " " .. table.concat(names, ", ")
end

local function drawFeedEntry(line, entry)
  line.data = entry
  line.reactors:SetText(reactorsText(entry))
  line.react:SetShown(entry.canReact)
  if entry.canReact then
    line.react:SetReaction(entry.reaction, entry.reacted)
  end
  line.node:SetKind(entry.kind, entry.icon)
  line.text:SetText(entry.text)
  Skin.color(line.text, entry.highlight and GOLD or entry.own and MUTED or TEXT)
  line.time:SetText(date("%H:%M", entry.time))
  line.new:SetShown(entry.new)
end

-- Draws the Feed, which Panel.refresh has opened (core:openFeed).
local function drawFeed(feed)
  if not feedView then createFeedView() end
  local y, dayCount, entryCount = -INSET, 0, 0
  for _, day in ipairs(feed.days) do
    dayCount = dayCount + 1
    local chip = feedView.days[dayCount] or createFeedDay()
    chip:ClearAllPoints()
    chip:SetPoint("TOPLEFT", feedView.content, "TOPLEFT", INSET - 4, y)
    chip:SetPoint("RIGHT", feedView.content, "RIGHT", -INSET, 0)
    chip.label:SetText(day.title)
    chip:Show()
    y = y - FEED_DAY
    for _, entry in ipairs(day.entries) do
      entryCount = entryCount + 1
      local line = feedView.entries[entryCount] or createFeedEntry()
      line:ClearAllPoints()
      line:SetPoint("TOPLEFT", feedView.content, "TOPLEFT", 0, y)
      line:SetPoint("RIGHT", feedView.content, "RIGHT")
      drawFeedEntry(line, entry)
      line:Show()
      y = y - FEED_ENTRY
    end
  end
  hideAll(feedView.days, dayCount + 1)
  hideAll(feedView.entries, entryCount + 1)
  feedView.emptyText:SetWidth(contentWidth() - 2 * INSET - NODE - 10)
  feedView.empty:SetShown(entryCount == 0)
  feedView.line:ClearAllPoints()
  feedView.line:SetPoint("TOPLEFT", LINE_X, -INSET - 8)
  feedView.line:SetPoint("BOTTOMLEFT", LINE_X, INSET + 8)
  feedView.line:SetShown(entryCount > 0)
  feedView.content:SetHeight(math.max(-y + INSET, 1))
  feedView:Show()
  updateThumb(feedView)
end

-- Goals: drawn by GoalsTab into a scroll view of the panel's.
local function drawGoals()
  if not goalsView then
    goalsView = createScrollView()
    goalsView:SetPoint("TOPLEFT")
    goalsView:SetPoint("BOTTOMRIGHT", -6, 0)
  end
  ns.GoalsTab.draw(goalsView, core, listWidth(), Panel.refresh)
  goalsView:Show()
  updateThumb(goalsView)
end

-- When: a menu to pick the Crew or a Member, a line saying what the
-- grid shows, the grid, a legend and a note when there's little data.
local function showWhenMenu(owner)
  MenuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateTitle("Show")
    root:CreateRadio("The Crew", function() return whenMember == nil end, function()
      whenMember = nil
      Panel.refresh()
    end)
    for _, row in ipairs(core:rows("name")) do
      local label = row.own and "You" or row.displayName or row.name
      root:CreateRadio(label, function() return whenMember == row.memberId end, function()
        whenMember = row.memberId
        Panel.refresh()
      end)
    end
  end)
end

-- A cell's shade: faint when 0, then more gold the more it holds.
local function shadeCell(cell, value, max)
  if value <= 0 or max <= 0 then
    cell.texture:SetColorTexture(1, 1, 1, 0.05)
  else
    cell.texture:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.2 + 0.8 * math.min(value / max, 1))
  end
end

local function showCellTooltip(cell)
  local view = whenView.data
  if not view then return end
  local value = view.grid[cell.day][cell.hour]
  GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
  GameTooltip:AddLine(("%s %02d:00-%02d:00"):format(DAY_NAMES[cell.day], cell.hour - 1, cell.hour % 24), 1, 1, 1)
  if view.memberId then
    local who = view.own and "You" or view.displayName or "They"
    GameTooltip:AddLine(("%s played %d of the last %d weeks"):format(who, value, view.weeks),
      MUTED[1], MUTED[2], MUTED[3])
  else
    GameTooltip:AddLine(("%d of %d Members usually play"):format(value, view.max), MUTED[1], MUTED[2], MUTED[3])
  end
  GameTooltip:Show()
end

local function createWhenView()
  whenView = CreateFrame("Frame", nil, frame.content)
  whenView:SetAllPoints()

  whenView.pick = CreateFrame("Button", nil, whenView)
  whenView.pick:SetHeight(SMALL_BUTTON)
  whenView.pick:SetPoint("TOPLEFT", INSET, -INSET)
  Skin.fill(whenView.pick, Skin.SECONDARY)
  Skin.border(whenView.pick, Skin.BORDER)
  Skin.fill(whenView.pick, Skin.HOVER, "HIGHLIGHT")
  whenView.pick.label = Skin.label(whenView.pick, "small", TEXT)
  whenView.pick.iconRoom = Skin.leadIcon(whenView.pick, "filter", TEXT)
  whenView.pick:SetScript("OnClick", showWhenMenu)

  whenView.intro = Skin.label(whenView, "small", MUTED)
  whenView.intro:SetPoint("TOPLEFT", whenView.pick, "BOTTOMLEFT", 0, -8)
  whenView.intro:SetWordWrap(true)
  whenView.intro:SetJustifyH("LEFT")

  whenView.hours = {}
  for hour = 0, 21, 3 do
    local label = Skin.label(whenView, "tiny", DIM)
    label:SetText(("%02d"):format(hour))
    label.hour = hour
    whenView.hours[#whenView.hours + 1] = label
  end
  whenView.days = {}
  whenView.cells = {}
  for day = 1, 7 do
    local label = Skin.label(whenView, "small", MUTED)
    label:SetText(DAY_NAMES[day])
    whenView.days[day] = label
    for hour = 1, 24 do
      local cell = CreateFrame("Frame", nil, whenView)
      cell.texture = cell:CreateTexture(nil, "ARTWORK")
      cell.texture:SetAllPoints()
      cell.day, cell.hour = day, hour
      cell:EnableMouse(true)
      cell:SetScript("OnEnter", showCellTooltip)
      cell:SetScript("OnLeave", hideTooltip)
      whenView.cells[#whenView.cells + 1] = cell
    end
  end

  whenView.legendLow = Skin.label(whenView, "tiny", DIM)
  whenView.legend = {}
  local anchor = whenView.legendLow
  for i = 1, 4 do
    local swatch = whenView:CreateTexture(nil, "ARTWORK")
    swatch:SetSize(WHEN_CELL - 1, WHEN_ROW - 2)
    swatch:SetPoint("LEFT", anchor, "RIGHT", i == 1 and 6 or 1, 0)
    whenView.legend[i] = { texture = swatch }
    anchor = swatch
  end
  whenView.legendHigh = Skin.label(whenView, "tiny", DIM)
  whenView.legendHigh:SetPoint("LEFT", anchor, "RIGHT", 6, 0)

  whenView.note = Skin.label(whenView, "small", MUTED)
  whenView.note:SetWordWrap(true)
  whenView.note:SetJustifyH("LEFT")
end

-- Sizes the grid to fill the view at the window's current size, in whole
-- pixels, and hangs the legend and note below it.
local function placeWhenGrid()
  local cellWidth = math.max(WHEN_CELL, math.floor((contentWidth() - 2 * INSET - WHEN_DAYS) / 24))
  local rowHeight = math.max(WHEN_ROW, math.floor((contentHeight() + WHEN_TOP - WHEN_BELOW) / 7))
  for _, label in ipairs(whenView.hours) do
    label:SetPoint("BOTTOMLEFT", whenView, "TOPLEFT", INSET + WHEN_DAYS + label.hour * cellWidth, WHEN_TOP + 2)
  end
  for day, label in ipairs(whenView.days) do
    label:SetPoint("LEFT", whenView, "TOPLEFT", INSET, WHEN_TOP - (day - 1) * rowHeight + 1 - math.floor(rowHeight / 2))
  end
  for _, cell in ipairs(whenView.cells) do
    cell:SetSize(cellWidth - 1, rowHeight - 2)
    cell:SetPoint("TOPLEFT", INSET + WHEN_DAYS + (cell.hour - 1) * cellWidth, WHEN_TOP - (cell.day - 1) * rowHeight)
  end
  local below = WHEN_TOP - 7 * rowHeight - 10
  whenView.legendLow:SetPoint("TOPLEFT", INSET + WHEN_DAYS, below)
  whenView.note:SetPoint("TOPLEFT", INSET, below - 24)
end

local function drawWhen()
  if not whenView then createWhenView() end
  local view = whenMember and core:playTimes(whenMember)
  if not view then
    whenMember = nil
    view = core:playTimes()
  end
  whenView.data = view
  whenView.pick.label:SetText("Show: " .. view.title)
  whenView.pick:SetWidth(whenView.pick.label:GetStringWidth() + whenView.pick.iconRoom + 16)
  whenView.intro:SetWidth(contentWidth() - 2 * INSET)
  whenView.intro:SetText(view.intro)
  whenView.note:SetWidth(contentWidth() - 2 * INSET)
  whenView.note:SetText(view.note or "")
  placeWhenGrid()
  for _, cell in ipairs(whenView.cells) do
    shadeCell(cell, view.grid[cell.day][cell.hour], view.max)
  end
  whenView.legendLow:SetText(view.memberId and "0" or "None")
  whenView.legendHigh:SetText(view.memberId and ("%d weeks"):format(view.weeks) or "Everyone")
  for i, swatch in ipairs(whenView.legend) do
    shadeCell(swatch, i - 1, 3)
  end
  if GameTooltip:GetOwner() and GameTooltip:GetOwner():GetParent() == whenView then
    showCellTooltip(GameTooltip:GetOwner())
  end
  whenView:Show()
end

-- Spares: From the Crew, then Yours, each under a heading, in one
-- scrolling list.
local getItemIcon = C_Item and C_Item.GetItemIconByID or GetItemIcon

StaticPopupDialogs.BFF_GIVE_SPARE = {
  text = "Give %s to %s? Do this once you've mailed it: BFF only tells the Crew.",
  button1 = YES,
  button2 = NO,
  OnAccept = function(_, data)
    local ok, reason = core:giveSpare(data.id, data.winner)
    if not ok then ns.say(ns.MESSAGES[reason]) end
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
}

-- Places a heading or row across the list, at y from its top.
local function placeSpare(line, y)
  line:ClearAllPoints()
  line:SetPoint("TOPLEFT", sparesView.content, "TOPLEFT", 0, y)
  line:SetPoint("TOPRIGHT", sparesView.content, "TOPRIGHT", 0, y)
end

-- An item dropped on the drop slot, or a click on it while holding one:
-- a click with an item on the cursor may arrive as either, so both do the
-- same. The item always goes back to its bag slot.
local function onSpareDrop()
  if not GetCursorInfo() then return end
  ns.sayPosted(ns.Bags.postFromCursor(core))
end

-- The drop slot: an empty item slot with a line saying what it's for.
local function createSpareDrop(parent)
  local drop = CreateFrame("Button", nil, parent)
  drop:SetHeight(SPARE_ROW)
  Skin.fill(drop, Skin.HOVER, "HIGHLIGHT")
  drop.slot = CreateFrame("Frame", nil, drop)
  drop.slot:SetSize(SPARE_ICON, SPARE_ICON)
  drop.slot:SetPoint("LEFT", INSET, 0)
  Skin.fill(drop.slot, Skin.RAISED)
  Skin.border(drop.slot)
  drop.plus = Skin.label(drop.slot, "body", DIM)
  drop.plus:SetPoint("CENTER")
  drop.plus:SetText("+")
  drop.label = Skin.label(drop, "body", MUTED)
  drop.label:SetPoint("LEFT", drop.slot, "RIGHT", 8, 0)
  drop.label:SetPoint("RIGHT", -INSET, 0)
  drop.label:SetText(SPARES_DROP)
  drop:SetScript("OnReceiveDrag", onSpareDrop)
  drop:SetScript("OnClick", onSpareDrop)
  return drop
end

local function createSparesView()
  sparesView = createScrollView()
  sparesView:SetPoint("TOPLEFT")
  sparesView:SetPoint("BOTTOMRIGHT", -6, 0)
  sparesView.headings = {}
  sparesView.rows = {}
  sparesView.notes = {}
  sparesView.drop = createSpareDrop(sparesView.content)
end

-- "FROM THE CREW ————— 2 of 20 Claims".
local function spareHeading(index)
  local heading = sparesView.headings[index]
  if heading then return heading end
  heading = CreateFrame("Frame", nil, sparesView.content)
  heading:SetHeight(SPARE_SECTION)
  heading.label = Skin.label(heading, "label", DIM)
  heading.label:SetPoint("LEFT", INSET, -2)
  heading.count = Skin.label(heading, "small", MUTED)
  heading.count:SetPoint("RIGHT", -INSET, -2)
  heading.line = heading:CreateTexture(nil, "ARTWORK")
  heading.line:SetColorTexture(Skin.LINE[1], Skin.LINE[2], Skin.LINE[3], Skin.LINE[4])
  heading.line:SetHeight(1)
  heading.line:SetPoint("LEFT", heading.label, "RIGHT", 8, 0)
  heading.line:SetPoint("RIGHT", heading.count, "LEFT", -8, 0)
  sparesView.headings[index] = heading
  return heading
end

-- A line of muted text in the list: no Spares yet, or how to post one.
local function spareNote(index)
  local note = sparesView.notes[index]
  if note then return note end
  note = Skin.label(sparesView.content, "small", MUTED)
  note:SetWordWrap(true)
  sparesView.notes[index] = note
  return note
end

local function showItemTooltip(row)
  if not row.data then return end
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  GameTooltip:SetHyperlink(row.data.item)
  GameTooltip:Show()
end

-- Claims for one of your Characters, saying why not if it can't.
local function claim(data, guid)
  local ok, reason = core:claimSpare(data.ownerId, data.id, guid)
  if not ok then ns.say(ns.MESSAGES[reason]) end
end

-- Right-click Claim: pick which of your Characters it's for.
local function showClaimMenu(owner, data)
  local claimFor = sparesView.claimFor
  if not claimFor or #claimFor == 0 then return end
  MenuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateTitle("Claim it for")
    for _, character in ipairs(claimFor) do
      root:CreateButton(character.label, function() claim(data, character.guid) end)
    end
  end)
end

-- The buttons: Claim (left-click for the Character you play, right-click
-- to pick one) or Withdraw your Claim on the Crew's; Give and Withdraw on
-- yours.
local function onSparePrimary(button, mouse)
  local row = button:GetParent()
  local data = row.data
  if not data then return end
  if row.yours then
    StaticPopup_Show("BFF_GIVE_SPARE", data.link or "it",
      data.winner and ("%s (%s)"):format(data.winner.name, data.winner.character) or "?",
      { id = data.id, winner = data.winner and data.winner.memberId })
  elseif mouse == "RightButton" then
    showClaimMenu(button, data)
  else
    claim(data)
  end
end

local function onSpareSecondary(button)
  local row = button:GetParent()
  local data = row.data
  if not data then return end
  local ok, reason
  if row.yours then
    ok, reason = core:withdrawSpare(data.id)
  else
    ok, reason = core:withdrawClaim(data.ownerId, data.id)
  end
  if not ok then ns.say(ns.MESSAGES[reason]) end
end

local function createSpareRow()
  local row = CreateFrame("Button", nil, sparesView.content)
  row:SetHeight(SPARE_ROW)
  Skin.fill(row, Skin.HOVER, "HIGHLIGHT")
  -- Shift-click puts the link in the chat box, like any item.
  row:SetScript("OnClick", function(self)
    local insertLink = ChatFrameUtil and ChatFrameUtil.InsertLink or ChatEdit_InsertLink
    if self.data and self.data.link and insertLink and IsModifiedClick("CHATLINK") then insertLink(self.data.link) end
  end)
  row:SetScript("OnEnter", showItemTooltip)
  row:SetScript("OnLeave", hideTooltip)

  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(SPARE_ICON, SPARE_ICON)
  row.icon:SetPoint("TOPLEFT", INSET, -8)
  row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  row.primary = Skin.button(row, "Claim", onSparePrimary, true)
  row.primary:SetSize(SPARE_BUTTON, SMALL_BUTTON)
  row.primary:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  row.secondary = Skin.button(row, "Withdraw", onSpareSecondary)
  row.secondary:SetSize(SPARE_BUTTON, SMALL_BUTTON)

  row.item = Skin.label(row, "body")
  row.item:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 1)
  row.item:SetWordWrap(false)
  row.level = Skin.badge(row)
  row.info = Skin.label(row, "small", MUTED)
  row.info:SetPoint("TOPLEFT", row.item, "BOTTOMLEFT", 0, -3)
  row.info:SetWordWrap(false)
  sparesView.rows[#sparesView.rows + 1] = row
  return row
end

-- Places the buttons shown at the right. Returns the width left for the
-- text.
local function placeSpareButtons(row, primary, secondary)
  row.primary:SetShown(primary ~= nil)
  row.secondary:SetShown(secondary ~= nil)
  local anchor
  for _, pair in ipairs({ { row.primary, primary }, { row.secondary, secondary } }) do
    local button, text = pair[1], pair[2]
    if text then
      button:SetText(text)
      button:ClearAllPoints()
      if anchor then
        button:SetPoint("RIGHT", anchor, "LEFT", -4, 0)
      else
        button:SetPoint("RIGHT", row, "RIGHT", -INSET, 0)
      end
      anchor = button
    end
  end
  local buttons = (primary and SPARE_BUTTON + 4 or 0) + (secondary and SPARE_BUTTON + 4 or 0)
  return listWidth() - 2 * INSET - SPARE_ICON - 8 - buttons - 4
end

-- The item's link, then its required level on a badge, then a line under
-- them, all short of the buttons (width).
local function drawSpareText(row, data, width)
  row.item:SetWidth(0)
  row.item:SetText(data.link or "Loading...")
  row.item:SetWidth(math.min(row.item:GetStringWidth() + 1, width - 30))
  row.level:SetShown(data.level > 0)
  row.level:SetText(data.level)
  row.level:ClearAllPoints()
  row.level:SetPoint("LEFT", row.item, "RIGHT", 6, 0)
  row.info:SetWidth(width)
end

-- Draws a row as Core words it. A Given Spare of yours dims less than
-- one of the Crew's you can't use.
local function drawSpareRow(row, data, yours)
  row.data, row.yours = data, yours
  row.icon:SetTexture(getItemIcon and getItemIcon(data.item) or QUESTION_MARK)
  row.info:SetText(data.info)
  Skin.color(row.info, data.highlight and GOLD or MUTED)
  drawSpareText(row, data, placeSpareButtons(row, data.primary and data.primary.label,
    data.secondary and data.secondary.label))
  if data.primary then row.primary:SetEnabled(data.primary.enabled) end
  row:SetAlpha(data.dimmed and (yours and 0.6 or 0.45) or 1)
  row:Show()
end

local function drawSpares()
  if not sparesView then createSparesView() end
  local view = core:spares()
  sparesView.claimFor = view.claimFor
  local y, headings, rows, notes = -4, 0, 0, 0
  local function heading(text, count)
    headings = headings + 1
    local item = spareHeading(headings)
    placeSpare(item, y)
    item.label:SetText(text)
    item.count:SetText(count)
    item:Show()
    y = y - SPARE_SECTION
  end
  local function note(text)
    notes = notes + 1
    local item = spareNote(notes)
    item:ClearAllPoints()
    item:SetPoint("TOPLEFT", sparesView.content, "TOPLEFT", INSET, y - 2)
    item:SetWidth(listWidth() - 2 * INSET)
    item:SetText(text)
    item:Show()
    y = y - item:GetStringHeight() - 12
  end
  local function list(data, yours)
    for _, item in ipairs(data) do
      rows = rows + 1
      local row = sparesView.rows[rows] or createSpareRow()
      placeSpare(row, y)
      drawSpareRow(row, item, yours)
      y = y - SPARE_ROW
    end
  end

  heading("FROM THE CREW", ("%d of %d Claims"):format(view.claims, view.maxClaims))
  if #view.crew == 0 then note(SPARES_NONE) end
  list(view.crew, false)
  y = y - 6
  heading("YOURS", ("%d of %d up"):format(view.open, view.maxOpen))
  placeSpare(sparesView.drop, y)
  y = y - SPARE_ROW
  list(view.yours, true)
  note(SPARES_HOW)

  hideAll(sparesView.headings, headings + 1)
  hideAll(sparesView.rows, rows + 1)
  hideAll(sparesView.notes, notes + 1)
  sparesView.content:SetHeight(-y + 6)
  sparesView:Show()
  updateThumb(sparesView)
  if view.unseen > 0 then core:sparesSeen() end
end

-- Professions: the column icons on top, then a scrolling row per Member.
-- Clicking an icon sorts by that profession (again: back to the Roster's
-- order).
local professionSort
local drawProfessions

local function showProfessionTooltip(owner)
  if not owner.tooltip then return end
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  owner.tooltip(owner)
  GameTooltip:Show()
end

local function hoverable(parent)
  local item = CreateFrame("Frame", nil, parent)
  item:EnableMouse(true)
  item:SetScript("OnEnter", function(self)
    if self.column then
      professionsView.columnWash:ClearAllPoints()
      professionsView.columnWash:SetPoint("TOPLEFT", professionsView.list.content, "TOPLEFT", self.x, 0)
      professionsView.columnWash:SetPoint("BOTTOMLEFT", professionsView.list.content, "BOTTOMLEFT", self.x, 0)
      professionsView.columnWash:SetWidth(self.width)
      professionsView.columnWash:Show()
    end
    if self.row then self.row.hover:Show() end
    showProfessionTooltip(self)
  end)
  item:SetScript("OnLeave", function(self)
    professionsView.columnWash:Hide()
    if self.row then self.row.hover:Hide() end
    hideTooltip()
  end)
  return item
end

local function createProfessionsView()
  professionsView = CreateFrame("Frame", nil, frame.content)
  professionsView:SetAllPoints()
  professionsView.head = CreateFrame("Frame", nil, professionsView)
  professionsView.head:SetPoint("TOPLEFT")
  professionsView.head:SetPoint("TOPRIGHT")
  professionsView.head:SetHeight(PROFESSION_HEAD)
  Skin.edge(professionsView.head, "BOTTOM", Skin.LINE)
  professionsView.icons = {}
  professionsView.sortMark = Skin.fill(professionsView.head, TEXT, "ARTWORK")
  professionsView.sortMark:ClearAllPoints()
  professionsView.sortMark:SetSize(PROFESSION_ICON, 2)
  professionsView.divider = professionsView:CreateTexture(nil, "ARTWORK")
  professionsView.divider:SetColorTexture(Skin.LINE[1], Skin.LINE[2], Skin.LINE[3], Skin.LINE[4])
  professionsView.divider:SetWidth(1)
  professionsView.list = createScrollView()
  professionsView.list:SetParent(professionsView)
  professionsView.list:SetPoint("TOPLEFT", 0, -PROFESSION_HEAD)
  professionsView.list:SetPoint("BOTTOMRIGHT", -6, 0)
  professionsView.columnWash = Skin.fill(professionsView.list.content, Skin.HOVER, "BORDER")
  professionsView.columnWash:Hide()
  professionsView.rows = {}
end

-- Where each column starts, from the left, how wide a tile is and how
-- wide the name column is. Twelve tiles fit at 18px at the smallest
-- window; more shrink them. A wider window grows the name column up to
-- its most, then the tiles take the rest, so the grid always fills it.
local function professionColumns(professions)
  local divider = 0
  for _, p in ipairs(professions) do
    if p.secondary then divider = PROFESSION_DIVIDER end
  end
  local count = math.max(#professions, 1)
  local room = listWidth() - INSET - divider
  local name = math.max(PROFESSION_NAME,
    math.min(PROFESSION_NAME_MAX, room - count * (PROFESSION_TILE + PROFESSION_GAP)))
  local width = math.floor((room - name) / count) - PROFESSION_GAP
  local xs, dividerX = {}, nil
  local x = INSET + name
  for i, p in ipairs(professions) do
    if p.secondary and not dividerX then
      dividerX = x + PROFESSION_DIVIDER / 2 - 1
      x = x + PROFESSION_DIVIDER
    end
    xs[i] = x
    x = x + width + PROFESSION_GAP
  end
  return xs, width, dividerX, name
end

local function iconTooltip(icon)
  local p = icon.profession
  GameTooltip:AddLine(p.name, 1, 1, 1)
  local count = 0
  for _, member in ipairs(professionsView.data.members) do
    if member.cells[icon.index] then count = count + 1 end
  end
  local text = count == 0 and "Nobody in the Crew has it yet"
    or ("%d Member%s %s it"):format(count, count == 1 and "" or "s", count == 1 and "has" or "have")
  GameTooltip:AddLine(text, MUTED[1], MUTED[2], MUTED[3])
  GameTooltip:AddLine(professionSort == p.skillLine and "Click to sort as the Roster" or "Click to sort by it",
    DIM[1], DIM[2], DIM[3])
end

local function professionIcon(index)
  local icon = professionsView.icons[index]
  if icon then return icon end
  icon = hoverable(professionsView.head)
  icon:SetSize(PROFESSION_ICON, PROFESSION_ICON)
  icon.texture = icon:CreateTexture(nil, "ARTWORK")
  icon.texture:SetAllPoints()
  icon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  icon.tooltip = iconTooltip
  icon:SetScript("OnMouseUp", function(self)
    professionSort = professionSort ~= self.profession.skillLine and self.profession.skillLine or nil
    drawProfessions()
    if GameTooltip:IsOwned(self) then showProfessionTooltip(self) end
  end)
  professionsView.icons[index] = icon
  return icon
end

-- A tile's tooltip: the profession, then each of the Member's Characters who
-- have it, with rank and skill/max.
local function tileTooltip(tile)
  local member, profession = tile.member, tile.profession
  GameTooltip:AddLine(profession.name, 1, 1, 1)
  local cell = member.cells[tile.index]
  if not cell then
    local who = member.own and "You don't" or ("%s doesn't"):format(member.displayName or "They")
    GameTooltip:AddLine(who .. " have it", MUTED[1], MUTED[2], MUTED[3])
    return
  end
  for _, character in ipairs(cell.characters) do
    local skill = ("%d/%d"):format(character.skill, character.max)
    if character.rank then skill = Skin.hex(MUTED) .. character.rank .. "|r " .. skill end
    local r, g, b = classColor(character.classFilename)
    GameTooltip:AddDoubleLine(character.name, skill, r, g, b, TEXT[1], TEXT[2], TEXT[3])
  end
end

-- A tile: the skill on a wash by rank, and a 2px skill/max bar under it.
local function professionTile(row, index)
  local tile = row.tiles[index]
  if tile then return tile end
  tile = hoverable(row)
  tile.row = row
  tile.column = true
  tile.tooltip = tileTooltip
  tile.plate = tile:CreateTexture(nil, "ARTWORK")
  tile.plate:SetPoint("TOPLEFT")
  tile.plate:SetPoint("TOPRIGHT")
  tile.plate:SetHeight(PROFESSION_TILE)
  tile.value = Skin.label(tile, "tiny")
  tile.value:SetPoint("CENTER", tile.plate, "CENTER", 0, 0)
  tile.track = Skin.fill(tile, Skin.TRACK, "ARTWORK")
  tile.track:ClearAllPoints()
  tile.track:SetPoint("BOTTOMLEFT")
  tile.track:SetPoint("BOTTOMRIGHT")
  tile.track:SetHeight(PROFESSION_BAR)
  tile.bar = Skin.fill(tile, Skin.BAR, "OVERLAY")
  tile.bar:ClearAllPoints()
  tile.bar:SetPoint("BOTTOMLEFT")
  tile.bar:SetHeight(PROFESSION_BAR)
  row.tiles[index] = tile
  return tile
end

local function drawProfessionTile(tile, cell, width)
  -- The tile, 2px of gap, then the bar.
  tile:SetSize(width, PROFESSION_TILE + 2 + PROFESSION_BAR)
  tile.width = width
  local shade = not cell and Skin.TILE_NONE or cell.capped and Skin.TILE_CAPPED
    or Skin.RANK_SHADES[cell.rank] or Skin.RANK_SHADES.Apprentice
  tile.plate:SetColorTexture(shade[1], shade[2], shade[3], shade[4])
  tile.value:SetShown(cell ~= false)
  tile.track:SetShown(cell ~= false)
  tile.bar:SetShown(cell ~= false and cell.skill > 0)
  if cell then
    tile.value:SetText(cell.skill)
    Skin.color(tile.value, cell.capped and Skin.WINDOW or TEXT)
    tile.bar:SetWidth(math.max(1, width * math.min(cell.skill / cell.max, 1)))
  end
  tile:Show()
end

local function professionRow(index)
  local row = professionsView.rows[index]
  if row then return row end
  row = CreateFrame("Frame", nil, professionsView.list.content)
  row:SetHeight(PROFESSION_ROW)
  row.ownBackground = Skin.fill(row, { GOLD[1], GOLD[2], GOLD[3], 0.05 })
  row.hover = Skin.fill(row, Skin.HOVER, "BORDER")
  row.hover:Hide()
  row.edge = Skin.edge(row, "TOP", Skin.LINE)
  row.name = Skin.label(row, "body")
  row.name:SetPoint("LEFT", INSET, 0)
  row.name:SetWordWrap(false)
  row.unknown = Skin.label(row, "small", MUTED)
  row.unknown:SetText("Not shared yet")
  row.tiles = {}
  professionsView.rows[index] = row
  return row
end

function drawProfessions()
  if not professionsView then createProfessionsView() end
  local view = core:professions(order, professionSort)
  professionsView.data = view
  local xs, width, dividerX, nameWidth = professionColumns(view.professions)

  for i, p in ipairs(view.professions) do
    local icon = professionIcon(i)
    icon.profession, icon.index = p, i
    icon:ClearAllPoints()
    icon:SetPoint("TOPLEFT", professionsView.head, "TOPLEFT", xs[i] + (width - PROFESSION_ICON) / 2, -5)
    icon.texture:SetTexture(p.icon or QUESTION_MARK)
    -- Nobody has it: desaturated at 55%, as an unused Reaction.
    icon.texture:SetDesaturated(not p.had)
    icon:SetAlpha(p.had and 1 or 0.55)
    icon:Show()
  end
  hideAll(professionsView.icons, #view.professions + 1)
  local sorted
  for i, p in ipairs(view.professions) do
    if p.skillLine == professionSort then sorted = i end
  end
  professionsView.sortMark:SetShown(sorted ~= nil)
  if sorted then
    professionsView.sortMark:ClearAllPoints()
    professionsView.sortMark:SetPoint("BOTTOMLEFT", professionsView.head, "BOTTOMLEFT",
      xs[sorted] + (width - PROFESSION_ICON) / 2, 1)
  end

  local y = 0
  for i, member in ipairs(view.members) do
    local row = professionRow(i)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", professionsView.list.content, "TOPLEFT", 0, y)
    row:SetPoint("TOPRIGHT", professionsView.list.content, "TOPRIGHT", 0, y)
    row.ownBackground:SetShown(member.own)
    row.edge:SetShown(i > 1)
    row.name:SetWidth(nameWidth - 4)
    row.name:SetText(member.displayName or (member.own and "You") or "")
    row.unknown:ClearAllPoints()
    row.unknown:SetPoint("LEFT", INSET + nameWidth, 0)
    Skin.color(row.name, TEXT)
    row.unknown:SetShown(not member.known)
    for c, p in ipairs(view.professions) do
      local tile = professionTile(row, c)
      if member.known then
        tile.member, tile.profession, tile.index, tile.x = member, p, c, xs[c]
        tile:ClearAllPoints()
        tile:SetPoint("TOPLEFT", row, "TOPLEFT", xs[c], -2)
        drawProfessionTile(tile, member.cells[c], width)
      else
        tile:Hide()
      end
    end
    hideAll(row.tiles, #view.professions + 1)
    row:Show()
    y = y - PROFESSION_ROW
  end
  hideAll(professionsView.rows, #view.members + 1)

  professionsView.divider:ClearAllPoints()
  professionsView.divider:SetShown(dividerX ~= nil)
  if dividerX then
    professionsView.divider:SetPoint("TOPLEFT", professionsView, "TOPLEFT", dividerX, -4)
    professionsView.divider:SetPoint("BOTTOMLEFT", professionsView, "BOTTOMLEFT", dividerX, 4)
  end

  professionsView.list.content:SetHeight(-y + 6)
  professionsView:Show()
  updateThumb(professionsView.list)
end

-- Puts the window where Core says it opens: the player's size and
-- position, kept on this screen, or the default size, centred.
local function applyPlace()
  local saved = core:panelPlace(UIParent:GetWidth(), UIParent:GetHeight())
  frame:SetSize(saved.width, saved.height)
  frame:ClearAllPoints()
  if saved.left then
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", saved.left, saved.top)
  else
    frame:SetPoint("CENTER")
  end
end

-- Saves where a move or resize left the window. Core saves it account-wide
-- (not the game's layout cache, which is applied before the panel exists),
-- and its settingChanged redraws the views at the new size.
local function savePlace()
  frame.sizing, frame.moving = nil, nil
  frame:StopMovingOrSizing()
  frame:SetUserPlaced(false)
  core:setPanelPlace(frame:GetWidth(), frame:GetHeight(), frame:GetLeft(), frame:GetTop())
end

-- The grip in the bottom right corner: drag to resize, double-click to go
-- back to the default size, centred. Anchored parts stretch while
-- dragging; the views redraw once, when it ends.
local function createGrip()
  frame:SetResizable(true)
  local limits = ns.Core
  -- Midnight's API; older clients had the min and max calls.
  if frame.SetResizeBounds then
    frame:SetResizeBounds(limits.PANEL_MIN_WIDTH, limits.PANEL_MIN_HEIGHT,
      limits.PANEL_MAX_WIDTH, limits.PANEL_MAX_HEIGHT)
  else
    frame:SetMinResize(limits.PANEL_MIN_WIDTH, limits.PANEL_MIN_HEIGHT)
    frame:SetMaxResize(limits.PANEL_MAX_WIDTH, limits.PANEL_MAX_HEIGHT)
  end
  local grip = CreateFrame("Button", nil, frame)
  grip:SetSize(GRIP, GRIP)
  grip:SetPoint("BOTTOMRIGHT", -1, 1)
  grip:SetFrameLevel(frame:GetFrameLevel() + 10)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:SetScript("OnMouseDown", function(_, button)
    if button == "LeftButton" then
      frame.sizing = true
      frame:StartSizing("BOTTOMRIGHT")
    end
  end)
  grip:SetScript("OnMouseUp", function()
    if frame.sizing then savePlace() end
  end)
  grip:SetScript("OnDoubleClick", function() core:resetPanelPlace() end)
  grip:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Drag to resize")
    GameTooltip:AddLine("Double-click: default size, centred", MUTED[1], MUTED[2], MUTED[3])
    GameTooltip:Show()
  end)
  grip:SetScript("OnLeave", hideTooltip)
  frame.grip = grip
end

local function create()
  frame = Skin.window("BFFPanel", ns.Core.PANEL_WIDTH, TITLE)
  applyPlace()
  frame:SetScript("OnDragStart", function()
    frame.moving = true
    frame:StartMoving()
  end)
  frame:SetScript("OnDragStop", savePlace)
  createGrip()
  frame:SetScript("OnShow", Panel.refresh)
  -- A move or resize the panel closed during still saves where it got to.
  frame:SetScript("OnHide", function()
    if frame.sizing or frame.moving then savePlace() end
    core:leaveFeed()
    core:leaveGoals()
  end)
  local sinceRedraw = 0
  frame:SetScript("OnUpdate", function(_, elapsed)
    sinceRedraw = sinceRedraw + elapsed
    if sinceRedraw >= REDRAW_EVERY then
      sinceRedraw = 0
      Panel.refresh()
    end
  end)

  -- "● 2 of 3 online", left of the close button.
  frame.onlineDot = frame.header:CreateTexture(nil, "OVERLAY")
  frame.onlineDot:SetSize(6, 6)
  frame.onlineDot:SetColorTexture(1, 1, 1, 1)
  Skin.color(frame.onlineDot, ONLINE)
  Skin.round(frame.header, frame.onlineDot)
  frame.onlineDot:SetPoint("RIGHT", frame.headerRight, "LEFT", -5, 0)

  camp = ns.CampScene.new(frame)
  camp:SetPoint("TOPLEFT", 1, -HEADER)
  camp:SetPoint("TOPRIGHT", -1, -HEADER)
  Skin.edge(camp, "BOTTOM", Skin.LINE, "OVERLAY")

  frame.sidebar = CreateFrame("Frame", nil, frame)
  frame.sidebar:SetPoint("BOTTOMLEFT", 1, 1)
  frame.sidebar:SetWidth(SIDEBAR - 1)
  Skin.fill(frame.sidebar, Skin.SIDEBAR)
  Skin.edge(frame.sidebar, "RIGHT", Skin.LINE)

  frame.content = CreateFrame("Frame", nil, frame)
end

-- The Camp band, when Core has one: across the window, under the header,
-- at its full height, or the short one in a small window. Nil without a
-- Crew.
local function drawCamp(inCrew)
  local view
  if inCrew then
    local width = frame:GetWidth() - 2
    local columns, height = camp:Measure(width, frame:GetHeight() < CAMP_SMALL_UNDER and ns.CampScene.SHORT_HEIGHT or ns.CampScene.HEIGHT)
    view = core:camp(columns)
    campHeight = view and height or 0
  else
    campHeight = 0
  end
  camp:SetHeight(math.max(campHeight, 1))
  camp:Draw(view)
end

-- With a Crew the content sits right of the sidebar, under the Camp; without one it takes
-- the whole window.
local function layout(inCrew)
  drawCamp(inCrew)
  local top = -HEADER - campHeight
  frame.sidebar:SetShown(inCrew)
  frame.sidebar:ClearAllPoints()
  frame.sidebar:SetPoint("TOPLEFT", 1, top)
  frame.sidebar:SetPoint("BOTTOMLEFT", 1, 1)
  frame.content:ClearAllPoints()
  frame.content:SetPoint("TOPLEFT", inCrew and SIDEBAR or 1, top)
  frame.content:SetPoint("BOTTOMRIGHT", -1, 1)
  frame.onlineDot:SetShown(inCrew)
  if not inCrew then frame.headerRight:SetText("") end
end

-- The setup view, centred in the window: Display name, then Start a Crew
-- and Join a Crew side by side, a hairline between them.
local function createSetup()
  setup = CreateFrame("Frame", nil, frame.content)
  setup:SetSize(SETUP_WIDTH, -SETUP_COLUMNS_Y + 90)
  setup:SetPoint("CENTER", 0, 10)

  local nameLabel = Skin.label(setup, "label", DIM)
  nameLabel:SetPoint("TOPLEFT")
  nameLabel:SetText("DISPLAY NAME")
  setup.name = Skin.editBox(setup, SETUP_WIDTH)
  setup.name:SetMaxLetters(16)
  setup.name:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 0, -6)
  setup.nameError = Skin.label(setup, "small", ERROR)
  setup.nameError:SetPoint("TOPLEFT", setup.name, "BOTTOMLEFT", 0, -4)
  setup.nameError:SetWidth(SETUP_WIDTH)

  local startLabel = Skin.label(setup, "label", DIM)
  startLabel:SetPoint("TOPLEFT", 0, SETUP_COLUMNS_Y)
  startLabel:SetText("START A CREW")
  setup.start = Skin.button(setup, "Start", function()
    local _, reason = core:startCrew(setup.name:GetText())
    setup.nameError:SetText(reason and ns.MESSAGES[reason] or "")
  end, true)
  setup.start:SetWidth(SETUP_COLUMN)
  setup.start:SetPoint("TOPLEFT", startLabel, "BOTTOMLEFT", 0, -6)

  local divider = setup:CreateTexture(nil, "ARTWORK")
  divider:SetColorTexture(Skin.LINE[1], Skin.LINE[2], Skin.LINE[3], Skin.LINE[4])
  divider:SetWidth(1)
  divider:SetHeight(70)
  divider:SetPoint("TOP", setup, "TOPLEFT", SETUP_WIDTH / 2, SETUP_COLUMNS_Y)

  local joinLabel = Skin.label(setup, "label", DIM)
  joinLabel:SetPoint("TOPLEFT", SETUP_WIDTH - SETUP_COLUMN, SETUP_COLUMNS_Y)
  joinLabel:SetText("JOIN A CREW")
  setup.code = Skin.editBox(setup, SETUP_COLUMN)
  setup.code:SetMaxLetters(12)
  setup.code:SetPoint("TOPLEFT", joinLabel, "BOTTOMLEFT", 0, -6)
  local function join()
    local _, reason = core:joinCrew(setup.code:GetText(), setup.name:GetText())
    setup.nameError:SetText(reason == "invalidName" and ns.MESSAGES.invalidName or "")
    setup.codeError:SetText(reason and reason ~= "invalidName" and ns.MESSAGES[reason] or "")
  end
  setup.code:SetScript("OnEnterPressed", join)
  setup.join = Skin.button(setup, "Join", join)
  setup.join:SetWidth(SETUP_COLUMN)
  setup.join:SetPoint("TOPLEFT", setup.code, "BOTTOMLEFT", 0, -6)
  setup.codeError = Skin.label(setup, "small", ERROR)
  setup.codeError:SetPoint("TOPLEFT", setup.join, "BOTTOMLEFT", 0, -4)
  setup.codeError:SetWidth(SETUP_COLUMN)
end

local function showSetup()
  if not setup then createSetup() end
  if not setup:IsShown() then
    setup.name:SetText(ns.defaultDisplayName())
    setup.code:SetText("")
    setup.nameError:SetText("")
    setup.codeError:SetText("")
  end
  setup:Show()
end

-- Re-add a removed Member, from a menu of everyone removed.
local function showRemovedMenu(owner)
  MenuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateTitle("Removed Members")
    for _, member in ipairs(core:removed()) do
      root:CreateButton("Re-add " .. (member.displayName or "a Member without a name"), function()
        core:readdMember(member.memberId)
      end)
    end
  end)
end

-- Below the rows: the waiting, leaving or appear-offline line, then the
-- Crew code in a read-only box with the text selected (addons can't copy
-- to the clipboard), with the hidden count and removed Members right of
-- it.
local function createFooter()
  footer = CreateFrame("Frame", nil, frame.content)
  footer:SetPoint("BOTTOMLEFT")
  footer:SetPoint("BOTTOMRIGHT")
  Skin.fill(footer, { 0, 0, 0, 0.2 })
  Skin.edge(footer, "TOP", Skin.LINE)

  footer.removed = CreateFrame("Button", nil, footer)
  footer.removed:SetHeight(14)
  footer.removed:SetPoint("BOTTOMRIGHT", -INSET, CODE_LINE)
  footer.removed.text = Skin.label(footer.removed, "small", GOLD)
  footer.removed.text:SetPoint("BOTTOMRIGHT")
  footer.removed.text:SetJustifyH("RIGHT")
  footer.removed:SetScript("OnClick", showRemovedMenu)

  footer.hidden = Skin.label(footer, "small", DIM)
  footer.hidden:SetJustifyH("RIGHT")

  footer.status = Skin.label(footer, "small", MUTED)
  footer.status:SetPoint("TOPLEFT", INSET, -10)
  footer.status:SetWordWrap(true)

  local codeLabel = Skin.label(footer, "small", MUTED)
  codeLabel:SetPoint("BOTTOMLEFT", INSET, CODE_LINE)
  codeLabel:SetText("Crew code")
  footer.code = Skin.editBox(footer, 100)
  footer.code:SetHeight(22)
  footer.code:SetJustifyH("CENTER")
  footer.code:SetPoint("LEFT", codeLabel, "RIGHT", 8, 0)
  -- The text stays selected for copying; a faint selection keeps the code
  -- from being the brightest thing in the panel.
  footer.code:SetHighlightColor(1, 1, 1, 0.15)
  footer.code:SetScript("OnEditFocusGained", function(box) box:HighlightText() end)
  footer.code:SetScript("OnTextChanged", function(box, userInput)
    if userInput then
      box:SetText(box.crewCode)
      box:HighlightText()
    end
  end)
end

-- Draws the footer and returns its height.
local function drawFooter(crew, summary)
  if not footer then createFooter() end
  local removed = #core:removed()
  footer.removed.text:SetText(removed > 0 and ("Removed: %d"):format(removed) or "")
  footer.removed:SetWidth(footer.removed.text:GetStringWidth())
  footer.removed:SetShown(removed > 0)
  footer.hidden:ClearAllPoints()
  if removed > 0 then
    footer.hidden:SetPoint("BOTTOMRIGHT", footer.removed, "BOTTOMLEFT", -10, 0)
  else
    footer.hidden:SetPoint("BOTTOMRIGHT", -INSET, CODE_LINE)
  end
  footer.hidden:SetText(summary.hidden > 0 and ("Hidden: %d (unseen %dd)"):format(summary.hidden,
    ns.Core.HIDE_AFTER_DAYS) or "")

  footer.code.crewCode = crew.code
  footer.code:SetText(crew.code)
  footer.code:HighlightText()

  -- Set outright, to the window's width, so the wrapped text has a height
  -- before layout.
  footer.status:SetWidth(contentWidth() - 2 * INSET)
  footer.status:SetText(crew.status or "")
  local height = 46
  if crew.status then height = height + footer.status:GetStringHeight() + 6 end
  footer:SetHeight(height)
  footer:Show()
  return height
end

-- Hides every tab's view but the one named ("roster", "feed", "goals",
-- "when", "spares", "professions", "together"; nil hides them all). Each draw function shows
-- its own.
local function hideViewsBut(name)
  if name ~= "roster" then
    if rosterView then rosterView:Hide() end
    if footer then footer:Hide() end
  end
  if name ~= "feed" and feedView then feedView:Hide() end
  if name ~= "goals" then
    if goalsView then goalsView:Hide() end
    ns.GoalsTab.leave()
  end
  if name ~= "when" and whenView then whenView:Hide() end
  if name ~= "spares" and sparesView then sparesView:Hide() end
  if name ~= "professions" and professionsView then professionsView:Hide() end
  if name ~= "together" then ns.TogetherTab.hide() end
end

local function drawRoster(crew, summary)
  if not rosterView then rosterView = createScrollView() end
  local footerHeight = drawFooter(crew, summary)
  rosterView:ClearAllPoints()
  rosterView:SetPoint("TOPLEFT")
  rosterView:SetPoint("BOTTOMRIGHT", -6, footerHeight)
  rosterView:Show()
  drawSection(summary.spares)
  section:Hide()

  local y = -6
  local rowCount, altCount, later = 0, 0, 0
  local current
  for _, data in ipairs(core:rows(order)) do
    if not data.own and data.section ~= current then
      current = data.section
      local heading = section
      if section:IsShown() then
        later = later + 1
        heading = laterSection(later)
      end
      heading.label:SetText(current)
      place(heading, y)
      heading:Show()
      y = y - SECTION
    end
    rowCount = rowCount + 1
    local row = rowFrames[rowCount] or createRow()
    place(row, y)
    drawRow(row, data)
    y = y - ROW_HEIGHT
    if expanded[data.memberId] then
      for _, altData in ipairs(data.alts) do
        altCount = altCount + 1
        local alt = altFrames[altCount] or createAlt()
        place(alt, y)
        drawAlt(alt, data, altData)
        y = y - ALT_HEIGHT
      end
    end
  end
  hideAll(rowFrames, rowCount + 1)
  hideAll(altFrames, altCount + 1)
  hideAll(laterSections, later + 1)

  rosterView.content:SetHeight(-y + 6)
  updateThumb(rosterView)
end

-- Redraws from Core, if the panel is open.
function Panel.refresh()
  if not frame or not frame:IsShown() then return end
  local crew = core:crew()
  layout(crew ~= nil)
  if not crew then
    hideViewsBut(nil)
    showSetup()
    return
  end
  if setup then setup:Hide() end
  -- Showing the Feed starts or continues a Feed visit, before anything is
  -- read; any other tab ends it.
  if tab == "feed" then core:openFeed() else core:leaveFeed() end
  -- Likewise a Goals tab visit, for the latest win's "since you last looked".
  if tab == "goals" then core:openGoals() else core:leaveGoals() end

  local summary = core:summary()
  frame.headerRight:SetText(summary.header)
  drawNav(core:unseen(), core:unseenSpares())
  hideViewsBut(tab)
  if tab == "feed" then
    drawFeed(core:feed())
  elseif tab == "goals" then
    drawGoals()
  elseif tab == "when" then
    drawWhen()
  elseif tab == "spares" then
    drawSpares()
  elseif tab == "professions" then
    drawProfessions()
  elseif tab == "together" then
    ns.TogetherTab.draw(frame.content, core)
  else
    drawRoster(crew, summary)
  end
end

-- Pause sharing shows in the Roster's footer, whose height the rows sit
-- above, so the open tab redraws. A new panel place (a resize, a move or a
-- reset) puts the window there and redraws the views at its size.
function Panel.settingChanged(key)
  if key == "panelPlace" and frame then applyPlace() end
  if key == "paused" or key == "panelPlace" or key == "camp" then Panel.refresh() end
end

-- You Cheered a Member (from the Feed, a toast or While you were away):
-- they hop, if they're seated by the fire.
function Panel.cheered(memberId)
  if camp and memberId then camp:Hop(memberId) end
end

function Panel.toggle()
  if not frame then create() end
  frame:SetShown(not frame:IsShown())
end

-- Opens the panel on a tab: "roster", "feed", "goals", "when", "spares",
-- "professions" or "together".
function Panel.show(name)
  if not frame then create() end
  tab = name
  if frame:IsShown() then Panel.refresh() else frame:Show() end
end

-- Opens the When tab on a Member, or the Crew for nil.
function Panel.showWhen(memberId)
  whenMember = memberId
  Panel.show("when")
end

function Panel.start(theCore)
  core = theCore
end
