@echo off
pushd %~dp0\..
cls
set LUA=..\luas\lua51\lua.exe

%LUA% tests\basic_tests.lua > tests\output.txt
%LUA% tests\correctness_tests.lua >> tests\output.txt

popd
