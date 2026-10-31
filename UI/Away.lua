-- Away: the While you were away popup from the Feed decision (#14), in the
-- Skin's flat look. Draws Core's summary as a scoreboard, Members by most
-- recent activity: a row per Character with its level now, a bar for the
-- jump (gold when it reached max level), levels gained and deaths. The
-- Member's name sits on their first row, with joined or left beside it.
-- Dismiss and Open Feed. App shows it once out of combat. See
-- docs/design/feed.md.

local _, ns = ...

local Away = {}
ns.Away = Away

local Skin = ns.Skin

local WIDTH = 360
local INSET = 14
local INTRO = 30
local HEADINGS = 18
local BUTTONS = 46
local ICON = 14
local ROW = 26
-- A row with the Character's name under the Member's.
local TALL_ROW = 38
-- Columns, as x from the left of the scoreboard and from its right.
local LEVEL_X = 136
local BAR = 90
local GAINED_RIGHT = 30
-- The names stop short of the level column.
local NAME_WIDTH = LEVEL_X - 8
local GAINED = Skin.ONLINE
local STAR = "|T" .. Skin.FEED_ICONS.maxLevel .. ":12|t"
local SKULL = "|T" .. Skin.FEED_ICONS.death .. ":12|t"

local frame
local rows = {}

local function hex(color)
  return ("|cff%02x%02x%02x"):format(color[1] * 255, color[2] * 255, color[3] * 255)
end

local function classHex(classFilename)
  local color = classFilename and RAID_CLASS_COLORS[classFilename]
  if color then return hex({ color.r, color.g, color.b }) end
  return hex(Skin.TEXT)
end

local function heading(text, point, x)
  local label = Skin.label(frame, "tiny", Skin.DIM)
  label:SetText(text)
  label:SetPoint(point, x, -Skin.HEADER_HEIGHT - INTRO)
  return label
end

local function create()
  frame = Skin.window("BFFAway", WIDTH, "While you were away")
  frame:SetPoint("CENTER", 0, 120)

  frame.intro = Skin.label(frame, "small", Skin.MUTED)
  frame.intro:SetPoint("TOPLEFT", INSET, -Skin.HEADER_HEIGHT - 10)

  heading("LEVEL", "TOPLEFT", INSET + LEVEL_X)
  local gained = heading("GAINED", "TOPRIGHT", -INSET - GAINED_RIGHT)
  gained:SetJustifyH("RIGHT")
  local deaths = heading(SKULL, "TOPRIGHT", -INSET)
  deaths:SetJustifyH("RIGHT")

  local open = Skin.button(frame, "Open Feed", function()
    frame:Hide()
    ns.Panel.show("feed")
  end, true)
  open:SetPoint("BOTTOMRIGHT", -INSET, INSET)
  local dismiss = Skin.button(frame, "Dismiss", function() frame:Hide() end)
  dismiss:SetPoint("RIGHT", open, "LEFT", -8, 0)
end

-- A scoreboard row: the Member (on their first row) and the Character on
-- the left, then level and bar, levels gained and deaths.
local function row(index)
  local item = rows[index]
  if item then return item end
  item = CreateFrame("Frame", nil, frame)
  item.edge = Skin.edge(item, "TOP", Skin.LINE)
  item.icon = item:CreateTexture(nil, "ARTWORK")
  item.icon:SetSize(ICON, ICON)
  item.member = Skin.label(item, "text")
  item.member:SetPoint("LEFT", item.icon, "RIGHT", 6, 0)
  item.member:SetWidth(NAME_WIDTH - ICON - 6)
  item.member:SetWordWrap(false)
  item.character = Skin.label(item, "small", Skin.MUTED)
  item.character:SetWidth(NAME_WIDTH)
  item.character:SetWordWrap(false)
  item.level = Skin.label(item, "text")
  item.track = Skin.fill(item, { 1, 1, 1, 0.08 }, "ARTWORK")
  item.track:ClearAllPoints()
  item.track:SetSize(BAR, 4)
  item.before = Skin.fill(item, Skin.MUTED, "ARTWORK", 1)
  item.before:ClearAllPoints()
  item.gain = Skin.fill(item, GAINED, "ARTWORK", 1)
  item.gain:ClearAllPoints()
  item.gained = Skin.label(item, "text")
  item.gained:SetJustifyH("RIGHT")
  item.gained:SetPoint("RIGHT", -GAINED_RIGHT, 0)
  item.deaths = Skin.label(item, "text", Skin.DIM)
  item.deaths:SetJustifyH("RIGHT")
  item.deaths:SetPoint("RIGHT", 0, 0)
  rows[index] = item
  return item
end

-- The level column: the level now (gold with a star at max level) over a
-- bar from 0 to max level, the part before in grey and the jump in green,
-- or gold at max level. A dash for a Character that only died.
local function drawLevel(item, character, maxLevel)
  local shown = character.level ~= nil
  item.track:SetShown(shown)
  item.before:Hide()
  item.gain:Hide()
  item.level:ClearAllPoints()
  if not shown then
    item.level:SetText(character.deaths and hex(Skin.DIM) .. "-|r" or "")
    item.level:SetPoint("LEFT", LEVEL_X, 0)
    return
  end

  item.level:SetText(character.maxLevel and hex(Skin.GOLD) .. character.level .. "|r " .. STAR
    or tostring(character.level))
  item.level:SetPoint("BOTTOMLEFT", item, "LEFT", LEVEL_X, -1)
  item.track:SetPoint("TOPLEFT", item, "LEFT", LEVEL_X, -3)

  local scale = BAR / math.max(maxLevel, character.level)
  local from = character.from or 0
  if from > 0 then
    item.before:SetPoint("TOPLEFT", item.track)
    item.before:SetSize(from * scale, 4)
    item.before:Show()
  end
  local color = character.maxLevel and Skin.GOLD or GAINED
  item.gain:SetColorTexture(color[1], color[2], color[3])
  item.gain:SetPoint("TOPLEFT", item.track, "TOPLEFT", from * scale, 0)
  item.gain:SetSize(math.max(2, (character.level - from) * scale), 4)
  item.gain:Show()
end

-- Draws one row and returns its height. character is nil for a Member
-- with no Character rows (joined or left only).
local function drawRow(item, member, character, first, maxLevel)
  item.edge:SetShown(first)
  item.icon:SetShown(first and member.classFilename ~= nil)
  item.member:SetShown(first)
  if first then
    item.icon:SetAtlas("classicon-" .. (member.classFilename or ""):lower())
    local tags = {}
    for _, highlight in ipairs(member.highlights) do
      if highlight.kind ~= "maxLevel" then tags[#tags + 1] = highlight.kind end
    end
    local text = classHex(member.classFilename) .. member.displayName .. "|r"
    if #tags > 0 then text = text .. "  " .. hex(Skin.GOLD) .. table.concat(tags, ", ") .. "|r" end
    item.member:SetText(text)
  end

  -- The Character's name, unless it is the Member's own name on their Main.
  local name
  if character and not (character.main and character.name == member.displayName) then
    name = character.main and character.name or "Alt " .. character.name
  end
  item.character:SetText(name or "")
  item.character:SetShown(name ~= nil)

  local height = (first and name) and TALL_ROW or ROW
  item:SetHeight(height)
  item.icon:ClearAllPoints()
  item.character:ClearAllPoints()
  if first and name then
    item.icon:SetPoint("TOPLEFT", 0, -6)
    item.character:SetPoint("TOPLEFT", item.member, "BOTTOMLEFT", 0, -2)
  else
    item.icon:SetPoint("LEFT", 0, 0)
    item.character:SetPoint("LEFT", 0, 0)
  end

  drawLevel(item, character or {}, maxLevel)
  if character and character.new then
    item.gained:SetText(hex(Skin.GOLD) .. "new|r")
  elseif character and character.from then
    item.gained:SetText(hex(GAINED) .. "+" .. (character.level - character.from) .. "|r")
  else
    item.gained:SetText("")
  end
  item.deaths:SetText(character and character.deaths or "")
  item:Show()
  return height
end

-- Shows the summary from Core's awaySummary: { members, count }.
function Away.show(summary)
  if not frame then create() end
  frame.intro:SetText(summary.count == 1 and "1 thing happened while you were away."
    or ("%d things happened while you were away."):format(summary.count))

  local maxLevel = GetMaxLevelForPlayerExpansion()
  local y = -Skin.HEADER_HEIGHT - INTRO - HEADINGS
  local index = 0
  for _, member in ipairs(summary.members) do
    local characters = member.characters
    for i = 1, math.max(#characters, 1) do
      index = index + 1
      local item = row(index)
      item:ClearAllPoints()
      item:SetPoint("TOPLEFT", INSET, y)
      item:SetPoint("TOPRIGHT", -INSET, y)
      y = y - drawRow(item, member, characters[i], i == 1, maxLevel)
    end
  end
  for i = index + 1, #rows do rows[i]:Hide() end

  frame:SetHeight(-y + BUTTONS)
  frame:Show()
end
