-- Report: /bff report's window, for bug reports. A diagnostics report (the
-- versions, the Crew and the link, where the player is, and the sync log) in
-- a scrollable text box, all selected so Ctrl+C copies it. The player
-- pastes it themselves: nothing is sent anywhere. See
-- docs/design/code-structure.md.

local _, ns = ...

local Report = {}
ns.Report = Report

local WIDTH = 560
local HEIGHT = 420
local INSET = 14
local INTRO = "For a bug report: press Ctrl+C to copy this, then paste it where you were asked. "
  .. "It includes your Crew's Character names."

local function yesNo(value)
  return value and "yes" or "no"
end

-- The report, as plain text.
function Report.text()
  local gameVersion, build, _, interface = GetBuildInfo()
  local forever = WOW_PROJECT_CAMELOT ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT
  local crew = ns.core:crew()
  local link = ns.ChannelLink.state()
  local log = ns.syncLog:lines()

  local lines = {
    "BFF report · " .. date("%Y-%m-%d %H:%M:%S"),
    "BFF " .. tostring(ns.VERSION),
    ("Game %s (build %s) · interface %s · WoW: Forever: %s"):format(
      tostring(gameVersion), tostring(build), tostring(interface), yesNo(forever)),
    ("Crew: %s · other Members known: %d · peers in the channel: %d"):format(
      yesNo(crew), crew and ns.core:summary().members or 0, link.peers),
    "Link: " .. (link.up and "up" or ("down (%s)"):format(link.reason or "not started")),
    ("In an instance: %s · chat messaging lockdown: %s"):format(
      link.instance or "no", yesNo(link.lockdown)),
    "",
    ("Sync log, oldest first (%d lines):"):format(#log),
  }
  for _, line in ipairs(log) do lines[#lines + 1] = line end
  return table.concat(lines, "\n")
end

local frame

local function create()
  local Skin = ns.Skin
  frame = Skin.window("BFFReport", WIDTH, "BFF report")
  frame:SetHeight(HEIGHT)
  frame:SetPoint("CENTER")

  local intro = Skin.label(frame, "small", Skin.MUTED)
  intro:SetPoint("TOPLEFT", INSET, -Skin.HEADER_HEIGHT - 10)
  intro:SetPoint("RIGHT", -INSET, 0)
  intro:SetJustifyH("LEFT")
  intro:SetText(INTRO)

  local close = Skin.button(frame, CLOSE, function() frame:Hide() end, true)
  close:SetPoint("BOTTOMRIGHT", -INSET, INSET)

  local plate = CreateFrame("Frame", nil, frame)
  plate:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -10)
  plate:SetPoint("RIGHT", -INSET, 0)
  plate:SetPoint("BOTTOM", close, "TOP", 0, 10)
  Skin.fill(plate, { 0, 0, 0, 0.35 })
  Skin.border(plate, Skin.BORDER)

  local scroller = CreateFrame("ScrollFrame", nil, plate)
  scroller:SetPoint("TOPLEFT", 8, -6)
  scroller:SetPoint("BOTTOMRIGHT", -8, 6)
  scroller:EnableMouseWheel(true)
  scroller:SetScript("OnMouseWheel", function(self, delta)
    local scroll = self:GetVerticalScroll() - delta * 40
    self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), scroll)))
  end)

  local box = CreateFrame("EditBox", nil, scroller)
  box:SetMultiLine(true)
  box:SetMaxLetters(0)
  box:SetAutoFocus(false)
  box:SetFontObject(Skin.fonts.small)
  box:SetWidth(WIDTH - 2 * INSET - 16)
  scroller:SetScrollChild(box)
  scroller:SetScript("OnSizeChanged", function(_, width) box:SetWidth(width) end)
  -- Keeps the cursor in view as it moves.
  box:SetScript("OnCursorChanged", function(_, _, y, _, height)
    local top = -y
    local offset = scroller:GetVerticalScroll()
    local visible = scroller:GetHeight()
    if top < offset then
      scroller:SetVerticalScroll(top)
    elseif top + height > offset + visible then
      scroller:SetVerticalScroll(top + height - visible)
    end
  end)
  -- Read-only: typing puts the report back, selected.
  box:SetScript("OnTextChanged", function(self, userInput)
    if userInput then
      self:SetText(frame.text)
      self:HighlightText()
    end
  end)
  box:SetScript("OnEscapePressed", function() frame:Hide() end)
  frame:SetScript("OnHide", function() box:ClearFocus() end)
  frame.box = box
  frame.scroller = scroller
end

-- Opens the window with a fresh report, all of it selected.
function Report.show()
  if not frame then create() end
  frame.text = Report.text()
  frame:Show()
  frame.box:SetText(frame.text)
  frame.box:SetCursorPosition(0)
  frame.scroller:SetVerticalScroll(0)
  frame.box:SetFocus()
  frame.box:HighlightText()
end
