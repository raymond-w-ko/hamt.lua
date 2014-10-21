#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"
cd ..

LUA=luajit

$LUA -jv tests/basic_tests.lua > tests/luajit_output.txt

#$LUA -jv tests/correctness_tests.lua >> tests/luajit_output.txt 2>&1
$LUA -jv -jp=a tests/correctness_tests.lua >> tests/luajit_output.txt 2>&1

#$LUA -joff -jv tests/correctness_tests.lua >> tests/luajit_output.txt 2>&1
#$LUA -joff -jv -jp=a tests/correctness_tests.lua >> tests/luajit_output.txt 2>&1
