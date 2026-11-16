-- SettingsTab: the panel's Settings view, opened from the sidebar's
-- Settings, the minimap button's menu and /bff settings. You (display
-- name, and the Crew code read-only while in one) on top, then a section
-- per section of Core's settings(), each a section label over rows split
-- by Hairlines: the setting's label on the left, wrapping in a narrow
-- window, and its control at the right. An on/off setting is a switch
-- (Skin.switch), and its whole row is clickable; Map pin size and the
-- Pocket Camp's In combat are segmented controls, the toast sound a
-- picker with Play, the Pocket Camp's backdrop opacity and Fade to
-- sliders, and Move toasts and Reset BFF window small buttons. Leave Crew
-- sits under Appear offline. A control greys out while what it needs is
-- off, and a row Core marks hidden (Fade to, while the Pocket Camp doesn't
-- fade in combat) is left off. Out of a Crew there's a Back button on top,
-- to the setup view. Panel owns the scroll view; this fills its content.
-- Everything is read and written through Core. See
-- docs/design/settings-and-release.md.

local _, ns = ...

local SettingsTab = {}
ns.SettingsTab = SettingsTab

local Skin = ns.Skin

local TEXT = Skin.TEXT
local MUTED = Skin.MUTED
local DIM = Skin.DIM
local ERROR = { 1, 0.42, 0.42 }

local INSET = 12
local TOP_GAP = 6
-- A section's label, as What's new's, with room above every one but the
-- first.
local SECTION = 26
local SECTION_GAP = 12
-- A row is at least this tall; a wrapped label gets ROW_PAD above and
-- below.
local ROW = 34
local ROW_PAD = 8
-- Between a row's label and its control.
local CONTROL_GAP = 16
local SMALL_BUTTON = 20
local NAME_BOX = 160
local CODE_BOX = 110
local SLIDER = 120
local SLIDER_VALUE = 36

local view, core
local onBack
local back
-- Sections in order, each { heading, rows }, every row a frame with
-- .control, and :draw(value) and :setEnabled(on) where it has a value.
local sections
-- The rows by setting key.
local rows = {}
local nameRow, codeRow, leaveRow

-- A small button: the secondary plate, 20px high with Small text, as wide
-- as its text.
local function smallButton(parent, text, onClick)
  local button = Skin.button(parent, text, onClick)
  button:SetHeight(SMALL_BUTTON)
  button.label:SetFontObject(Skin.fonts.small)
  function button:SetText(value)
    self.label:SetText(value)
    self:SetWidth(math.max(56, self.label:GetStringWidth() + 20))
  end
  button:SetText(text)
  return button
end

local function sectionHeading(title)
  local heading = CreateFrame("Frame", nil, view.content)
  heading:SetHeight(SECTION)
  heading.label = Skin.sectionLabel(heading, 0, 0)
  heading.label:SetText(title:upper())
  local rule = Skin.rule(heading)
  rule:SetPoint("LEFT", heading.label, "RIGHT", 8, 0)
  rule:SetPoint("RIGHT")
  return heading
end

-- A row with its label; clickable rows get the hover wash.
local function createRow(text, clickable)
  local row = CreateFrame(clickable and "Button" or "Frame", nil, view.content)
  if clickable then Skin.fill(row, Skin.HOVER, "HIGHLIGHT") end
  row.line = row:CreateTexture(nil, "BORDER")
  row.line:SetColorTexture(Skin.LINE[1], Skin.LINE[2], Skin.LINE[3], Skin.LINE[4])
  row.line:SetPoint("TOPLEFT", INSET, 0)
  row.line:SetPoint("TOPRIGHT", -INSET, 0)
  row.line:SetHeight(1)
  row.label = Skin.label(row, "text", TEXT)
  row.label:SetPoint("LEFT", INSET, 0)
  row.label:SetWordWrap(true)
  row.label:SetText(text)
  return row
end

-- Puts a row's control at its right.
local function placeControl(row, control)
  control:SetPoint("RIGHT", row, "RIGHT", -INSET, 0)
  row.control = control
end

local function dimLabel(row, on)
  Skin.color(row.label, on and TEXT or DIM)
end

-- The controls, by kind: each makes the setting's row.
local makers = {}

