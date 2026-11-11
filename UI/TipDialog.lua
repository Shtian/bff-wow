-- TipDialog: Core's Tip as a small window, shown once per Tip the first
-- time Core offers it (the tip event): its title, its text, and Turn on and
-- No thanks, which answer it. Closing it (the X or Escape) answers nothing,
-- so the Tip stays as the card at the top of the panel. Silent. See
-- docs/design/pocket-camp.md.

local _, ns = ...

local TipDialog = {}
ns.TipDialog = TipDialog

local Skin = ns.Skin

local WIDTH = 360
local INSET = 14
local BUTTON = 96

local core
local frame

local function create()
  frame = Skin.window("BFFTip", WIDTH, "")
  frame:SetPoint("TOP", UIParent, "TOP", 0, -140)
  frame.text = Skin.label(frame, "body", Skin.TEXT)
  frame.text:SetPoint("TOPLEFT", INSET, -Skin.HEADER_HEIGHT - INSET)
  frame.text:SetWidth(WIDTH - 2 * INSET)
  frame.text:SetWordWrap(true)
  frame.accept = Skin.button(frame, "", function()
    frame:Hide()
    core:acceptTip(frame.key)
  end, true)
  frame.accept:SetWidth(BUTTON)
  frame.accept:SetPoint("BOTTOMRIGHT", -INSET, INSET)
  frame.dismiss = Skin.button(frame, "", function()
    frame:Hide()
    core:dismissTip(frame.key)
  end)
  frame.dismiss:SetWidth(BUTTON)
  frame.dismiss:SetPoint("RIGHT", frame.accept, "LEFT", -8, 0)
end

-- Shows a Tip as Core's tip event gives it: { key, title, text, accept,
-- dismiss }.
function TipDialog.show(tip)
  if not frame then create() end
  frame.key = tip.key
  frame.title:SetText(tip.title)
  frame.text:SetText(tip.text)
  frame.accept:SetText(tip.accept)
  frame.dismiss:SetText(tip.dismiss)
  frame:SetHeight(Skin.HEADER_HEIGHT + math.ceil(frame.text:GetStringHeight()) + 3 * INSET + 24)
  frame:Show()
end

-- Closes the window once its Tip is no longer the one Core has: it was
-- answered from the panel's card, or its feature was turned on in Settings.
function TipDialog.refresh()
  if not frame or not frame:IsShown() then return end
  local tip = core:tip()
  if not tip or tip.key ~= frame.key then frame:Hide() end
end

function TipDialog.start(theCore)
  core = theCore
end
