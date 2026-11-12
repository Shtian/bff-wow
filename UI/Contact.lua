-- Contact: the Get in touch window, opened from the panel's header. Where
-- to send a question, an idea or a bug: the addon's GitHub issues and its
-- CurseForge page, each in a box that selects itself for Ctrl+C, since the
-- game can't open links. Its Report a bug button opens the Report window.
-- See docs/design/code-structure.md.

local _, ns = ...

local Contact = {}
ns.Contact = Contact

local WIDTH = 380
local INSET = 14
local INTRO = "Found a bug, or have a question or an idea? Open an issue on GitHub, "
  .. "or leave a comment on CurseForge. Click a link and press Ctrl+C to copy it. "
  .. "For a bug, also paste in the bug report: Report a bug shows it, ready to copy."

local LINKS = {
  { label = "GitHub issues", url = "https://github.com/Shtian/bff-wow/issues" },
  { label = "CurseForge", url = "https://www.curseforge.com/wow/addons/bff-best-friends-in-forever" },
}

local frame

-- A read-only box holding a link: clicking or typing selects all of it
-- (the click that focuses it places the cursor after OnEditFocusGained, so
-- OnMouseUp selects it again).
local function linkBox(parent, url)
  local box = ns.Skin.editBox(parent, WIDTH - 2 * INSET)
  box:SetFontObject(ns.Skin.fonts.small)
  box:SetText(url)
  box:SetCursorPosition(0)
  box:SetScript("OnTextChanged", function(self, userInput)
    if userInput then
      self:SetText(url)
      self:HighlightText()
    end
  end)
  box:SetScript("OnEditFocusGained", box.HighlightText)
  box:SetScript("OnMouseUp", box.HighlightText)
  box:SetScript("OnEditFocusLost", function(self)
    self:HighlightText(0, 0)
    self:SetCursorPosition(0)
  end)
  box:SetScript("OnEscapePressed", function() frame:Hide() end)
  return box
end

local function create()
  local Skin = ns.Skin
  frame = Skin.window("BFFContact", WIDTH, "Get in touch")
  frame:SetPoint("CENTER")

  local intro = Skin.label(frame, "small", Skin.MUTED)
  intro:SetPoint("TOPLEFT", INSET, -Skin.HEADER_HEIGHT - INSET)
  intro:SetWidth(WIDTH - 2 * INSET)
  intro:SetJustifyH("LEFT")
  intro:SetWordWrap(true)
  intro:SetText(INTRO)

  local above, gap = intro, 12
  for _, link in ipairs(LINKS) do
    local label = Skin.label(frame, "small", Skin.MUTED)
    label:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -gap)
    label:SetText(link.label)
    local box = linkBox(frame, link.url)
    box:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
    above, gap = box, 10
  end
  frame.lastBox = above

  local close = Skin.button(frame, CLOSE, function() frame:Hide() end, true)
  close:SetPoint("BOTTOMRIGHT", -INSET, INSET)
  local report = Skin.button(frame, "Report a bug", function()
    frame:Hide()
    ns.Report.show()
  end)
  report:SetWidth(110)
  report:SetPoint("RIGHT", close, "LEFT", -8, 0)
end

-- Opens the window, as tall as its links plus the buttons under them.
function Contact.show()
  if not frame then create() end
  frame:SetHeight(1)
  frame:Show()
  local linksBottom = frame:GetTop() - frame.lastBox:GetBottom()
  frame:SetHeight(math.ceil(linksBottom) + 18 + 24 + INSET)
end
