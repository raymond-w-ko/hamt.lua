-- Hash Array Mapped Tries (Bagwell Tries)
--
-- basically a port from https://github.com/mattbierner/hamt.git
-- lots of thanks to him providing the Javascript / Kepri implementation
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
if rawget(_G, 'jit') and type(jit) == 'table' then
  band = bit.band
  arshift = bit.arshift
  rshift = bit.rshift
  lshift = bit.lshift
  tobit = bit.tobit
  bor = bit.bor
  bnot = bit.bnot
  bxor = bit.bxor
else
  -- if you are running plain Lua, get Mike Pall's BitOp, which is used in LuaJIT
  -- DO NOT use Lua 5.2 bit32 as that has different semantics and is untested.

  if _G.__STRICT then
    global('bit')
  end
  local bit = require('bit')
  band = bit.band
  arshift = bit.arshift
  rshift = bit.rshift
  lshift = bit.lshift
  tobit = bit.tobit
  bor = bit.bor
  bnot = bit.bnot
  bxor = bit.bxor

  -- in Lua 5.2, bit32.bnot(0) would == 0xFFFFFFFF, which is not the same
  assert(bnot(0) == -1)
end

local function slow_len(t)
  local count = 0
  for k, v in pairs(t) do
    count = count + 1
  end
  return count
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
  return band(rshift(h, shift), MASK)
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

-- from my tests in correctness_tests.lua, THIS CLASS OF FUNCTIONS IS THE BOTTLENECK
function M.arrayUpdate(index, new_value, array, max_bounds)
  -- do not use this, instead use the specialized versions
  assert(false)
  -- pre allocate an array part with 32 slots. this seems to speed things up
  -- since the following copy phase doesn't need to trigger a re-hash
  -- TODO: this might use way too much memory
  --local copy = {
    --nil, nil, nil, nil, nil, nil, nil, nil,
    --nil, nil, nil, nil, nil, nil, nil, nil,
    --nil, nil, nil, nil, nil, nil, nil, nil,
    --nil, nil, nil, nil, nil, nil, nil, nil,
  --}
  -- In an ideal world, we would like to use this below. However, since we are
  -- copying afterwards, we trigger unnecessary resizings of the array part, which
  -- With an exhaustive bounds in the correctness_tests.lua, above does use like 80MB more memory.
  local copy = {}

  -- how unfortunate it can't be the below since the '#" operator doesn't
  -- always work properly on an array with holes like in Javascript
  --for i = 1, #array do
  --for i = 1, max_bounds do
  for i = 1, max_bounds do
    copy[i] = array[i]
  end
  copy[index + 1] = new_value

  --local len1 = slow_len(copy)
  --local len2 = slow_len(array)
  --assert(
    --(len1 == len2
     --or (new_value ~= nil and (len1 == (len2 + 1)))
     --or (new_value == nil and (len1 == (len2 - 1)))
    --))
  return copy
end
local arrayUpdate = M.arrayUpdate

-- THIS IS THE BOTTLENECK, probably due to Lua's and convesely LuaJIT's poor GC
local function arrayUpdate_ArrayNode(index, new_value, array)
  -- this is the intent
  local copy = {
    -- make sure this is equal to BUCKET_SIZE
    nil, nil, nil, nil, nil, nil, nil, nil,
    nil, nil, nil, nil, nil, nil, nil, nil,
    nil, nil, nil, nil, nil, nil, nil, nil,
    nil, nil, nil, nil, nil, nil, nil, nil,
  }
  for i = 1, BUCKET_SIZE do
    copy[i] = array[i]
  end

  -- unrolled version actually hurts performance
  --local copy = {
    ---- make sure this is equal to BUCKET_SIZE
    --array[ 1], array[ 2], array[ 3], array[ 4], array[ 5], array[ 6], array[ 7], array [8],
    --array[ 9], array[10], array[11], array[12], array[13], array[14], array[15], array[16],
    --array[17], array[18], array[19], array[20], array[21], array[22], array[23], array[24],
    --array[25], array[26], array[27], array[28], array[29], array[30], array[31], array[32],
  --}

  copy[index + 1] = new_value

  return copy
