local _, ns = ...

local EmptyState = {}
ns.EmptyState = EmptyState

local Skin = ns.Skin
local Sheet = ns.CampSheet.vignettes

local FPS = 6
local TEXT_MAX = 300
local GAP_ART = 8
local GAP_LINE = 4
local GAP_ACTION = 10
local GAP_HINT = 4
local CODE_WIDTH = 128
local CODE_HEIGHT = 24
local HINT = "Ctrl+C to copy"
local PLACE_AT = 0.4
local PLACE_INSET = 12

local ALONE = {
  art = "alone",
  title = "Your Crew hasn't arrived yet",
  text = "Share your Crew code. Members join with /bff join, and show up here once one of them is online.",
}
local JOINED = {
  art = "alone",
  title = "Waiting for the Crew",
  text = "You're in. The rest of the Crew shows up here once one of them is online.",
}

function EmptyState.view(own, still)
  return { art = own.art, title = own.title, text = own.text, still = still }
end

function EmptyState.alone(crew, still)
  local from = crew.joined and JOINED or ALONE
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

function EmptyState.new(parent)
  local self = CreateFrame("Frame", nil, parent)
  self:Hide()
  self.played = 0
  self.art = self:CreateTexture(nil, "ARTWORK")
  self.art:SetTexture(Sheet.file, "CLAMP", "CLAMP", "NEAREST")
  Skin.snapToPixels(self)

  self.title = Skin.label(self, "heading", Skin.TEXT)
  self.title:SetJustifyH("CENTER")
  self.title:SetPoint("TOP", self.art, "BOTTOM", 0, -GAP_ART)
  self.text = Skin.label(self, "small", Skin.MUTED)
  self.text:SetJustifyH("CENTER")
  self.text:SetWordWrap(true)
  self.text:SetPoint("TOP", self.title, "BOTTOM", 0, -GAP_LINE)

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
