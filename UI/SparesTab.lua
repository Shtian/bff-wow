local _, ns = ...

local SparesTab = {}
ns.SparesTab = SparesTab

local Skin = ns.Skin

local INSET = 12
local SMALL_BUTTON = 20
local SPARE_ROW = 44
local SPARE_ICON = 28
local SPARE_BUTTON = 58
local SPARE_SECTION = 28
local DROP = "Drop an item from your bags here to offer it to your Crew."
local HOW = "Offer an item: drop it on the slot above, or type /bff spares add and shift-click it into the chat box. Mail it to the winner, then Give it."
local EMPTY = { art = "spares", title = "The crate is empty",
  text = "Got something your Crew could use? Drop it on the slot below." }
local QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"

local GOLD = Skin.GOLD
local MUTED = Skin.MUTED
local DIM = Skin.DIM

local core
local page
local view

local getItemIcon = C_Item and C_Item.GetItemIconByID or GetItemIcon

StaticPopupDialogs.BFF_GIVE_SPARE = {
  text = "Give %s to %s? Do this once you've mailed it: BFF only tells the Crew.",
  button1 = YES,
  button2 = NO,
  OnAccept = function(_, data)
    local ok, reason = core:giveSpare(data.id, data.winner)
    if not ok then ns.say(ns.MESSAGES[reason]) end
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
}

local function place(line, y)
  line:ClearAllPoints()
  line:SetPoint("TOPLEFT", view.content, "TOPLEFT", 0, y)
  line:SetPoint("TOPRIGHT", view.content, "TOPRIGHT", 0, y)
end

-- WoW: dropping an item from the cursor may arrive as OnReceiveDrag or
-- as OnClick.
local function onDrop()
  if not GetCursorInfo() then return end
  ns.sayPosted(ns.Bags.postFromCursor(core))
end

local function createDrop(parent)
  local drop = CreateFrame("Button", nil, parent)
  drop:SetHeight(SPARE_ROW)
  Skin.fill(drop, Skin.HOVER, "HIGHLIGHT")
  drop.slot = CreateFrame("Frame", nil, drop)
  drop.slot:SetSize(SPARE_ICON, SPARE_ICON)
  drop.slot:SetPoint("LEFT", INSET, 0)
  Skin.fill(drop.slot, Skin.RAISED)
  Skin.border(drop.slot)
  drop.plus = Skin.label(drop.slot, "body", DIM)
  drop.plus:SetPoint("CENTER")
  drop.plus:SetText("+")
  drop.label = Skin.label(drop, "body", MUTED)
  drop.label:SetPoint("LEFT", drop.slot, "RIGHT", 8, 0)
  drop.label:SetPoint("RIGHT", -INSET, 0)
  drop.label:SetText(DROP)
  drop:SetScript("OnReceiveDrag", onDrop)
  drop:SetScript("OnClick", onDrop)
  return drop
end

local function createView()
  view = page:scrollView()
  view.headings = {}
  view.rows = {}
  view.notes = {}
  view.drop = createDrop(view.content)
  view.empty = ns.EmptyState.new(view.content)
end

local function heading(index)
  local item = view.headings[index]
  if item then return item end
  item = CreateFrame("Frame", nil, view.content)
  item:SetHeight(SPARE_SECTION)
  item.label = Skin.sectionLabel(item, INSET, -2)
  item.count = Skin.label(item, "small", MUTED)
  item.count:SetPoint("RIGHT", -INSET, -2)
  item.line = Skin.rule(item)
  item.line:SetPoint("LEFT", item.label, "RIGHT", 8, 0)
  item.line:SetPoint("RIGHT", item.count, "LEFT", -8, 0)
  view.headings[index] = item
  return item
end

local function note(index)
  local item = view.notes[index]
  if item then return item end
  item = Skin.label(view.content, "small", MUTED)
  item:SetWordWrap(true)
  view.notes[index] = item
  return item
end

local function showItemTooltip(row)
  if not row.data then return end
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  GameTooltip:SetHyperlink(row.data.item)
  GameTooltip:Show()
end

local function hideTooltip()
  GameTooltip:Hide()
end

local function claim(data, guid)
  local ok, reason = core:claimSpare(data.ownerId, data.id, guid)
  if not ok then ns.say(ns.MESSAGES[reason]) end
end

local function showClaimMenu(owner, data)
  local claimFor = view.claimFor
  if not claimFor or #claimFor == 0 then return end
  MenuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateTitle("Claim it for")
    for _, character in ipairs(claimFor) do
      root:CreateButton(character.label, function() claim(data, character.guid) end)
    end
  end)
end

local function onPrimary(button, mouse)
  local row = button:GetParent()
  local data = row.data
  if not data then return end
  if row.yours then
    StaticPopup_Show("BFF_GIVE_SPARE", data.link or "it",
      data.winner and ("%s (%s)"):format(data.winner.name, data.winner.character) or "?",
      { id = data.id, winner = data.winner and data.winner.memberId })
  elseif mouse == "RightButton" then
    showClaimMenu(button, data)
  else
    claim(data)
  end
end

local function onSecondary(button)
  local row = button:GetParent()
  local data = row.data
  if not data then return end
  local ok, reason
  if row.yours then
    ok, reason = core:withdrawSpare(data.id)
  else
    ok, reason = core:withdrawClaim(data.ownerId, data.id)
  end
  if not ok then ns.say(ns.MESSAGES[reason]) end
end

