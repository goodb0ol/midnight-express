@echo off
rem Launches the game with the Godot build from Downloads.
rem "%~dp0." not "%~dp0": a trailing backslash would escape the closing quote.
start "" "%USERPROFILE%\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe" --path "%~dp0."
