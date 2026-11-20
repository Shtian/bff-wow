local _, ns = ...

local ScrollView = {}
ns.ScrollView = ScrollView

local STEP = 40
local THUMB_MIN = 24
local THUMB_OUT = 4

local function placeThumb(view)
  local range = view:GetVerticalScrollRange()
  local thumb = view.thumb
  if range <= 0 then
    view:SetVerticalScroll(0)
    thumb:Hide()
    return
  end
  if view:GetVerticalScroll() > range then view:SetVerticalScroll(range) end
  local visible = view:GetHeight()
  local height = math.max(THUMB_MIN, visible * visible / (visible + range))
  thumb:SetHeight(height)
  thumb:ClearAllPoints()
  thumb:SetPoint("TOPRIGHT", view, "TOPRIGHT", THUMB_OUT, -(visible - height) * view:GetVerticalScroll() / range)
  thumb:Show()
end

local function scroll(view, delta)
  local range = view:GetVerticalScrollRange()
  view:SetVerticalScroll(math.min(range, math.max(0, view:GetVerticalScroll() - delta * STEP)))
  placeThumb(view)
end

local function fit(view, height)
  view.content:SetHeight(math.max(height, 1))
  placeThumb(view)
end

function ScrollView.new(parent, width)
  local view = CreateFrame("ScrollFrame", nil, parent)
  view:EnableMouseWheel(true)
  view:SetScript("OnMouseWheel", scroll)
  view.content = CreateFrame("Frame", nil, view)
  view.content:SetSize(width or 1, 1)
  view:SetScrollChild(view.content)
  view:SetScript("OnSizeChanged", function(self, newWidth)
    self.content:SetWidth(newWidth)
    placeThumb(self)
  end)
  view.thumb = view:CreateTexture(nil, "OVERLAY")
  view.thumb:SetColorTexture(1, 1, 1, 0.18)
  view.thumb:SetWidth(3)
  view.Fit = fit
  return view
end
