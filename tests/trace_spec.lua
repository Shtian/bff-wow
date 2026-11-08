local load = require("tests.load")

-- A net with Ann and Bob logged in and in one Crew, settled.
local function crew()
  local ns = load()
  local net = ns.FakeNet.new()
  local a = net:add("Ann"):login()
  local b = net:add("Bob"):login()
  b:join(a:join())
  net:run(20)
  return net, a, b, ns
end

-- Starts a sync trace on a client's Core: the lines it reports.
local function trace(client)
  local lines = {}
  client.core:setTrace(function(line) lines[#lines + 1] = line end)
  return lines
end

-- The lines starting with `prefix`.
local function starting(lines, prefix)
  local found = {}
  for _, line in ipairs(lines) do
    if line:sub(1, #prefix) == prefix then found[#found + 1] = line end
  end
  return found
end

describe("The sync trace", function()
  it("reports each send with its type, records, versions and size", function()
    local net, a = crew()
    local lines = trace(a)
    local mark = #net.wire

    a:play({ level = 11 })
    net:run(2)

    local sends = starting(lines, "send DATA")
    assert.equal(1, #sends)
    local sent = net.wire[mark + 1]
    assert.equal("Ann", sent.from)
    local own = a.core:rows()[1]
    assert.equal("Ann", own.displayName)
    assert.truthy(sends[1]:find(("· %d B ·"):format(#sent.message), 1, true))
    assert.truthy(sends[1]:find("Ann (", 1, true))
    assert.truthy(sends[1]:find(" v%d+$"))
  end)

  it("reports a DIGEST sent with how many versions it carries", function()
    local net, a = crew()
    local lines = trace(a)

    a:lockdown(true)
    net:run(1)
    a:lockdown(false)
    net:run(1)

    local sends = starting(lines, "send DIGEST")
    assert.equal(1, #sends)
    assert.truthy(sends[1]:find("· 2 versions ·", 1, true))
    assert.truthy(sends[1]:find("%d+ B$"))
  end)

  it("reports a DATA received with its sender, result, versions and how late it is", function()
    local net, a, b = crew()
    local lines = trace(b)

    a:lockdown(true)
    a:play({ level = 11 })
    net:run(60)
    a:lockdown(false)
    net:run(5)

    local received = starting(lines, "receive DATA from Ann · ok")
    assert.is_true(#received >= 1)
    local line = received[1]
    assert.truthy(line:find("Ann (", 1, true))
    assert.truthy(line:find(" v%d+"))
    assert.truthy(line:find("merged", 1, true))
    local late = tonumber(line:match("late (%d+)s"))
    assert.is_true(late >= 60 and late <= 62, line)
  end)

  it("reports a DATA already held as not newer", function()
    local net, a, b = crew()
    local lines = trace(b)

    a:lockdown(true)
    a:play({ level = 11 })
    net:run(1)
    a:lockdown(false)
    net:run(5)
    -- The same record again, as another Member relaying it would.
    a:lockdown(true)
    net:run(1)
    a:lockdown(false)
    net:run(5)

    local merged = starting(lines, "receive DATA from Ann · ok")
    assert.truthy(merged[1]:find("merged", 1, true))
    for i = 2, #merged do assert.truthy(merged[i]:find("not newer", 1, true), merged[i]) end
  end)

  it("reports a DIGEST received with the versions in it", function()
    local net, a, b = crew()
    local lines = trace(b)

    a:lockdown(true)
    net:run(1)
    a:lockdown(false)
    net:run(1)

    local received = starting(lines, "receive DIGEST from Ann · ok · ")
    assert.equal(1, #received)
    assert.truthy(received[1]:find("Ann v%d+"))
    assert.truthy(received[1]:find("Bob v%d+"))
  end)

  it("reports messages it can't read or that come from a newer BFF", function()
    local _, a = crew()
    local lines = trace(a)

    a.core:received("garbage")
    a.core:received("99|whatever")

    assert.same({ "receive · invalid · 7 B", "receive · newer · 11 B" }, lines)
  end)

  it("reports its own messages coming back as ignored", function()
    local net, a = crew()
    local lines = trace(a)

    a:play({ level = 11 })
    net:run(2)

    assert.equal(1, #starting(lines, "receive DATA from you · ignored"))
  end)

  it("stops when cleared", function()
    local net, a = crew()
    local lines = trace(a)
    a.core:setTrace(nil)

    a:play({ level = 11 })
    net:run(5)
    a.core:received("garbage")

    assert.same({}, lines)
  end)
end)