end
M.arrayUpdate_ArrayNode = arrayUpdate_ArrayNode

local function arrayUpdate_IndexedNode(index, new_value, array)
  -- according to the profile, this does not matter that much?
  --local copy = {
    -- make sure this is equal to MAX_INDEX_NODE
    --nil, nil, nil, nil,
    --nil, nil, nil, nil,
    --nil, nil, nil, nil,
    --nil, nil, nil, nil,
  --}
  local copy = {}
  for i = 1, MAX_INDEX_NODE do
    copy[i] = array[i]
  end
  copy[index + 1] = new_value
  return copy
end

local function arrayUpdate_Collision(index, new_value, array)
  local copy = {}
  for i = 1, #array do
    copy[i] = array[i]
  end
  copy[index + 1] = new_value
  return copy
end

function M.arraySpliceOut(index, array)
  -- these assumptions always seem to hold so bounds fixing like the JavaScript
  -- version does not appear to be necessary
  --assert(index >= 0)
  --assert(index <= slow_len(array))

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
  --assert(slow_len(copy) == (slow_len(array) - 1))
  return copy
end
local arraySpliceOut = M.arraySpliceOut

function M.arraySpliceIn(index, new_value, array)
  -- these assumptions always seem to hold so bounds fixing like the JavaScript
  -- version does not appear to be necessary
  --assert(index >= 0)
  --assert(index <= slow_len(array))

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
  if i == index then
    copy[j] = new_value
    --j = j + 1 
  end

  --assert(slow_len(copy) == (slow_len(array) + 1))
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

-- empty node
M.empty = nil

-- nothing value
local nothing = {}

--------------------------------------------------------------------------------

-- 
-- Leaf holding a value.
-- 
-- @member hash Hash of key.
-- @member key Key.
-- @member value Value stored.
-- 
local Leaf = {}
local LeafMetatable = {__index = Leaf}

function Leaf.new(hash, key, value)
  return setmetatable({hash = hash, key = key, value = value} , LeafMetatable)
end

--------------------------------------------------------------------------------

-- 
-- Leaf holding multiple values with the same hash but different keys.
-- 
-- @member hash Hash of key.
-- @member children Array of collision children node.
-- 
local Collision = {}
local CollisionMetatable = {__index = Collision}

function Collision.new(hash, children)
  --for k, v in pairs(children) do
    --assert(v.hash == hash)
  --end
  return setmetatable({hash = hash, children = children}, CollisionMetatable)
end

--------------------------------------------------------------------------------

-- 
-- Internal node with a sparse set of children.
-- 
-- Uses a bitmap and array to pack children.
-- 
-- @member mask Bitmap that encode the positions of children in the array.
-- @member children Array of child nodes.
-- 
local IndexedNode = {}
local IndexedNodeMetatable = {__index = IndexedNode}

function IndexedNode.new(mask, children)
  return setmetatable({mask = mask, children = children}, IndexedNodeMetatable)
end

--------------------------------------------------------------------------------

-- 
-- Internal node with many children.
-- 
-- @member count Number of children.
-- @member children Array of child nodes.
-- 
local ArrayNode = {}
local ArrayNodeMetatable = {__index = ArrayNode}

function ArrayNode.new(count, children)
  return setmetatable({count = count, children = children}, ArrayNodeMetatable)
end

--------------------------------------------------------------------------------

-- 
-- Is `node` a leaf node?
-- 
local function isLeaf(node)
  --if node == M.empty then
  if node == nil then
    return true
  end

  local mt = getmetatable(node)
  if mt == LeafMetatable or mt == CollisionMetatable then
    return true
  end

  return false
end

-- 
-- Expand an indexed node into an array node.
-- 
-- @param frag Index of added child.
-- @param child Added child.
-- @param bitmap Decoding bitmap of where children are located in sparse array subNodes
-- @param subNodes Index node children before child added.
-- 
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
  --assert(slow_len(arr) == slow_len(subNodes) + 1)
  return ArrayNode.new(count + 1, arr)
end

