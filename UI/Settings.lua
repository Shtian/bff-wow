-- Settings: the one page in the game's Settings panel (AddOns → BFF) from
-- the settings decision (#16): You (display name, read-only Crew code),
-- then a section per section of Core's settings list (Sharing, with Leave
-- Crew under Appear offline; Notifications and display; Toasts from the
-- toasts decision). Every on/off setting in the list gets a checkbox built
-- from core:settings(); the sound picker and Move toasts are drawn by hand.
-- A canvas page, since the standard controls have no text box. Everything
-- is read and written through Core. See docs/design/settings-and-release.md
-- and docs/design/toasts.md.

local _, ns = ...

local Page = {}
ns.Settings = Page

-- The settings panel calls this for Okay and Defaults; nothing waits for
-- them.
local function noop() end

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
  nameLabel.inset = INDENT
  frame.codeLabel.inset = INDENT
end

-- The sound picker: a radio per sound the client has; choosing one plays
-- it.
local function buildSoundMenu(_, root)
  for _, sound in ipairs(ns.Toasts.sounds()) do
    root:CreateRadio(sound.label, function() return core:setting("toastSound") == sound.key end, function()
      core:setSetting("toastSound", sound.key)
      ns.Toasts.play(sound.key)
    end)
  end
end

-- The game's own dropdown, as on its Settings pages: the chosen sound in
-- a select box with an arrow. A client without the template gets a button
-- that opens the same menu.
local DROPDOWN = "WowStyle1DropdownTemplate"

-- Each picker has :draw(), which shows the chosen sound: the dropdown
-- reads it from its menu's radios, the button is given it as text.
local function createSoundPicker()
  local hasDropdown = C_XMLUtil and C_XMLUtil.GetTemplateInfo
    and C_XMLUtil.GetTemplateInfo(DROPDOWN) ~= nil
  if hasDropdown then
    local dropdown = CreateFrame("DropdownButton", nil, frame, DROPDOWN)
    dropdown:SetupMenu(buildSoundMenu)
    dropdown.draw = dropdown.GenerateMenu
    return dropdown
  end
  local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  button:SetScript("OnClick", function(owner) MenuUtil.CreateContextMenu(owner, buildSoundMenu) end)
  function button:draw()
    self:SetText(ns.Toasts.soundLabel(core:setting("toastSound")))
  end
  return button
end

-- The controls for settings that aren't on/off, by kind: each makes the
-- control, with :draw(value) and the element the page lays out.
local custom = {}

-- The sound, chosen from a dropdown, with Play beside it.
function custom.sound(setting)
  local label = createLabel(frame, setting.label)
  label.inset, label.gap = INDENT, 14
  local picker = createSoundPicker()
  picker:SetSize(160, 22)
  picker:SetPoint("LEFT", label, "LEFT", 116, 0)
  local play = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  play:SetSize(60, 22)
  play:SetText("Play")
  play:SetPoint("LEFT", picker, "RIGHT", 6, 0)
  play:SetScript("OnClick", function() ns.Toasts.play(core:setting(setting.key)) end)
  return {
    element = label,
    draw = function() picker:draw() end,
    setEnabled = function(on)
      label:SetAlpha(on and 1 or 0.5)
      picker:SetEnabled(on)
      play:SetEnabled(on)
    end,
  }
end

-- Move toasts: the position is set by dragging, so there's nothing to draw.
function custom.position(setting)
  local move = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  move:SetSize(120, 22)
  move:SetText(setting.label)
  move:SetScript("OnClick", ns.Toasts.move)
  move.inset, move.gap = INDENT, 14
  return {
    element = move,
    draw = noop,
    setEnabled = function(on) move:SetEnabled(on) end,
  }
end

-- An on/off setting: a checkbox.
local function createToggle(setting)
  local box = createCheckbox(setting.label, function(checked)
    core:setSetting(setting.key, checked)
  end)
  box.inset, box.gap = INDENT - 4, 4
  return {
    element = box,
    draw = function(on) box:SetChecked(on) end,
    setEnabled = function(on) box:SetEnabled(on) end,
  }
end

-- Leave Crew, under Appear offline.
local function createLeave()
  local leave = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  leave:SetSize(120, 22)
  leave:SetText("Leave Crew")
  leave:SetScript("OnClick", ns.confirmLeave)
  leave.inset, leave.gap = INDENT, 8
  frame.leave = leave
  return leave
end

-- What the page puts under a setting's control, by key.
local extras = { paused = createLeave }

-- A header and a control per setting for each section of Core's list, in
-- order, as frame.elements for refresh to lay out.
local function createSections()
  frame.controls = {}
  for _, section in ipairs(core:settings()) do
    local header = createLabel(frame, section.title, "GameFontNormalLarge")
    header.inset, header.header = 0, true
    frame.elements[#frame.elements + 1] = header
    for _, setting in ipairs(section.settings) do
      local make = setting.kind == "toggle" and createToggle or custom[setting.kind]
      local control = make(setting)
      control.section, control.kind = section.title, setting.kind
      frame.controls[setting.key] = control
      frame.elements[#frame.elements + 1] = control.element
      if extras[setting.key] then
        frame.elements[#frame.elements + 1] = extras[setting.key]()
      end
    end
  end
end

-- Stacks the sections under the You section (under the Crew code while in
-- a Crew, else the display name). Each element sits its own inset in from
-- the section's left edge; hidden ones close up.
local function layout(crew)
  local above = crew and frame.codeLabel or frame.nameLabel
  for _, element in ipairs(frame.elements) do
    if element:IsShown() then
      element:ClearAllPoints()
      if element.header then
        element:SetPoint("TOPLEFT", above, "BOTTOMLEFT", -above.inset, -SECTION_GAP)
      else
        element:SetPoint("TOPLEFT", above, "BOTTOMLEFT", element.inset - above.inset,
          -(above.header and 8 or element.gap))
      end
      above = element
    end
  end
end

-- Draws one setting's control. With toasts off, the Toasts section's
-- controls that aren't on/off (sound, Move toasts) are greyed out.
local function drawSetting(key, value)
  local control = frame.controls[key]
  if not control then return end
  control.draw(value)
  if key == "toasts" then
    for _, other in pairs(frame.controls) do
      if other.kind ~= "toggle" and other.section == control.section then other.setEnabled(value) end
    end
  end
end

local function create()
  frame = CreateFrame("Frame")
  frame:Hide()
  frame.title = createLabel(frame, "BFF", "GameFontNormalHuge")
  frame.title:SetPoint("TOPLEFT", 16, -16)
  createYou()
  frame.elements = {}
  createSections()
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
  frame.leave:SetShown(crew ~= nil and not crew.leaving)
  layout(crew)

  for _, section in ipairs(core:settings()) do
    for _, setting in ipairs(section.settings) do drawSetting(setting.key, setting.value) end
  end
  -- Appear offline needs a Crew to appear offline to.
  frame.controls.paused.setEnabled(crew ~= nil)
end

-- Updates the control for a setting that changed, if the page is open.
function Page.settingChanged(key, value)
  if not frame or not frame:IsShown() then return end
  drawSetting(key, value)
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
