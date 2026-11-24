local _, ns = ...

local RosterTab = {}
ns.RosterTab = RosterTab

local Skin = ns.Skin

local ROW_HEIGHT = 44
local ALT_HEIGHT = 20
local SECTION = 26
local INSET = 12
local SMALL_BUTTON = 20
local CODE_LINE = 15
local ALONE_CARD_PAD = 16
local SORTS = { { "online", "Online first" }, { "level", "Level" }, { "name", "Name" } }

local GOLD = Skin.GOLD
local MUTED = Skin.MUTED
local DIM = Skin.DIM
local ONLINE = Skin.ONLINE

local core
local page
local view
local section
local footer
local laterSections = {}
local rowFrames = {}
local altFrames = {}
local order = "online"
local expanded = {}

local classColor = Skin.classColor

StaticPopupDialogs.BFF_REMOVE_MEMBER = {
  text = "Remove %s? Only you stop seeing them; the rest of the Crew still does.",
  button1 = YES,
  button2 = NO,
  OnAccept = function(_, memberId) core:removeMember(memberId) end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
}

function RosterTab.order()
  return order
end

local function showTooltip(owner)
  if not owner.row then return end
  ns.CharacterTooltip.showBeside(page.window, owner, owner.row, owner.character)
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
      root:CreateButton(("When does %s play?"):format(name), function() ns.Panel.showPlayTimes(row.memberId) end)
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
  local button = CreateFrame("Button", nil, view.content)
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
    page.redraw()
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
  Skin.color(row.dot, data.online and ONLINE or Skin.OFFLINE)
  row.icon:SetAtlas("classicon-" .. (data.classFilename or ""):lower())
  row.icon:SetShown(not page.campShown)
  if page.campShown then row.figure:SetClass(data.classFilename, data.hat) else row.figure:Hide() end
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

local function place(line, y)
  line:ClearAllPoints()
  line:SetPoint("TOPLEFT", view.content, "TOPLEFT", 0, y)
  line:SetPoint("TOPRIGHT", view.content, "TOPRIGHT", 0, y)
end

local function showSortMenu(owner)
  MenuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateTitle("Sort by")
    for _, sort in ipairs(SORTS) do
      root:CreateRadio(sort[2], function() return order == sort[1] end, function()
        order = sort[1]
        page.redraw()
      end)
    end
  end)
end

local function createSection()
  section = CreateFrame("Frame", nil, view.content)
  section:SetHeight(SECTION)
  local label = Skin.sectionLabel(section, INSET, -2)
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
  section.spares:SetScript("OnClick", function() ns.Panel.show("spares") end)

  local line = Skin.rule(section)
  line:SetPoint("LEFT", label, "RIGHT", 8, 0)
  section.line = line
end

local function laterSection(index)
  local heading = laterSections[index]
  if heading then return heading end
  heading = CreateFrame("Frame", nil, view.content)
  heading:SetHeight(SECTION)
  heading.label = Skin.sectionLabel(heading, INSET, -2)
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
  footer = CreateFrame("Frame", nil, page.frame)
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

  footer.report = Skin.button(footer, "Report a bug", function() ns.Contact.show() end)
  footer.report:SetWidth(110)
  footer.report:SetPoint("TOPLEFT", footer.status, "BOTTOMLEFT", 0, -6)

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
  footer.status:SetWidth(page.width - 2 * INSET)
  local status = not crew.waiting and crew.status or nil
  footer.status:SetText(status or "")
  local height = 46
  if status then height = height + footer.status:GetStringHeight() + 6 end
  footer.report:SetShown(crew.capped and not crew.alone)
  if footer.report:IsShown() then height = height + footer.report:GetHeight() + 6 end
  footer:SetHeight(height)
  return height
end

function RosterTab.showCode()
  ns.Panel.show("roster")
  local box = view and view.alone:IsShown() and view.alone.code:IsShown() and view.alone.code or footer and footer.code
  if not box then return end
  box:SetFocus()
  box:HighlightText()
end

function RosterTab.draw(thePage)
  page, core = thePage, thePage.core
  local crew = core:crew()
  local counts = core:rosterCounts()
  if not view then
    view = page:scrollView()
    view.alone = ns.EmptyState.new(view.content)
  end
  view.alone:SetShown(crew.alone)
  local footerHeight = drawFooter(crew, counts)
  view:Between(0, footerHeight)
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
      view.alone:Set(ns.EmptyState.alone(crew, not core:setting("camp")))
      view.alone:ClearAllPoints()
      view.alone:SetPoint("TOPLEFT", view.content, "TOPLEFT", 0, y - ALONE_CARD_PAD)
      view.alone:Show()
      y = y - ALONE_CARD_PAD - view.alone:Layout(page.listWidth) - ALONE_CARD_PAD
    end
  end
  Skin.hideFrom(rowFrames, rowCount + 1)
  Skin.hideFrom(altFrames, altCount + 1)
  Skin.hideFrom(laterSections, later + 1)

  view:Fit(-y + 6)
end
