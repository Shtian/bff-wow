-- Panel: the BFF window, in the Skin's flat look. Without a Crew it shows
-- the setup view (display name, Start or Join); in one, a sidebar with
-- Roster, Feed, Goals and Settings. The Roster has your own row pinned on top,
-- then a row per Member with expandable Alts, a sort menu, a tooltip and
-- right-click menu per Character, and a footer with the hidden count,
-- removed Members and the Crew code. The Feed is a timeline
-- of Core's entries by day, an icon per kind, who reacted to each and a
-- button to react, and marks them seen while open. Goals has a row per
-- Crew goal track: the next rung, a progress bar with numbers and the last
-- rung reached. It never sees a Member record.

local _, ns = ...

local Panel = {}
ns.Panel = Panel

local Skin = ns.Skin

local WIDTH = 440
local SIDEBAR = 104
local CONTENT_WIDTH = WIDTH - SIDEBAR - 1
local HEADER = Skin.HEADER_HEIGHT
local NAV_HEIGHT = 30
local ROW_HEIGHT = 44
local ALT_HEIGHT = 20
local SECTION = 26
local INSET = 12
-- One height for every view, so switching tabs never resizes the window;
-- the Roster and the Feed scroll inside it.
local HEIGHT = 380
local FEED_ENTRY = 38
local REACT = 20
local FEED_DAY = 26
-- The timeline's line runs through the middle of the entry icons.
local NODE = 26
local LINE_X = INSET + NODE / 2 - 1
-- Last seen goes stale, so the open panel redraws this often.
local REDRAW_EVERY = 30
local SCROLL_STEP = 40

local TITLE = "Best Friends in Forever"
local WAITING = "Waiting for your Crew. Members show up when they or someone who has seen them is online."
local LEAVING = "Leaving the Crew. It finishes once BFF's channel is reachable."
local PAUSED = "You appear offline: the others don't see you. Change it in Settings."
local FEED_EMPTY = "Nothing yet. Dings, deaths and new Characters show up here."
local GOALS_INTRO = "Reached together: everyone's progress counts."
local GOAL_ROW = 74
local GOAL_BAR = 6

local GOLD = Skin.GOLD
local MUTED = Skin.MUTED
local DIM = Skin.DIM
local TEXT = Skin.TEXT
local ONLINE = Skin.ONLINE
local ERROR = { 1, 0.42, 0.42 }

local SORTS = { { "online", "Online first" }, { "level", "Level" }, { "name", "Name" } }
local HIGHLIGHT = Skin.FEED_HIGHLIGHT

local core
local frame
local setup
local nav
local section
local rosterView
local feedView
local goalsView
local footer
local rowFrames = {}
local altFrames = {}
-- What the UI itself remembers: the tab, the sort, which Members show
-- Alts, and which Feed entries were unseen when the Feed was opened (they
-- keep their "new" tag until you leave the Feed).
local tab = "roster"
local order = "online"
local expanded = {}
local fresh = {}

local function classColor(classFilename)
  local color = classFilename and RAID_CLASS_COLORS[classFilename]
  if color then return color.r, color.g, color.b end
  return 1, 1, 1
end

local function className(classFilename)
  return LOCALIZED_CLASS_NAMES_MALE[classFilename] or classFilename or ""
end

-- "online", or how long ago: 5m, 3h, 2d.
local function ago(seconds)
  seconds = math.max(0, seconds)
  if seconds < 60 * 60 then return ("%dm"):format(math.floor(seconds / 60)) end
  if seconds < 24 * 60 * 60 then return ("%dh"):format(math.floor(seconds / 3600 + 0.5)) end
  return ("%dd"):format(math.floor(seconds / 86400 + 0.5))
end

local function lastSeenText(online, sinceSeen)
  if online then return "online" end
  return ago(sinceSeen) .. " ago"
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

