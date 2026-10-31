-- Loads Core the way the game does: the pure libraries Core uses, then every
-- Core/ file listed in BFF.toc, in order, called with the addon name and a
-- shared private namespace. FakeNet comes along for the scenario tests.

-- LibStub keeps one copy of each library per process, as in game.
local libraries = {
  "Libs/LibStub/LibStub.lua",
  "Libs/LibSerialize/LibSerialize.lua",
  "Libs/LibDeflate/LibDeflate.lua",
}
for _, path in ipairs(libraries) do
  local chunk = loadfile(path)
  assert(chunk, path .. " is missing; run scripts/fetch-libs.sh")
  chunk()
end

local function coreFiles()
  local files = {}
  for line in io.lines("BFF.toc") do
    local path = line:match("^%s*(Core/[^%s]+%.lua)%s*$")
    if path then files[#files + 1] = path end
  end
  assert(#files > 0, "BFF.toc lists no Core files")
  return files
end

return function()
  local ns = {}
  for _, path in ipairs(coreFiles()) do
    assert(loadfile(path))("BFF", ns)
  end
  assert(loadfile("Dev/FakeNet.lua"))("BFF", ns)
  return ns
end
