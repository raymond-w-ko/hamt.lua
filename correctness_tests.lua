require('util')
local hamt = require('hamt')

math.randomseed(42)

local data = {}
for i = 1, 0xFFFF do
  table.insert(data, {tostring(i), math.random()})
end

local persistent_list = {}
local mutable_list = { }

for i = 1, 33 do
  local datum = data[i]
  local key = datum[1]
  local value = datum[2]

  local persistent = persistent_list[i - 1]
  print('key: '..key)
  persistent = hamt.set(key, value, persistent)
  print('count: ' .. hamt.count(persistent))
  print(table.show(persistent))
  table.insert(persistent_list, persistent)

  print('--------------------------------------------------------------------------------')
end

for i = 1, #persistent_list do
  local persistent = persistent_list[i]
  --print(table.show(persistent))
end
