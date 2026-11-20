local _, ns = ...

local FeedTab = {}
ns.FeedTab = FeedTab

local Skin = ns.Skin

local INSET = 12
local FEED_ENTRY = 38
local REACT = 20
local FEED_DAY = 26
local NODE = 26
local NEW_DOT = Skin.UNREAD_DOT
local LINE_X = INSET + NODE / 2 - 1
local DAY_HEIGHT = 16
local DAY_GAP = 4
local EMPTY = { art = "feed", title = "Quiet by the fire",
  text = "Dings, deaths, new Characters and Crew wins land here, and wait for you while you're away." }

local GOLD = Skin.GOLD
local MUTED = Skin.MUTED
local TEXT = Skin.TEXT

local core
local view

local function createView(page)
  view = page:scrollView()
  view.segments = {}
  view.days = {}
  view.entries = {}
  view.empty = ns.EmptyState.new(view)
end

local function hideAll(lines, from)
  for i = from, #lines do lines[i]:Hide() end
end

local function createDay()
  local day = CreateFrame("Frame", nil, view.content)
  day:SetHeight(DAY_HEIGHT)
  day.label = Skin.sectionLabel(day, 4, 0)
  local line = Skin.rule(day)
  line:SetPoint("LEFT", day.label, "RIGHT", 8, 0)
  line:SetPoint("RIGHT")
  view.days[#view.days + 1] = day
  return day
end

local function drawTimeline(stretches)
  local top = stretches[1] and stretches[1].top
  local bottom = stretches[1] and stretches[#stretches].bottom
  local new, old = Skin.TIMELINE_NEW, Skin.TIMELINE_OLD
  local function colourAt(y)
    local share = top > bottom and (top - y) / (top - bottom) or 0
    return Skin.alpha(new, new[4] + (old[4] - new[4]) * share)
  end
  local shown = 0
  for _, stretch in ipairs(stretches) do
    if stretch.top > stretch.bottom then
      shown = shown + 1
      local segment = view.segments[shown]
      if not segment then
        segment = view.content:CreateTexture(nil, "BACKGROUND")
        segment:SetColorTexture(1, 1, 1, 1)
        segment:SetWidth(2)
        view.segments[shown] = segment
      end
      segment:ClearAllPoints()
      segment:SetPoint("TOPLEFT", LINE_X, stretch.top)
      segment:SetHeight(stretch.top - stretch.bottom)
      Skin.gradient(segment, "VERTICAL", colourAt(stretch.bottom), colourAt(stretch.top))
      segment:Show()
    end
  end
  for i = shown + 1, #view.segments do view.segments[i]:Hide() end
end

local function createEntry()
  local entry = CreateFrame("Frame", nil, view.content)
  entry:SetHeight(FEED_ENTRY)
  local node = Skin.feedPicture(entry, NODE)
  node:SetPoint("TOPLEFT", INSET, -4)
  entry.node = node

  entry.text = Skin.label(entry, "text")
  entry.text:SetPoint("TOPLEFT", node, "TOPRIGHT", 10, -2)
  entry.text:SetPoint("RIGHT", -INSET - 36, 0)
  entry.text:SetWordWrap(false)
  entry.new = Skin.unreadDot(entry)
  entry.new:SetPoint("CENTER", node, "LEFT", -(NEW_DOT / 2 + 3), 0)
  entry.time = Skin.label(entry, "small", MUTED)
  entry.time:SetPoint("TOPLEFT", entry.text, "BOTTOMLEFT", 0, -2)
  entry.reactors = Skin.label(entry, "small", MUTED)
  entry.reactors:SetPoint("LEFT", entry.time, "RIGHT", 8, 0)
  entry.reactors:SetPoint("RIGHT", -INSET - 36, 0)
  entry.reactors:SetWordWrap(false)

  entry.react = Skin.reactionButton(entry, REACT, function(self)
    local data = self:GetParent().data
    if data and data.key and core:react(data.key) and data.reaction == "cheer" then
      ns.Panel.cheered(data.memberId)
    end
  end)
  entry.react:SetPoint("TOPRIGHT", -INSET - 4, -4)
  view.entries[#view.entries + 1] = entry
  return entry
end

local function reactorsText(entry)
  if #entry.reactors == 0 then return "" end
  local names = {}
  for i, reactor in ipairs(entry.reactors) do
    names[i] = reactor.you and Skin.hex(TEXT) .. reactor.name .. "|r" or reactor.name
  end
  return Skin.reactionGlyph(entry.reaction, 12) .. " " .. table.concat(names, ", ")
end

local function drawEntry(line, entry)
  line.data = entry
  line.reactors:SetText(reactorsText(entry))
  line.react:SetShown(entry.canReact)
  if entry.canReact then
    line.react:SetReaction(entry.reaction, entry.reacted)
  end
  line.node:SetKind(entry.kind, entry.icon, entry.edge)
  line.text:SetText(entry.text)
  Skin.color(line.text, entry.highlight and GOLD or entry.own and MUTED or TEXT)
  line.time:SetText(date("%H:%M", entry.time))
  line.new:SetShown(entry.new)
end

function FeedTab.draw(page)
  core = page.core
  if not view then createView(page) end
  core:openFeed()
  local feed = core:feed()
  local y, dayCount, entryCount = -INSET, 0, 0
  local stretches = {}
  for _, day in ipairs(feed.days) do
    dayCount = dayCount + 1
    if stretches[dayCount - 1] then stretches[dayCount - 1].bottom = y + DAY_GAP end
    stretches[dayCount] = { top = y - DAY_HEIGHT - DAY_GAP }
    local chip = view.days[dayCount] or createDay()
    chip:ClearAllPoints()
    chip:SetPoint("TOPLEFT", view.content, "TOPLEFT", INSET - 4, y)
    chip:SetPoint("RIGHT", view.content, "RIGHT", -INSET, 0)
    chip.label:SetText(day.title)
    chip:Show()
    y = y - FEED_DAY
    for _, entry in ipairs(day.entries) do
      entryCount = entryCount + 1
      local line = view.entries[entryCount] or createEntry()
      line:ClearAllPoints()
      line:SetPoint("TOPLEFT", view.content, "TOPLEFT", 0, y)
      line:SetPoint("RIGHT", view.content, "RIGHT")
      drawEntry(line, entry)
      line:Show()
      y = y - FEED_ENTRY
    end
  end
  hideAll(view.days, dayCount + 1)
  hideAll(view.entries, entryCount + 1)
  if entryCount == 0 then
    view.empty:Set(ns.EmptyState.view(EMPTY, not core:setting("camp")))
    view.empty:Place(view, page.listWidth, page.height)
  else
    view.empty:Hide()
  end
  if stretches[dayCount] then stretches[dayCount].bottom = y + 8 end
  drawTimeline(entryCount > 0 and stretches or {})
  view:Fit(-y + INSET)
end

function FeedTab.leave()
  core:leaveFeed()
end
