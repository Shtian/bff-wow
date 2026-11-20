local _, ns = ...

local Panel = {}
ns.Panel = Panel

local Skin = ns.Skin

local SIDEBAR = 124
local GRIP = 12
local HEADER = Skin.HEADER_HEIGHT
local NAV_HEIGHT = 30
local NAV_TOP = 8
local NAV_BOTTOM = 22
local NAV_ROWS = 9
local NAV_CHIP_X = 6
local NAV_CHIP_Y = 2
local NAV_CHIP_RADIUS = 2
local VERSION_HEIGHT = 18
local CODE_LINE = 15
local ROW_HEIGHT = 44
local ALT_HEIGHT = 20
local SECTION = 26
local INSET = 12
local SMALL_BUTTON = 20
local FEED_ENTRY = 38
local REACT = 20
local FEED_DAY = 26
local NODE = 26
local NEW_DOT = Skin.UNREAD_DOT
local LINE_X = INSET + NODE / 2 - 1
local REDRAW_EVERY = 30
local CAMP_SMALL_UNDER = 460
local SCROLL_STEP = 40

local TITLE = "Best Friends in Forever"
local FEED_EMPTY = { art = "feed", title = "Quiet by the fire",
  text = "Dings, deaths, new Characters and Crew wins land here, and wait for you while you're away." }
local PLAY_TIMES_EMPTY_TITLE = "Too soon to tell"
local SPARES_EMPTY = { art = "spares", title = "The crate is empty",
  text = "Got something your Crew could use? Drop it on the slot below." }
local PROFESSIONS_EMPTY = { art = "professions", title = "No trades yet",
  text = "When anyone learns a profession, it shows up here with their skill." }
local ALONE_CARD_PAD = 16
local SETUP_WIDTH = 320
local SETUP_COLUMN = 150
local SETUP_COLUMNS_Y = -72
local PLAY_TIMES_CELL = 11
local PLAY_TIMES_ROW = 18
local PLAY_TIMES_DAYS = 30
local PLAY_TIMES_TOP = -INSET - SMALL_BUTTON - 8 - 36
local PLAY_TIMES_BELOW = 74
local DAY_NAMES = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" }
local SPARE_ROW = 44
local SPARE_ICON = 28
local SPARE_BUTTON = 58
local SPARE_SECTION = 28
local SPARES_DROP = "Drop an item from your bags here to offer it to your Crew."
local SPARES_HOW = "Offer an item: drop it on the slot above, or type /bff spares add and shift-click it into the chat box. Mail it to the winner, then Give it."
local QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"
local PROFESSION_HEAD = 26
local PROFESSION_ICON = 16
local PROFESSION_NAME = 82
local PROFESSION_NAME_MAX = 140
local PROFESSION_TILE = 18
local PROFESSION_GAP = 1
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
local camp
local campHeight = 0
local firelight
local tipCard
local tipHeight = 0
local TIP_BUTTON = 84
local TIP_PAD = 10
local setup
local nav
local section
local rosterView
local feedView
local trophiesView
local whatsNewView
local settingsView
local playTimesView
local sparesView
local professionsView
local footer
local rowFrames = {}
local altFrames = {}
local tab = "roster"
local playTimesMember
local order = "online"
local expanded = {}

local classColor = Skin.classColor

local function emptyState(own)
  return ns.EmptyState.view(own, not core:setting("camp"))
end

local function contentWidth()
  return frame:GetWidth() - SIDEBAR - 1
end

local function contentHeight()
  return frame:GetHeight() - HEADER - campHeight - tipHeight - 1
end

local function listWidth()
  return contentWidth() - 6
end

local function className(classFilename)
  return LOCALIZED_CLASS_NAMES_MALE[classFilename] or classFilename or ""
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

-- WoW: GameTooltip's ANCHOR_RIGHT on a row near the top of the screen
-- puts the tooltip in the screen's corner.
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

function Panel.characterTooltip(row, character)
  GameTooltip:AddLine(character.fullName, classColor(character.classFilename))
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
end

local function showTooltip(owner)
  if not owner.row then return end
  placeBeside(owner)
  Panel.characterTooltip(owner.row, owner.character)
  GameTooltip:Show()
end

local function hideTooltip()
  GameTooltip:Hide()
end

local function showMenu(owner)
  local row, character = owner.row, owner.character
  if not row then return end
  MenuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateTitle(character.fullName)
    if row.own then
      local setMain = root:CreateButton("Set as Main", function() core:setMain(character.guid) end)
      setMain:SetEnabled(not (character.main and row.mainSet))
      if row.mainSet then
        root:CreateButton("Main: most recently played", function() core:setMain(nil) end)
      end
    else
      root:CreateButton("Whisper", function() ns.Actions.whisper(character.fullName) end):SetEnabled(character.playing)
      root:CreateButton("Invite", function() ns.Actions.invite(character.fullName) end):SetEnabled(character.playing)
      local name = row.displayName or character.name
      root:CreateButton(("When does %s play?"):format(name), function() Panel.showPlayTimes(row.memberId) end)
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

  row.ownBackground = Skin.litWash(row)

  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(28, 28)
  row.icon:SetPoint("TOPLEFT", INSET, -7)
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
  if camp:IsShown() then row.figure:SetClass(data.classFilename, data.hat) else row.figure:Hide() end
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

