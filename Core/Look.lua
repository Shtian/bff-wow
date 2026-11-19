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

local worn = {}
for _, hat in ipairs(Look.HATS) do
  if hat.key ~= "none" then worn[hat.key] = true end
end

function Look.known(key)
  return key == "none" or worn[key] == true
end

function Look.hat(look)
  if type(look) ~= "table" then return nil end
  local key = look.hat
  return worn[key] and key or nil
end
