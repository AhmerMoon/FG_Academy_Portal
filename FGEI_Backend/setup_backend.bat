@echo off
title FG Academy Automation Setup

cd /d "%~dp0"

echo.
echo ===============================================
echo   FG Academy Automation - First Time Setup
echo ===============================================
echo.

where py >nul 2>nul

if errorlevel 1 (
    echo ERROR: Python is not installed.
    echo.
    echo Install Python 3.10 first and then run this file again.
    echo.
    pause
    exit /b 1
)

echo Checking Python 3.10...
py -3.10 --version

if errorlevel 1 (
    echo.
    echo ERROR: Python 3.10 was not found.
    echo Install Python 3.10 and run setup again.
    echo.
    pause
    exit /b 1
)

echo.
echo Creating Python virtual environment...
py -3.10 -m venv .venv

if errorlevel 1 (
    echo.
    echo ERROR: Could not create virtual environment.
    pause
    exit /b 1
)

echo.
echo Updating pip...
".venv\Scripts\python.exe" -m pip install --upgrade pip

echo.
echo Installing FG Academy automation packages...
".venv\Scripts\python.exe" -m pip install -r requirements.txt

if errorlevel 1 (
    echo.
    echo ERROR: Package installation failed.
    echo Check internet connection and try again.
    pause
    exit /b 1
)

echo.
echo ===============================================
echo   SETUP COMPLETED SUCCESSFULLY
echo ===============================================
echo.
echo Next:
echo 1. Create .env file in this folder.
echo 2. Login to WhatsApp Web.
echo 3. Run main.bat once for testing.
echo.

pause