-- On/off: a switch, and a click anywhere on the row flips it.
function makers.toggle(setting)
  local row = createRow(setting.label, true)
  local switch = Skin.switch(row)
  placeControl(row, switch)
  row:SetScript("OnClick", function()
    local on = not core:setting(setting.key)
    switch:SetOn(on, true)
    core:setSetting(setting.key, on)
  end)
  function row.draw(on) switch:SetOn(on) end
  function row.setEnabled(on)
    row:SetEnabled(on)
    switch:SetEnabled(on)
    dimLabel(row, on)
  end
  return row
end

-- One of a few choices (Map pin size): a cell per choice, side by side,
-- the chosen one on a chip.
function makers.choice(setting)
  local row = createRow(setting.label)
  local control = CreateFrame("Frame", nil, row)
  control:SetHeight(SMALL_BUTTON)
  Skin.border(control, Skin.BORDER)
  local cells, x = {}, 0
  for i, choice in ipairs(setting.choices) do
    local cell = CreateFrame("Button", nil, control)
    cell:SetHeight(SMALL_BUTTON)
    cell.chosen = Skin.fill(cell, Skin.CHIP)
    Skin.fill(cell, Skin.HOVER, "HIGHLIGHT")
    cell.label = Skin.label(cell, "small", MUTED)
    cell.label:SetPoint("CENTER")
    cell.label:SetText(choice.label)
    cell:SetWidth(cell.label:GetStringWidth() + 18)
    cell:SetPoint("LEFT", x, 0)
    if i > 1 then Skin.edge(cell, "LEFT", Skin.BORDER) end
    cell:SetScript("OnClick", function() core:setSetting(setting.key, choice.key) end)
    cell.key = choice.key
    x = x + cell:GetWidth()
    cells[i] = cell
  end
  control:SetWidth(x)
  placeControl(row, control)
  function row.draw(value)
    for _, cell in ipairs(cells) do
      cell.chosen:SetShown(cell.key == value)
      Skin.color(cell.label, cell.key == value and TEXT or MUTED)
    end
  end
  function row.setEnabled(on)
    control:SetAlpha(on and 1 or 0.4)
    for _, cell in ipairs(cells) do cell:SetEnabled(on) end
    dimLabel(row, on)
  end
  return row
end

-- The toast sound: a picker showing the chosen sound, opening a menu of
-- every sound the client has (choosing one plays it), and Play.
function makers.sound(setting)
  local row = createRow(setting.label)
  local control = CreateFrame("Frame", nil, row)
  control:SetHeight(SMALL_BUTTON)
  local play = smallButton(control, "Play", function() ns.Toasts.play(core:setting(setting.key)) end)
  play:SetPoint("RIGHT")
  local picker = smallButton(control, "", function(owner)
    MenuUtil.CreateContextMenu(owner, function(_, root)
      for _, sound in ipairs(ns.Toasts.sounds()) do
        root:CreateRadio(sound.label, function() return core:setting(setting.key) == sound.key end, function()
          core:setSetting(setting.key, sound.key)
          ns.Toasts.play(sound.key)
        end)
      end
    end)
  end)
  picker:SetPoint("RIGHT", play, "LEFT", -6, 0)
  placeControl(row, control)
  function row.draw(value)
    picker:SetText(ns.Toasts.soundLabel(value))
    picker:SetWidth(math.max(120, picker:GetWidth()))
    control:SetWidth(picker:GetWidth() + 6 + play:GetWidth())
  end
  function row.setEnabled(on)
    picker:SetEnabled(on)
    play:SetEnabled(on)
    dimLabel(row, on)
  end
  return row
end

-- Move toasts: the panel steps aside while the sample toast is dragged,
-- and comes back on Settings once it's done.
function makers.position(setting)
  local row = createRow(setting.label)
  local move = smallButton(row, setting.button, function()
    ns.Panel.hide()
    ns.Toasts.move(function() ns.Panel.show("settings") end)
  end)
  placeControl(row, move)
  function row.setEnabled(on)
    move:SetEnabled(on)
    dimLabel(row, on)
  end
  return row
end

