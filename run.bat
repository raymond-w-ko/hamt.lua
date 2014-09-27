@echo off
REM ..\luajit-2.0\src\luajit.exe -jv tests.lua > output.txt

REM ..\luajit-2.0\src\luajit.exe -joff -jv -jp=a correctness_tests.lua > output.txt
..\luajit-2.0\src\luajit.exe -jp=a correctness_tests.lua > output.txt
REM ..\luajit-2.0\src\luajit.exe -jv correctness_tests.lua > output.txt
