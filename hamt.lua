-- Hash Array Mapped Tries (Bagwell Tries)
-- basically a port from https://github.com/mattbierner/hamt.git
local M = {}

local band
local arshift
local rshift
local lshift
local tobit
local bor
-- LuaJIT has builtin bit manipulation primitives that get JITed, so use these
if type(jit) == 'table' then
  band = bit.band
  arshift = bit.arshift
  rshift = bit.rshift
  lshift = bit.lshift
  tobit = bit.tobit
  bor = bit.bor
else
  -- TODO: if not running in LuaJIT, other bit manipulation functions are
  -- necessary
  assert(false)
end

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------
local SIZE = 5
local BUCKET_SIZE = math.pow(2, SIZE)
local MASK = BUCKET_SIZE - 1;
local MAX_INDEX_NODE = BUCKET_SIZE / 2;
local MIN_ARRAY_NODE = BUCKET_SIZE / 4;

--------------------------------------------------------------------------------
-- Hamming Weight / Population Count
--------------------------------------------------------------------------------
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
local popcount = M.popcount

local function hashFragment(shift, h)
  return band(rshift(h), MASK)
end

local function toBitmap(n)
  return lshift(1, n)
end

local function fromBitmap(bitmap, bit)
  return popcount(band(bitmap, bit - 1))
end

--------------------------------------------------------------------------------
-- Array Ops
--
-- These functions' arguments are 0 index based, meaning 0 is the first element
-- of the array, but still produce Lua array that are 1 based
--------------------------------------------------------------------------------
function M.arrayUpdate(index, new_value, array)
  local copy = {}
  for i = 1, #array do
    copy[i] = array[i]
  end
  copy[index + 1] = new_value;
  return copy
end
local arrayUpdate = M.arrayUpdate

function M.arraySpliceOut(index, array)
  index = index + 1

  local copy = {}
  local i = 1
  local j = 1
  while true do
    local item = array[i]
    if item == nil then
      break
    end

    if i ~= index then
      copy[j] = item
      j = j + 1 
    end

    i = i + 1
  end
  return copy
end
local arraySpliceOut = M.arraySpliceOut

function M.arraySpliceIn(index, new_value, array)
  index = index + 1

  local copy = {}
  local i = 1
  local j = 1
  while true do
    local item = array[i]
    if item == nil then
      break
    end

    if i == index then
      copy[j] = new_value
      j = j + 1 
    end
    copy[j] = item
    j = j + 1

    i = i + 1 
  end
  return copy
end
local arraySpliceIn = M.arraySpliceIn

--------------------------------------------------------------------------------
-- get 32 bit hash of string
function M.hash(str)
  if type(str) == 'number' then return str end

  local hash = 0
  for i = 1, str:len() do
    hash = tobit((lshift(hash, 5) - hash) + str:byte(i))
  end
  return hash
end
local hash = M.hash
--------------------------------------------------------------------------------

local nothing = {}

local Leaf = {}
local LeafMetatable = {__index = Leaf}

function Leaf.new(hash, key, value)
  return setmetatable({ hash = hash, key = key, value = value } , LeafMetatable)
end

function Leaf:lookup(_dummy1, _dummy2, key)
  if self.key == key then
    return self.value
  else
    return nothing
  end
end

function Leaf:modify(shift, fn, hash, key)
  if self.key == key then
    local v = fn(self.value) 
    if v == nothing then
      return nil
    else
      return Leaf.new(hash, key, v)
    end
  else
    local v = fn()
    if v == nothing then
      return self
    else
      return mergeLeaves(shift, self, Leaf.new(hash, key, v))
    end
  end
end

function Leaf:fold(fn, z)
  return fn(z, self)
end

--------------------------------------------------------------------------------

local Collision = {}
local CollisionMetatable = {__index = Collision}

function Collision.new(hash, children)
  return setmetatable({hash = hash, children = children}, CollisionMetatable)
end

--------------------------------------------------------------------------------

local IndexedNode = {}
local IndexedNodeMetatable = {__index = IndexedNode}

function IndexedNode.new(mask, children)
  return setmetatable({mask = mask, children = children}, IndexedNodeMetatable)
end

--------------------------------------------------------------------------------

local ArrayNode = {}
local ArrayNodeMetatable = {__index = ArrayNode}

function ArrayNode.new(count, children)
  return setmetatable({count = count, children = children}, ArrayNodeMetatable)
end

--------------------------------------------------------------------------------

local function isLeaf(node)
  if node == nil then
    return true
  end

  local mt = getmetatable(node)
  if mt == LeafMetatable or mt == CollisionMetatable then
    return true
  end

  return false
end

-- Does the inverse of the function below, given a "packed" array and a decoding bitmap
-- return a full size array with holes.
local function expand(frag, child, bitmap, subNodes)
  local arr = {}
  local count = 0

  local i = 0
  while bitmap ~= 0 do
    if band(bitmap, 1) == 1 then
      arr[i + 1] = subNodes[count + 1] -- NOTICE: 0 index to 1 index
      count = count + 1
    end
    bit = rshift(bit, 1)

    i = i + 1
  end

  arr[frag + 1] = child -- NOTICE: 0 index to 1 index
  return ArrayNode.new(count + 1, arr)
end

-- Given an array and an index created an IndexedNode with all the elements in
-- that array except that index. Also constructs a bitmap for the IndexedNode
-- to mark which slots are filled in the "virtual array".
--
-- so given something like { 1, 2, nil, nil, nil, nil, nil, 8 }
-- IndexedNode would actually contain
-- {1, 2, 8} and a decoding bitmap of 0b10000011 to save space
local function pack(removed_index, elements)
  local children = {}
  local next_children_index = 1
  local bitmap = 0
  
  local i = 0
  local len = #elements
  while i < len do
    local elem = elements[i + 1] -- NOTICE: 0 index to 1 index
    if i ~= removed_index and elem then
      -- table.insert(children, elem)
      children[next_children_index] = elem
      next_children_index = next_children_index + 1

      bitmap = bor(bitmap, lshift(1, i))
    end

    i = i + 1
  end

  return IndexedNode.new(bitmap, children)
end

local function mergeLeaves(shift, node1, node2)
  local hash1 = node1.hash
  local hash2 = node2.hash

  if hash1 == hash2 then
    return Collision.new(hash1, {node2, node1})
  else
    -- hash fragment
    local subhash1 = band(rshift(hash1, shift), MASK)
    -- hash fragment
    local subhash2 = band(rshift(hash2, shift), MASK)
    -- toBitmap | toBitmap
    local bitmap = bor(lshift(1, subhash1), lshift(1, subhash2))

    local children
    if subhash1 == subhash2 then
      children = {mergeLeaves(shift + SIZE, node1, node2)}
    else
      if subhash1 < subhash2 then
        children = {node1, node2}
      else
        children = {node2, node1}
      end
    end

    return IndexedNode.new(bitmap, children)
  end
end

local function updateCollisionList(hash, list, update_fn, key)
  local target
  local i = 0

  local len = #list
  while i < len do
    local child = list[i + 1] -- NOTICE: 0 index to 1 index
    if child.key == key then
      target = key
      break
    end

    i = i + 1
  end

  local value
  if target then
    value = update_fn(target.value)
  else
    value = update_fn()
  end

  if value == nothing then
    return arraySpliceOut(i, list)
  else
    return arrayUpdate(i, Leaf.new(hash, key, value), list)
  end
end

return M
