-- Hash Array Mapped Tries (Bagwell Tries)
-- basically a port from https://github.com/mattbierner/hamt.git
local M = {}

local function constant(x) return x end

-- Configuration
--------------------------------------------------------------------------------
local SIZE = 5
local BUCKET_SIZE = math.pow(2, 5)
local mask = BUCKET_SIZE - 1;
local MAX_INDEX_NODE = BUCKET_SIZE / 2;
local MIN_ARRAY_NODE = BUCKET_SIZE / 4;

-- Nothing
--------------------------------------------------------------------------------
local nothing = {}
local function isNothing(x) return x == nothing end

-- Hamming Weight / Population Count
local band = bit.band
local arshift = bit.arshift
local rshift = bit.rshift
local lshift = bit.lshift
do 
  local m1 = 0x55555555
  local m2 = 0x33333333
  local m4 = 0x0f0f0f0f
  function M.popcount(x)
    x = x - band(arshift(x, 1), m1)
    x = band(x, m2) + (band(arshift(x, 2), m2))
    x = band((x + arshift(x, 4)), m4)
    x = x + arshift(x, 8)
    x = x + arshift(x, 16)
    return band(x, 0x7f)
  end
end
local popcount = M.popcount

local function hashFragment(shift, h)
  return band(rshift(h), mask)
end

local function toBitmap(n)
  return lshift(1, n)
end

local function fromBitmap(bitmap, bit)
  return popcount(band(bitmap, bit - 1))
end

function M.arrayUpdate(index, new_value, array)
  index = index + 1

  local out = {}
  local i = 1
  while true do
    local item = array[i]
    if item == nil then break end
    out[i] = item
    i = i + 1
  end
  out[index] = new_value;
  return out
end
local arrayUpdate = M.arrayUpdate

function M.arraySpliceOut(index, array)
  index = index + 1

  local out = {}
  local i = 1
  local j = 1
  while true do
    local item = array[i]
    if item == nil then break end
    if i ~= index then
      out[j] = item
      j = j + 1 
    end
    i = i + 1
  end
  return out
end
local arraySpliceOut = M.arraySpliceOut

function M.arraySpliceIn(index, new_value, array)
  index = index + 1

  local out = {}
  local i = 1
  while true do
    local item = array[i]
    if item == nil then break end
    if i == index then
      out[i] = new_value
      i = i + 1 
    end

    out[i] = item
    i = i + 1 
  end
  return out
end
local arraySpliceIn = M.arraySpliceIn

return M
