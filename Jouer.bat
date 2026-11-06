@echo off
rem Launches the game with the Godot build from Downloads.
rem Direct3D 12: Vulkan fails every frame on this PC, even with an empty project.
rem "%~dp0." not "%~dp0": a trailing backslash would escape the closing quote.
start "" "%USERPROFILE%\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe" --rendering-driver d3d12 --path "%~dp0."
