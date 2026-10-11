
@echo off
setlocal
cd /d "%~dp0"

set "PYTHON_EXE="

if exist "%~dp0.venv\Scripts\python.exe" (
    set "PYTHON_EXE=%~dp0.venv\Scripts\python.exe"
)

if not defined PYTHON_EXE if exist "%~dp0venv\Scripts\python.exe" (
    set "PYTHON_EXE=%~dp0venv\Scripts\python.exe"
)

if not defined PYTHON_EXE if exist "%~dp0..\.venv\Scripts\python.exe" (
    set "PYTHON_EXE=%~dp0..\.venv\Scripts\python.exe"
)

if not defined PYTHON_EXE (
    set "PYTHON_EXE=python"
)

echo.
echo IlmRise Academy - Attendance Automation
echo.

"%PYTHON_EXE%" "%~dp0main.py" %*

set "EXIT_CODE=%ERRORLEVEL%"

echo.
if not "%EXIT_CODE%"=="0" (
    echo Automation failed. Exit code: %EXIT_CODE%
) else (
    echo Automation finished.
)

echo.
pause
exit /b %EXIT_CODE%