local function sectionLabel(parent)
  return Skin.sectionLabel(parent, INSET, -2)
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

  section.spares = CreateFrame("Button", nil, section)
  section.spares:SetHeight(18)
  section.spares:SetPoint("RIGHT", section.sort, "LEFT", -8, 0)
  section.spares.label = Skin.label(section.spares, "small", GOLD)
  section.spares.label:SetPoint("RIGHT")
  section.spares:SetScript("OnClick", function() Panel.show("spares") end)

  local line = Skin.rule(section)
  line:SetPoint("LEFT", label, "RIGHT", 8, 0)
  section.line = line
end

local laterSections = {}

local function laterSection(index)
  local heading = laterSections[index]
  if heading then return heading end
  heading = CreateFrame("Frame", nil, rosterView.content)
  heading:SetHeight(SECTION)
  heading.label = sectionLabel(heading)
  local line = Skin.rule(heading)
  line:SetPoint("LEFT", heading.label, "RIGHT", 8, 0)
  line:SetPoint("RIGHT", -INSET, 0)
  laterSections[index] = heading
  return heading
end

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

local function navButton(label, onClick)
  local button = CreateFrame("Button", nil, frame.sidebar)
  button:SetHeight(NAV_HEIGHT)
  button.selected = Skin.chip(button, Skin.CHIP, NAV_CHIP_X, NAV_CHIP_Y, NAV_CHIP_RADIUS)
  Skin.chip(button, Skin.CHIP_HOVER, NAV_CHIP_X, NAV_CHIP_Y, NAV_CHIP_RADIUS, "HIGHLIGHT")
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
  nav.roster:SetPoint("TOPLEFT", 0, -NAV_TOP)
  nav.roster:SetPoint("TOPRIGHT", 0, -NAV_TOP)
  nav.feed = navButton("Feed", open("feed"))
  nav.feed:SetPoint("TOPLEFT", nav.roster, "BOTTOMLEFT")
  nav.feed:SetPoint("TOPRIGHT", nav.roster, "BOTTOMRIGHT")
  nav.feed.badge = Skin.badge(nav.feed, "tiny", { 0.1, 0.08, 0 }, GOLD)
  nav.feed.badge:SetPoint("RIGHT", -10, 0)
  nav.trophies = navButton("Trophies", open("trophies"))
  nav.trophies:SetPoint("TOPLEFT", nav.feed, "BOTTOMLEFT")
  nav.trophies:SetPoint("TOPRIGHT", nav.feed, "BOTTOMRIGHT")
  nav.playTimes = navButton("Play Times", open("playtimes"))
  nav.playTimes:SetPoint("TOPLEFT", nav.trophies, "BOTTOMLEFT")
  nav.playTimes:SetPoint("TOPRIGHT", nav.trophies, "BOTTOMRIGHT")
  nav.spares = navButton("Spares", open("spares"))
  nav.spares:SetPoint("TOPLEFT", nav.playTimes, "BOTTOMLEFT")
  nav.spares:SetPoint("TOPRIGHT", nav.playTimes, "BOTTOMRIGHT")
  nav.spares.badge = Skin.badge(nav.spares, "tiny", { 0.1, 0.08, 0 }, GOLD)
  nav.spares.badge:SetPoint("RIGHT", -10, 0)
  nav.professions = navButton("Professions", open("professions"))
  nav.professions:SetPoint("TOPLEFT", nav.spares, "BOTTOMLEFT")
  nav.professions:SetPoint("TOPRIGHT", nav.spares, "BOTTOMRIGHT")
  nav.dungeons = navButton("Dungeons", open("dungeons"))
  nav.dungeons:SetPoint("TOPLEFT", nav.professions, "BOTTOMLEFT")
  nav.dungeons:SetPoint("TOPRIGHT", nav.professions, "BOTTOMRIGHT")
  nav.catches = navButton("Catches", open("catches"))
  nav.catches:SetPoint("TOPLEFT", nav.dungeons, "BOTTOMLEFT")
  nav.catches:SetPoint("TOPRIGHT", nav.dungeons, "BOTTOMRIGHT")
  nav.settings = navButton("Settings", open("settings"))
  nav.settings:SetPoint("BOTTOMLEFT", 0, NAV_BOTTOM)
  nav.settings:SetPoint("BOTTOMRIGHT", 0, NAV_BOTTOM)
  nav.version = CreateFrame("Button", nil, frame.sidebar)
  nav.version:SetHeight(VERSION_HEIGHT)
  nav.version:SetPoint("BOTTOMLEFT", 0, NAV_BOTTOM - VERSION_HEIGHT)
  nav.version:SetPoint("BOTTOMRIGHT", 0, NAV_BOTTOM - VERSION_HEIGHT)
  nav.version.selected = Skin.chip(nav.version, Skin.CHIP, NAV_CHIP_X, 1, NAV_CHIP_RADIUS)
  Skin.chip(nav.version, Skin.CHIP_HOVER, NAV_CHIP_X, 1, NAV_CHIP_RADIUS, "HIGHLIGHT")
  nav.version.label = Skin.label(nav.version, "tiny", DIM)
  nav.version.label:SetPoint("LEFT", NAV_CHIP_X + 10, 0)
  nav.version.label:SetText(ns.VERSION)
  nav.version.dot = Skin.unreadDot(nav.version)
  nav.version.dot:SetPoint("CENTER", nav.version.label, "LEFT", -(NEW_DOT / 2 + 3), 0)
  nav.version:SetScript("OnClick", open("whatsnew"))
  nav.version:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("What's new in BFF")
    GameTooltip:Show()
  end)
  nav.version:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function drawNav(unseen, sparesUnseen)
  if not nav then createNav() end
  setSelected(nav.roster, tab == "roster")
  setSelected(nav.feed, tab == "feed")
  setSelected(nav.trophies, tab == "trophies")
  setSelected(nav.playTimes, tab == "playtimes")
  setSelected(nav.spares, tab == "spares")
  setSelected(nav.professions, tab == "professions")
  setSelected(nav.dungeons, tab == "dungeons")
  setSelected(nav.catches, tab == "catches")
  setSelected(nav.settings, tab == "settings")
  nav.version.selected:SetShown(tab == "whatsnew")
  Skin.color(nav.version.label, tab == "whatsnew" and TEXT or DIM)
  nav.version.dot:SetShown(core:hasNewChanges())
  nav.version:EnableMouse(core:whatsNew() ~= nil)
  local sidebarHeight = frame:GetHeight() - HEADER - campHeight - tipHeight - 1
  local height = math.min(NAV_HEIGHT, math.floor((sidebarHeight - NAV_TOP - NAV_BOTTOM) / NAV_ROWS))
  for _, button in ipairs({ nav.roster, nav.feed, nav.trophies, nav.playTimes, nav.spares, nav.professions, nav.dungeons,
    nav.catches, nav.settings }) do
    button:SetHeight(height)
  end
  nav.feed.badge:SetText(unseen)
  nav.feed.badge:SetShown(unseen > 0 and tab ~= "feed")
  nav.spares.badge:SetText(sparesUnseen)
  nav.spares.badge:SetShown(sparesUnseen > 0 and tab ~= "spares")