-- Reset BFF window: back to the default size, centred. Greyed out while
-- the panel already opens there.
function makers.panelPlace(setting)
  local row = createRow(setting.label)
  local reset = smallButton(row, setting.button, function() core:resetPanelPlace() end)
  placeControl(row, reset)
  function row.draw(place) reset:SetEnabled(place ~= nil) end
  return row
end

-- A percentage, 0 to 100, in steps of 5: a flat slider with its value
-- beside it, saved as it's dragged.
function makers.percent(setting)
  local row = createRow(setting.label)
  local control = CreateFrame("Frame", nil, row)
  control:SetSize(SLIDER + 8 + SLIDER_VALUE, 16)
  local slider = CreateFrame("Slider", nil, control)
  slider:SetOrientation("HORIZONTAL")
  slider:SetSize(SLIDER, 16)
  slider:SetPoint("LEFT")
  slider:SetMinMaxValues(0, 100)
  slider:SetValueStep(5)
  if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
  local track = Skin.fill(slider, Skin.TRACK, "BACKGROUND")
  track:ClearAllPoints()
  track:SetPoint("LEFT")
  track:SetPoint("RIGHT")
  track:SetHeight(4)
  local thumb = slider:CreateTexture(nil, "OVERLAY")
  thumb:SetColorTexture(TEXT[1], TEXT[2], TEXT[3], 1)
  thumb:SetSize(6, 14)
  slider:SetThumbTexture(thumb)
  local fill = Skin.fill(slider, Skin.BAR, "ARTWORK")
  fill:ClearAllPoints()
  fill:SetPoint("LEFT", track, "LEFT")
  fill:SetPoint("RIGHT", thumb, "CENTER")
  fill:SetHeight(4)
  local value = Skin.label(control, "small", MUTED)
  value:SetPoint("RIGHT")
  value:SetJustifyH("RIGHT")
  slider:SetScript("OnValueChanged", function(_, percent, userInput)
    value:SetText(("%d%%"):format(percent))
    if userInput then core:setSetting(setting.key, percent) end
  end)
  placeControl(row, control)
  function row.draw(percent) slider:SetValue(percent) end
  function row.setEnabled(on)
    slider:SetEnabled(on)
    control:SetAlpha(on and 1 or 0.4)
    dimLabel(row, on)
  end
  return row
end

-- Puts the current name back, without saving.
local function showName()
  nameRow.box.shown = ns.defaultDisplayName()
  nameRow.box:SetText(nameRow.box.shown)
  nameRow.error:SetText("")
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
  if ok then showName() else nameRow.error:SetText(ns.MESSAGES[reason]) end
end

-- You: Display name, saved as it loses focus, and the Crew code, read-only
-- with the text selected, since addons can't copy to the clipboard.
local function createYou()
  nameRow = createRow("Display name")
  local box = Skin.editBox(nameRow, NAME_BOX)
  box:SetMaxLetters(16)
  box:SetScript("OnEnterPressed", box.ClearFocus)
  box:SetScript("OnEscapePressed", function(self)
    self.cancelled = true
    self:ClearFocus()
  end)
  box:SetScript("OnEditFocusLost", nameFocusLost)
  nameRow.box = box
  placeControl(nameRow, box)
  nameRow.error = Skin.label(nameRow, "small", ERROR)
  nameRow.error:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", 0, -4)
  nameRow.error:SetJustifyH("RIGHT")

  codeRow = createRow("Crew code")
  local code = Skin.editBox(codeRow, CODE_BOX)
  code:SetJustifyH("CENTER")
  code:SetHighlightColor(1, 1, 1, 0.15)
  code:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
  code:SetScript("OnTextChanged", function(self, userInput)
    if userInput then
      self:SetText(self.crewCode)
      self:HighlightText()
    end
  end)
  codeRow.box = code
  placeControl(codeRow, code)

  return { heading = sectionHeading("You"), rows = { nameRow, codeRow } }
end

-- What goes under a setting's row, by key: Leave Crew under Appear offline.
local function createLeave()
  leaveRow = createRow("Leave your Crew")
  placeControl(leaveRow, smallButton(leaveRow, "Leave Crew", ns.confirmLeave))
  return leaveRow
end
local extras = { paused = createLeave }

