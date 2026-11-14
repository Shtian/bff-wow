-- WhatsNew: what changed in BFF since you last looked (docs/design/whats-new.md).
-- Holds the releases the build carries (Changelog), the version running and
-- the one last seen (db.changesSeen, account-wide), and the visit: opening
-- What's new marks every change seen, but the releases new when it opened
-- stay marked until it's left, as the Feed's New entries do. Also the line
-- While you were away gets, once per update (db.changesTold). A fresh
-- install has nothing new; saved data from before What's new has only the
-- release installed. Pure; Core's internal seam.

local _, ns = ...

local WhatsNew = {}
WhatsNew.__index = WhatsNew
ns.WhatsNew = WhatsNew

local Changelog = ns.Changelog

-- How many releases the view lists, newest first.
WhatsNew.SHOWN = 5
local OLDER = "Older updates are on BFF's CurseForge page."

local function plural(count, word)
  return ("%d %s%s"):format(count, word, count == 1 and "" or "s")
end

-- db is the account-wide saved data, version the .toc's ("v2.3.0", or
-- "dev" in a checkout), text the changelog the build carries, and fresh
-- whether db was empty (a fresh install).
function WhatsNew.new(db, version, text, fresh)
  local self = setmetatable({ db = db, version = Changelog.version(version), releases = {} }, WhatsNew)
  if not self.version then return self end
  for _, release in ipairs(Changelog.parse(text)) do
    -- A changelog newer than the build (it can't be) lists nothing early.
    if not Changelog.newer(release.version, self.version) then self.releases[#self.releases + 1] = release end
  end
  if #self.releases == 0 then return self end
  if fresh then
    db.changesSeen = self.version
  elseif not Changelog.version(db.changesSeen) then
    -- Saved data from before What's new: only the release installed is new.
    local previous = self.releases[2]
    db.changesSeen = previous and previous.version or self.version
  end
  return self
end

function WhatsNew:available()
  return #self.releases > 0
end

-- The releases newer than the one seen, newest first.
local function unseen(self)
  local list = {}
  local seen = Changelog.version(self.db.changesSeen)
  for _, release in ipairs(self.releases) do
    if seen and Changelog.newer(release.version, seen) then list[#list + 1] = release end
  end
  return list
end

local function countChanges(releases)
  local count = 0
  for _, release in ipairs(releases) do count = count + #release.entries end
  return count
end

local function majorOf(releases)
  for _, release in ipairs(releases) do
    for _, entry in ipairs(release.entries) do
      if entry.kind == "major" then return release end
    end
  end
end

function WhatsNew:hasNew()
  return #unseen(self) > 0
end

-- What a visit opened now would show as new: { list (the unseen releases),
-- new (by version), since (the version seen before) }.
local function newVisit(self)
  local list, new = unseen(self), {}
  for _, release in ipairs(list) do new[release.version] = true end
  return { list = list, new = new, since = self.db.changesSeen }
end

-- Starts a visit if none is open, marking every change seen. Returns true
-- if that changed what's seen.
function WhatsNew:open()
  if self.visit or not self:available() then return false end
  self.visit = newVisit(self)
  self.db.changesSeen = self.version
  return #self.visit.list > 0
end

function WhatsNew:leave()
  self.visit = nil
end

-- Make sure your friends update: for a major release new on this visit,
-- the Members (from Roster rows, not you) known to run an older BFF.
-- everyone says there are friends, each one's version is known and none is
-- behind. text says why it matters, and who says everyone is up to date
-- (nil otherwise: the view names those behind). versionOf(memberId) is the
-- BFF version a Member's record carries.
local function friends(release, rows, versionOf)
  local behind, known, others = {}, 0, 0
  for _, row in ipairs(rows) do
    if not row.own then
      others = others + 1
      local version = Changelog.version(versionOf(row.memberId))
      if version then
        known = known + 1
        if Changelog.newer(release.version, version) then
          behind[#behind + 1] = { name = row.displayName, classFilename = row.classFilename, version = version }
        end
      end
    end
  end
  local everyone = others > 0 and known == others and #behind == 0
  return {
    version = release.version, behind = behind, everyone = everyone,
    text = ("Since %s, friends on an older BFF see an \"out of date\" notice and stop seeing you until they update.")
      :format(release.version),
    who = everyone and ("Everyone in your Crew is on %s or later."):format(release.version) or nil,
  }
end

-- The What's new view: { title, line, friends (nil, or { version, behind,
-- everyone, text, who }), releases (the last SHOWN: { version, date, new, entries
-- ({ title, detail }) }), older (a line about older updates, or nil) }.
-- rows and versionOf as for friends(). Nil without a changelog.
function WhatsNew:view(rows, versionOf)
  if not self:available() then return nil end
  local visit = self.visit or newVisit(self)
  local view = { releases = {} }
  local missedOut = 0
  for i, release in ipairs(self.releases) do
    if i <= WhatsNew.SHOWN then
      local entries = {}
      for j, entry in ipairs(release.entries) do entries[j] = { title = entry.title, detail = entry.detail } end
      view.releases[i] = { version = release.version, date = release.date, new = visit.new[release.version] == true,
        entries = entries }
    elseif visit.new[release.version] then
      missedOut = missedOut + 1
    end
  end
  if #visit.list > 0 then
    view.title = "Updated to " .. self.version
    view.line = plural(countChanges(visit.list), "change") .. " since " .. tostring(visit.since)
    if missedOut > 0 then view.line = view.line .. (" · the last %d updates are below"):format(WhatsNew.SHOWN) end
    local major = majorOf(visit.list)
    if major then view.friends = friends(major, rows, versionOf) end
  else
    view.title = "What's new in BFF"
    view.line = ("You're on %s, from %s"):format(self.version, self.releases[1].date)
  end
  if #self.releases > WhatsNew.SHOWN then
    view.older = missedOut > 0 and ("%s you missed %s shown here. %s"):format(plural(missedOut, "older update"),
      missedOut == 1 and "isn't" or "aren't", OLDER) or OLDER
  end
  return view
end

-- While you were away's section, once per update: { title (its label),
-- lines (the newest change, then "Make sure your friends update too" when
-- a major release came with it), more ("and 2 more changes", or nil) }, or
-- nil. Taken whether or not the popup shows, so it's never kept for later.
function WhatsNew:takeAwayLine()
  local new = unseen(self)
  if #new == 0 or self.db.changesTold == self.version then return nil end
  self.db.changesTold = self.version
  local lines = { new[1].entries[1].title }
  if majorOf(new) then lines[2] = "Make sure your friends update too" end
  local more = countChanges(new) - 1
  return {
    title = "BFF UPDATED TO " .. self.version,
    lines = lines,
    more = more > 0 and "and " .. plural(more, "more change") or nil,
  }
end
