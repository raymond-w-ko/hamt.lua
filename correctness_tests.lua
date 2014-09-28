require('util')
local hamt = require('hamt')

math.randomseed(42)

-- if bounds is 0x2FFFFF, then LuaJIT crashes due to out of memory limitations
-- since it causes around 1.8 GB of memory to be used. the limit is probably
-- lower on 64 bit Linux due to how MAP_32bit works?
local bounds = 0x1FFFFF

-- since count() uses fold() which is O(n) checking every step would make it
-- O(mn) where m is bounds and n is current size, which is close to O(n^2)
--
-- use statistical sampling to check only some of the time to avoid this
local count_check_rate = 0.0001

local existing_keys = {}
local data = {}
for i = 1, bounds do
  local key
  for try = 1, 64 do
    key = tostring(math.random(1, 100000000))
    if existing_keys[key] == nil then
      existing_keys[key] = true
      break
    else
      key = nil
    end
  end
  if key == nil then
    print('need to increase random int space')
    assert(false)
  end

  local value = math.random()

  table.insert(data, {key, value})
end
print('memory used to store data: '..collectgarbage('count'))

local map = nil

local start_time = os.clock()

local function h(key)
  io.write('key: ')
  io.write(key)
  io.write(' -> hash: ')
  io.write(hamt.hash(key))
  io.write('\n')
end

--h("85035710")
--h("27815778")
--h("14756006")

-- add
for i = 1, bounds do
  local datum = data[i]
  local key = datum[1]
  local value = datum[2]

  assert(hamt.get(key, map) == nil)

  map = hamt.set(key, value, map)

  -- too slow, causes O(n^2) explosision since count() is O(n)
  --local count = hamt.count(map)
  --if i ~= count then
    --print('key: '..tostring(key))
    --print('count: ' .. count)
    --print(table.show(map))
    --assert(false)
  --end
  
  if math.random() < count_check_rate then
    assert(hamt.count(map) == i)
  end

  local fetched_value = hamt.get(key, map)
  if value ~= fetched_value then
    print('did not retrieve immediately inserted key value pair')
    print('key: '..key)
    print('hash: '..hamt.hash(key))
    print('value: '..value)
    print('fetched_value: '..tostring(fetched_value))
    assert(false)
  end
end

assert(hamt.count(map) == bounds)

table.shuffle(data)

for i = 1, bounds do
  local datum = data[i]
  local key = datum[1]
  local value = datum[2]

  local fetched_value = hamt.get(key, map)
  if fetched_value ~= value then
    print('retrieved wrong value for key')
    print('key: '..key)
    print('hash: '..hamt.hash(key))
    print('value: '..value)
    print('fetched_value'..fetched_value)
    assert(false)
  end
end

-- remove
for i = bounds, 1, -1 do
  local datum = data[i]
  local key = datum[1]
  map = hamt.remove(key, map)

  -- too slow, causes O(n^2) explosision since count() is O(n)
  --local count = hamt.count(map)
  --if (i - 1) ~= count then
    --print('key: '..tostring(key))
    --print('count: ' .. count)
    --print(table.show(map))
    --assert(false)
  --end

  if math.random() <= count_check_rate then
    assert(hamt.count(map) == (i - 1))
  end
end

assert(hamt.count(map) == 0)

print(os.clock() - start_time)
