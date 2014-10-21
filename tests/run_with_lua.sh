#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"
cd ..

LUA=lua5.1

$LUA tests/basic_tests.lua > tests/lua_output.txt
$LUA tests/correctness_tests.lua >> tests/lua_output.txt
