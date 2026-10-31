local load = require("tests.load")

local record = {
  id = "k3j9x2qa",
  version = 1761900000,
  characters = {
    ["Player-1-0000AAAA"] = {
      guid = "Player-1-0000AAAA", name = "Thrallbane", classFilename = "WARRIOR",
      level = 24, xp = 1200, maxXp = 2000, zone = "Stranglethorn Vale",
      deaths = 3, lastPlayed = 1761900000,
    },
  },
}

describe("Codec", function()
  it("round-trips a record", function()
    local Codec = load().Codec
    local value, err = Codec.decode(Codec.encode(record))
    assert.is_nil(err)
    assert.same(record, value)
  end)

  it("puts a plain-text protocol header in front", function()
    local Codec = load().Codec
    assert.equal(Codec.PROTOCOL .. "|", Codec.encode(record):match("^%d+|"))
  end)

  it("encodes into something an addon channel can carry", function()
    local encoded = load().Codec.encode(record)
    assert.is_nil(encoded:find("%z"))
  end)

  it("detects a newer protocol version before decoding anything", function()
    local Codec = load().Codec
    local value, err = Codec.decode((Codec.PROTOCOL + 1) .. "|this is not a valid body")
    assert.is_nil(value)
    assert.equal("newer", err)
  end)

  it("rejects garbage", function()
    local Codec = load().Codec
    for _, message in ipairs({ "", "hello", "x|abc", Codec.PROTOCOL .. "|not deflated" }) do
      local value, err = Codec.decode(message)
      assert.is_nil(value)
      assert.equal("invalid", err)
    end
  end)
end)
