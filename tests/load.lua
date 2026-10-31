-- Loads Core the way the game does: every Core/ file listed in BFF.toc, in
-- order, called with the addon name and a shared private namespace.

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
  return ns
end
