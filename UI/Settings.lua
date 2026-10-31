-- Settings: the one page in the game's Settings panel (AddOns → BFF) from
-- the settings decision (#16): You (display name, read-only Crew code),
-- Sharing (Appear offline, Leave Crew) and Notifications and display (chat
-- line, While you were away, minimap button). A canvas page, since the
-- standard controls have no text box. Everything is read and written
-- through Core. See docs/design/settings-and-release.md.

local _, ns = ...

local Page = {}
ns.Settings = Page

local INDENT = 16
local SECTION_GAP = 22

local core
local category
local frame

local function createLabel(parent, text, template)
  local label = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
  label:SetText(text)
  label:SetJustifyH("LEFT")
  return label
end

local function createEditBox(width)
  local box = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
  box:SetSize(width, 20)
  box:SetAutoFocus(false)
  return box
end

-- A checkbox with its label, calling set(checked) on click.
local function createCheckbox(text, set)
  local box = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
  box:SetSize(26, 26)
  box:SetScript("OnClick", function(self) set(self:GetChecked()) end)
  box.label = createLabel(frame, text)
  box.label:SetPoint("LEFT", box, "RIGHT", 4, 0)
  return box
end

-- Puts the current name back, without saving.
local function showName()
  frame.name.shown = ns.defaultDisplayName()
  frame.name:SetText(frame.name.shown)
  frame.nameError:SetText("")
end

-- Saves the typed display name when the box loses focus, or says why it
-- can't. Escape cancels, and an untouched box saves nothing.
local function nameFocusLost(box)
  if box.cancelled then
    box.cancelled = nil
    return showName()
  end
  if box:GetText() == box.shown then return end
  local ok, reason = core:setDisplayName(box:GetText())
  if ok then showName() else frame.nameError:SetText(ns.MESSAGES[reason]) end
end

local function createYou()
  local header = createLabel(frame, "You", "GameFontNormalLarge")
  header:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -SECTION_GAP)

  local nameLabel = createLabel(frame, "Display name")
  nameLabel:SetPoint("TOPLEFT", header, "BOTTOMLEFT", INDENT, -12)
  frame.name = createEditBox(180)
  frame.name:SetMaxLetters(16)
  frame.name:SetPoint("LEFT", nameLabel, "LEFT", 120, 0)
  frame.name:SetScript("OnEnterPressed", frame.name.ClearFocus)
  frame.name:SetScript("OnEscapePressed", function(box)
    box.cancelled = true
    box:ClearFocus()
  end)
  frame.name:SetScript("OnEditFocusLost", nameFocusLost)
  frame.nameError = createLabel(frame, "", "GameFontRedSmall")
  frame.nameError:SetPoint("LEFT", frame.name, "RIGHT", 10, 0)

  -- Read-only, with the text selected, since addons can't copy to the
  -- clipboard.
  frame.codeLabel = createLabel(frame, "Crew code")
  frame.codeLabel:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 0, -16)
  frame.code = createEditBox(110)
  frame.code:SetPoint("LEFT", frame.codeLabel, "LEFT", 120, 0)
  frame.code:SetScript("OnEditFocusGained", function(box) box:HighlightText() end)
  frame.code:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
  frame.code:SetScript("OnTextChanged", function(box, userInput)
    if userInput then
      box:SetText(box.crewCode)
      box:HighlightText()
    end
  end)
  frame.nameLabel = nameLabel
end

local function createSharing()
  frame.sharing = createLabel(frame, "Sharing", "GameFontNormalLarge")
  frame.pause = createCheckbox("Appear offline: send nothing, so your Crew sees you as offline", function(checked)
    core:setPaused(checked)
  end)
  frame.pause.inset = INDENT - 4
  frame.pause:SetPoint("TOPLEFT", frame.sharing, "BOTTOMLEFT", frame.pause.inset, -8)
  frame.leave = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  frame.leave:SetSize(120, 22)
  frame.leave:SetText("Leave Crew")
  frame.leave.inset = INDENT
  frame.leave:SetPoint("TOPLEFT", frame.pause, "BOTTOMLEFT", frame.leave.inset - frame.pause.inset, -8)
  frame.leave:SetScript("OnClick", ns.confirmLeave)
