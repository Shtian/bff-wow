local _, ns = ...

local CharacterTooltip = {}
ns.CharacterTooltip = CharacterTooltip

local Skin = ns.Skin

local GOLD = Skin.GOLD
local MUTED = Skin.MUTED
local DIM = Skin.DIM
local TEXT = Skin.TEXT
local ONLINE = Skin.ONLINE
local ROOM = 280

local function className(classFilename)
  return LOCALIZED_CLASS_NAMES_MALE[classFilename] or classFilename or ""
end

local function muted(text)
  GameTooltip:AddLine(text, MUTED[1], MUTED[2], MUTED[3])
end

function CharacterTooltip.add(row, character)
  GameTooltip:AddLine(character.fullName, Skin.classColor(character.classFilename))
  GameTooltip:AddLine(("Level %d %s %s"):format(character.level, className(character.classFilename),
    character.main and "(Main)" or "(Alt)"), 1, 1, 1)
  GameTooltip:AddLine(row.own and "Your Character" or ("%s's Character"):format(row.displayName or "?"), 1, 1, 1)
  if character.zone then GameTooltip:AddLine(character.zone) end
  if character.maxXp and character.maxXp > 0 then
    muted(("XP %d%%"):format(math.floor(100 * (character.xp or 0) / character.maxXp)))
  end
  muted(("Deaths: %d"):format(character.deaths or 0))
  local gold = ns.Core.goldText(character.money)
  if gold then muted(gold) end
  for _, profession in ipairs(character.professions or {}) do
    local icon = profession.icon and Skin.iconGlyph(profession.icon, 14) .. " " or ""
    local rank = profession.rank and (" %s%s|r"):format(Skin.hex(DIM), profession.rank) or ""
    local skill = profession.full and profession.capped and GOLD or MUTED
    GameTooltip:AddDoubleLine(icon .. profession.name .. rank, ("%d/%d"):format(profession.skill, profession.max),
      TEXT[1], TEXT[2], TEXT[3], skill[1], skill[2], skill[3])
  end
  if character.playing then
    GameTooltip:AddLine(row.own and "Playing now" or "Online now", ONLINE[1], ONLINE[2], ONLINE[3])
  else
    muted("Last seen " .. character.lastSeenText)
  end
  if not row.online and row.via then muted("Heard via " .. row.via) end
  if character.canPlay then
    GameTooltip:AddLine(("Within %d levels of you: can play together"):format(ns.Core.CAN_PLAY_LEVELS),
      GOLD[1], GOLD[2], GOLD[3])
  end
end

-- WoW: GameTooltip's ANCHOR_RIGHT on a row near the top of the screen
-- puts the tooltip in the screen's corner.
function CharacterTooltip.showBeside(window, owner, row, character)
  GameTooltip:SetOwner(owner, "ANCHOR_NONE")
  local y = owner:GetTop() - window:GetTop()
  if window:GetRight() + ROOM > UIParent:GetRight() then
    GameTooltip:SetPoint("TOPRIGHT", window, "TOPLEFT", -6, y)
  else
    GameTooltip:SetPoint("TOPLEFT", window, "TOPRIGHT", 6, y)
  end
  CharacterTooltip.add(row, character)
  GameTooltip:Show()
end