-- The Character under the mouse: owner.row is its Member's row, and
-- owner.character the Character (the row itself for the shown one).
local function showTooltip(owner)
  local row, character = owner.row, owner.character
  if not row then return end
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:AddLine(character.name, classColor(character.classFilename))
  GameTooltip:AddLine(("Level %d %s %s"):format(character.level, className(character.classFilename),
    character.main and "(Main)" or "(Alt)"), 1, 1, 1)
  GameTooltip:AddLine(row.own and "Your Character" or ("%s's Character"):format(row.displayName or "?"), 1, 1, 1)
  if character.zone then GameTooltip:AddLine(character.zone) end
  if character.maxXp and character.maxXp > 0 then
    GameTooltip:AddLine(("XP %d%%"):format(math.floor(100 * (character.xp or 0) / character.maxXp)), MUTED[1], MUTED[2], MUTED[3])
  end
  GameTooltip:AddLine(("Deaths: %d"):format(character.deaths or 0), MUTED[1], MUTED[2], MUTED[3])
  if character.playing then
    GameTooltip:AddLine(row.own and "Playing now" or "Online now", ONLINE[1], ONLINE[2], ONLINE[3])
  else
    GameTooltip:AddLine("Last seen " .. ago(character.sinceSeen) .. " ago", MUTED[1], MUTED[2], MUTED[3])
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

  -- The gold left border for "can play with you".
  row.border = row:CreateTexture(nil, "ARTWORK")
  row.border:SetColorTexture(GOLD[1], GOLD[2], GOLD[3])
  row.border:SetPoint("TOPLEFT")
  row.border:SetPoint("BOTTOMLEFT")
  row.border:SetWidth(2)

  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(28, 28)
  row.icon:SetPoint("TOPLEFT", INSET, -7)
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
  Skin.fill(row.xp, { 1, 1, 1, 0.06 })

  rowFrames[#rowFrames + 1] = row
  return row
end

local function drawRow(row, data)
  row.row, row.character = data, data
  row.ownBackground:SetShown(data.own)
  row.border:SetShown(data.canPlay)
  setDot(row.dot, data.online)
  row.icon:SetAtlas("classicon-" .. (data.classFilename or ""):lower())
  row.name:SetText(data.name)
  row.name:SetTextColor(classColor(data.classFilename))
  row.level:SetText(data.level)
  setTag(row.member, data.own and "you" or data.displayName, MUTED)
  setTag(row.onAlt, data.onAlt and "on alt" or nil, MUTED)
  setTag(row.canPlay, data.canPlay and "can play" or nil, GOLD)
  placeTags(row.level, { row.member, row.onAlt, row.canPlay })
  row.zone:SetText(data.zone or "")

  row.seen:SetText(data.own and "" or lastSeenText(data.online, data.sinceSeen))
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
  row.xp:SetStatusBarColor(classColor(data.classFilename))
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
  alt.right:SetText(zone .. ago(data.sinceSeen) .. " ago")
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

-- "CREW ———— [Sort: Online first]" between your row and the Members'.
local function createSection()
  section = CreateFrame("Frame", nil, rosterView.content)
  section:SetHeight(SECTION)
  local label = Skin.label(section, "tiny", DIM)
  label:SetPoint("LEFT", INSET, -2)
  label:SetText("CREW")

  section.sort = CreateFrame("Button", nil, section)
  section.sort:SetHeight(18)
  section.sort:SetPoint("RIGHT", -INSET, -2)
  Skin.border(section.sort, Skin.BORDER)
  Skin.fill(section.sort, Skin.HOVER, "HIGHLIGHT")
  section.sort.label = Skin.label(section.sort, "small", MUTED)
  section.sort.label:SetPoint("CENTER")
  section.sort:SetScript("OnClick", showSortMenu)

  local line = section:CreateTexture(nil, "ARTWORK")
  line:SetColorTexture(Skin.LINE[1], Skin.LINE[2], Skin.LINE[3], Skin.LINE[4])
  line:SetHeight(1)
  line:SetPoint("LEFT", label, "RIGHT", 8, 0)
  line:SetPoint("RIGHT", section.sort, "LEFT", -8, 0)
end

local function drawSection()
  if not section then createSection() end
  for _, sort in ipairs(SORTS) do
    if sort[1] == order then section.sort.label:SetText("Sort: " .. sort[2]) end
  end
  section.sort:SetWidth(section.sort.label:GetStringWidth() + 16)
end

-- The sidebar: Roster and Feed on top, Settings at the bottom, each with a
-- greyed game icon tinted like its label.
local NAV_ICONS = {
  roster = "Interface\\FriendsFrame\\UI-Toast-FriendOnlineIcon",
  feed = "Interface\\FriendsFrame\\UI-Toast-ChatInviteIcon",
  goals = Skin.FEED_ICONS.goal,
  settings = "Interface\\Buttons\\UI-OptionsButton",
}

local function navButton(label, icon, onClick)
  local button = CreateFrame("Button", nil, frame.sidebar)
  button:SetHeight(NAV_HEIGHT)
  button.selected = Skin.fill(button, { GOLD[1], GOLD[2], GOLD[3], 0.07 })
  button.bar = button:CreateTexture(nil, "ARTWORK")
  button.bar:SetColorTexture(GOLD[1], GOLD[2], GOLD[3])
  button.bar:SetPoint("TOPLEFT")
  button.bar:SetPoint("BOTTOMLEFT")
  button.bar:SetWidth(2)
  Skin.fill(button, { 1, 1, 1, 0.03 }, "HIGHLIGHT")
  button.icon = button:CreateTexture(nil, "ARTWORK")
  button.icon:SetSize(14, 14)
  button.icon:SetPoint("LEFT", 12, 0)
  button.icon:SetTexture(icon)
  button.icon:SetDesaturated(true)
  button.label = Skin.label(button, "text", MUTED)
  button.label:SetPoint("LEFT", button.icon, "RIGHT", 7, 0)
  button.label:SetText(label)
  button:SetScript("OnClick", onClick)
  return button
end

local function setSelected(button, selected)
  button.selected:SetShown(selected)
  button.bar:SetShown(selected)
  Skin.color(button.label, selected and TEXT or MUTED)
  Skin.color(button.icon, selected and GOLD or MUTED)
end

local function createNav()
  nav = {}
  local function open(name)
    return function()
      tab = name
      Panel.refresh()
    end
  end
  nav.roster = navButton("Roster", NAV_ICONS.roster, open("roster"))
  nav.roster:SetPoint("TOPLEFT", 0, -8)
  nav.roster:SetPoint("TOPRIGHT", 0, -8)
  nav.feed = navButton("Feed", NAV_ICONS.feed, open("feed"))
  nav.feed:SetPoint("TOPLEFT", nav.roster, "BOTTOMLEFT")
  nav.feed:SetPoint("TOPRIGHT", nav.roster, "BOTTOMRIGHT")
  nav.feed.badge = Skin.badge(nav.feed, "tiny", { 0.1, 0.08, 0 }, GOLD)
  nav.feed.badge:SetPoint("RIGHT", -10, 0)
  nav.goals = navButton("Goals", NAV_ICONS.goals, open("goals"))
  nav.goals:SetPoint("TOPLEFT", nav.feed, "BOTTOMLEFT")
  nav.goals:SetPoint("TOPRIGHT", nav.feed, "BOTTOMRIGHT")
  -- The panel steps aside so it doesn't cover the settings.
  nav.settings = navButton("Settings", NAV_ICONS.settings, function()
    if ns.Settings.open() then frame:Hide() end
  end)
  nav.settings:SetPoint("BOTTOMLEFT", 0, 8)
  nav.settings:SetPoint("BOTTOMRIGHT", 0, 8)
end

local function drawNav(unseen)
  if not nav then createNav() end
  setSelected(nav.roster, tab == "roster")
  setSelected(nav.feed, tab == "feed")
  setSelected(nav.goals, tab == "goals")
  setSelected(nav.settings, false)
  nav.feed.badge:SetText(unseen)
  nav.feed.badge:SetShown(unseen > 0 and tab ~= "feed")
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
  view.content:SetSize(CONTENT_WIDTH - 6, 1)
  view:SetScrollChild(view.content)
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
  feedView.empty = Skin.label(feedView.content, "text", MUTED)
  feedView.empty:SetPoint("TOPLEFT", INSET, -INSET)
  feedView.empty:SetWidth(CONTENT_WIDTH - 2 * INSET)
  feedView.empty:SetText(FEED_EMPTY)
end

-- A day's label in a chip on the timeline's line.
local function createFeedDay()
  local day = CreateFrame("Frame", nil, feedView.content)
  day:SetHeight(16)
  Skin.fill(day, Skin.RAISED)
  Skin.border(day, Skin.BORDER)
  day.label = Skin.label(day, "tiny", DIM)
  day.label:SetPoint("CENTER", 0, 0)
  feedView.days[#feedView.days + 1] = day
  return day
end

local function roundTexture(parent, size, color, sublevel)
  local texture = parent:CreateTexture(nil, "ARTWORK", nil, sublevel)
  texture:SetSize(size, size)
  texture:SetPoint("CENTER")
  texture:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
  return Skin.round(parent, texture)
end

-- An entry: a round node on the line with the kind's icon, the text, and
-- the time under it.
local function createFeedEntry()
  local entry = CreateFrame("Frame", nil, feedView.content)
  entry:SetHeight(FEED_ENTRY)
  local node = CreateFrame("Frame", nil, entry)
  node:SetSize(NODE + 2, NODE + 2)
  node:SetPoint("TOPLEFT", INSET - 1, -3)
  roundTexture(node, NODE + 2, { 1, 1, 1, 0.12 }, 1)
  roundTexture(node, NODE, { Skin.WINDOW[1], Skin.WINDOW[2], Skin.WINDOW[3] }, 2)
  roundTexture(node, NODE - 4, { 0.13, 0.12, 0.16 }, 3)
  entry.icon = node:CreateTexture(nil, "OVERLAY")
  entry.icon:SetSize(16, 16)
  entry.icon:SetPoint("CENTER")
  entry.glyph = Skin.label(node, "glyph", Skin.FEED_ICON_COLOR)
  entry.glyph:SetPoint("CENTER", 0, 0)

  entry.text = Skin.label(entry, "text")
  entry.text:SetPoint("TOPLEFT", node, "TOPRIGHT", 10, -2)
  entry.text:SetPoint("RIGHT", -INSET - 36, 0)
  entry.text:SetWordWrap(false)
  entry.new = Skin.badge(entry, "tiny", { 0.1, 0.08, 0 }, GOLD)
  entry.new:SetText("NEW")
  entry.time = Skin.label(entry, "small", MUTED)
  entry.time:SetPoint("TOPLEFT", entry.text, "BOTTOMLEFT", 0, -2)
  entry.reactors = Skin.label(entry, "small", MUTED)
  entry.reactors:SetPoint("LEFT", entry.time, "RIGHT", 8, 0)
  entry.reactors:SetPoint("RIGHT", -INSET - 36, 0)
  entry.reactors:SetWordWrap(false)

  -- The Reaction button. With no Reactions yet it only shows on hover.
  entry.react = Skin.reactionButton(entry, REACT, function(self)
    local data = self:GetParent().data
    if data and data.key then core:react(data.key) end
  end)
  entry.react:SetPoint("TOPRIGHT", -INSET - 4, -4)
  local function updateHoverOnly()
    local button = entry.react
    button:SetAlpha((not button.hoverOnly or entry:IsMouseOver()) and 1 or 0)
  end
  entry.react.onHover = updateHoverOnly
  entry:EnableMouse(true)
  entry:SetScript("OnEnter", updateHoverOnly)
  entry:SetScript("OnLeave", updateHoverOnly)
  entry.updateHoverOnly = updateHoverOnly
  feedView.entries[#feedView.entries + 1] = entry
  return entry
end

local function dayTitle(day)
  if day.daysAgo == 0 then return "TODAY" end
  if day.daysAgo == 1 then return "YESTERDAY" end
  return date("%A %d %B", day.time):upper()
end

local function entryKey(entry)
  return ("%d:%s:%s:%s"):format(entry.time, entry.memberId or "", entry.kind, entry.guid or "")
end

-- Who reacted, after the time: the Reaction's icon and their names, You
-- in gold.
local function reactorsText(entry)
  if #entry.reactors == 0 then return "" end
  local names = {}
  for i, reactor in ipairs(entry.reactors) do
    names[i] = reactor.you and Skin.hex(GOLD) .. "You|r" or reactor.name
  end
  return Skin.reactionGlyph(entry.reaction, 12) .. " " .. table.concat(names, ", ")
end

local function drawFeedEntry(line, entry)
  line.data = entry
  line.reactors:SetText(reactorsText(entry))
  line.react:SetShown(entry.canReact)
  if entry.canReact then
    line.react:SetReaction(entry.reaction, entry.reacted)
    line.react.hoverOnly = #entry.reactors == 0
    line.updateHoverOnly()
  end
  Skin.feedIcon(line.icon, line.glyph, entry.kind)
  line.text:SetText(entry.text)
  Skin.color(line.text, HIGHLIGHT[entry.kind] and GOLD or entry.own and MUTED or TEXT)
  line.time:SetText(date("%H:%M", entry.time))
  local isNew = fresh[entryKey(entry)]
  line.new:ClearAllPoints()
  line.new:SetPoint("LEFT", line.text, "LEFT", line.text:GetStringWidth() + 6, 0)
  line.new:SetShown(isNew == true)
end

-- Draws the Feed and marks it seen; what was unseen keeps its tag while
-- the Feed stays open.
local function drawFeed(feed)
  if not feedView then createFeedView() end
  for _, day in ipairs(feed.days) do
    for _, entry in ipairs(day.entries) do
      if not entry.seen then fresh[entryKey(entry)] = true end
    end
  end

  local y, dayCount, entryCount = -INSET, 0, 0
  for _, day in ipairs(feed.days) do
    dayCount = dayCount + 1
    local chip = feedView.days[dayCount] or createFeedDay()
    chip:ClearAllPoints()
    chip:SetPoint("TOPLEFT", feedView.content, "TOPLEFT", INSET - 4, y)
    chip.label:SetText(dayTitle(day))
    chip:SetWidth(chip.label:GetStringWidth() + 16)
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
  feedView.empty:SetShown(entryCount == 0)
  feedView.line:ClearAllPoints()
  feedView.line:SetPoint("TOPLEFT", LINE_X, -INSET - 8)
  feedView.line:SetPoint("BOTTOMLEFT", LINE_X, INSET + 8)
  feedView.line:SetShown(entryCount > 0)
  feedView.content:SetHeight(math.max(-y + INSET, 1))
  feedView:Show()
  updateThumb(feedView)
  if feed.unseen > 0 then core:feedSeen() end
end

-- Goals: a row per track, in the panel's fixed height.
local function createGoalsView()
  goalsView = CreateFrame("Frame", nil, frame.content)
  goalsView:SetAllPoints()
  goalsView.intro = Skin.label(goalsView, "small", MUTED)
  goalsView.intro:SetPoint("TOPLEFT", INSET, -INSET)
  goalsView.intro:SetText(GOALS_INTRO)
  goalsView.rows = {}
  for i = 1, 3 do
    local row = CreateFrame("Frame", nil, goalsView)
    row:SetHeight(GOAL_ROW)
    row:SetPoint("TOPLEFT", 0, -INSET - 22 - (i - 1) * GOAL_ROW)
    row:SetPoint("RIGHT")
    Skin.edge(row, "TOP", Skin.LINE)
    row.title = Skin.label(row, "body")
    row.title:SetPoint("TOPLEFT", INSET, -12)
    row.numbers = Skin.label(row, "text")
    row.numbers:SetJustifyH("RIGHT")
    row.numbers:SetPoint("TOPRIGHT", -INSET, -13)
    row.bar = CreateFrame("StatusBar", nil, row)
    row.bar:SetPoint("TOPLEFT", INSET, -36)
    row.bar:SetPoint("RIGHT", -INSET, 0)
    row.bar:SetHeight(GOAL_BAR)
    row.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    Skin.fill(row.bar, { 1, 1, 1, 0.08 })
    row.last = Skin.label(row, "small", MUTED)
    row.last:SetPoint("TOPLEFT", row.bar, "BOTTOMLEFT", 0, -8)
    goalsView.rows[i] = row
  end
end

-- "Reached 200 on 14 Oct", or that nothing is yet.
local function lastReached(goal)
  if not goal.last then return "Not reached yet" end
  local when = date("%d %b", goal.last.time):gsub("^0", "")
  if goal.complete then return "Complete since " .. when end
  return ("Reached %d on %s"):format(goal.last.rung, when)
end

local function drawGoal(row, goal)
  row.title:SetText(goal.title)
  if goal.complete then
    row.numbers:SetText("Complete")
    Skin.color(row.numbers, GOLD)
    row.bar:SetMinMaxValues(0, 1)
    row.bar:SetValue(1)
  else
    -- Everyone at level N counts Members; the others count up to the rung.
    local unit = goal.track == "everyone" and " Members" or ""
    row.numbers:SetText(("%d / %d%s"):format(goal.value, goal.goal, unit))
    Skin.color(row.numbers, TEXT)
    row.bar:SetMinMaxValues(0, math.max(goal.goal, 1))
    row.bar:SetValue(math.min(goal.value, goal.goal))
  end
  row.bar:SetStatusBarColor(GOLD[1], GOLD[2], GOLD[3], goal.complete and 1 or 0.85)
  row.last:SetText(lastReached(goal))
  Skin.color(row.last, goal.complete and GOLD or MUTED)
end

local function drawGoals()
  if not goalsView then createGoalsView() end
  for i, goal in ipairs(core:goals()) do
    if goalsView.rows[i] then drawGoal(goalsView.rows[i], goal) end
  end
  goalsView:Show()
end

local function create()
  frame = Skin.window("BFFPanel", WIDTH, TITLE)
  frame:SetPoint("CENTER")
  frame:SetHeight(HEIGHT)
  frame:SetScript("OnShow", Panel.refresh)
  frame:SetScript("OnHide", function() fresh = {} end)
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

  frame.sidebar = CreateFrame("Frame", nil, frame)
  frame.sidebar:SetPoint("TOPLEFT", 1, -HEADER)
  frame.sidebar:SetPoint("BOTTOMLEFT", 1, 1)
  frame.sidebar:SetWidth(SIDEBAR - 1)
  Skin.fill(frame.sidebar, Skin.SIDEBAR)
  Skin.edge(frame.sidebar, "RIGHT", Skin.LINE)

  frame.content = CreateFrame("Frame", nil, frame)
end

-- With a Crew the content sits right of the sidebar; without one it takes
-- the whole window.
local function layout(inCrew)
  frame.sidebar:SetShown(inCrew)
  frame.content:ClearAllPoints()
  frame.content:SetPoint("TOPLEFT", inCrew and SIDEBAR or 1, -HEADER)
  frame.content:SetPoint("BOTTOMRIGHT", -1, 1)
  frame.onlineDot:SetShown(inCrew)
  if not inCrew then frame.headerRight:SetText("") end
end

-- The setup view: display name, then Start a Crew or Join a Crew.
local function createSetup()
  setup = CreateFrame("Frame", nil, frame.content)
  setup:SetPoint("TOPLEFT", INSET + 4, -INSET)
  setup:SetPoint("BOTTOMRIGHT", -INSET - 4, INSET)

  local nameLabel = Skin.label(setup, "small", MUTED)
  nameLabel:SetPoint("TOPLEFT", 0, -4)
  nameLabel:SetText("DISPLAY NAME")
  setup.name = Skin.editBox(setup, 220)
  setup.name:SetMaxLetters(16)
  setup.name:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 0, -6)
  setup.nameError = Skin.label(setup, "small", ERROR)
  setup.nameError:SetPoint("TOPLEFT", setup.name, "BOTTOMLEFT", 0, -4)

  local startLabel = Skin.label(setup, "small", MUTED)
  startLabel:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 0, -62)
  startLabel:SetText("START A CREW")
  setup.start = Skin.button(setup, "Start", function()
    local _, reason = core:startCrew(setup.name:GetText())
    setup.nameError:SetText(reason and ns.MESSAGES[reason] or "")
  end, true)
  setup.start:SetPoint("TOPLEFT", startLabel, "BOTTOMLEFT", 0, -6)

  local joinLabel = Skin.label(setup, "small", MUTED)
  joinLabel:SetPoint("TOPLEFT", startLabel, "BOTTOMLEFT", 0, -50)
  joinLabel:SetText("JOIN A CREW")
  setup.code = Skin.editBox(setup, 140)
  setup.code:SetMaxLetters(12)
  setup.code:SetPoint("TOPLEFT", joinLabel, "BOTTOMLEFT", 0, -6)
  local function join()
    local _, reason = core:joinCrew(setup.code:GetText(), setup.name:GetText())
    setup.nameError:SetText(reason == "invalidName" and ns.MESSAGES.invalidName or "")
    setup.codeError:SetText(reason and reason ~= "invalidName" and ns.MESSAGES[reason] or "")
  end
  setup.code:SetScript("OnEnterPressed", join)
  setup.join = Skin.button(setup, "Join", join)
  setup.join:SetPoint("LEFT", setup.code, "RIGHT", 8, 0)
  setup.codeError = Skin.label(setup, "small", ERROR)
  setup.codeError:SetPoint("TOPLEFT", setup.code, "BOTTOMLEFT", 0, -4)
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
  footer.removed:SetPoint("BOTTOMRIGHT", -INSET, 19)
  footer.removed.text = Skin.label(footer.removed, "small", GOLD)
  footer.removed.text:SetPoint("RIGHT")
  footer.removed.text:SetJustifyH("RIGHT")
  footer.removed:SetScript("OnClick", showRemovedMenu)

  footer.hidden = Skin.label(footer, "small", DIM)
  footer.hidden:SetJustifyH("RIGHT")

  footer.status = Skin.label(footer, "small", MUTED)
  footer.status:SetPoint("TOPLEFT", INSET, -10)
  -- Set outright so the wrapped text has a height before layout.
  footer.status:SetWidth(CONTENT_WIDTH - 2 * INSET)
  footer.status:SetWordWrap(true)

  local codeLabel = Skin.label(footer, "small", MUTED)
  codeLabel:SetPoint("BOTTOMLEFT", INSET, 15)
  codeLabel:SetText("Crew code")
  footer.code = Skin.editBox(footer, 100)
  footer.code:SetHeight(22)
  footer.code:SetJustifyH("CENTER")
  footer.code:SetPoint("LEFT", codeLabel, "RIGHT", 8, 0)
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
    footer.hidden:SetPoint("RIGHT", footer.removed, "LEFT", -10, 0)
  else
    footer.hidden:SetPoint("BOTTOMRIGHT", -INSET, 19)
  end
  footer.hidden:SetText(summary.hidden > 0 and ("Hidden: %d (unseen %dd)"):format(summary.hidden,
    ns.Core.HIDE_AFTER_DAYS) or "")

  footer.code.crewCode = crew.code
  footer.code:SetText(crew.code)
  footer.code:HighlightText()

  local status = ""
  if crew.leaving then
    status = LEAVING
  elseif core:isPaused() then
    status = PAUSED
  elseif crew.alone then
    status = WAITING
  end
  footer.status:SetText(status)
  local height = 46
  if status ~= "" then height = height + footer.status:GetStringHeight() + 6 end
  footer:SetHeight(height)
  footer:Show()
  return height
end

local function hideRoster()
  if rosterView then rosterView:Hide() end
  if footer then footer:Hide() end
end

local function drawRoster(crew, summary)
  if feedView then feedView:Hide() end
  if goalsView then goalsView:Hide() end
  if not rosterView then rosterView = createScrollView() end
  local footerHeight = drawFooter(crew, summary)
  rosterView:ClearAllPoints()
  rosterView:SetPoint("TOPLEFT")
  rosterView:SetPoint("BOTTOMRIGHT", -6, footerHeight)
  rosterView:Show()
  drawSection()
  section:Hide()

  local y = -6
  local rowCount, altCount = 0, 0
  for i, data in ipairs(core:rows(order)) do
    if not data.own and not section:IsShown() and i > 1 then
      place(section, y)
      section:Show()
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

  rosterView.content:SetHeight(-y + 6)
  updateThumb(rosterView)
end

-- Redraws from Core, if the panel is open.
function Panel.refresh()
  if not frame or not frame:IsShown() then return end
  local crew = core:crew()
  layout(crew ~= nil)
  if not crew then
    hideRoster()
    if feedView then feedView:Hide() end
    if goalsView then goalsView:Hide() end
    showSetup()
    return
  end
  if setup then setup:Hide() end

  local summary = core:summary()
  frame.headerRight:SetText(("%d of %d online"):format(summary.online, summary.members))
  local feed = core:feed()
  drawNav(feed.unseen)
  if tab == "feed" then
    hideRoster()
    if goalsView then goalsView:Hide() end
    drawFeed(feed)
  elseif tab == "goals" then
    hideRoster()
    if feedView then feedView:Hide() end
    fresh = {}
    drawGoals()
  else
    fresh = {}
    drawRoster(crew, summary)
  end
end

function Panel.toggle()
  if not frame then create() end
  frame:SetShown(not frame:IsShown())
end

-- Opens the panel on a tab: "roster", "feed" or "goals".
function Panel.show(name)
  if not frame then create() end
  tab = name
  if frame:IsShown() then Panel.refresh() else frame:Show() end
end

function Panel.start(theCore)
  core = theCore
end
