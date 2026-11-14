-- Changelog: reads CHANGELOG.md as bumpy writes it, for What's new
-- (docs/design/whats-new.md). The release build writes the newest releases'
-- text into ChangelogText.lua (scripts/changelog-text.sh); this turns it
-- into releases, newest first: { version, date ("13 Nov"), entries }, each
-- entry { kind ("major", "minor" or "patch"), title, detail (nil if none) }.
-- A bump file's first paragraph is its title and the rest its detail; an
-- older one-paragraph entry splits after its first sentence. Pure.

local _, ns = ...

local Changelog = {}
ns.Changelog = Changelog

local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }

-- A release version from a tag or the .toc ("v2.2.0" or "2.2.0"), or nil
-- for anything else (a dev checkout's "dev").
function Changelog.version(text)
  if type(text) ~= "string" then return nil end
  local major, minor, patch = text:match("^v?(%d+)%.(%d+)%.(%d+)$")
  if not major then return nil end
  return ("%d.%d.%d"):format(tonumber(major), tonumber(minor), tonumber(patch))
end

-- Whether release version a is newer than b, by number.
function Changelog.newer(a, b)
  local x, y = { a:match("^(%d+)%.(%d+)%.(%d+)$") }, { b:match("^(%d+)%.(%d+)%.(%d+)$") }
  for i = 1, 3 do
    local p, q = tonumber(x[i]), tonumber(y[i])
    if p ~= q then return p > q end
  end
  return false
end

local function shortDate(iso)
  local month, day = iso:match("^%d+%-(%d+)%-(%d+)$")
  if not month or not MONTHS[tonumber(month)] then return iso end
  return ("%d %s"):format(tonumber(day), MONTHS[tonumber(month)])
end

-- Markdown marks the game can't show: code spans and bold.
local function plain(text)
  return (text:gsub("`", ""):gsub("%*%*", ""):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

-- An entry from its paragraphs.
local function entry(kind, paragraphs)
  local texts = {}
  for _, lines in ipairs(paragraphs) do
    local text = plain(table.concat(lines, " "))
    if text ~= "" then texts[#texts + 1] = text end
  end
  if #texts == 0 then return nil end
  local title, detail = texts[1], nil
  if #texts > 1 then
    detail = table.concat(texts, " ", 2)
  else
    -- The first sentence: up to a full stop followed by a capital.
    local first, rest = title:match("^(.-[%.!?])%s+(%u.*)$")
    if first then title, detail = first, rest end
  end
  return { kind = kind, title = title, detail = detail }
end

function Changelog.parse(text)
  local releases = {}
  if type(text) ~= "string" then return releases end
  local release, kind, paragraphs
  local function finish()
    if release and kind then
      local item = entry(kind, paragraphs)
      if item then release.entries[#release.entries + 1] = item end
    end
    kind, paragraphs = nil, nil
  end
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    line = line:gsub("\r$", "")
    local version = line:match("^##%s+(%S+)%s*$")
    local bullet, rest = line:match("^%- %*%((%a+)%)%*%s*(.*)$")
    if version then
      finish()
      release = Changelog.version(version) and { version = Changelog.version(version), entries = {} } or nil
      if release then releases[#releases + 1] = release end
    elseif release and not release.date and line:match("<sub>") then
      release.date = shortDate(line:match("<sub>%s*(.-)%s*</sub>") or "")
    elseif release and bullet then
      finish()
      kind, paragraphs = bullet, { {} }
      if rest ~= "" then table.insert(paragraphs[1], rest) end
    elseif kind and line:match("^%s+%S") then
      table.insert(paragraphs[#paragraphs], line)
    elseif kind and line:match("^%s*$") then
      if #paragraphs[#paragraphs] > 0 then paragraphs[#paragraphs + 1] = {} end
    else
      finish()
    end
  end
  finish()
  for _, item in ipairs(releases) do item.date = item.date or "" end
  return releases
end