local function create()
  back = smallButton(view.content, "Back", function() if onBack then onBack() end end)
  sections = { createYou() }
  for _, section in ipairs(core:settings()) do
    local list = {}
    for _, setting in ipairs(section.settings) do
      local row = makers[setting.kind](setting)
      row.key, row.kind, row.needs, row.section = setting.key, setting.kind, setting.needs, section.title
      rows[setting.key] = row
      list[#list + 1] = row
      if extras[setting.key] then list[#list + 1] = extras[setting.key]() end
    end
    sections[#sections + 1] = { heading = sectionHeading(section.title), rows = list }
  end
end

-- Whether a setting's control is usable: not while a setting it needs is
-- off (Map pin size, ALT over a friend), nor the Toasts section's controls
-- that aren't on/off while toasts are off, nor Appear offline out of a
-- Crew, with no one to appear offline to.
local function enabled(row, values, crew)
  if row.needs and not values[row.needs] then return false end
  if row.kind ~= "toggle" and row.section == rows.toasts.section and not values.toasts then return false end
  if row.key == "paused" then return crew ~= nil end
  return true
end

-- Lays a row out at y, as wide as width, and returns the y under it.
local function placeRow(row, y, first, width)
  row:ClearAllPoints()
  row:SetPoint("TOPLEFT", view.content, "TOPLEFT", 0, y)
  row:SetWidth(width)
  row.line:SetShown(not first)
  local labelWidth = width - 2 * INSET - row.control:GetWidth() - CONTROL_GAP
  row.label:SetWidth(math.max(60, labelWidth))
  local height = math.max(ROW, row.label:GetStringHeight() + 2 * ROW_PAD)
  -- A refused display name says why under the box.
  if row.error and row.error:GetText() ~= "" then
    row.error:SetWidth(width - 2 * INSET)
    height = height + row.error:GetStringHeight() + 4
  end
  row:SetHeight(height)
  row:Show()
  return y - height
end

-- Draws the settings into the scroll view, width wide. backToSetup, when
-- given (out of a Crew), is what Back does.
function SettingsTab.draw(scrollView, theCore, width, backToSetup)
  view, core, onBack = scrollView, theCore, backToSetup
  if not sections then create() end
  local crew = core:crew()

  -- The values, and which controls they leave usable.
  local values, hidden = {}, {}
  for _, section in ipairs(core:settings()) do
    for _, setting in ipairs(section.settings) do
      values[setting.key] = setting.value
      hidden[setting.key] = setting.hidden
    end
  end
  for key, row in pairs(rows) do
    if row.draw then row.draw(values[key]) end
    if row.setEnabled then row.setEnabled(enabled(row, values, crew)) end
    row:SetShown(not hidden[key])
  end

  local box = nameRow.box
  if not box:HasFocus() and nameRow.error:GetText() == "" then showName() end
  -- Left alone while focused, so the selection holds.
  if crew and not codeRow.box:HasFocus() then
    codeRow.box.crewCode = crew.code
    codeRow.box:SetText(crew.code)
  end
  codeRow:SetShown(crew ~= nil)
  leaveRow:SetShown(crew ~= nil and not crew.leaving)

  local y = -INSET
  back:SetShown(onBack ~= nil)
  if onBack then
    back:ClearAllPoints()
    back:SetPoint("TOPLEFT", view.content, "TOPLEFT", INSET, y)
    y = y - SMALL_BUTTON - TOP_GAP
  end
  for i, section in ipairs(sections) do
    if i > 1 then y = y - SECTION_GAP end
    local heading = section.heading
    heading:ClearAllPoints()
    heading:SetPoint("TOPLEFT", view.content, "TOPLEFT", INSET - 4, y)
    heading:SetPoint("RIGHT", view.content, "RIGHT", -INSET, 0)
    y = y - SECTION
    local first = true
    for _, row in ipairs(section.rows) do
      if row:IsShown() then
        y = placeRow(row, y, first, width)
        first = false
      end
    end
  end
  view.content:SetHeight(-y + INSET)
end

-- The view was left: a typed name is saved as its box loses focus, and a
-- refused one is forgotten.
function SettingsTab.leave()
  if not nameRow then return end
  nameRow.box:ClearFocus()
  nameRow.error:SetText("")
end
