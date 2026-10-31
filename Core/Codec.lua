-- Codec: turns a message into a string an addon channel can carry, and back.
-- A plain-text protocol version comes first (`1|<payload>`), so a message
-- from a newer BFF is recognised before anything is decoded. The payload is
-- LibSerialize, then LibDeflate, then LibDeflate's addon channel encoding.

local _, ns = ...

local LibSerialize = LibStub("LibSerialize")
local LibDeflate = LibStub("LibDeflate")

local Codec = {}
ns.Codec = Codec

Codec.PROTOCOL = 1

function Codec.encode(value)
  local compressed = LibDeflate:CompressDeflate(LibSerialize:Serialize(value))
  return Codec.PROTOCOL .. "|" .. LibDeflate:EncodeForWoWAddonChannel(compressed)
end

-- Returns the value, or nil and "newer" (sent by a newer BFF) or "invalid".
function Codec.decode(message)
  local protocol, payload = message:match("^(%d+)|(.*)$")
  protocol = tonumber(protocol)
  if not protocol then return nil, "invalid" end
  if protocol > Codec.PROTOCOL then return nil, "newer" end
  if protocol < Codec.PROTOCOL then return nil, "invalid" end

  local compressed = LibDeflate:DecodeForWoWAddonChannel(payload)
  local serialized = compressed and LibDeflate:DecompressDeflate(compressed)
  if not serialized then return nil, "invalid" end
  local ok, value = LibSerialize:Deserialize(serialized)
  if not ok then return nil, "invalid" end
  return value
end
