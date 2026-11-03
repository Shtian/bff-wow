local load = require("tests.load")

local Text = load().Text

local HOUR, DAY = 3600, 86400
-- Monday 2026-11-02 00:00 UTC.
local MONDAY = 1793577600

describe("Text", function()
  it("says how long ago in minutes, hours or days", function()
    assert.equal("0m", Text.ago(-5))
    assert.equal("0m", Text.ago(59))
    assert.equal("5m", Text.ago(5 * 60 + 30))
    assert.equal("59m", Text.ago(HOUR - 1))
    assert.equal("1h", Text.ago(HOUR))
    assert.equal("3h", Text.ago(2.5 * HOUR))
    assert.equal("24h", Text.ago(DAY - 1))
    assert.equal("1d", Text.ago(DAY))
    assert.equal("3d", Text.ago(2.5 * DAY))
    assert.equal("5m ago", Text.since(5 * 60))
  end)

  it("titles a Feed day: today, yesterday, else weekday and date", function()
    assert.equal("TODAY", Text.dayTitle(0, MONDAY, 0))
    assert.equal("YESTERDAY", Text.dayTitle(1, MONDAY, 0))
    assert.equal("MONDAY 02 NOVEMBER", Text.dayTitle(2, MONDAY + 10 * HOUR, 0))
    assert.equal("SUNDAY 01 NOVEMBER", Text.dayTitle(2, MONDAY - HOUR, 0))
    assert.equal("THURSDAY 01 JANUARY", Text.dayTitle(5, 0, 0))
    assert.equal("TUESDAY 29 FEBRUARY", Text.dayTitle(5, 951782400, 0))
  end)

  it("reads dates in local time", function()
    -- Sunday 23:00 UTC is Monday at UTC+2; Monday 01:00 UTC is Sunday at UTC-2.
    assert.equal("MONDAY 02 NOVEMBER", Text.dayTitle(2, MONDAY - HOUR, 2 * HOUR))
    assert.equal("SUNDAY 01 NOVEMBER", Text.dayTitle(2, MONDAY + HOUR, -2 * HOUR))
    assert.equal("2 Nov", Text.shortDate(MONDAY - HOUR, 2 * HOUR))
    assert.equal("1 Nov", Text.shortDate(MONDAY - HOUR, 0))
    assert.equal("31 Dec", Text.shortDate(MONDAY + 59 * DAY, 0))
  end)
end)