end

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
  view:SetScript("OnSizeChanged", function(self, width)
    self.content:SetWidth(width)
    updateThumb(self)
  end)
  view.thumb = view:CreateTexture(nil, "OVERLAY")
  view.thumb:SetColorTexture(1, 1, 1, 0.18)
  view.thumb:SetWidth(3)
  return view
end

local function createFeedView()
  feedView = createScrollView()
  feedView:SetPoint("TOPLEFT")
  feedView:SetPoint("BOTTOMRIGHT", -6, 0)

  feedView.segments = {}
  feedView.days = {}
  feedView.entries = {}

  feedView.empty = ns.EmptyState.new(feedView)
end

local DAY_HEIGHT = 16
local DAY_GAP = 4

local function createFeedDay()
  local day = CreateFrame("Frame", nil, feedView.content)
  day:SetHeight(DAY_HEIGHT)
  day.label = Skin.sectionLabel(day, 4, 0)
  local line = Skin.rule(day)
  line:SetPoint("LEFT", day.label, "RIGHT", 8, 0)
  line:SetPoint("RIGHT")
  feedView.days[#feedView.days + 1] = day
  return day
end

local function drawTimeline(stretches)
  local top = stretches[1] and stretches[1].top
  local bottom = stretches[1] and stretches[#stretches].bottom
  local new, old = Skin.TIMELINE_NEW, Skin.TIMELINE_OLD
  local function colourAt(y)
    local share = top > bottom and (top - y) / (top - bottom) or 0
    return Skin.alpha(new, new[4] + (old[4] - new[4]) * share)
  end
  local shown = 0
  for _, stretch in ipairs(stretches) do
    if stretch.top > stretch.bottom then
      shown = shown + 1
      local segment = feedView.segments[shown]
      if not segment then
        segment = feedView.content:CreateTexture(nil, "BACKGROUND")
        segment:SetColorTexture(1, 1, 1, 1)
        segment:SetWidth(2)
        feedView.segments[shown] = segment
      end
      segment:ClearAllPoints()
      segment:SetPoint("TOPLEFT", LINE_X, stretch.top)
      segment:SetHeight(stretch.top - stretch.bottom)
      Skin.gradient(segment, "VERTICAL", colourAt(stretch.bottom), colourAt(stretch.top))
      segment:Show()
    end
  end
  for i = shown + 1, #feedView.segments do feedView.segments[i]:Hide() end
end

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
  entry.new = Skin.unreadDot(entry)
  entry.new:SetPoint("CENTER", node, "LEFT", -(NEW_DOT / 2 + 3), 0)
  entry.time = Skin.label(entry, "small", MUTED)
  entry.time:SetPoint("TOPLEFT", entry.text, "BOTTOMLEFT", 0, -2)
  entry.reactors = Skin.label(entry, "small", MUTED)
  entry.reactors:SetPoint("LEFT", entry.time, "RIGHT", 8, 0)
  entry.reactors:SetPoint("RIGHT", -INSET - 36, 0)
  entry.reactors:SetWordWrap(false)

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
  line.node:SetKind(entry.kind, entry.icon, entry.edge)
  line.text:SetText(entry.text)
  Skin.color(line.text, entry.highlight and GOLD or entry.own and MUTED or TEXT)
  line.time:SetText(date("%H:%M", entry.time))
  line.new:SetShown(entry.new)
end

local function drawFeed(feed)
  if not feedView then createFeedView() end
  local y, dayCount, entryCount = -INSET, 0, 0
  local stretches = {}
  for _, day in ipairs(feed.days) do
    dayCount = dayCount + 1
    if stretches[dayCount - 1] then stretches[dayCount - 1].bottom = y + DAY_GAP end
    stretches[dayCount] = { top = y - DAY_HEIGHT - DAY_GAP }
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
  if entryCount == 0 then
    feedView.empty:Set(emptyState(FEED_EMPTY))
    feedView.empty:Place(feedView, listWidth(), contentHeight())
  else
    feedView.empty:Hide()
  end
  if stretches[dayCount] then stretches[dayCount].bottom = y + 8 end
  drawTimeline(entryCount > 0 and stretches or {})
  feedView.content:SetHeight(math.max(-y + INSET, 1))
  feedView:Show()
  updateThumb(feedView)
end

local function drawTrophies()
  if not trophiesView then
    trophiesView = createScrollView()
    trophiesView:SetPoint("TOPLEFT")
    trophiesView:SetPoint("BOTTOMRIGHT", -6, 0)
  end
  ns.TrophiesTab.draw(trophiesView, core, listWidth(), Panel.refresh)
  trophiesView:Show()
  updateThumb(trophiesView)
end

local function drawSettings(inCrew)
  if not settingsView then
    settingsView = createScrollView()
    settingsView:SetPoint("TOPLEFT")
    settingsView:SetPoint("BOTTOMRIGHT", -6, 0)
  end
  local width = inCrew and listWidth() or frame:GetWidth() - 2 - 6
  ns.SettingsTab.draw(settingsView, core, width, not inCrew and function()
    tab = "roster"
    Panel.refresh()
  end or nil)
  settingsView:Show()
  updateThumb(settingsView)
end

local function drawWhatsNew()
  if not whatsNewView then
    whatsNewView = createScrollView()
    whatsNewView:SetPoint("TOPLEFT")
    whatsNewView:SetPoint("BOTTOMRIGHT", -6, 0)
  end
  ns.WhatsNewTab.draw(whatsNewView, core, listWidth(), Panel.refresh)
  whatsNewView:Show()
  updateThumb(whatsNewView)
end

local function showPlayTimesMenu(owner)
  MenuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateTitle("Show")
    root:CreateRadio("The Crew", function() return playTimesMember == nil end, function()
      playTimesMember = nil
      Panel.refresh()
    end)
    for _, row in ipairs(core:rows("name")) do
      local label = row.own and "You" or row.displayName or row.name
      root:CreateRadio(label, function() return playTimesMember == row.memberId end, function()
        playTimesMember = row.memberId
        Panel.refresh()
      end)
    end
  end)
end

local function shadeCell(cell, value, max)
  if value <= 0 or max <= 0 then
    cell.texture:SetColorTexture(1, 1, 1, 0.05)
  else
    cell.texture:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.2 + 0.8 * math.min(value / max, 1))
  end
