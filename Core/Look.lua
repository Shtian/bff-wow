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

Look.PETS = {
  { key = "none", label = "None" },
  { key = "cat", label = "Cat" },
  { key = "dog", label = "Dog" },
  { key = "owl", label = "Owl" },
  { key = "frog", label = "Frog" },
  { key = "rabbit", label = "Rabbit" },
  { key = "fox", label = "Fox" },
}

local function labelsOf(list)
  local labels = {}
  for _, item in ipairs(list) do labels[item.key] = item.label end
  return labels
end

local hatLabels, petLabels = labelsOf(Look.HATS), labelsOf(Look.PETS)

local function chosen(labels, look, field)
  if type(look) ~= "table" then return nil end
  local key = look[field]
  return key ~= "none" and labels[key] and key or nil
end

function Look.knownHat(key)
  return hatLabels[key] ~= nil
end

function Look.hatLabel(key)
  return hatLabels[key or "none"]
end

function Look.hat(look)
  return chosen(hatLabels, look, "hat")
end

function Look.knownPet(key)
  return petLabels[key] ~= nil
end

function Look.petLabel(key)
  return petLabels[key or "none"]
end

function Look.pet(look)
  return chosen(petLabels, look, "pet")
end
