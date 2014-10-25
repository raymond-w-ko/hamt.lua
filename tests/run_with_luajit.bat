@echo off
pushd %~dp0\..
cls
set LUA=..\luas\luajit\luajit.exe

%LUA% -jv tests\basic_tests.lua > tests\luajit_output.txt

REM %LUA% tests\correctness_tests.lua >> tests\luajit_output.txt 2>&1
%LUA% -jv tests\correctness_tests.lua >> tests\luajit_output.txt 2>&1
REM %LUA% -joff -jv tests\correctness_tests.lua >> tests\luajit_output.txt 2>&1
REM %LUA% -joff -jv -jp=a tests\correctness_tests.lua >> tests\luajit_output.txt 2>&1
REM %LUA% -jp=a tests\correctness_tests.lua >> tests\luajit_output.txt 2>&1

popd
