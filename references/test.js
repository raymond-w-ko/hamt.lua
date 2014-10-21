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

var run_tests;

var shuffle = function(t) {
  var n = t.length - 1;
  while (n > 0) {
    var k = Math.floor(Math.random() * n);
    var swap = t[n];
    t[n] = t[k];
    t[k] = swap;
    n = n - 1;
  }
  return t;
}


var filePath = path.join(__dirname, 'data.txt');
var data = [];
fs.readFile(filePath, {encoding: 'utf-8'}, function(err, filedata) {
  var lines = filedata.split('\n');
  for (var i = 0; i < lines.length; ++i) {
    var line = lines[i];
    var kv = line.split(' ');
    var key = kv[0];
    var value = kv[1];
    var item = [key, value];
    data.push(item);
  }

  run_tests();
});

run_tests = function() {
  // add
  for (var i = 0; i < data.length; ++i) {
    var datum = data[i];
    var key = datum[0];
    var value = datum[1];
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

  shuffle(data);

  // get
  for (var i = 0; i < data.length; ++i) {
    var datum = data[i];
    var key = datum[0];
    var value = datum[1];
    var fetched_value = hamt.get(key, map);
    if (fetched_value !== value) {
      console.log('retrieved wrong value for key'); 
      console.log('key: ' + key); 
      console.log('fetched value: ' + fetched_value); 
      console.log('expected value: ' + value); 
      assert(false);
    }
  }

  // get
  for (var i = 0; i < data.length; ++i) {
    var datum = data[i];
    var key = datum[0];
    var value = datum[1];
    map= hamt.remove(key, map);
  }

  assert(hamt.count(map) == 0);
};
