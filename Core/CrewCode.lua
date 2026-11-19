local _, ns = ...

local CrewCode = {}
ns.CrewCode = CrewCode

local ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
local BODY_LENGTH = 7
local HASH_LENGTH = 7

local function value(char)
  local index = ALPHABET:find(char, 1, true)
  return index and index - 1
end

local function char(n)
  return ALPHABET:sub(n + 1, n + 1)
end

local function checkChar(body)
  local sum = 0
  for i = 1, BODY_LENGTH do
    sum = sum + value(body:sub(i, i)) * (2 * i - 1)
  end
  return char(sum % 32)
end

local function format(plain)
  return plain:sub(1, 4) .. "-" .. plain:sub(5)
end

function CrewCode.generate(random)
  local chars = {}
  for i = 1, BODY_LENGTH do
    chars[i] = char(math.floor(random() * 32) % 32)
  end
  local body = table.concat(chars)
  return format(body .. checkChar(body))
end

function CrewCode.normalise(input)
  if type(input) ~= "string" then return nil end
  local plain = input:upper():gsub("[%s%-]", ""):gsub("O", "0"):gsub("[IL]", "1")
  if #plain ~= BODY_LENGTH + 1 then return nil end
  for i = 1, #plain do
    if not value(plain:sub(i, i)) then return nil end
  end
  local body = plain:sub(1, BODY_LENGTH)
  if checkChar(body) ~= plain:sub(-1) then return nil end
  return format(plain)
end

-- WoW: Lua 5.1 numbers are doubles, exact only up to 2^53.
local function fnv1a(text)
  local hash = 2166136261
  for i = 1, #text do
    hash = bit.bxor(hash, text:byte(i)) % 2 ^ 32
    hash = (hash * 403 + (hash % 256) * 2 ^ 24) % 2 ^ 32
  end
  return hash
end

local function base32(n)
  local chars = {}
  for i = HASH_LENGTH, 1, -1 do
    chars[i] = char(n % 32)
    n = math.floor(n / 32)
  end
  return table.concat(chars)
end

function CrewCode.channel(code)
  return "BFF" .. base32(fnv1a("name:" .. code)), base32(fnv1a("pass:" .. code))
end
