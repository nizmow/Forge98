@echo off
md C:\FORGE98 2>NUL
rem %0 is the full path to this script; %0\.. is its directory.
copy %0\..\BOOT.BAT C:\FORGE98\BOOT.BAT
copy %0\..\BOOT.BAT "C:\WINDOWS\Start Menu\Programs\Startup\FORGE98.BAT"
echo FORGE98 harness installed. Reboot to activate.
