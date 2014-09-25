-- Hash Array Mapped Tries (Bagwell Tries)
-- basically a port from https://github.com/mattbierner/hamt.git
local M = {}

local band
local arshift
local rshift
local lshift
local tobit
local bor
local bnot
local bxor
-- LuaJIT has builtin bit manipulation primitives that get JITed, so use these
if type(jit) == 'table' then
  band = bit.band
  arshift = bit.arshift
  rshift = bit.rshift
  lshift = bit.lshift
  tobit = bit.tobit
  bor = bit.bor
  bnot = bit.bnot
  bxor = bit.bxor
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
--
--local function expand(frag, child, bitmap, subNodes)
local function expand(frag, child, bit, subNodes)
  local arr = {}
  local count = 0

  local i = 0
  while bit ~= 0 do
    if band(bit, 1) == 1 then
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

local lookup

function Leaf:lookup(_1, _2, key)
  if self.key == key then
    return self.value
  else
    return nothing
  end
end

function Collision:lookup(_, hash, key)
  if hash == self.hash then
    local children = self.children
    local i = 0
    local len = #children
    while i < len do
      local child = children[i + 1] -- NOTICE: 0 index to 1 index
      if child.key == key then
        return child.value
      end

      i = i + 1
    end
  end
  return nothing
end

function IndexedNode:lookup(shift, hash, key)
  local frag = band(rshift(hash, shift), MASK)
  local bit = lshift(1, frag)
  local mask = self.mask
  if band(mask, bit) ~= 0 then
    local index = popcount(band(mask, bit - 1))
    local node = self.children[index]
    return lookup(node, shift + SIZE, hash, key)
  else
    return nothing
  end
end

function ArrayNode:lookup(shift, hash, key)
  local frag = band(rshift(hash, shift), MASK)
  local child = self.children[frag]
  return lookup(child, shift + SIZE, hash, key)
end

lookup = function(node, shift, hash, key)
  if node == nil then
    return nothing
  else
    return node:lookup(shift, hash, key)
  end
end

local alter

function Leaf:modify(shift, fn, hash, key)
  if self.key == key then
    local value = fn(self.value)
    if value == nothing then
      return nil
    else
      return Leaf.new(hash, key, value)
    end
  else
    local value = fn()
    if value == nothing then
      return self
    else
      return mergeLeaves(shift, self, Leaf.new(hash, key, value))
    end
  end
end

function Collision:modify(shift, fn, hash, key)
  local list = updateCollisionList(self.hash, self.children, fn, key)
  if #list > 1 then
    return Collision.new(self.hash, list)
  else
    return list[1] -- NOTICE: 0 index to 1 index
  end
end

function IndexedNode:modify(shift, fn, hash, key)
  local mask = self.mask
  local children = self.children
  local frag = band(rshift(hash, shift), MASK)
  local bit = lshift(1, frag)
  local index = popcount(band(mask, bit - 1))
  local exists = band(mask, bit) ~= 0

  local node
  if exists then
    node = children[index]
  else
    node = nil
  end
  local child = alter(node, shift + SIZE, fn, hash, key)

  local removed = exists and (child == nil)
  local added = (not exists) and (child ~= nil)

  local bitmap
  if removed then
    bitmap = band(mask, bnot(bit))
  elseif added then
    bitmap = bor(mask, bit)
  else
    bitmap = mask
  end

  if bitmap == 0 then
    return nil
  elseif removed then
    local node = children[bxor(index, 1)]
    if #children <= 2 and isLeaf(node) then
      return node
    else
      return IndexedNode.new(bitmap, arraySpliceOut(index, children))
    end
  elseif added then
    if #children >= MAX_INDEX_NODE then
      return expand(frag, child, mask, children)
    else
      return IndexedNode.new(bitmap, arraySpliceIn(index, child, children))
    end
  else
    return IndexedNode.new(bitmap, arrayUpdate(index, child, children))
  end
end

function ArrayNode:modify(shift, fn, hash, key)
  local count = self.count
  local children = self.children
  local frag = band(rshift(hash, shift), MASK)
  local child = children[frag]
  local newChild = alter(child, shift + SIZE, fn, hash, key)
  if child == nil and newChild ~= nil then
    return ArrayNode.new(count + 1, arrayUpdate(frag, newChild, children))
  elseif child ~= nil and newChild == nil then
    if (count - 1) <= MIN_ARRAY_NODE then
      return pack(frag, children)
    else
      return ArrayNode.new(count - 1, arrayUpdate(frag, nil, children))
    end
  else
    return ArrayNode.new(count, arrayUpdate(frag, newChild, children))
  end
end

alter = function(node, shift, fn, hash, key)
  if node == nil then
    local value = fn()
    if value == nothing then
      return nil
    else
      return Leaf.new(hash, key, value)
    end
  else
    return node:modify(shift, fn, hash, key)
  end
end

-- Looup a value.
--
-- Returns the value stored for the given hash and key, or alt_fallback_value if none.
function M.tryGetHash(alt_fallback_value, hash, key, hamt)
  local value
  if hamt == nil then
    value = nothing
  else
    value = hamt:lookup(0, hash, key)
  end
  if value == nothing then
    return alt_fallback_value
  else
    return value
  end
end
local tryGetHash

-- Lookup a value using the internal hash.
function M.tryGet(alt_fallback_value, key, hamt)
  return tryGetHash(alt_fallback_value, hash(key), key, hamt)
end
local tryGet = M.tryGet

function M.getHash(hash, key, hamt)
  return tryGetHash(nil, hash, key, hamt)
end
local getHash = M.getHash

function M.get(key, hamt)
  return tryGet(nil, key, hamt)
end

function M.hasHash(hash, key, hamt)
  local value
  if hamt == nil then
    value = nothing
  else
    hamt:lookup(0, hash, key)
  end
  return value ~= nothing
end
local hasHash = M.hasHash

function M.has(key, hamt)
  return hasHash(hash(key), key, hamt)
end

function M.modifyHash(hash, key, fn, hamt)
  if hamt == nil then
    local value = fn()
    if value == nothing then
      return nil
    else
      return Leaf.new(hash, key, value)
    end
  else
    return hamt:modify(0, fn, hash, key)
  end
end
local modifyHash = M.modifyHash

function M.modify(key, fn, hamt)
  return modifyHash(hash(key), key, fn, hamt)
end

function M.setHash(hash, key, value, hamt)
  local function fn()
    return value
  end
  return modifyHash(hash, key, fn, hamt)
end
local setHash = M.setHash

function M.set(key, value, hamt)
  return setHash(hash(key), key, value, hamt)
end

local function del_fn()
  return nothing
end
function M.removeHash(hash, key, hamt)
  return modifyHash(hash, key, del_fn, hamt)
end
local removeHash = M.removeHash

function M.remove(key, hamt)
  return removeHash(hash(key), key, hamt)
end

return M
