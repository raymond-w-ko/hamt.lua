var use_plus = false;

var hamt;
if (!use_plus) {
  hamt = require('./mattbierner_hamt/hamt.js');
} else {
  hamt = require('./mattbierner_hamt_plus/hamt.js');
}

var fs = require('fs');
var path = require('path');
var assert = require('assert');

var map;
if (!use_plus) {
  map = hamt.empty;
} else {
  map = hamt.make();
}

var filePath = path.join(__dirname, 'data.txt');
fs.readFile(filePath, {encoding: 'utf-8'}, function(err, data) {
  var lines = data.split('\n');
  for (var i = 0; i < lines.length; ++i) {
    var line = lines[i];
    var kv = line.split(' ');
    var key = kv[0];
    var value = kv[1];

    map = hamt.set(key, value, map);

    var fetched_value = hamt.get(key, map);
    if (fetched_value !== value) {
      console.log('failed to get immediately inserted key value pair'); 
      console.log('key: ' + key); 
      console.log('fetched value: ' + fetched_value); 
      console.log('expected value: ' + value); 
      assert(false);
    }
  }
});
