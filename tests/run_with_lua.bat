@echo off
pushd %~dp0\..
cls
REM set LUA=..\luas\lua51\lua.exe
set LUA=..\luas\lua52\lua.exe

%LUA% tests\basic_tests.lua > tests\lua_output.txt
%LUA% tests\correctness_tests.lua >> tests\lua_output.txt

popd
