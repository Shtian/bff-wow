-- Panel: the BFF window, variant A "Roster" from the panel decision (#7).
-- Without a Crew it shows the setup view (display name, Start or Join); in
-- one, a Roster and a Feed tab. The Roster has your own row pinned on top,
-- then a row per Member with expandable Alts, sort buttons, a tooltip and
-- right-click menu per Character, and a footer with Pause sharing, the
-- hidden count, removed Members and the Crew code. The Feed lists Core's
-- entries by day and marks them seen while open. It never sees a Member
-- record.

local _, ns = ...

local Panel = {}
ns.Panel = Panel

local WIDTH = 360
local ROW_HEIGHT = 38
local ALT_HEIGHT = 18
local DIVIDER = 18
local PADDING = 12
local TOP = 30
local TABS = 26
local SORTBAR = 24
local FEED_HEIGHT = 320
local FEED_LINE = 16
local FEED_DAY = 22
local FOOTER = 92
local SETUP_HEIGHT = 230
-- Last seen goes stale, so the open panel redraws this often.
local REDRAW_EVERY = 30

local WAITING = "Waiting for your Crew. Members show up when they or someone who has seen them is online."
local LEAVING = "Leaving the Crew. It finishes once BFF's channel is reachable."
local PAUSED = "Sharing is paused: the others see you as offline."
local FEED_EMPTY = "Nothing yet. Dings, deaths and new Characters show up here."
local RECEIVE_ONLY = "Trial accounts can join a Crew and see it, but the others won't see you."

local GOLD = { 1, 0.82, 0 }
local MUTED = { 0.6, 0.6, 0.6 }
local WHITE = { 1, 1, 1 }
local ONLINE = { 0.25, 1, 0.25 }

local SORTS = { { "online", "Online" }, { "level", "Level" }, { "name", "Name" } }
-- Entries shown in gold.
local HIGHLIGHT = { maxLevel = true, joined = true, left = true }

local core
local frame
local setup
local tabBar
local feedView
local sortBar
local footer
local divider
local rowFrames = {}
local altFrames = {}
-- What the UI itself remembers: the tab, the sort, which Members show
-- Alts, and which Feed entries were new when the Feed tab showed them.
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
  return ago(sinceSeen)
end

local function setColor(fontString, color)
  fontString:SetTextColor(color[1], color[2], color[3])
end

local function setDot(texture, online)
  texture:SetTexture(online and "Interface\\FriendsFrame\\StatusIcon-Online"
    or "Interface\\FriendsFrame\\StatusIcon-Offline")
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

local function createLabel(parent, text, template)
  local label = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormal")
  label:SetJustifyH("LEFT")
  label:SetText(text)
  return label
end

local function createTag(parent)
  local tag = createLabel(parent, "", "GameFontNormalSmall")
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
  if text then setColor(tag, color) end
end

local function characterButton(height)
  local button = CreateFrame("Button", nil, frame)
  button:SetHeight(height)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
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

local function createRow()
  local row = characterButton(ROW_HEIGHT)
  row:SetScript("OnClick", onRowClick)

  -- The gold left border for "can play with you".
  row.border = row:CreateTexture(nil, "ARTWORK")
  row.border:SetColorTexture(GOLD[1], GOLD[2], GOLD[3])
  row.border:SetPoint("TOPLEFT")
  row.border:SetPoint("BOTTOMLEFT")
  row.border:SetWidth(2)

  row.dot = row:CreateTexture(nil, "ARTWORK")
  row.dot:SetSize(12, 12)
  row.dot:SetPoint("TOPLEFT", 6, -5)

  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(22, 22)
  row.icon:SetPoint("TOPLEFT", 20, -3)

  row.name = createLabel(row, "", "GameFontNormal")
  row.name:SetPoint("TOPLEFT", 48, -4)
  row.level = createLabel(row, "", "GameFontHighlightSmall")
  row.level:SetPoint("LEFT", row.name, "RIGHT", 5, 0)
  row.member = createTag(row)
  row.onAlt = createTag(row)
  row.canPlay = createTag(row)

  row.zone = createLabel(row, "", "GameFontHighlightSmall")
  row.zone:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
  setColor(row.zone, MUTED)

  row.seen = createLabel(row, "", "GameFontHighlightSmall")
  row.seen:SetJustifyH("RIGHT")
  row.seen:SetPoint("TOPRIGHT", -4, -4)
  row.more = createLabel(row, "", "GameFontHighlightSmall")
  row.more:SetJustifyH("RIGHT")
  row.more:SetPoint("TOPRIGHT", row.seen, "BOTTOMRIGHT", 0, -2)

  row.xp = CreateFrame("StatusBar", nil, row)
  row.xp:SetPoint("BOTTOMLEFT", 48, 2)
  row.xp:SetPoint("BOTTOMRIGHT", -4, 2)
  row.xp:SetHeight(3)
  row.xp:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  row.xp:SetStatusBarColor(0.58, 0.0, 0.55)
  local background = row.xp:CreateTexture(nil, "BACKGROUND")
  background:SetAllPoints()
  background:SetColorTexture(0, 0, 0, 0.5)

  rowFrames[#rowFrames + 1] = row
  return row
end

local function drawRow(row, data)
  row.row, row.character = data, data
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

  row.seen:SetText(lastSeenText(data.online, data.sinceSeen))
  setColor(row.seen, data.online and ONLINE or MUTED)
  if #data.alts > 0 then
    row.more:SetText(("%s %d more"):format(expanded[data.memberId] and "-" or "+", #data.alts))
    setColor(row.more, data.altsCanPlay and GOLD or MUTED)
  else
    row.more:SetText("")
  end

  local maxXp = data.maxXp or 0
  row.xp:SetMinMaxValues(0, math.max(maxXp, 1))
  row.xp:SetValue(maxXp > 0 and (data.xp or 0) or 0)
  row:SetAlpha(data.online and 1 or 0.7)
  row:Show()
end

local function onAltClick(button, mouse)
  if mouse == "RightButton" then showMenu(button) end
end

local function createAlt()
  local alt = characterButton(ALT_HEIGHT)
  alt:SetScript("OnClick", onAltClick)
  alt.dot = alt:CreateTexture(nil, "ARTWORK")
  alt.dot:SetSize(10, 10)
  alt.dot:SetPoint("LEFT", 30, 0)
  alt.name = createLabel(alt, "", "GameFontNormalSmall")
  alt.name:SetPoint("LEFT", 44, 0)
  alt.level = createLabel(alt, "", "GameFontHighlightSmall")
  alt.level:SetPoint("LEFT", alt.name, "RIGHT", 5, 0)
  alt.main = createTag(alt)
  alt.canPlay = createTag(alt)
  alt.right = createLabel(alt, "", "GameFontHighlightSmall")
  alt.right:SetJustifyH("RIGHT")
  alt.right:SetPoint("RIGHT", -4, 0)
  setColor(alt.right, MUTED)
  altFrames[#altFrames + 1] = alt
  return alt
end

local function drawAlt(alt, row, data)
  alt.row, alt.character = row, data
  setDot(alt.dot, false)
  alt.name:SetText(data.name)
  alt.name:SetTextColor(classColor(data.classFilename))
  alt.level:SetText(data.level)
  setTag(alt.main, data.main and "main" or nil, MUTED)
  setTag(alt.canPlay, data.canPlay and "can play" or nil, GOLD)
  placeTags(alt.level, { alt.main, alt.canPlay })
  local zone = data.zone and data.zone .. " · " or ""
  alt.right:SetText(zone .. ago(data.sinceSeen))
  alt:Show()
end

local function hideAll(lines, from)
  for i = from, #lines do lines[i]:Hide() end
end

-- Places a line under the previous one, at y from the frame's top.
local function place(line, y)
  line:ClearAllPoints()
  line:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, y)
  line:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PADDING, y)
end

local function createSortBar()
  sortBar = CreateFrame("Frame", nil, frame)
  sortBar:SetHeight(SORTBAR)
  sortBar:SetPoint("TOPLEFT", PADDING, -TOP - TABS)
  sortBar:SetPoint("TOPRIGHT", -PADDING, -TOP - TABS)
  local label = createLabel(sortBar, "Sort", "GameFontNormalSmall")
  label:SetPoint("LEFT", 4, 0)
  local anchor = label
  sortBar.buttons = {}
  for _, sort in ipairs(SORTS) do
    local button = CreateFrame("Button", nil, sortBar, "UIPanelButtonTemplate")
    button:SetSize(60, 18)
    button:SetText(sort[2])
    button:SetPoint("LEFT", anchor, "RIGHT", 6, 0)
    button:SetScript("OnClick", function()
      order = sort[1]
      Panel.refresh()
    end)
    button.order = sort[1]
    sortBar.buttons[#sortBar.buttons + 1] = button
    anchor = button
  end
end

local function drawSortBar()
  if not sortBar then createSortBar() end
  for _, button in ipairs(sortBar.buttons) do
    button:SetEnabled(button.order ~= order)
  end
  sortBar:Show()
end

local function createTabBar()
  tabBar = CreateFrame("Frame", nil, frame)
  tabBar:SetHeight(TABS)
  tabBar:SetPoint("TOPLEFT", PADDING, -TOP)
  tabBar:SetPoint("TOPRIGHT", -PADDING, -TOP)
  tabBar.buttons = {}
  local anchor
  for _, name in ipairs({ "roster", "feed" }) do
    local button = CreateFrame("Button", nil, tabBar, "UIPanelButtonTemplate")
    button:SetSize(90, 20)
    if anchor then
      button:SetPoint("LEFT", anchor, "RIGHT", 4, 0)
    else
      button:SetPoint("LEFT", 0, 0)
    end
    button:SetScript("OnClick", function()
      tab = name
      Panel.refresh()
    end)
    button.tab = name
    tabBar.buttons[name] = button
    anchor = button
  end
  local line = tabBar:CreateTexture(nil, "ARTWORK")
  line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.3)
  line:SetHeight(1)
  line:SetPoint("BOTTOMLEFT", 0, 1)
  line:SetPoint("BOTTOMRIGHT", 0, 1)
end

local function drawTabBar(unseen)
  if not tabBar then createTabBar() end
  tabBar.buttons.roster:SetText("Roster")
  tabBar.buttons.feed:SetText(unseen > 0 and tab ~= "feed" and ("Feed (%d)"):format(unseen) or "Feed")
  for name, button in pairs(tabBar.buttons) do button:SetEnabled(name ~= tab) end
  tabBar:Show()
end

-- The Feed tab: a scrolling list of day headers and entry lines.
local function createFeedView()
  feedView = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  feedView:SetPoint("TOPLEFT", PADDING, -TOP - TABS - 4)
  feedView:SetPoint("RIGHT", frame, "RIGHT", -PADDING - 24, 0)
  feedView:SetHeight(FEED_HEIGHT)
  feedView.content = CreateFrame("Frame", nil, feedView)
  feedView.content:SetSize(WIDTH - 2 * PADDING - 24, FEED_HEIGHT)
  feedView:SetScrollChild(feedView.content)
  feedView.days = {}
  feedView.lines = {}
  feedView.empty = createLabel(feedView.content, FEED_EMPTY, "GameFontHighlightSmall")
  feedView.empty:SetPoint("TOPLEFT", 4, -8)
  feedView.empty:SetPoint("RIGHT", -4, 0)
  setColor(feedView.empty, MUTED)
end

local function createFeedDay()
  local day = createLabel(feedView.content, "", "GameFontNormalSmall")
  feedView.days[#feedView.days + 1] = day
  return day
end

local function createFeedLine()
  local line = CreateFrame("Frame", nil, feedView.content)
  line:SetHeight(FEED_LINE)
  line.dot = line:CreateTexture(nil, "ARTWORK")
  line.dot:SetSize(8, 8)
  line.dot:SetPoint("LEFT", 0, 0)
  line.dot:SetTexture("Interface\\FriendsFrame\\StatusIcon-Online")
  line.time = createLabel(line, "", "GameFontHighlightSmall")
  line.time:SetPoint("LEFT", 12, 0)
  line.time:SetWidth(36)
  setColor(line.time, MUTED)
  line.text = createLabel(line, "", "GameFontHighlightSmall")
  line.text:SetPoint("LEFT", line.time, "RIGHT", 4, 0)
  line.text:SetPoint("RIGHT", -2, 0)
  line.text:SetWordWrap(false)
  feedView.lines[#feedView.lines + 1] = line
  return line
end

local function entryKey(entry)
  return ("%d|%s|%s|%s"):format(entry.time, entry.memberId, entry.kind, entry.guid or "")
end

local function dayTitle(day)
  if day.daysAgo == 0 then return "Today" end
  if day.daysAgo == 1 then return "Yesterday" end
  return date("%A %d %B", day.time)
end

local function placeInFeed(item, y)
  item:ClearAllPoints()
  item:SetPoint("TOPLEFT", feedView.content, "TOPLEFT", 4, y)
  item:SetPoint("RIGHT", feedView.content, "RIGHT", -4, 0)
end

-- Draws the Feed and marks it seen. Entries unseen until now keep a dot
-- while the panel stays open.
local function drawFeed(feed)
  if not feedView then createFeedView() end
  local y, dayCount, lineCount = 0, 0, 0
  for _, day in ipairs(feed.days) do
    dayCount = dayCount + 1
    local title = feedView.days[dayCount] or createFeedDay()
    placeInFeed(title, y - 6)
    title:SetText(dayTitle(day))
    title:Show()
    y = y - FEED_DAY
    for _, entry in ipairs(day.entries) do
      local key = entryKey(entry)
      if not entry.seen then fresh[key] = true end
      lineCount = lineCount + 1
      local line = feedView.lines[lineCount] or createFeedLine()
      placeInFeed(line, y)
      line.dot:SetShown(fresh[key] == true)
      line.time:SetText(date("%H:%M", entry.time))
      line.text:SetText(entry.text)
      setColor(line.text, HIGHLIGHT[entry.kind] and GOLD or entry.own and MUTED or WHITE)
      line:Show()
      y = y - FEED_LINE
    end
  end
  hideAll(feedView.days, dayCount + 1)
  hideAll(feedView.lines, lineCount + 1)
  feedView.empty:SetShown(lineCount == 0)
  feedView.content:SetHeight(math.max(-y, 1))
  feedView:Show()
  frame:SetHeight(TOP + TABS + FEED_HEIGHT + 2 * PADDING)
  if feed.unseen > 0 then core:feedSeen() end
end

local function createDivider()
  divider = CreateFrame("Frame", nil, frame)
  divider:SetHeight(DIVIDER)
  local label = createLabel(divider, "Crew", "GameFontNormalSmall")
  label:SetPoint("LEFT", 4, 0)
  local line = divider:CreateTexture(nil, "ARTWORK")
  line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.3)
  line:SetHeight(1)
  line:SetPoint("LEFT", label, "RIGHT", 6, 0)
  line:SetPoint("RIGHT", -4, 0)
end

local function create()
  frame = CreateFrame("Frame", "BFFPanel", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(WIDTH, TOP + ROW_HEIGHT + PADDING)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("DIALOG")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
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
  frame:Hide()
  -- Closes on Escape.
  table.insert(UISpecialFrames, "BFFPanel")

  local title = frame.TitleText
  if not title then
    title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", 0, -5)
  end
  frame.title = title
  title:SetText("BFF")
end

local function createEditBox(parent, width)
  local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  box:SetSize(width, 20)
  box:SetAutoFocus(false)
  box:SetScript("OnEscapePressed", box.ClearFocus)
  return box
end

local function createButton(parent, text, onClick)
  local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  button:SetSize(110, 22)
  button:SetText(text)
  button:SetScript("OnClick", onClick)
  return button
end

-- The setup view: display name, then Start a Crew or Join a Crew.
local function createSetup()
  setup = CreateFrame("Frame", nil, frame)
  setup:SetPoint("TOPLEFT", PADDING + 4, -TOP)
  setup:SetPoint("BOTTOMRIGHT", -PADDING - 4, PADDING)

  local nameLabel = createLabel(setup, "Display name")
  nameLabel:SetPoint("TOPLEFT", 0, -4)
  setup.name = createEditBox(setup, 200)
  setup.name:SetMaxLetters(16)
  setup.name:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 6, -6)
  setup.nameError = createLabel(setup, "", "GameFontRedSmall")
  setup.nameError:SetPoint("TOPLEFT", setup.name, "BOTTOMLEFT", -6, -4)

  local startLabel = createLabel(setup, "Start a Crew")
  startLabel:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 0, -56)
  setup.start = createButton(setup, "Start", function()
    local _, reason = core:startCrew(setup.name:GetText())
    setup.nameError:SetText(reason and ns.MESSAGES[reason] or "")
  end)
  setup.start:SetPoint("TOPLEFT", startLabel, "BOTTOMLEFT", 0, -6)
  setup.receiveOnly = createLabel(setup, RECEIVE_ONLY, "GameFontHighlightSmall")
  setup.receiveOnly:SetPoint("TOPLEFT", startLabel, "BOTTOMLEFT", 0, -8)
  setup.receiveOnly:SetPoint("RIGHT", setup, "RIGHT")

  local joinLabel = createLabel(setup, "Join a Crew")
  joinLabel:SetPoint("TOPLEFT", startLabel, "BOTTOMLEFT", 0, -48)
  setup.code = createEditBox(setup, 140)
  setup.code:SetMaxLetters(12)
  setup.code:SetPoint("TOPLEFT", joinLabel, "BOTTOMLEFT", 6, -6)
  local function join()
    local _, reason = core:joinCrew(setup.code:GetText(), setup.name:GetText())
    setup.nameError:SetText(reason == "invalidName" and ns.MESSAGES.invalidName or "")
    setup.codeError:SetText(reason and reason ~= "invalidName" and ns.MESSAGES[reason] or "")
  end
  setup.code:SetScript("OnEnterPressed", join)
  setup.join = createButton(setup, "Join", join)
  setup.join:SetPoint("LEFT", setup.code, "RIGHT", 8, 0)
  setup.codeError = createLabel(setup, "", "GameFontRedSmall")
  setup.codeError:SetPoint("TOPLEFT", setup.code, "BOTTOMLEFT", -6, -4)
end

local function showSetup()
  if not setup then createSetup() end
  if not setup:IsShown() then
    setup.name:SetText(ns.defaultDisplayName())
    setup.code:SetText("")
    setup.nameError:SetText("")
    setup.codeError:SetText("")
  end
  local receiveOnly = core:isReceiveOnly()
  setup.start:SetShown(not receiveOnly)
  setup.receiveOnly:SetShown(receiveOnly)
  setup:Show()
  frame.title:SetText("BFF")
  frame:SetHeight(SETUP_HEIGHT)
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

-- Below the rows: Pause sharing and the hidden count, removed Members, the
-- waiting, leaving or paused line, and the Crew code in a read-only box
-- with the text selected, since addons can't copy to the clipboard.
local function createFooter()
  footer = CreateFrame("Frame", nil, frame)
  footer:SetHeight(FOOTER)
  footer:SetPoint("BOTTOMLEFT", PADDING, PADDING)
  footer:SetPoint("BOTTOMRIGHT", -PADDING, PADDING)

  footer.pause = CreateFrame("CheckButton", nil, footer, "UICheckButtonTemplate")
  footer.pause:SetSize(22, 22)
  footer.pause:SetPoint("TOPLEFT", 0, 0)
  footer.pause:SetScript("OnClick", function(box)
    core:setPaused(box:GetChecked())
  end)
  local pauseLabel = createLabel(footer, "Pause sharing", "GameFontNormalSmall")
  pauseLabel:SetPoint("LEFT", footer.pause, "RIGHT", 2, 0)

  footer.hidden = createLabel(footer, "", "GameFontHighlightSmall")
  footer.hidden:SetPoint("TOPRIGHT", -4, -5)
  setColor(footer.hidden, MUTED)

  footer.removed = CreateFrame("Button", nil, footer)
  footer.removed:SetSize(120, 14)
  footer.removed:SetPoint("TOPRIGHT", footer.hidden, "BOTTOMRIGHT", 0, -4)
  footer.removed.text = createLabel(footer.removed, "", "GameFontNormalSmall")
  footer.removed.text:SetPoint("RIGHT")
  footer.removed.text:SetJustifyH("RIGHT")
  footer.removed:SetScript("OnClick", showRemovedMenu)

  footer.status = createLabel(footer, "", "GameFontHighlightSmall")
  footer.status:SetPoint("TOPLEFT", footer.pause, "BOTTOMLEFT", 2, -18)
  footer.status:SetPoint("RIGHT")

  local codeLabel = createLabel(footer, "Crew code", "GameFontNormalSmall")
  codeLabel:SetPoint("BOTTOMLEFT", 0, 6)
  footer.code = createEditBox(footer, 110)
  footer.code:SetPoint("LEFT", codeLabel, "RIGHT", 12, 0)
  footer.code:SetScript("OnEditFocusGained", function(box) box:HighlightText() end)
  footer.code:SetScript("OnTextChanged", function(box, userInput)
    if userInput then
      box:SetText(box.crewCode)
      box:HighlightText()
    end
  end)
end

local function drawFooter(crew, summary)
  if not footer then createFooter() end
  footer.pause:SetChecked(core:isPaused())
  footer.pause:SetEnabled(not core:isReceiveOnly())
  footer.hidden:SetText(("Hidden: %d Character%s (unseen %dd)"):format(summary.hidden,
    summary.hidden == 1 and "" or "s", ns.Core.HIDE_AFTER_DAYS))
  local removed = #core:removed()
  footer.removed.text:SetText(removed > 0 and ("Removed: %d"):format(removed) or "")
  footer.removed:SetShown(removed > 0)

  footer.code.crewCode = crew.code
  footer.code:SetText(crew.code)
  footer.code:HighlightText()
  if crew.leaving then
    footer.status:SetText(LEAVING)
  elseif core:isPaused() then
    footer.status:SetText(PAUSED)
  elseif crew.alone then
    footer.status:SetText(WAITING)
  else
    footer.status:SetText("")
  end
  footer:Show()
end

local function hideRoster()
  hideAll(rowFrames, 1)
  hideAll(altFrames, 1)
  if sortBar then sortBar:Hide() end
  if divider then divider:Hide() end
  if footer then footer:Hide() end
end

-- Redraws from Core, if the panel is open.
function Panel.refresh()
  if not frame or not frame:IsShown() then return end
  local crew = core:crew()
  if not crew then
    hideRoster()
    if tabBar then tabBar:Hide() end
    if feedView then feedView:Hide() end
    showSetup()
    return
  end
  if setup then setup:Hide() end

  local summary = core:summary()
  frame.title:SetText(("BFF  ·  %d/%d online"):format(summary.online, summary.members))
  local feed = core:feed()
  drawTabBar(feed.unseen)
  if tab == "feed" then
    hideRoster()
    drawFeed(feed)
    return
  end
  if feedView then feedView:Hide() end

  drawSortBar()
  if not divider then createDivider() end
  divider:Hide()

  local y = -TOP - TABS - SORTBAR
  local rowCount, altCount = 0, 0
  for i, data in ipairs(core:rows(order)) do
    if not data.own and not divider:IsShown() and i > 1 then
      place(divider, y)
      divider:Show()
      y = y - DIVIDER
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

  drawFooter(crew, summary)
  frame:SetHeight(-y + FOOTER + PADDING)
end

function Panel.toggle()
  if not frame then create() end
  frame:SetShown(not frame:IsShown())
end

-- Opens the panel on a tab: "roster" or "feed".
function Panel.show(name)
  if not frame then create() end
  tab = name
  if frame:IsShown() then Panel.refresh() else frame:Show() end
end

function Panel.start(theCore)
  core = theCore
end
