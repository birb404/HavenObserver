@echo off
setlocal

set "OBS_EXE=C:\Program Files\obs-studio\bin\64bit\obs64.exe"
set "OBS_DIR=C:\Program Files\obs-studio\bin\64bit"

tasklist /FI "IMAGENAME eq obs64.exe" 2>NUL | find /I "obs64.exe" >NUL
if not errorlevel 1 (
    echo OBS Studio is already running.
    echo Close OBS and run this file again so automatic recording can start reliably.
    pause
    exit /b 1
)

if not exist "%OBS_EXE%" (
    set "OBS_EXE=C:\Program Files (x86)\obs-studio\bin\64bit\obs64.exe"
    set "OBS_DIR=C:\Program Files (x86)\obs-studio\bin\64bit"
)

if not exist "%OBS_EXE%" (
    echo HavenObserver could not find OBS Studio.
    echo Expected obs64.exe under Program Files\obs-studio\bin\64bit.
    pause
    exit /b 1
)

echo Starting OBS Studio with the WOW Retail scene...
echo Use the shared HavenObserver/OBS hotkey to start both recordings together.
start "" /D "%OBS_DIR%" "%OBS_EXE%" --profile "HavenObserver" --collection "Untitled" --scene "WOW Retail"
exit /b 0
