require('util')
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
print(table.show(arr))

print('peristent array update')
print('--------------------------------------------------------------------------------')
local arr1 = hamt.arrayUpdate(1, 'psycho', arr)
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