end

local function createNotifications()
  frame.notifications = createLabel(frame, "Notifications and display", "GameFontNormalLarge")
  frame.chatLines = createCheckbox("Chat message for live events", function(checked)
    core:setChatLines(checked)
  end)
  frame.chatLines:SetPoint("TOPLEFT", frame.notifications, "BOTTOMLEFT", INDENT - 4, -8)
  frame.away = createCheckbox("Show While you were away on login", function(checked)
    core:setAwayPopup(checked)
  end)
  frame.away:SetPoint("TOPLEFT", frame.chatLines, "BOTTOMLEFT", 0, -4)
  frame.minimap = createCheckbox("Show minimap button", function(checked)
    core:setMinimapShown(checked)
  end)
  frame.minimap:SetPoint("TOPLEFT", frame.away, "BOTTOMLEFT", 0, -4)
end

-- The settings panel calls these; nothing waits for Okay or Defaults.
local function noop() end

local function create()
  frame = CreateFrame("Frame")
  frame:Hide()
  frame.title = createLabel(frame, "BFF", "GameFontNormalHuge")
  frame.title:SetPoint("TOPLEFT", 16, -16)
  createYou()
  createSharing()
  createNotifications()
  frame:SetScript("OnShow", Page.refresh)
  -- A refused name is forgotten once the page closes.
  frame:SetScript("OnHide", function() frame.nameError:SetText("") end)
  frame.OnRefresh = Page.refresh
  frame.OnCommit = noop
  frame.OnDefault = noop
end

-- Redraws from Core, if the page is open. Out of a Crew the Crew code and
-- Leave Crew are hidden, and the sections below close up.
function Page.refresh()
  if not frame or not frame:IsShown() then return end
  local crew = core:crew()

  if not frame.name:HasFocus() and frame.nameError:GetText() == "" then showName() end
  frame.codeLabel:SetShown(crew ~= nil)
  frame.code:SetShown(crew ~= nil)
  -- Left alone while focused, so the selection holds.
  if crew and not frame.code:HasFocus() then
    frame.code.crewCode = crew.code
    frame.code:SetText(crew.code)
  end

  frame.sharing:ClearAllPoints()
  frame.sharing:SetPoint("TOPLEFT", crew and frame.codeLabel or frame.nameLabel, "BOTTOMLEFT",
    -INDENT, -SECTION_GAP)
  frame.pause:SetChecked(core:isPaused())
  frame.pause:SetEnabled(crew ~= nil)
  frame.leave:SetShown(crew ~= nil and not crew.leaving)

  -- Under Leave Crew, or else Appear offline, back at the section's left
  -- edge (each sits a different inset in from it).
  local under = frame.leave:IsShown() and frame.leave or frame.pause
  frame.notifications:ClearAllPoints()
  frame.notifications:SetPoint("TOPLEFT", under, "BOTTOMLEFT", -under.inset, -SECTION_GAP)
  frame.chatLines:SetChecked(core:isChatLinesOn())
  frame.away:SetChecked(core:isAwayPopupOn())
  frame.minimap:SetChecked(core:isMinimapShown())
end

-- Opens the game's Settings panel on this page. Returns true, or false in
-- combat, where the panel can't open.
function Page.open()
  if InCombatLockdown() then
    ns.say(ns.MESSAGES.settingsInCombat)
    return false
  end
  Settings.OpenToCategory(category:GetID())
  return true
end

function Page.start(theCore)
  core = theCore
  create()
  category = Settings.RegisterCanvasLayoutCategory(frame, "BFF")
  Settings.RegisterAddOnCategory(category)
end