-- 
-- Collapse an array node into a indexed node.
-- 
-- Given an array and an index create an IndexedNode with all the elements in
-- that array except that index. Also constructs a bitmap for the IndexedNode
-- to mark which slots are filled in the "virtual array".
--
-- so given something like { 1, 2, nil, nil, nil, nil, nil, 8 }
-- IndexedNode would actually contain
-- {1, 2, 8} and a decoding bitmap of 0b10000011 to save space
local function pack(removed_index, elements)
  local children = {}
  local next_slot = 1
  local bitmap = 0
  
  local i = 0
  while i < BUCKET_SIZE do
    local elem = elements[i + 1] -- NOTICE: 0 index to 1 index
    if i ~= removed_index and elem ~= nil then
      -- table.insert(children, elem)
      children[next_slot] = elem
      next_slot = next_slot + 1

      bitmap = bor(bitmap, lshift(1, i))
    end

    i = i + 1
  end

  --if (slow_len(elements) - 1 ~= (slow_len(children))) then
    --print('removed_index: '..tostring(removed_index))
    --print(table.show(elements, 'elements'))
    --print(table.show(children, 'children'))
    --assert(false)
  --end

  return IndexedNode.new(bitmap, children)
end

-- 
-- Merge two leaf nodes.
-- 
-- @param shift Current shift.
-- @param node1 Node.
-- @param node2 Node.
-- 
local function mergeLeaves(shift, node1, node2)
  local hash1 = node1.hash
  local hash2 = node2.hash

  if hash1 == hash2 then
    return Collision.new(hash1, {node2, node1})
  else
    -- inline hashFragment(shift, hash1)
    local subhash1 = band(rshift(hash1, shift), MASK)
    -- inline hashFragment(shift, hash2)
    local subhash2 = band(rshift(hash2, shift), MASK)
    -- toBitmap(subhash1) | toBitmap(subhash2)
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

-- 
-- Update an entry in a collision list.
-- 
-- @param hash Hash of collision list.
-- @param list Collision list.
-- @param update_fn Update function.
-- @param key Key to update.
-- 
local function updateCollisionList(hash, list, update_fn, key)
  -- this should most definitely hold
  --assert(M.hash(key) == hash)
  local target
  local i = 0

  local len = #list
  -- a Collision is just an array of Leaf, so the below should hold
  --assert(slow_len(list) == len)
  while i < len do
    local child = list[i + 1] -- NOTICE: 0 index to 1 index
    if child.key == key then
      target = child
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
    return arrayUpdate_Collision(i, Leaf.new(hash, key, value), list)
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
  -- hashFragment(shift, hash)
  local frag = band(rshift(hash, shift), MASK)
  local bit = lshift(1, frag)
  local mask = self.mask
  if band(mask, bit) ~= 0 then
    local index = popcount(band(mask, bit - 1))
    local node = self.children[index + 1] -- NOTICE: 0 index to 1 index
    return lookup(node, shift + SIZE, hash, key)
  else
    return nothing
  end
end

function ArrayNode:lookup(shift, hash, key)
  -- hashFragment(shift, hash)
  local frag = band(rshift(hash, shift), MASK)
  local child = self.children[frag + 1] -- NOTICE: 0 index to 1 index
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

