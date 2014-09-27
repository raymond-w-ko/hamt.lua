require('util')
local hamt = require('hamt')

math.randomseed(42)

local bounds = 0xFFFFF

--local file = io.open('data.txt', 'w')
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

  --file:write(key)
  --file:write(' ')
  --file:write(value)
  --file:write('\n')

  table.insert(data, {key, })
end
--file:close()

local map = nil

local x = os.clock()

local function h(key)
  io.write('key: ')
  io.write(key)
  io.write(' -> hash: ')
  io.write(hamt.hash(key))
  io.write('\n')
end

h("85035710")
h("27815778")
h("14756006")

-- add
for i = 1, bounds do
  local datum = data[i]
  local key = datum[1]
  local value = datum[2]

  assert(hamt.get(key, map) == nil)

  map = hamt.set(key, value, map)

  --local count = hamt.count(map)
  --if i ~= count then
    --print('key: '..tostring(key))
    --print('count: ' .. count)
    --print(table.show(map))
    --assert(false)
  --end

  local fetched_value = hamt.get(key, map)
  if value ~= fetched_value then
    print('key:'..key)
    print('hash:'..hamt.hash(key))
    print('value:'..value)
    print('fetched_value:'..tostring(fetched_value))
    assert(false)
  end
end
assert(hamt.count(map) == bounds)

for i = 1, bounds do
  local datum = data[i]
  local key = datum[1]
  local value = datum[2]

  local fetched_value = hamt.get(key, map)
  if fetched_value ~= value then
    print(key)
    print(hamt.hash(key))
    print(value)
    print(fetched_value)
    assert(false)
  end
end

-- remove
for i = bounds, 1, -1 do
  local datum = data[i]
  local key = datum[1]
  map = hamt.remove(key, map)

  --local count = hamt.count(map)
  --if (i - 1) ~= count then
    --print('key: '..tostring(key))
    --print('count: ' .. count)
    --print(table.show(map))
    --assert(false)
  --end
end
assert(hamt.count(map) == 0)
print(os.clock() - x)
