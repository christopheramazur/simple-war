@echo off
setlocal EnableExtensions
pushd "%~dp0\.."

echo =================================================================
echo  Simple War — Project Status
echo  cwd : %cd%
echo  date: %date% %time%
echo =================================================================

echo.
echo --- Git ---
git branch --show-current 2>nul
git status --short --branch 2>nul

echo.
echo --- Engine / project.godot ---
type project.godot 2>nul | findstr /i "config/features"
type project.godot 2>nul | findstr /i "config/version"
type project.godot 2>nul | findstr /i "config/name"
type project.godot 2>nul | findstr /i "run/main_scene"

echo.
echo --- Autoloads ---
type project.godot 2>nul | findstr /i "^\[autoload\]"
type project.godot 2>nul | findstr /i "ECS="
type project.godot 2>nul | findstr /i "GUIDE="
type project.godot 2>nul | findstr /i "Dialogic="

echo.
echo --- Data assets (data/defaults) ---
dir /b data\defaults 2>nul

echo.
echo --- src/ (game code) ---
set /a GD=0
for /f "delims=" %%f in ('dir /b src\*.gd 2^>nul') do @set /a GD+=1
set /a SC=0
for /f "delims=" %%f in ('dir /b src\*.tscn 2^>nul') do @set /a SC+=1
echo     .gd  files : %GD%
echo     .tscn files : %SC%
if "%GD%"=="0" if "%SC%"=="0" (
    echo     NOTE: src/ is EMPTY — no game code present yet.
    echo           Project is in the foundation / PoC phase.
    echo           GDD + docs\godot-skill-distillation.md define the target design.
)
if "%GD%"=="0" if not "%SC%"=="0" echo     NOTE: src/ has scenes but no .gd yet.
if not "%GD%"=="0" if "%SC%"=="0" echo     NOTE: src/ has .gd but no .tscn yet.

echo.
echo --- Skills library ---
set /a SK=0
for /d %%s in (GD-Agentic-Skills\skills\*) do @set /a SK+=1
echo     %SK% godot-* skills in GD-Agentic-Skills\skills
echo     Master distillation: docs\godot-skill-distillation.md
echo     Reference scripts : GD-Agentic-Skills\skills\godot-master\scripts

popd
endlocal