function Collision:modify(shift, fn, key_hash, key)
  local node_hash = self.hash
  if (key_hash == node_hash) then
    local list = updateCollisionList(node_hash, self.children, fn, key)
    if #list > 1 then
      return Collision.new(node_hash, list)
    else
      -- there is no longer a collision, so return the single internal Leaf
      return list[1] -- NOTICE: 0 index to 1 index
    end
  else
    local value = fn()
    if value == nothing then
      return self
    else
      return mergeLeaves(shift, self, Leaf.new(key_hash, key, value))
    end
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
    node = children[index + 1] -- NOTICE: 0 index to 1 index
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
    local node = children[bxor(index, 1) + 1] -- NOTICE: 0 index to 1 index
    -- IndexedNode are a sparse arrays with a bitmap used to decode true
    -- position. The children are stored in a dense array and inserted
    -- sequentially so the below should always be true.
    --assert(slow_len(children) == #children)
    if #children <= 2 and isLeaf(node) then
      return node
    else
      return IndexedNode.new(bitmap, arraySpliceOut(index, children))
    end
  elseif added then
    -- see note above, the below should always be true
    --assert(slow_len(children) == #children)
    if #children >= MAX_INDEX_NODE then
      return expand(frag, child, mask, children)
    else
      return IndexedNode.new(bitmap, arraySpliceIn(index, child, children))
    end
  else
    return IndexedNode.new(bitmap, arrayUpdate_IndexedNode(index, child, children))
  end
end

function ArrayNode:modify(shift, fn, hash, key)
  local count = self.count
  local children = self.children
  local frag = band(rshift(hash, shift), MASK)
  local child = children[frag + 1] -- NOTICE: 0 index to 1 index
  local newChild = alter(child, shift + SIZE, fn, hash, key)
  if child == nil and newChild ~= nil then
    return ArrayNode.new(count + 1, arrayUpdate_ArrayNode(frag, newChild, children))
  elseif child ~= nil and newChild == nil then
    if (count - 1) <= MIN_ARRAY_NODE then
      return pack(frag, children)
    else
      return ArrayNode.new(count - 1, arrayUpdate_ArrayNode(frag, nil, children))
    end
  else
    return ArrayNode.new(count, arrayUpdate_ArrayNode(frag, newChild, children))
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

--------------------------------------------------------------------------------
-- Queries
--------------------------------------------------------------------------------

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
local tryGetHash = M.tryGetHash

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

--------------------------------------------------------------------------------
-- Single Updates
--------------------------------------------------------------------------------

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

--------------------------------------------------------------------------------
-- Fold
--------------------------------------------------------------------------------

function Leaf:fold(fn, starting_value)
  return fn(starting_value, self)
end

-- adapted from the code in Polyfill section
-- https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Array/Reduce
local function reduce(array, fn, starting_value)
  local value = starting_value
  
  for i = 1, #array do
    local item = array[i]
    if item ~= nil then
      value = fn(value, item)
    end
  end
  return value
end
function Collision:fold(fn, starting_value)
  return reduce(self.children, fn, starting_value)
end

function IndexedNode:fold(fn, starting_value)
  local children = self.children
  local folded_value = starting_value
  -- The below assumption does hold since children is a normal dense array with no holes
  --assert(slow_len(children) == #children)
  -- Thus the below is not necessary
  --for i = 1, MAX_INDEX_NODE do
  for i = 1, #children do
    local child = children[i] -- NOTICE: normally 0 index to 1 index, but just iterating over
    if child then
      if getmetatable(child) == LeafMetatable then
        folded_value = fn(folded_value, child)
      else
        folded_value = child:fold(fn, folded_value)
      end
    end
  end
  return folded_value
end

function ArrayNode:fold(fn, starting_value)
  local children = self.children
  local folded_value = starting_value

  -- this assumption below does not hold sometimes!!!
  --assert(slow_len(children) == #children)
  -- thus this can't be used!!!
  --for i = 1, #children do
  for i = 1, BUCKET_SIZE do
    local child = children[i] -- NOTICE: normally 0 index to 1 index, but just iterating over
    if child then
      if getmetatable(child) == LeafMetatable then
        folded_value = fn(folded_value, child)
      else
        folded_value = child:fold(fn, folded_value)
      end
    end
  end
  return folded_value
end

function M.fold(fn, starting_value, hamt)
  if hamt == nil then
    return starting_value
  else
    return hamt:fold(fn, starting_value)
  end
end
local fold = M.fold

--------------------------------------------------------------------------------
-- Aggregate
--------------------------------------------------------------------------------
local function increment_fn(x)
  return 1 + x
end
function M.count(hamt)
  return fold(increment_fn, 0, hamt)
end

local table_insert = table.insert

local function build_key_value_fn(collection_array, item)
  table_insert(collection_array, {item.key, item.value})
  return collection_array
end
function M.pairs(hamt)
  return fold(build_key_value_fn, {}, hamt)
end

local function build_key_fn(collection_array, item)
  table_insert(collection_array, item.key)
  return collection_array
end 
function M.keys(hamt)
  return fold(build_key_fn, {}, hamt)
end

local function build_value_fn(collection_array, item)
  table_insert(collection_array, item.value)
  return collection_array
end 
function M.values(hamt)
  return fold(build_value_fn, {}, hamt)
end

return M
