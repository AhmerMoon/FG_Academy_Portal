@echo off
title FG Academy WhatsApp Attendance Reports

cd /d "%~dp0"

echo.
echo ===============================================
echo   FG Academy Attendance Automation
echo ===============================================
echo.

if not exist ".venv\Scripts\python.exe" (
    echo ERROR: Python environment is not installed.
    echo.
    echo Please run setup_backend.bat first.
    echo.
    pause
    exit /b 1
)

".venv\Scripts\python.exe" "%~dp0main.py"

echo.
echo ===============================================
echo   Automation Finished
echo ===============================================
echo.

pause