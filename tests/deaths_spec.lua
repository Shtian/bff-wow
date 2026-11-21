local load = require("tests.load")

describe("Deaths", function()
  local Deaths
  before_each(function() Deaths = load().Deaths end)

  it("don't count in a battleground", function()
    assert.is_false(Deaths.counts("pvp"))
  end)

  it("don't count in an arena", function()
    assert.is_false(Deaths.counts("arena"))
  end)

  it("count in the open world, dungeons, raids and anywhere else", function()
    for _, instanceType in ipairs({ "none", "party", "raid", "scenario", "delve" }) do
      assert.is_true(Deaths.counts(instanceType), instanceType)
    end
  end)

  it("count when the instance type can't be read", function()
    assert.is_true(Deaths.counts(nil))
  end)
end)
