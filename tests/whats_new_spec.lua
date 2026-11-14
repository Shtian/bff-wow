local load = require("tests.load")

-- A changelog with a major release in the middle and more releases than What's
-- new shows.
local TEXT = [[
# Changelog

## 2.3.0
<sub>2026-11-15</sub>

- *(minor)*
  The panel is lit by the Camp's fire

  Its glow spills under the band.
- *(patch)* Fixed the bug report.

## 2.2.0
<sub>2026-11-13</sub>

- *(minor)* Friends who are away sit by the fire.

## 2.1.0
<sub>2026-11-13</sub>

- *(minor)* Rares earn the Crew a Trophy.

## 2.0.0
<sub>2026-11-12</sub>

- *(major)* Updates no longer arrive garbled. Friends on an older BFF stop seeing you.
- *(patch)* BFF stops whispering friends it can't reach.

## 1.6.2
<sub>2026-11-12</sub>

- *(patch)* Members you removed stay removed.

## 1.6.1
<sub>2026-11-12</sub>

- *(patch)* The bug report records channel notices.

## 1.6.0
<sub>2026-11-12</sub>

- *(minor)* The Pocket Camp shows what friends are doing.
]]

local function playing(name)
  return {
    guid = "Player-0-" .. name, name = name, classFilename = "MAGE",
    level = 10, xp = 0, maxXp = 1000, zone = "Elwynn Forest", deaths = 0,
  }
end

-- A client on the given BFF version, with saved data db.
local function client(net, name, version, db)
  return net:add(name, { character = playing(name), version = version, changelog = TEXT, db = db })
end

