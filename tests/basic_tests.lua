require('tests.util')
local hamt = require('hamt')

-- popcount test
print('popcount')
print('--------------------------------------------------------------------------------')
local popcount = hamt.popcount
local nums = {
  0,1,1,2,1,2,2,3,1,2,2,3,2,3,3,4,1,2,2,3,2,3,3,4,2,3,3,4,3,4,4,5,
  1,2,2,3,2,3,3,4,2,3,3,4,3,4,4,5,2,3,3,4,3,4,4,5,3,4,4,5,4,5,5,6,
  1,2,2,3,2,3,3,4,2,3,3,4,3,4,4,5,2,3,3,4,3,4,4,5,3,4,4,5,4,5,5,6,
  2,3,3,4,3,4,4,5,3,4,4,5,4,5,5,6,3,4,4,5,4,5,5,6,4,5,5,6,5,6,6,7,
  1,2,2,3,2,3,3,4,2,3,3,4,3,4,4,5,2,3,3,4,3,4,4,5,3,4,4,5,4,5,5,6,
  2,3,3,4,3,4,4,5,3,4,4,5,4,5,5,6,3,4,4,5,4,5,5,6,4,5,5,6,5,6,6,7,
  2,3,3,4,3,4,4,5,3,4,4,5,4,5,5,6,3,4,4,5,4,5,5,6,4,5,5,6,5,6,6,7,
  3,4,4,5,4,5,5,6,4,5,5,6,5,6,6,7,4,5,5,6,5,6,6,7,5,6,6,7,6,7,7,8,
};
for i = 1, #nums do
  assert(nums[i] == popcount(i - 1))
end
assert(popcount(0xFFFFFFFF) == 32)
assert(popcount(0xFFFFFFFF + 1) == 0)
assert(popcount(0xFFFFFFFF + 2) == 1)

local arr = {'angel', 'clown', 'mandarin', 'surgeon'}

print('peristent array update')
print('--------------------------------------------------------------------------------')
local arr1 = hamt.arrayUpdate_ArrayNode(1, 'psycho', arr)
print(table.show(arr1))
print(table.show(arr))

print('peristent array remove')
print('--------------------------------------------------------------------------------')
local arr1 = hamt.arraySpliceOut(1, arr)
print(table.show(arr1))
print(table.show(arr))

local arr1 = hamt.arraySpliceOut(3, arr)
print(table.show(arr1))
print(table.show(arr))

local arr1 = hamt.arraySpliceOut(0, arr)
print(table.show(arr1))
print(table.show(arr))

print('peristent array add')
print('--------------------------------------------------------------------------------')

local arr1 = hamt.arraySpliceIn(2, 'peanuts', arr)
print(table.show(arr1))
print(table.show(arr))

print(string.format('%x', hamt.hash('asdf')))
local text = {}
for i = 1, 100000 do table.insert(text, 'a') end
text = table.concat(text)
--print(string.format('%x', hamt.hash(text)))

local function benchmark(fn)
  collectgarbage()
  local x = os.clock()
  for i = 1, 2000000 do
    --fn()
  end
  print(string.format("elapsed time: %.3f\n", os.clock() - x))
end

-- ranked in order of speed, 3rd approach seems to confuse JIT
local function copyarray1(array)
  local out = {}
  for i = 1, #array do
    out[i] = array[i]
  end
  return out
end

local function copyarray2(array)
  local out = {}
  local i = 1
  while true do
    local item = array[i]
    if item == nil then break end
    out[i] = item
    i = i + 1
  end
  return out
end

local function copyarray3(array)
  local out = {}
  local i = 1
  local item
  repeat
    item = array[i]
    out[i] = item
    i = i + 1
  until item == nil
  return out
end


local src = {
  0,1,1,2,1,2,2,3,1,2,2,3,2,3,3,4,1,2,2,3,2,3,3,4,2,3,3,4,3,4,4,5,
  --1,2,2,3,2,3,3,4,2,3,3,4,3,4,4,5,2,3,3,4,3,4,4,5,3,4,4,5,4,5,5,6,
  --1,2,2,3,2,3,3,4,2,3,3,4,3,4,4,5,2,3,3,4,3,4,4,5,3,4,4,5,4,5,5,6,
  --2,3,3,4,3,4,4,5,3,4,4,5,4,5,5,6,3,4,4,5,4,5,5,6,4,5,5,6,5,6,6,7,
  --1,2,2,3,2,3,3,4,2,3,3,4,3,4,4,5,2,3,3,4,3,4,4,5,3,4,4,5,4,5,5,6,
  --2,3,3,4,3,4,4,5,3,4,4,5,4,5,5,6,3,4,4,5,4,5,5,6,4,5,5,6,5,6,6,7,
  --2,3,3,4,3,4,4,5,3,4,4,5,4,5,5,6,3,4,4,5,4,5,5,6,4,5,5,6,5,6,6,7,
  --3,4,4,5,4,5,5,6,4,5,5,6,5,6,6,7,4,5,5,6,5,6,6,7,5,6,6,7,6,7,7,8,
};

local dst

local function fn1()
  dst = copyarray1(src)
end
benchmark(fn1)

local function fn2()
  dst = copyarray2(src)
end
benchmark(fn2)

local function fn3()
  dst = copyarray3(src)
end
benchmark(fn3)
