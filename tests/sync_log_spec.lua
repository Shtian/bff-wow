local wow = require("tests.wow_stubs")

local function newLog(cap)
  local game = wow()
  return game.load("Game/SyncLog.lua", {}).SyncLog.new(cap)
end

local function fill(log, from, to)
  for i = from, to do log:add("line " .. i) end
end

describe("The sync log", function()
  it("keeps every line, oldest first", function()
    local log = newLog(5)
    fill(log, 1, 3)
    assert.same({ "line 1", "line 2", "line 3" }, log:lines())
  end)

  it("never holds more than its cap, dropping the oldest first", function()
    local log = newLog(3)
    fill(log, 1, 10)
    assert.same({ "line 8", "line 9", "line 10" }, log:lines())
  end)

  it("saves its lines as a plain array no longer than the cap", function()
    local log = newLog(3)
    fill(log, 1, 4)
    local saved = log:save()
    assert.same({ "line 2", "line 3", "line 4" }, saved)
    -- A copy: lines added later don't change what was saved.
    log:add("line 5")
    assert.same({ "line 2", "line 3", "line 4" }, saved)
  end)

  it("restores saved lines before a separator, then keeps adding", function()
    local before = newLog(10)
    fill(before, 1, 3)

    local after = newLog(10)
    after:restore(before:save(), "-- earlier session --")
    after:add("line 4")

    assert.same({ "line 1", "line 2", "line 3", "-- earlier session --", "line 4" }, after:lines())
  end)

  it("keeps within the cap after a restore, the separator included", function()
    local before = newLog(3)
    fill(before, 1, 3)

    local after = newLog(3)
    after:restore(before:save(), "-- earlier session --")
    assert.same({ "line 2", "line 3", "-- earlier session --" }, after:lines())
    after:add("line 4")
    assert.same({ "line 3", "-- earlier session --", "line 4" }, after:lines())
    assert.equal(3, #after:save())
  end)

  it("restores only the newest lines of a saved log longer than the cap", function()
    local log = newLog(3)
    log:restore({ "a", "b", "c", "d", "e" }, "--")
    assert.same({ "d", "e", "--" }, log:lines())
  end)

  it("adds no separator when nothing was saved, and skips anything that isn't a line", function()
    local log = newLog(5)
    log:restore(nil, "--")
    log:restore({}, "--")
    assert.same({}, log:lines())

    log:restore({ "a", 7, false, "b" }, "--")
    assert.same({ "a", "b", "--" }, log:lines())

    log:restore("not a table", "--")
    assert.same({ "a", "b", "--" }, log:lines())
  end)
end)
