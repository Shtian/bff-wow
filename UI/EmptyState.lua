-- EmptyState: what a tab shows when it has nothing to show yet (DESIGN.md,
-- Empty states): a small pixel vignette in the Camp's art, a headline, one
-- line on what will fill the tab and, for the alone state, the Crew code
-- ready to copy. Stacked and centred: the vignette on top, the words under
-- it. :Set({ art, title, text, code, still }) fills it, art naming one of
-- CampSheet.vignettes.art; :Layout(width) lays it out across width and
-- returns its height; :Place(parent, width, height, top) also sets it in a
-- view of that size, `top` down parent, its middle at about 40% of the way
-- down. EmptyState.pick chooses between a tab's own state and the alone
-- state, which wins while you're the only Member known. The vignette is a
-- whole number of screen pixels per art pixel near the Camp band's, and
-- steps its frames on the band's 6 a second while shown, unless still (the
-- Camp is off, so nothing in the panel moves). See docs/design/camp.md.

local _, ns = ...

local EmptyState = {}
ns.EmptyState = EmptyState

local Skin = ns.Skin
local Sheet = ns.CampSheet.vignettes

local FPS = 6
-- The words' widest, and the gaps: vignette to headline, headline to line,
-- line to the code box, and the code box to its hint.
local TEXT_MAX = 300
local GAP_ART = 8
local GAP_LINE = 4
local GAP_ACTION = 10
local GAP_HINT = 4
-- The Crew code's box, as the Settings code row's.
local CODE_WIDTH = 128
local CODE_HEIGHT = 24
local HINT = "Ctrl+C to copy"
-- Where the block's middle sits in a view it's placed in, from the top,
-- and the least room above it.
local PLACE_AT = 0.4
local PLACE_INSET = 12

-- The alone state: for whoever started the Crew, with its code to hand
-- out; for whoever joined it, only the wait.
local ALONE = {
  art = "alone",
  title = "Your Crew hasn't arrived yet",
  text = "Give your friends the Crew code. They join with /bff join, and show up here once one of them is online.",
}
local JOINED = {
  art = "alone",
  title = "Waiting for the Crew",
  text = "You're in. The rest of the Crew shows up here once one of them is online.",
}

-- The state to Set for a tab whose own empty state is `own` ({ art,
-- title, text }): the alone state instead while crew() (Core's) is alone.
-- still while the Camp is off.
function EmptyState.pick(crew, own, still)
  local alone = crew and crew.alone
  local from = alone and (crew.joined and JOINED or ALONE) or own
  return { art = from.art, title = from.title, text = from.text, code = from == ALONE and crew.code or nil,
    still = still }
end

local function showCell(self, index)
  local cell = self.cells[index]
  if self.cell == cell then return end
  self.cell = cell
  local left, top = cell[1] / Sheet.width, cell[2] / Sheet.height
  self.art:SetTexCoord(left, left + Sheet.columns / Sheet.width, top, top + Sheet.rows / Sheet.height)
end

local function step(self, elapsed)
  self.played = self.played + elapsed
  showCell(self, math.floor(self.played * FPS / self.cells.hold) % #self.cells + 1)
end

local function set(self, state)
  self.cells = Sheet.art[state.art]
  self.cell = nil
  showCell(self, 1)
  self:SetScript("OnUpdate", #self.cells > 1 and not state.still and step or nil)
  self.title:SetText(state.title)
  self.text:SetText(state.text)
  self.crewCode = state.code
  self.code:SetShown(state.code ~= nil)
  self.hint:SetShown(state.code ~= nil)
  if state.code then self.code:SetText(state.code) end
end

local function layout(self, width)
  local unit = ns.CampScene.artUnit(self, ns.CampScene.BAND_TARGET)
  local artWidth, artHeight = Sheet.columns * unit, Sheet.rows * unit
  self.art:SetSize(artWidth, artHeight)
  self.art:ClearAllPoints()
  self.art:SetPoint("TOPLEFT", math.floor((width - artWidth) / 2), 0)
  local textWidth = math.min(TEXT_MAX, width)
  self.title:SetWidth(textWidth)
  self.text:SetWidth(textWidth)
  local height = artHeight + GAP_ART + self.title:GetStringHeight() + GAP_LINE + self.text:GetStringHeight()
  if self.code:IsShown() then
    height = height + GAP_ACTION + CODE_HEIGHT + GAP_HINT + self.hint:GetStringHeight()
  end
  height = math.ceil(height)
  self:SetSize(width, height)
  return height
end

local function place(self, parent, width, height, top)
  local own = layout(self, width)
  self:ClearAllPoints()
  self:SetPoint("TOPLEFT", parent, "TOPLEFT", 0,
    -(top or 0) - math.max(PLACE_INSET, math.floor((height - own) * PLACE_AT)))
  self:Show()
  return own
end

-- A new empty state on parent, hidden until placed.
function EmptyState.new(parent)
  local self = CreateFrame("Frame", nil, parent)
  self:Hide()
  self.played = 0
  self.art = self:CreateTexture(nil, "ARTWORK")
  self.art:SetTexture(Sheet.file, "CLAMP", "CLAMP", "NEAREST")
  -- As the Camp's: ElvUI turns default texture snapping off.
  if self.SetRoundLayoutToNearestPixel then self:SetRoundLayoutToNearestPixel(true) end

  self.title = Skin.label(self, "heading", Skin.TEXT)
  self.title:SetJustifyH("CENTER")
  self.title:SetPoint("TOP", self.art, "BOTTOM", 0, -GAP_ART)
  self.text = Skin.label(self, "small", Skin.MUTED)
  self.text:SetJustifyH("CENTER")
  self.text:SetWordWrap(true)
  self.text:SetPoint("TOP", self.title, "BOTTOM", 0, -GAP_LINE)

  -- The code stays selected for copying, as the Roster footer's does; a
  -- faint selection keeps it from being the brightest thing in the panel.
  self.code = Skin.editBox(self, CODE_WIDTH)
  self.code:SetHeight(CODE_HEIGHT)
  self.code:SetJustifyH("CENTER")
  self.code:SetPoint("TOP", self.text, "BOTTOM", 0, -GAP_ACTION)
  self.code:SetHighlightColor(1, 1, 1, 0.15)
  self.code:SetScript("OnEditFocusGained", function(box) box:HighlightText() end)
  self.code:SetScript("OnTextChanged", function(box, userInput)
    if userInput then
      box:SetText(self.crewCode)
      box:HighlightText()
    end
  end)
  self.hint = Skin.label(self, "tiny", Skin.DIM)
  self.hint:SetPoint("TOP", self.code, "BOTTOM", 0, -GAP_HINT)
  self.hint:SetText(HINT)

  self.Set, self.Layout, self.Place = set, layout, place
  return self
end