local function events(c, name)
  local list = {}
  for _, event in ipairs(c.events) do
    if event[1] == name then list[#list + 1] = event[2] end
  end
  return list
end

local function newFlags(view)
  local flags = {}
  for _, release in ipairs(view.releases) do flags[#flags + 1] = release.version .. (release.new and "*" or "") end
  return flags
end

describe("What's new", function()
  local ns, net
  before_each(function()
    ns = load()
    net = ns.FakeNet.new()
  end)

  describe("on a fresh install", function()
    it("has nothing new: the version installed is seen", function()
      local ann = client(net, "Ann", "v2.3.0"):login()
      assert.is_false(ann.core:hasNewChanges())
      local view = ann.core:whatsNew()
      assert.are.equal("What's new in BFF", view.title)
      assert.are.equal("You're on 2.3.0, from 15 Nov", view.line)
      assert.are.same({ "2.3.0", "2.2.0", "2.1.0", "2.0.0", "1.6.2" }, newFlags(view))
      assert.is_nil(view.friends)
    end)
  end)

  describe("after an update", function()
    local ann
    before_each(function()
      ann = client(net, "Ann", "v2.3.0", { changesSeen = "2.1.0" }):login()
    end)

    it("has new changes, marked on the releases since the one seen", function()
      assert.is_true(ann.core:hasNewChanges())
      ann.core:openWhatsNew()
      local view = ann.core:whatsNew()
      assert.are.equal("Updated to 2.3.0", view.title)
      assert.are.equal("3 changes since 2.1.0", view.line)
      assert.are.same({ "2.3.0*", "2.2.0*", "2.1.0", "2.0.0", "1.6.2" }, newFlags(view))
    end)

    it("gives each release its date and entries as titles and details", function()
      ann.core:openWhatsNew()
      local release = ann.core:whatsNew().releases[1]
      assert.are.equal("15 Nov", release.date)
      assert.are.same({
        { title = "The panel is lit by the Camp's fire", detail = "Its glow spills under the band." },
        { title = "Fixed the bug report." },
      }, release.entries)
    end)

    it("are seen once opened, but stay marked until What's new is left", function()
      ann.core:openWhatsNew()
      assert.is_false(ann.core:hasNewChanges())
      assert.are.same({ "2.3.0*", "2.2.0*", "2.1.0", "2.0.0", "1.6.2" }, newFlags(ann.core:whatsNew()))
      ann.core:leaveWhatsNew()
      ann.core:openWhatsNew()
      assert.are.same({ "2.3.0", "2.2.0", "2.1.0", "2.0.0", "1.6.2" }, newFlags(ann.core:whatsNew()))
      assert.are.equal("What's new in BFF", ann.core:whatsNew().title)
    end)

    it("stay seen after a reload", function()
      ann.core:openWhatsNew()
      ann.core:leaveWhatsNew()
      ann:reload()
      assert.is_false(ann.core:hasNewChanges())
    end)

    it("redraws the panel when opening marks them seen", function()
      ann.events = {}
      ann.core:openWhatsNew()
      assert.are.equal(1, ann:count("changed"))
      ann.core:openWhatsNew()
      assert.are.equal(1, ann:count("changed"))
    end)

    it("come back with the next update", function()
      ann.core:openWhatsNew()
      ann.core:leaveWhatsNew()
      ann:logout()
      ann.version = "v2.4.0"
      ann.changelog = "## 2.4.0\n<sub>2026-11-20</sub>\n\n- *(patch)* A fix.\n\n" .. TEXT
      ann:login()
      assert.is_true(ann.core:hasNewChanges())
    end)
  end)

  it("marks only the release installed when What's new is new to the saved data", function()
    local ann = client(net, "Ann", "v2.3.0", { memberId = "ann-id" }):login()
    assert.is_true(ann.core:hasNewChanges())
    ann.core:openWhatsNew()
    assert.are.same({ "2.3.0*", "2.2.0", "2.1.0", "2.0.0", "1.6.2" }, newFlags(ann.core:whatsNew()))
    assert.are.equal("2 changes since 2.2.0", ann.core:whatsNew().line)
  end)

  it("shows the last 5 releases and says how many it leaves out", function()
    local ann = client(net, "Ann", "v2.3.0", { changesSeen = "1.5.0" }):login()
    ann.core:openWhatsNew()
    local view = ann.core:whatsNew()
    assert.are.equal("9 changes since 1.5.0 · the last 5 updates are below", view.line)
    assert.are.equal(5, #view.releases)
    assert.are.equal("2 older updates you missed aren't shown here. Older updates are on BFF's CurseForge page.",
      view.older)
  end)

  it("points to CurseForge for older updates when none of them were missed", function()
    local ann = client(net, "Ann", "v2.3.0", { changesSeen = "2.1.0" }):login()
    assert.are.equal("Older updates are on BFF's CurseForge page.", ann.core:whatsNew().older)
  end)

  describe("with a major release new", function()
    it("asks you to make sure your friends update, naming those on an older BFF", function()
      local ann = client(net, "Ann", "v2.3.0", { changesSeen = "1.6.2" }):login()
      local bob = client(net, "Bob", "v1.6.2"):login()
      local cat = client(net, "Cat", "v2.2.0"):login()
      local code = ann:join()
      bob:join(code)
      cat:join(code)
      net:run(60)
      ann.core:openWhatsNew()
      local friends = ann.core:whatsNew().friends
      assert.are.equal("2.0.0", friends.version)
      assert.are.same({ { name = "Bob", classFilename = "MAGE", version = "1.6.2" } }, friends.behind)
      assert.is_false(friends.everyone)
      assert.are.equal("Since 2.0.0, friends on an older BFF see an \"out of date\" notice and stop seeing you until"
        .. " they update.", friends.text)
    end)

    it("says when everyone in the Crew is up to date", function()
      local ann = client(net, "Ann", "v2.3.0", { changesSeen = "1.6.2" }):login()
      local bob = client(net, "Bob", "v2.0.0"):login()
      bob:join(ann:join())
      net:run(60)
      ann.core:openWhatsNew()
      local friends = ann.core:whatsNew().friends
      assert.are.same({}, friends.behind)
      assert.is_true(friends.everyone)
      assert.are.equal("Everyone in your Crew is on 2.0.0 or later.", friends.who)
    end)

    it("doesn't vouch for friends whose version it doesn't know", function()
      local ann = client(net, "Ann", "v2.3.0", { changesSeen = "1.6.2" }):login()
      local bob = client(net, "Bob", nil):login()
      bob:join(ann:join())
      net:run(60)
      ann.core:openWhatsNew()
      local friends = ann.core:whatsNew().friends
      assert.are.same({}, friends.behind)
      assert.is_false(friends.everyone)
      assert.is_nil(friends.who)
    end)

    it("doesn't vouch for a Crew of one", function()
      local ann = client(net, "Ann", "v2.3.0", { changesSeen = "1.6.2" }):login()
      ann:join()
      net:run(60)
      ann.core:openWhatsNew()
      assert.is_false(ann.core:whatsNew().friends.everyone)
      assert.is_nil(ann.core:whatsNew().friends.who)
    end)

    it("isn't asked once the major release was seen", function()
      local ann = client(net, "Ann", "v2.3.0", { changesSeen = "2.0.0" }):login()
      ann.core:openWhatsNew()
      assert.is_nil(ann.core:whatsNew().friends)
    end)
  end)

  describe("in While you were away", function()
    local function crewAfterUpdate(seen)
      local ann = client(net, "Ann", "v2.3.0"):login()
      local bob = client(net, "Bob", "v2.3.0"):login()
      bob:join(ann:join())
      net:run(60)
      -- A login that takes the Crew's news, so the next one has none.
      ann:logout()
      ann:login()
      net:run(60)
      ann:logout()
      ann.db.changesSeen = seen
      ann.events = {}
      ann:login()
      net:run(60)
      return ann, bob
    end

    it("says BFF updated, with the newest change and how many more, even with no other news", function()
      local ann = crewAfterUpdate("2.1.0")
      local summaries = events(ann, "awaySummary")
      assert.are.equal(1, #summaries)
      assert.are.same({ title = "BFF UPDATED TO 2.3.0",
        lines = { "The panel is lit by the Camp's fire" }, more = "and 2 more changes" }, summaries[1].update)
    end)

    it("says so when the update holds a major release", function()
      local ann = crewAfterUpdate("1.6.2")
      assert.are.same({ "The panel is lit by the Camp's fire", "Make sure your friends update too" },
        events(ann, "awaySummary")[1].update.lines)
    end)

    it("says it only once per update", function()
      local ann = crewAfterUpdate("2.1.0")
      ann:logout()
      ann.events = {}
      ann:login()
      net:run(60)
      for _, summary in ipairs(events(ann, "awaySummary")) do assert.is_nil(summary.update) end
      assert.is_true(ann.core:hasNewChanges())
    end)

    it("isn't kept for later while the popup is off", function()
      local ann = client(net, "Ann", "v2.3.0"):login()
      local bob = client(net, "Bob", "v2.3.0"):login()
      bob:join(ann:join())
      net:run(60)
      ann.core:setAwayPopup(false)
      ann:logout()
      ann.db.changesSeen = "2.1.0"
      ann:login()
      net:run(60)
      ann.core:setAwayPopup(true)
      ann:logout()
      ann.events = {}
      ann:login()
      net:run(60)
      for _, summary in ipairs(events(ann, "awaySummary")) do assert.is_nil(summary.update) end
      assert.is_true(ann.core:hasNewChanges())
    end)

    it("says nothing with no update", function()
      local ann = crewAfterUpdate("2.3.0")
      for _, summary in ipairs(events(ann, "awaySummary")) do assert.is_nil(summary.update) end
    end)
  end)

  describe("in a dev checkout", function()
    it("tells friends a new version when only that changed", function()
      local ann = client(net, "Ann", "v2.3.0", { changesSeen = "1.6.2" }):login()
      local bob = client(net, "Bob", "v1.6.2"):login()
      bob:join(ann:join())
      net:run(60)
      bob.version = "v2.3.0"
      bob:reload()
      net:run(60)
      ann.core:openWhatsNew()
      assert.is_true(ann.core:whatsNew().friends.everyone)
    end)

    it("has no What's new and tells friends no version", function()
      local ann = client(net, "Ann", "dev"):login()
      local bob = client(net, "Bob", "v2.3.0", { changesSeen = "1.6.2" }):login()
      bob:join(ann:join())
      net:run(60)
      assert.is_nil(ann.core:whatsNew())
      assert.is_false(ann.core:hasNewChanges())
      bob.core:openWhatsNew()
      assert.is_false(bob.core:whatsNew().friends.everyone)
    end)

    it("has no What's new without a changelog", function()
      local ann = net:add("Ann", { character = playing("Ann"), version = "v2.3.0" }):login()
      assert.is_nil(ann.core:whatsNew())
      assert.is_false(ann.core:hasNewChanges())
    end)
  end)
end)
