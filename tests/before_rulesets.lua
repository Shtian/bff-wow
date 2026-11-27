local RELEASE = "bff@2.18.0"

local function show(path)
  local pipe = assert(io.popen(("git show %s:%s 2>/dev/null"):format(RELEASE, path)))
  local source = pipe:read("*a")
  pipe:close()
  assert(source ~= "", ("%s:%s is missing; fetch the tags with git fetch --tags"):format(RELEASE, path))
  return source
end

local chunks

local function releaseChunks()
  if chunks then return chunks end
  chunks = {}
  for line in show("BFF.toc"):gmatch("[^\n]+") do
    local path = line:match("^%s*(Core/[^%s]+%.lua)%s*$") or line:match("^%s*(Link/[^%s]+%.lua)%s*$")
    if path then chunks[#chunks + 1] = assert(loadstring(show(path), ("@%s/%s"):format(RELEASE, path))) end
  end
  return chunks
end

return function()
  local ns = {}
  for _, chunk in ipairs(releaseChunks()) do chunk("BFF", ns) end
  return ns.Core
end