end

local function showCellTooltip(cell)
  local view = playTimesView.data
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

local function createPlayTimesView()
  playTimesView = CreateFrame("Frame", nil, frame.content)
  playTimesView:SetAllPoints()

  playTimesView.pick = CreateFrame("Button", nil, playTimesView)
  playTimesView.pick:SetHeight(SMALL_BUTTON)
  playTimesView.pick:SetPoint("TOPLEFT", INSET, -INSET)
  Skin.fill(playTimesView.pick, Skin.SECONDARY)
  Skin.border(playTimesView.pick, Skin.BORDER)
  Skin.fill(playTimesView.pick, Skin.HOVER, "HIGHLIGHT")
  playTimesView.pick.label = Skin.label(playTimesView.pick, "small", TEXT)
  playTimesView.pick.iconRoom = Skin.leadIcon(playTimesView.pick, "filter", TEXT)
  playTimesView.pick:SetScript("OnClick", showPlayTimesMenu)

  playTimesView.intro = Skin.label(playTimesView, "small", MUTED)
  playTimesView.intro:SetPoint("TOPLEFT", playTimesView.pick, "BOTTOMLEFT", 0, -8)
  playTimesView.intro:SetWordWrap(true)
  playTimesView.intro:SetJustifyH("LEFT")

  playTimesView.hours = {}
  for hour = 0, 21, 3 do
    local label = Skin.label(playTimesView, "tiny", DIM)
    label:SetText(("%02d"):format(hour))
    label.hour = hour
    playTimesView.hours[#playTimesView.hours + 1] = label
  end
  playTimesView.days = {}
  playTimesView.cells = {}
  for day = 1, 7 do
    local label = Skin.label(playTimesView, "small", MUTED)
    label:SetText(DAY_NAMES[day])
    playTimesView.days[day] = label
    for hour = 1, 24 do
      local cell = CreateFrame("Frame", nil, playTimesView)
      cell.texture = cell:CreateTexture(nil, "ARTWORK")
      cell.texture:SetAllPoints()
      cell.day, cell.hour = day, hour
      cell:EnableMouse(true)
      cell:SetScript("OnEnter", showCellTooltip)
      cell:SetScript("OnLeave", hideTooltip)
      playTimesView.cells[#playTimesView.cells + 1] = cell
    end
  end

  playTimesView.legendLow = Skin.label(playTimesView, "tiny", DIM)
  playTimesView.legend = {}
  local anchor = playTimesView.legendLow
  for i = 1, 4 do
    local swatch = playTimesView:CreateTexture(nil, "ARTWORK")
    swatch:SetSize(PLAY_TIMES_CELL - 1, PLAY_TIMES_ROW - 2)
    swatch:SetPoint("LEFT", anchor, "RIGHT", i == 1 and 6 or 1, 0)
    playTimesView.legend[i] = { texture = swatch }
    anchor = swatch
  end
  playTimesView.legendHigh = Skin.label(playTimesView, "tiny", DIM)
  playTimesView.legendHigh:SetPoint("LEFT", anchor, "RIGHT", 6, 0)

  playTimesView.note = Skin.label(playTimesView, "small", MUTED)
  playTimesView.note:SetWordWrap(true)
  playTimesView.note:SetJustifyH("LEFT")

  playTimesView.grid = { playTimesView.intro, playTimesView.legendLow, playTimesView.legendHigh, playTimesView.note }
  for _, list in ipairs({ playTimesView.hours, playTimesView.days, playTimesView.cells }) do
    for _, item in ipairs(list) do playTimesView.grid[#playTimesView.grid + 1] = item end
  end
  for _, swatch in ipairs(playTimesView.legend) do playTimesView.grid[#playTimesView.grid + 1] = swatch.texture end
  playTimesView.empty = ns.EmptyState.new(playTimesView)
end

local function placeWhenGrid()
  local cellWidth = math.max(PLAY_TIMES_CELL, math.floor((contentWidth() - 2 * INSET - PLAY_TIMES_DAYS) / 24))
  local rowHeight = math.max(PLAY_TIMES_ROW, math.floor((contentHeight() + PLAY_TIMES_TOP - PLAY_TIMES_BELOW) / 7))
  for _, label in ipairs(playTimesView.hours) do
    label:SetPoint("BOTTOMLEFT", playTimesView, "TOPLEFT", INSET + PLAY_TIMES_DAYS + label.hour * cellWidth, PLAY_TIMES_TOP + 2)
  end
  for day, label in ipairs(playTimesView.days) do
    label:SetPoint("LEFT", playTimesView, "TOPLEFT", INSET, PLAY_TIMES_TOP - (day - 1) * rowHeight + 1 - math.floor(rowHeight / 2))
  end
  for _, cell in ipairs(playTimesView.cells) do
    cell:SetSize(cellWidth - 1, rowHeight - 2)
    cell:SetPoint("TOPLEFT", INSET + PLAY_TIMES_DAYS + (cell.hour - 1) * cellWidth, PLAY_TIMES_TOP - (cell.day - 1) * rowHeight)
  end
  local below = PLAY_TIMES_TOP - 7 * rowHeight - 10
  playTimesView.legendLow:SetPoint("TOPLEFT", INSET + PLAY_TIMES_DAYS, below)
  playTimesView.note:SetPoint("TOPLEFT", INSET, below - 24)
end

local function drawPlayTimes()
  if not playTimesView then createPlayTimesView() end
  local view = playTimesMember and core:playTimes(playTimesMember)
  if not view then
    playTimesMember = nil
    view = core:playTimes()
  end
  playTimesView.data = view
  playTimesView.pick.label:SetText("Show: " .. view.title)
  playTimesView.pick:SetWidth(playTimesView.pick.label:GetStringWidth() + playTimesView.pick.iconRoom + 16)
  playTimesView.intro:SetWidth(contentWidth() - 2 * INSET)
  playTimesView.intro:SetText(view.intro)
  playTimesView.note:SetWidth(contentWidth() - 2 * INSET)
  playTimesView.note:SetText(view.note or "")
  placeWhenGrid()
  for _, cell in ipairs(playTimesView.cells) do
    shadeCell(cell, view.grid[cell.day][cell.hour], view.max)
  end
  playTimesView.legendLow:SetText(view.memberId and "0" or "None")
  playTimesView.legendHigh:SetText(view.memberId and ("%d weeks"):format(view.weeks) or "Everyone")
  for i, swatch in ipairs(playTimesView.legend) do
    shadeCell(swatch, i - 1, 3)
  end
  if GameTooltip:GetOwner() and GameTooltip:GetOwner():GetParent() == playTimesView then
    showCellTooltip(GameTooltip:GetOwner())
  end
  local empty = view.empty and not view.memberId
  for _, item in ipairs(playTimesView.grid) do item:SetShown(not empty) end
  if empty then
    playTimesView.empty:Set(emptyState({ art = "playTimes", title = PLAY_TIMES_EMPTY_TITLE, text = view.note }))
    local top = INSET + SMALL_BUTTON
    playTimesView.empty:Place(playTimesView, contentWidth(), contentHeight() - top, top)
  else
    playTimesView.empty:Hide()
  end
  playTimesView:Show()
end

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

local function placeSpare(line, y)
  line:ClearAllPoints()
  line:SetPoint("TOPLEFT", sparesView.content, "TOPLEFT", 0, y)
  line:SetPoint("TOPRIGHT", sparesView.content, "TOPRIGHT", 0, y)
end

-- WoW: dropping an item from the cursor may arrive as OnReceiveDrag or
-- as OnClick.
local function onSpareDrop()
  if not GetCursorInfo() then return end
  ns.sayPosted(ns.Bags.postFromCursor(core))
end

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
  sparesView.empty = ns.EmptyState.new(sparesView.content)
end

local function spareHeading(index)
  local heading = sparesView.headings[index]
  if heading then return heading end
  heading = CreateFrame("Frame", nil, sparesView.content)
  heading:SetHeight(SPARE_SECTION)
  heading.label = sectionLabel(heading)
  heading.count = Skin.label(heading, "small", MUTED)
  heading.count:SetPoint("RIGHT", -INSET, -2)
  heading.line = Skin.rule(heading)
  heading.line:SetPoint("LEFT", heading.label, "RIGHT", 8, 0)
  heading.line:SetPoint("RIGHT", heading.count, "LEFT", -8, 0)
  sparesView.headings[index] = heading
  return heading
end

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

local function claim(data, guid)
  local ok, reason = core:claimSpare(data.ownerId, data.id, guid)
  if not ok then ns.say(ns.MESSAGES[reason]) end
end

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
  sparesView.empty:SetShown(#view.crew == 0)
  if #view.crew == 0 then
    sparesView.empty:Set(emptyState(SPARES_EMPTY))
    sparesView.empty:ClearAllPoints()
    sparesView.empty:SetPoint("TOPLEFT", sparesView.content, "TOPLEFT", 0, y - 10)
    y = y - 10 - sparesView.empty:Layout(listWidth()) - 16
  end
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
  professionsView.empty = ns.EmptyState.new(professionsView)
end

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
    GameTooltip:AddDoubleLine(character.fullName, skill, r, g, b, TEXT[1], TEXT[2], TEXT[3])
  end
end

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
  row.ownBackground = Skin.litWash(row)
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

  local members = view.none and {} or view.members
  if view.none then
    professionsView.empty:Set(emptyState(PROFESSIONS_EMPTY))
    professionsView.empty:Place(professionsView, contentWidth(), contentHeight() - PROFESSION_HEAD, PROFESSION_HEAD)
  else
    professionsView.empty:Hide()
  end
  local y = 0
  for i, member in ipairs(members) do
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
  hideAll(professionsView.rows, #members + 1)

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

-- WoW: the game's layout cache (SetUserPlaced) is applied before the panel
-- exists.
local function savePlace()
  frame.sizing, frame.moving = nil, nil
  frame:StopMovingOrSizing()
  frame:SetUserPlaced(false)
  core:setPanelPlace(frame:GetWidth(), frame:GetHeight(), frame:GetLeft(), frame:GetTop())
end

local function createGrip()
  frame:SetResizable(true)
  local limits = ns.Core
  -- WoW: SetResizeBounds is Midnight's; older clients have SetMinResize and
  -- SetMaxResize.
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
  -- WoW: a frame hidden mid-move or mid-resize may get no OnDragStop or
  -- OnMouseUp.
  frame:SetScript("OnHide", function()
    if frame.sizing or frame.moving then savePlace() end
    core:leaveFeed()
    core:leaveTrophies()
    ns.TrophiesTab.hidden()
    core:leaveWhatsNew()
    ns.WhatsNewTab.leave()
    ns.SettingsTab.leave()
    if tab == "settings" and not core:crew() then tab = "roster" end
  end)
  local sinceRedraw = 0
  frame:SetScript("OnUpdate", function(_, elapsed)
    sinceRedraw = sinceRedraw + elapsed
    if sinceRedraw >= REDRAW_EVERY then
      sinceRedraw = 0
      Panel.refresh()
    end
  end)

  frame.contact = Skin.headerButton(frame.header, "message", "Get in touch", function() ns.Contact.show() end)
  frame.contact:SetPoint("RIGHT", frame.close, "LEFT", -2, 0)
  frame.report = Skin.headerButton(frame.header, "bug", "Report a bug", function() ns.Report.show() end)
  frame.report:SetPoint("RIGHT", frame.contact, "LEFT", -2, 0)

  frame.headerRight:ClearAllPoints()
  frame.headerRight:SetPoint("RIGHT", frame.report, "LEFT", -8, 0)
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
  firelight = ns.Firelight.new(frame)

  frame.sidebar = CreateFrame("Frame", nil, frame)
  frame.sidebar:SetPoint("BOTTOMLEFT", 1, 1)
  frame.sidebar:SetWidth(SIDEBAR - 1)
  Skin.fill(frame.sidebar, Skin.SIDEBAR)
  Skin.edge(frame.sidebar, "RIGHT", Skin.LINE)

  frame.content = CreateFrame("Frame", nil, frame)
end

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
  firelight:Place(camp, campHeight > 0 and frame:GetHeight() - HEADER - campHeight or nil)
end

local function createTip()
  tipCard = CreateFrame("Frame", nil, frame)
  Skin.fill(tipCard, Skin.SIDEBAR)
  Skin.edge(tipCard, "BOTTOM", Skin.LINE)
  Skin.edge(tipCard, "LEFT", GOLD)
  tipCard.text = Skin.label(tipCard, "small", TEXT)
  tipCard.text:SetPoint("LEFT", INSET, 0)
  tipCard.text:SetWordWrap(true)
  tipCard.dismiss = Skin.button(tipCard, "", function() core:dismissTip(tipCard.key) end)
  tipCard.dismiss:SetSize(TIP_BUTTON, SMALL_BUTTON)
  tipCard.dismiss:SetPoint("RIGHT", -INSET, 0)
  tipCard.accept = Skin.button(tipCard, "", function() core:acceptTip(tipCard.key) end, true)
  tipCard.accept:SetSize(TIP_BUTTON, SMALL_BUTTON)
  tipCard.accept:SetPoint("RIGHT", tipCard.dismiss, "LEFT", -6, 0)
end

local function drawTip()
  local tip = core:tip()
  if not tip then
    tipHeight = 0
    if tipCard then tipCard:Hide() end
    return
  end
  if not tipCard then createTip() end
  tipCard.key = tip.key
  tipCard.accept:SetText(tip.accept)
  tipCard.dismiss:SetText(tip.dismiss)
  -- WoW: a wrapping FontString has no height until its width is set.
  tipCard.text:SetWidth(frame:GetWidth() - 2 - 3 * INSET - 2 * TIP_BUTTON - 6)
  tipCard.text:SetText(tip.text)
  tipHeight = math.ceil(math.max(tipCard.text:GetStringHeight(), SMALL_BUTTON)) + 2 * TIP_PAD
  tipCard:ClearAllPoints()
  tipCard:SetPoint("TOPLEFT", 1, -HEADER - campHeight)
  tipCard:SetPoint("TOPRIGHT", -1, -HEADER - campHeight)
  tipCard:SetHeight(tipHeight)
  tipCard:Show()
end

local function layout(inCrew)
  drawCamp(inCrew)
  drawTip()
  local top = -HEADER - campHeight - tipHeight
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
  -- WoW: addons can't write to the clipboard, so the code stays selected
  -- for the player to copy.
  footer.code:SetHighlightColor(1, 1, 1, 0.15)
  footer.code:SetScript("OnEditFocusGained", function(box) box:HighlightText() end)
  footer.code:SetScript("OnTextChanged", function(box, userInput)
    if userInput then
      box:SetText(box.crewCode)
      box:HighlightText()
    end
  end)
end

local function drawFooter(crew, counts)
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
  footer.hidden:SetText(counts.hidden > 0 and ("Hidden: %d (unseen %dd)"):format(counts.hidden,
    ns.Core.HIDE_AFTER_DAYS) or "")

  footer.code.crewCode = crew.code
  footer.code:SetText(crew.code)
  footer.code:HighlightText()

  -- WoW: a wrapping FontString has no height until its width is set.
  footer.status:SetWidth(contentWidth() - 2 * INSET)
  local status = not crew.waiting and crew.status or nil
  footer.status:SetText(status or "")
  local height = 46
  if status then height = height + footer.status:GetStringHeight() + 6 end
  footer:SetHeight(height)
  footer:Show()
  return height
end

local function hideViewsBut(name)
  if name ~= "roster" then
    if rosterView then rosterView:Hide() end
    if footer then footer:Hide() end
  end
  if name ~= "feed" and feedView then feedView:Hide() end
  if name ~= "trophies" then
    if trophiesView then trophiesView:Hide() end
    ns.TrophiesTab.leave()
  end
  if name ~= "whatsnew" then
    if whatsNewView then whatsNewView:Hide() end
    ns.WhatsNewTab.leave()
  end
  if name ~= "settings" then
    if settingsView then settingsView:Hide() end
    ns.SettingsTab.leave()
  end
  if name ~= "playtimes" and playTimesView then playTimesView:Hide() end
  if name ~= "spares" and sparesView then sparesView:Hide() end
  if name ~= "professions" and professionsView then professionsView:Hide() end
  if name ~= "dungeons" then ns.DungeonsTab.hide() end
  if name ~= "catches" then ns.CatchesTab.hide() end
end

local function drawRoster(crew, counts)
  if not rosterView then
    rosterView = createScrollView()
    rosterView.alone = ns.EmptyState.new(rosterView.content)
  end
  rosterView.alone:SetShown(crew.alone)
  local footerHeight = drawFooter(crew, counts)
  rosterView:ClearAllPoints()
  rosterView:SetPoint("TOPLEFT")
  rosterView:SetPoint("BOTTOMRIGHT", -6, footerHeight)
  rosterView:Show()
  drawSection(counts.spares)
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
    if data.own and crew.alone then
      rosterView.alone:Set(ns.EmptyState.alone(crew, not core:setting("camp")))
      rosterView.alone:ClearAllPoints()
      rosterView.alone:SetPoint("TOPLEFT", rosterView.content, "TOPLEFT", 0, y - ALONE_CARD_PAD)
      rosterView.alone:Show()
      y = y - ALONE_CARD_PAD - rosterView.alone:Layout(listWidth()) - ALONE_CARD_PAD
    end
  end
  hideAll(rowFrames, rowCount + 1)
  hideAll(altFrames, altCount + 1)
  hideAll(laterSections, later + 1)

  rosterView.content:SetHeight(-y + 6)
  updateThumb(rosterView)
end

function Panel.refresh()
  if not frame or not frame:IsShown() then return end
  local crew = core:crew()
  layout(crew ~= nil)
  if not crew then
    hideViewsBut(tab == "settings" and "settings" or nil)
    if tab == "settings" then
      if setup then setup:Hide() end
      drawSettings(false)
    else
      showSetup()
    end
    return
  end
  if setup then setup:Hide() end
  if tab == "feed" then core:openFeed() else core:leaveFeed() end
  if tab == "trophies" then core:openTrophies() else core:leaveTrophies() end
  if tab == "whatsnew" then core:openWhatsNew() else core:leaveWhatsNew() end

  local counts = core:rosterCounts()
  frame.headerRight:SetText(counts.header)
  drawNav(core:unseen(), core:unseenSpares())
  hideViewsBut(tab)
  if tab == "feed" then
    drawFeed(core:feed())
  elseif tab == "trophies" then
    drawTrophies()
  elseif tab == "whatsnew" then
    drawWhatsNew()
  elseif tab == "playtimes" then
    drawPlayTimes()
  elseif tab == "spares" then
    drawSpares()
  elseif tab == "professions" then
    drawProfessions()
  elseif tab == "dungeons" then
    ns.DungeonsTab.draw(frame.content, core, camp:IsShown())
  elseif tab == "catches" then
    ns.CatchesTab.draw(frame.content, core)
  elseif tab == "settings" then
    drawSettings(true)
  else
    drawRoster(crew, counts)
  end
end

function Panel.settingChanged(key)
  if key == "panelPlace" and frame then applyPlace() end
  if key == "paused" or key == "panelPlace" or key == "camp" or key == "seasons" or key == "pocketCamp"
    or tab == "settings" then
    Panel.refresh()
  end
end

function Panel.cheered(memberId)
  if not memberId then return end
  if camp then camp:Hop(memberId) end
  ns.PocketCamp.cheered(memberId)
end

function Panel.campReaction(reaction)
  if camp and frame:IsShown() then camp:React(reaction) end
end

function Panel.toggle()
  if not frame then create() end
  frame:SetShown(not frame:IsShown())
end

function Panel.show(name)
  if not frame then create() end
  tab = name
  if frame:IsShown() then Panel.refresh() else frame:Show() end
end

function Panel.hide()
  if frame then frame:Hide() end
end

function Panel.showPlayTimes(memberId)
  playTimesMember = memberId
  Panel.show("playtimes")
end

function Panel.start(theCore)
  core = theCore
end
