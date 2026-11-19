local _, ns = ...

local LibSerialize = LibStub("LibSerialize")
local LibDeflate = LibStub("LibDeflate")

local Codec = {}
ns.Codec = Codec

Codec.PROTOCOL = 2
Codec.OLDEST = 1

function Codec.encode(value)
  local compressed = LibDeflate:CompressDeflate(LibSerialize:Serialize(value))
  return Codec.PROTOCOL .. "|" .. LibDeflate:EncodeForWoWAddonChannel(compressed)
end

function Codec.decode(message)
  local protocol, payload = message:match("^(%d+)|(.*)$")
  protocol = tonumber(protocol)
  if not protocol then return nil, "invalid" end
  if protocol > Codec.PROTOCOL then return nil, "newer" end
  if protocol < Codec.OLDEST then return nil, "invalid" end

  local compressed = LibDeflate:DecodeForWoWAddonChannel(payload)
  local serialized = compressed and LibDeflate:DecompressDeflate(compressed)
  if not serialized then return nil, "invalid" end
  local ok, value = LibSerialize:Deserialize(serialized)
  if not ok then return nil, "invalid" end
  return value
end
