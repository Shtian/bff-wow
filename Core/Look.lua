local _, ns = ...

local Look = {}
ns.Look = Look

Look.HATS = {
  { key = "none", label = "None" },
  { key = "templar", label = "Templar helm" },
  { key = "centurion", label = "Centurion helmet" },
  { key = "dwarf", label = "Dwarven helm" },
  { key = "wolfskin", label = "Wolfskin helmet" },
  { key = "coonskin", label = "Coonskin cap" },
  { key = "cowboy", label = "Cowboy hat" },
  { key = "straw", label = "Straw hat" },
  { key = "fez", label = "Fez" },
  { key = "beret", label = "Beret" },
  { key = "circlet", label = "Circlet" },
  { key = "bandana", label = "Bandana" },
  { key = "cap", label = "Feathered cap" },
  { key = "wizard", label = "Wizard hat" },
  { key = "horns", label = "Horned helm" },
  { key = "tophat", label = "Top hat" },
}

local labels = {}
for _, hat in ipairs(Look.HATS) do labels[hat.key] = hat.label end

function Look.known(key)
  return labels[key] ~= nil
end

function Look.label(key)
  return labels[key or "none"]
end

function Look.hat(look)
  if type(look) ~= "table" then return nil end
  local key = look.hat
  return key ~= "none" and labels[key] and key or nil
end
