@echo off
pushd %~dp0\..
cls
set LUA=..\luas\luajit\luajit.exe

%LUA% -jv tests\basic_tests.lua > tests\output.txt

%LUA% -jv tests\correctness_tests.lua >> tests\output.txt 2>&1
REM %LUA% -joff -jv -jp=a correctness_tests.lua >> tests\output.txt 2>&1
REM %LUA% -jp=a correctness_tests.lua >> tests\output.txt 2>&1

popd
