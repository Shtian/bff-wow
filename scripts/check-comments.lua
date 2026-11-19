local MARKER = "WoW:"

local function longBracketLevel(line, i)
  local eq = line:match("^%[(=*)%[", i)
  return eq and #eq
end

local function scan(path, failures)
  local file = assert(io.open(path, "r"))
  local lineNo, inLong, longClose, longIsComment = 0, false, nil, false
  local previousWasMarkedComment = false
  for line in file:lines() do
    lineNo = lineNo + 1
    local i, n, quote = 1, #line, nil
    local commentText, wholeLine = nil, false
    while i <= n do
      if inLong then
        local close = line:find(longClose, i, true)
        if not close then i = n + 1 else
          inLong = false
          i = close + #longClose
        end
      elseif quote then
        local c = line:sub(i, i)
        if c == "\\" then i = i + 2
        else
          if c == quote then quote = nil end
          i = i + 1
        end
      else
        local c = line:sub(i, i)
        if c == '"' or c == "'" then
          quote = c
          i = i + 1
        elseif c == "[" and longBracketLevel(line, i) then
          local level = longBracketLevel(line, i)
          inLong, longClose, longIsComment = true, "]" .. ("="):rep(level) .. "]", false
          i = i + level + 2
        elseif line:sub(i, i + 1) == "--" then
          commentText = line:sub(i + 2)
          wholeLine = not line:sub(1, i - 1):find("%S")
          local level = longBracketLevel(line, i + 2)
          if level then
            inLong, longClose, longIsComment = true, "]" .. ("="):rep(level) .. "]", true
          end
          break
        else
          i = i + 1
        end
      end
    end
    if commentText then
      local marked = commentText:match("^%s*" .. MARKER:gsub("%p", "%%%0"))
      local continues = wholeLine and previousWasMarkedComment
      if not (marked or continues) then
        failures[#failures + 1] = ("%s:%d: %s"):format(path, lineNo, line:match("^%s*(.-)%s*$"))
      end
      previousWasMarkedComment = wholeLine and (marked or continues) and true or false
    else
      previousWasMarkedComment = false
    end
    if inLong and longIsComment and not commentText then
      failures[#failures + 1] = ("%s:%d: %s"):format(path, lineNo, line)
    end
  end
  file:close()
end

local failures = {}
for path in io.lines() do scan(path, failures) end
for _, failure in ipairs(failures) do print(failure) end
if #failures > 0 then
  io.stderr:write(("%d comment line(s) without the %q prefix. See CODING_STANDARDS.md, \"Comments\".\n")
    :format(#failures, "-- " .. MARKER))
  os.exit(1)
end