local function createRow()
  local row = CreateFrame("Button", nil, view.content)
  row:SetHeight(SPARE_ROW)
  Skin.fill(row, Skin.HOVER, "HIGHLIGHT")
  row:SetScript("OnClick", function(self)
    local insertLink = ChatFrameUtil and ChatFrameUtil.InsertLink or ChatEdit_InsertLink
    if self.data and self.data.link and insertLink and IsModifiedClick("CHATLINK") then insertLink(self.data.link) end
  end)
  row:SetScript("OnEnter", showItemTooltip)
  row:SetScript("OnLeave", hideTooltip)

  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(SPARE_ICON, SPARE_ICON)
  row.icon:SetPoint("TOPLEFT", INSET, -8)
  row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  row.primary = Skin.button(row, "Claim", onPrimary, true)
  row.primary:SetSize(SPARE_BUTTON, SMALL_BUTTON)
  row.primary:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  row.secondary = Skin.button(row, "Withdraw", onSecondary)
  row.secondary:SetSize(SPARE_BUTTON, SMALL_BUTTON)

  row.item = Skin.label(row, "body")
  row.item:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 1)
  row.item:SetWordWrap(false)
  row.level = Skin.badge(row)
  row.info = Skin.label(row, "small", MUTED)
  row.info:SetPoint("TOPLEFT", row.item, "BOTTOMLEFT", 0, -3)
  row.info:SetWordWrap(false)
  view.rows[#view.rows + 1] = row
  return row
end

local function placeButtons(row, primary, secondary)
  row.primary:SetShown(primary ~= nil)
  row.secondary:SetShown(secondary ~= nil)
  local anchor
  for _, pair in ipairs({ { row.primary, primary }, { row.secondary, secondary } }) do
    local button, text = pair[1], pair[2]
    if text then
      button:SetText(text)
      button:ClearAllPoints()
      if anchor then
        button:SetPoint("RIGHT", anchor, "LEFT", -4, 0)
      else
        button:SetPoint("RIGHT", row, "RIGHT", -INSET, 0)
      end
      anchor = button
    end
  end
  local buttons = (primary and SPARE_BUTTON + 4 or 0) + (secondary and SPARE_BUTTON + 4 or 0)
  return page.listWidth - 2 * INSET - SPARE_ICON - 8 - buttons - 4
end

local function drawText(row, data, width)
  row.item:SetWidth(0)
  row.item:SetText(data.link or "Loading...")
  row.item:SetWidth(math.min(row.item:GetStringWidth() + 1, width - 30))
  row.level:SetShown(data.level > 0)
  row.level:SetText(data.level)
  row.level:ClearAllPoints()
  row.level:SetPoint("LEFT", row.item, "RIGHT", 6, 0)
  row.info:SetWidth(width)
end

local function drawRow(row, data, yours)
  row.data, row.yours = data, yours
  row.icon:SetTexture(getItemIcon and getItemIcon(data.item) or QUESTION_MARK)
  row.info:SetText(data.info)
  Skin.color(row.info, data.highlight and GOLD or MUTED)
  drawText(row, data, placeButtons(row, data.primary and data.primary.label,
    data.secondary and data.secondary.label))
  if data.primary then row.primary:SetEnabled(data.primary.enabled) end
  row:SetAlpha(data.dimmed and (yours and 0.6 or 0.45) or 1)
  row:Show()
end

function SparesTab.draw(thePage)
  page, core = thePage, thePage.core
  if not view then createView() end
  local spares = core:spares()
  view.claimFor = spares.claimFor
  local y, headings, rows, notes = -4, 0, 0, 0
  local function addHeading(text, count)
    headings = headings + 1
    local item = heading(headings)
    place(item, y)
    item.label:SetText(text)
    item.count:SetText(count)
    item:Show()
    y = y - SPARE_SECTION
  end
  local function addNote(text)
    notes = notes + 1
    local item = note(notes)
    item:ClearAllPoints()
    item:SetPoint("TOPLEFT", view.content, "TOPLEFT", INSET, y - 2)
    item:SetWidth(page.listWidth - 2 * INSET)
    item:SetText(text)
    item:Show()
    y = y - item:GetStringHeight() - 12
  end
  local function list(data, yours)
    for _, item in ipairs(data) do
      rows = rows + 1
      local row = view.rows[rows] or createRow()
      place(row, y)
      drawRow(row, item, yours)
      y = y - SPARE_ROW
    end
  end

  addHeading("FROM THE CREW", ("%d of %d Claims"):format(spares.claims, spares.maxClaims))
  view.empty:SetShown(#spares.crew == 0)
  if #spares.crew == 0 then
    view.empty:Set(ns.EmptyState.view(EMPTY, not core:setting("camp")))
    view.empty:ClearAllPoints()
    view.empty:SetPoint("TOPLEFT", view.content, "TOPLEFT", 0, y - 10)
    y = y - 10 - view.empty:Layout(page.listWidth) - 16
  end
  list(spares.crew, false)
  y = y - 6
  addHeading("YOURS", ("%d of %d up"):format(spares.open, spares.maxOpen))
  place(view.drop, y)
  y = y - SPARE_ROW
  list(spares.yours, true)
  addNote(HOW)

  Skin.hideFrom(view.headings, headings + 1)
  Skin.hideFrom(view.rows, rows + 1)
  Skin.hideFrom(view.notes, notes + 1)
  view:Fit(-y + 6)
  if spares.unseen > 0 then core:sparesSeen() end
end
