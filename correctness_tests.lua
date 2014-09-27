require('util')
local hamt = require('hamt')

math.randomseed(42)

local bounds = 0xFFFFF

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
  table.insert(data, {key, math.random()})
end

local persistent = nil


local x = os.clock()

-- add
for i = 1, bounds do
  local datum = data[i]
  local key = datum[1]
  local value = datum[2]

  persistent = hamt.set(key, value, persistent)

  --local count = hamt.count(persistent)
  --if i ~= count then
    --print('key: '..tostring(key))
    --print('count: ' .. count)
    --print(table.show(persistent))
    --assert(false)
  --end

  local fetched_value = hamt.get(key, persistent)
  if value ~= fetched_value then
    print('key:'..key)
    print('hash:'..hamt.hash(key))
    print('value:'..value)
    print('fetched_value:'..tostring(fetched_value))
    assert(false)
  end
end

for i = 1, bounds do
  local datum = data[i]
  local key = datum[1]
  local value = datum[2]

  local fetched_value = hamt.get(key, persistent)
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
  persistent = hamt.remove(key, persistent)

  --local count = hamt.count(persistent)
  --if (i - 1) ~= count then
    --print('key: '..tostring(key))
    --print('count: ' .. count)
    --print(table.show(persistent))
    --assert(false)
  --end
end
assert(hamt.count(persistent) == 0)
print(os.clock() - x)
