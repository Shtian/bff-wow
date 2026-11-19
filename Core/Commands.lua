local _, ns = ...

local Commands = {}
ns.Commands = Commands

Commands.WIDTH = 60

local GOLD = "|cffffd14a"
local GREY = "|cffadabb8"
local CONTINUED = "   "

local ENTRIES = {
  { name = "roster", group = "tab", forms = { { "", "open the Roster tab" } } },
  { name = "feed", group = "tab", forms = { { "", "open the Feed tab" } } },
  { name = "trophies", group = "tab", aliases = { "goals" }, forms = { { "", "open the Trophies tab" } } },
  { name = "playtimes", group = "tab", aliases = { "play", "when" }, forms = { { "", "open the Play Times tab" } } },
  { name = "spares", group = "tab", forms = {
    { "", "open the Spare Items tab" },
    { "add <item>", "offer an item from your bags: shift-click it in after add" },
  } },
  { name = "professions", group = "tab", forms = { { "", "open the Professions tab" } } },
  { name = "dungeons", group = "tab", aliases = { "together" }, forms = { { "", "open the Dungeons tab" } } },
  { name = "catches", group = "tab", forms = { { "", "open the Catches tab" } } },
  { name = "whatsnew", group = "tab", forms = { { "", "open What's new" } } },
  { name = "start", group = "crew", forms = { { "", "start a Crew and show its code to share" } } },
  { name = "join", group = "crew", forms = { { "<code>", "join a Crew with the code a friend shared" } } },
  { name = "code", group = "crew", forms = { { "", "show your Crew code" } } },
  { name = "name", group = "crew", forms = { { "<name>", "set the name your friends see" } } },
  { name = "leave", group = "crew", forms = { { "", "leave your Crew" } } },
  { name = "settings", group = "tools", forms = { { "", "open Settings" } } },
  { name = "minimap", group = "tools", forms = { { "", "bring back a hidden minimap button" } } },
  { name = "report", group = "tools", forms = { { "", "open a diagnostics report to copy into a bug report" } } },
  { name = "debug", group = "tools", forms = {
    { "sync", "print the sync trace in chat as well, until you turn it off or reload" },
  } },
  { name = "help", group = "help", forms = {
    { "", "list the commands" },
    { "<command>", "more about one command" },
  } },
  { name = "sim", group = "dev", forms = {
    { "", "add simulated Members, to try BFF alone" },
    { "ding", "a simulated Member dings" },
    { "fish", "a simulated Member catches something" },
    { "stop", "log the simulated Members out" },
  } },
}

local byWord = {}
for _, entry in ipairs(ENTRIES) do
  byWord[entry.name] = entry
  for _, alias in ipairs(entry.aliases or {}) do byWord[alias] = entry end
end

local function gold(text) return GOLD .. text .. "|r" end
local function grey(text) return GREY .. text .. "|r" end

local function visible(text)
  return #(text:gsub("·", "."))
end

local function usage(name, args)
  return args == "" and name or name .. " " .. args
end

local function described(command, about)
  return gold("/bff" .. (command == "" and "" or " " .. command)) .. grey("  " .. about)
end

local function listed(label, items, separator)
  local lines = {}
  local closing = separator:gsub("%s+$", "")
  local line = " " .. (label == "" and "" or grey(label)) .. gold("/bff " .. items[1])
  local width = 1 + visible(label) + visible("/bff " .. items[1])
  for i = 2, #items do
    local item = items[i]
    local reserved = i < #items and visible(closing) or 0
    if width + visible(separator) + visible(item) + reserved > Commands.WIDTH then
      lines[#lines + 1] = line .. grey(closing)
      line, width = CONTINUED .. gold(item), #CONTINUED + visible(item)
    else
      line = line .. grey(separator) .. gold(item)
      width = width + visible(separator) + visible(item)
    end
  end
  lines[#lines + 1] = line
  return lines
end

local function itemsIn(group)
  local items = {}
  for _, entry in ipairs(ENTRIES) do
    if entry.group == group then items[#items + 1] = usage(entry.name, entry.forms[1][1]) end
  end
  return items
end

local function append(lines, more)
  for _, line in ipairs(more) do lines[#lines + 1] = line end
end

local function shown(entry, dev)
  return entry and (dev or entry.group ~= "dev")
end

function Commands.names()
  local names = {}
  for i, entry in ipairs(ENTRIES) do names[i] = entry.name end
  return names
end

function Commands.resolve(word)
  local entry = byWord[(word or ""):lower()]
  return entry and entry.name
end

function Commands.help(dev)
  local lines = { "BFF commands", " " .. described("", "open or close the panel") }
  append(lines, listed("Open a tab: ", itemsIn("tab"), ", "))
  append(lines, listed("Crew: ", itemsIn("crew"), " · "))
  lines[#lines + 1] = " " .. described("spares add <item>", "offer an item from your bags")
  append(lines, listed("", itemsIn("tools"), " · "))
  lines[#lines + 1] = " " .. described("help <command>", "more about one")
  if dev then lines[#lines + 1] = " " .. described("sim", "simulated Members, to try BFF alone") end
  return lines
end

function Commands.helpFor(word, dev)
  local entry = byWord[(word or ""):lower()]
  if not shown(entry, dev) then return nil end
  local lines = {}
  for i, form in ipairs(entry.forms) do
    lines[i] = described(usage(entry.name, form[1]), form[2])
  end
  return lines
end

local function distance(a, b)
  local previous = {}
  for j = 0, #b do previous[j] = j end
  for i = 1, #a do
    local current = { [0] = i }
    for j = 1, #b do
      local cost = a:sub(i, i) == b:sub(j, j) and 0 or 1
      current[j] = math.min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
    end
    previous = current
  end
  return previous[#b]
end

local function closeness(input, word)
  if #input >= 2 and word:sub(1, #input) == input then return 0 end
  local edits = distance(input, word)
  if edits <= 2 and edits < #input then return edits end
end

function Commands.suggest(input, dev)
  input = (input or ""):lower()
  local best, bestScore
  for _, entry in ipairs(ENTRIES) do
    if shown(entry, dev) then
      local words = { entry.name }
      append(words, entry.aliases or {})
      for _, word in ipairs(words) do
        local score = closeness(input, word)
        if score and (not bestScore or score < bestScore) then best, bestScore = entry.name, score end
      end
    end
  end
  return best
end

function Commands.unknown(input, dev)
  local suggestion = Commands.suggest(input, dev)
  if suggestion then
    return ("No %s. Did you mean %s? (%s lists them)"):format(
      gold("/bff " .. input), gold("/bff " .. suggestion), gold("/bff help"))
  end
  return ("No %s. %s lists them."):format(gold("/bff " .. input), gold("/bff help"))
end
