local function sheetArt()
  local ns = {}
  assert(loadfile("UI/CampSheet.lua"))("BFF", ns)
  return ns.CampSheet.vignettes.art
end

local function artNamesIn(path)
  local file = assert(io.open(path))
  local source = file:read("*a")
  file:close()
  local names = {}
  for name in source:gmatch('art%s*=%s*"([%w_]+)"') do names[#names + 1] = name end
  return names
end

local function uiFiles()
  local files = {}
  for line in io.lines("BFF.toc") do
    local path = line:match("^%s*(UI/[^%s]+%.lua)%s*$")
    if path then files[#files + 1] = path end
  end
  return files
end

describe("empty state art", function()
  it("every art a tab asks for is on the empty states sheet", function()
    local art = sheetArt()
    local asked = 0
    for _, path in ipairs(uiFiles()) do
      for _, name in ipairs(artNamesIn(path)) do
        asked = asked + 1
        assert.is_table(art[name], path .. " asks for art \"" .. name .. "\"")
      end
    end
    assert.is_true(asked > 0, "found no art in UI/")
  end)
end)
