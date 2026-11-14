local load = require("tests.load")

-- A CHANGELOG.md as bumpy writes it: a title, blank lines, then a section per
-- release with its date and an item per bump file.
local TEXT = [[
# Changelog



## 2.3.0
<sub>2026-11-15</sub>

- *(minor)*
  The panel is lit by the Camp's fire

  Its glow spills under the band, and now and then an ember drifts down.
- *(patch)* Fixed `/bff report` on **Forever**.

## 2.0.0
<sub>2026-11-12</sub>

- *(major)*
  BFF now splits long messages into chunks itself. Friends on an older BFF are still seen.
- *(patch)*
  BFF stops whispering friends it can't reach.

## 1.6.1
<sub>2026-11-02</sub>

- *(patch)* One line only, with no full stop
]]

describe("Changelog", function()
  local Changelog
  before_each(function() Changelog = load().Changelog end)

  describe("parse", function()
    it("reads each release, newest first, with its date as the game shows it", function()
      local releases = Changelog.parse(TEXT)
      assert.are.equal(3, #releases)
      assert.are.same({ "2.3.0", "2.0.0", "1.6.1" }, { releases[1].version, releases[2].version, releases[3].version })
      assert.are.equal("15 Nov", releases[1].date)
      assert.are.equal("2 Nov", releases[3].date)
    end)

    it("takes an entry's first paragraph as its title and the rest as its detail", function()
      local entry = Changelog.parse(TEXT)[1].entries[1]
      assert.are.same({
        kind = "minor",
        title = "The panel is lit by the Camp's fire",
        detail = "Its glow spills under the band, and now and then an ember drifts down.",
      }, entry)
    end)

    it("reads an entry written on the bullet's own line, without Markdown marks", function()
      local entry = Changelog.parse(TEXT)[1].entries[2]
      assert.are.same({ kind = "patch", title = "Fixed /bff report on Forever." }, entry)
    end)

    it("splits a one-paragraph entry after its first sentence", function()
      local entry = Changelog.parse(TEXT)[2].entries[1]
      assert.are.equal("major", entry.kind)
      assert.are.equal("BFF now splits long messages into chunks itself.", entry.title)
      assert.are.equal("Friends on an older BFF are still seen.", entry.detail)
    end)

    it("keeps a one-sentence entry whole", function()
      assert.are.same({ kind = "patch", title = "BFF stops whispering friends it can't reach." },
        Changelog.parse(TEXT)[2].entries[2])
      assert.are.same({ kind = "patch", title = "One line only, with no full stop" },
        Changelog.parse(TEXT)[3].entries[1])
    end)

    it("reads nothing from no text", function()
      assert.are.same({}, Changelog.parse(nil))
      assert.are.same({}, Changelog.parse("# Changelog\n"))
    end)

    it("reads the real CHANGELOG.md", function()
      local file = assert(io.open("CHANGELOG.md"))
      local releases = Changelog.parse(file:read("*a"))
      file:close()
      assert.is_true(#releases > 0)
      for _, release in ipairs(releases) do
        assert.is_truthy(Changelog.version(release.version), release.version)
        assert.is_truthy(release.date:match("^%d+ %a%a%a$"), release.version)
        assert.is_true(#release.entries > 0, release.version)
        for _, entry in ipairs(release.entries) do
          assert.is_truthy(entry.title:match("%S"), release.version)
          assert.is_falsy(entry.title:find("`", 1, true), release.version)
        end
      end
    end)
  end)

  describe("version", function()
    it("reads a release version, with or without the tag's v", function()
      assert.are.equal("2.2.0", Changelog.version("2.2.0"))
      assert.are.equal("2.2.0", Changelog.version("v2.2.0"))
      assert.is_nil(Changelog.version("dev"))
      assert.is_nil(Changelog.version(nil))
      assert.is_nil(Changelog.version("2.2"))
    end)

    it("compares versions by number, not as text", function()
      assert.is_true(Changelog.newer("2.10.0", "2.9.1"))
      assert.is_true(Changelog.newer("3.0.0", "2.99.99"))
      assert.is_false(Changelog.newer("2.2.0", "2.2.0"))
      assert.is_false(Changelog.newer("1.6.2", "2.0.0"))
    end)
  end)
end)
