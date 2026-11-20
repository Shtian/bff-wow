local _, ns = ...

local Panel = {}
ns.Panel = Panel

local Skin = ns.Skin

local SIDEBAR = 124
local SCROLLBAR = 6
local GRIP = 12
local HEADER = Skin.HEADER_HEIGHT
local NAV_HEIGHT = 30
local NAV_TOP = 8
local NAV_BOTTOM = 22
local NAV_CHIP_X = 6
local NAV_CHIP_Y = 2
local NAV_CHIP_RADIUS = 2
local VERSION_HEIGHT = 18
local INSET = 12
local SMALL_BUTTON = 20
local NEW_DOT = Skin.UNREAD_DOT
local REDRAW_EVERY = 30
local TIP_BUTTON = 84
local TIP_PAD = 10

local TITLE = "Best Friends in Forever"
local SETUP_WIDTH = 320
local SETUP_COLUMN = 150
local SETUP_COLUMNS_Y = -72

local GOLD = Skin.GOLD
local MUTED = Skin.MUTED
local DIM = Skin.DIM
local TEXT = Skin.TEXT
local ONLINE = Skin.ONLINE
local ERROR = { 1, 0.42, 0.42 }

local TABS = {
  { key = "roster", label = "Roster", module = ns.RosterTab },
  { key = "feed", label = "Feed", module = ns.FeedTab, badge = function(core) return core:unseen() end },
  { key = "trophies", label = "Trophies", module = ns.TrophiesTab },
  { key = "playtimes", label = "Play Times", module = ns.PlayTimesTab },
  { key = "spares", label = "Spares", module = ns.SparesTab, badge = function(core) return core:unseenSpares() end },
  { key = "professions", label = "Professions", module = ns.ProfessionsTab },
  { key = "dungeons", label = "Dungeons", module = ns.DungeonsTab },
  { key = "catches", label = "Catches", module = ns.CatchesTab },
  { key = "settings", label = "Settings", module = ns.SettingsTab, nav = "foot" },
  { key = "whatsnew", module = ns.WhatsNewTab, nav = "version" },
}

local core
local frame
local camp
local campHeight = 0
local firelight
local tipCard
local tipHeight = 0
local setup
local nav
local pages = {}
local tab = "roster"
local shown

local function tabNamed(key)
  for _, entry in ipairs(TABS) do
    if entry.key == key then return entry end
  end
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

local function createVersion(onClick)
  local version = CreateFrame("Button", nil, frame.sidebar)
  version:SetHeight(VERSION_HEIGHT)
  version:SetPoint("BOTTOMLEFT", 0, NAV_BOTTOM - VERSION_HEIGHT)
  version:SetPoint("BOTTOMRIGHT", 0, NAV_BOTTOM - VERSION_HEIGHT)
  version.selected = Skin.chip(version, Skin.CHIP, NAV_CHIP_X, 1, NAV_CHIP_RADIUS)
  Skin.chip(version, Skin.CHIP_HOVER, NAV_CHIP_X, 1, NAV_CHIP_RADIUS, "HIGHLIGHT")
  version.label = Skin.label(version, "tiny", DIM)
  version.label:SetPoint("LEFT", NAV_CHIP_X + 10, 0)
  version.label:SetText(ns.VERSION)
  version.dot = Skin.unreadDot(version)
  version.dot:SetPoint("CENTER", version.label, "LEFT", -(NEW_DOT / 2 + 3), 0)
  version:SetScript("OnClick", onClick)
  version:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("What's new in BFF")
    GameTooltip:Show()
  end)
  version:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return version
end

local function createNav()
  nav = { buttons = {} }
  local above
  for _, entry in ipairs(TABS) do
    local open = function() Panel.show(entry.key) end
    local button
    if entry.nav == "version" then
      button = createVersion(open)
      nav.version = button
    else
      button = navButton(entry.label, open)
      nav.buttons[#nav.buttons + 1] = button
      if entry.nav == "foot" then
        button:SetPoint("BOTTOMLEFT", 0, NAV_BOTTOM)
        button:SetPoint("BOTTOMRIGHT", 0, NAV_BOTTOM)
      elseif above then
        button:SetPoint("TOPLEFT", above, "BOTTOMLEFT")
        button:SetPoint("TOPRIGHT", above, "BOTTOMRIGHT")
        above = button
      else
        button:SetPoint("TOPLEFT", 0, -NAV_TOP)
        button:SetPoint("TOPRIGHT", 0, -NAV_TOP)
        above = button
      end
      if entry.badge then
        button.badge = Skin.badge(button, "tiny", { 0.1, 0.08, 0 }, GOLD)
        button.badge:SetPoint("RIGHT", -10, 0)
      end
    end
    nav[entry.key] = button
  end
end

local function drawNav()
  if not nav then createNav() end
  local sidebarHeight = frame:GetHeight() - HEADER - campHeight - tipHeight - 1
  local height = math.min(NAV_HEIGHT, math.floor((sidebarHeight - NAV_TOP - NAV_BOTTOM) / #nav.buttons))
  for _, entry in ipairs(TABS) do
    local button = nav[entry.key]
    if entry.nav ~= "version" then
      setSelected(button, tab == entry.key)
      button:SetHeight(height)
    end
    if entry.badge then
      local count = entry.badge(core)
      button.badge:SetText(count)
      button.badge:SetShown(count > 0 and tab ~= entry.key)
    end
  end
  nav.version.selected:SetShown(tab == "whatsnew")
  Skin.color(nav.version.label, tab == "whatsnew" and TEXT or DIM)
  nav.version.dot:SetShown(core:hasNewChanges())
  nav.version:EnableMouse(core:whatsNew() ~= nil)
end

local function scrollView(page)
  if not page.view then
    page.view = ns.ScrollView.new(page.frame, page.listWidth)
    page.view:SetPoint("TOPLEFT")
    page.view:SetPoint("BOTTOMRIGHT", -SCROLLBAR, 0)
  end
  return page.view
end

local function pageFor(entry)
  local page = pages[entry.key]
  if page then return page end
  page = {
    frame = CreateFrame("Frame", nil, frame.content),
    window = frame,
    core = core,
    redraw = Panel.refresh,
    scrollView = scrollView,
  }
  page.frame:SetAllPoints()
  page.frame:Hide()
  pages[entry.key] = page
  return page
end

local function leave(entry, closed)
  if entry.module.leave then entry.module.leave(closed) end
end

local function switchTo(entry)
  if shown == entry then return end
  if shown then
    leave(shown, false)
    pages[shown.key].frame:Hide()
  end
  shown = entry
end

local function drawTab(entry, inCrew)
  local page = pageFor(entry)
  page.width = frame:GetWidth() - (inCrew and SIDEBAR + 1 or 2)
  page.listWidth = page.width - SCROLLBAR
  page.height = frame:GetHeight() - HEADER - campHeight - tipHeight - 1
  page.campShown = camp:IsShown()
  page.frame:Show()
  entry.module.draw(page)
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
  grip:SetScript("OnLeave", function() GameTooltip:Hide() end)
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
    if shown then leave(shown, true) end
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
    local columns, height = camp:Measure(width, ns.CampScene.BAND_ROWS)
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

local function hideSetup()
  if setup then setup:Hide() end
end

function Panel.refresh()
  if not frame or not frame:IsShown() then return end
  local crew = core:crew()
  layout(crew ~= nil)
  local entry
  if crew then
    entry = tabNamed(tab) or TABS[1]
  elseif tab == "settings" then
    entry = tabNamed(tab)
  end
  switchTo(entry)
  if not entry then return showSetup() end
  hideSetup()
  if crew then frame.headerRight:SetText(core:rosterCounts().header) end
  drawTab(entry, crew ~= nil)
  if crew then drawNav() end
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
  ns.PlayTimesTab.pick(memberId)
  Panel.show("playtimes")
end

function Panel.start(theCore)
  core = theCore
  ns.ProfessionsTab.sortLike(ns.RosterTab.order)
end
