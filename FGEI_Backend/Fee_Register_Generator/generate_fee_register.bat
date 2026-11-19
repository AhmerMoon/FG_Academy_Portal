@echo off
setlocal
cd /d "%~dp0"

if exist "..\.venv\Scripts\python.exe" (
  set "PYTHON_EXE=..\.venv\Scripts\python.exe"
  set "PIP_SCOPE="
) else (
  where python >nul 2>nul
  if errorlevel 1 (
    echo Python is not installed or is not available in PATH.
    echo Run the parent FGEI_Backend\setup_backend.bat first.
    pause
    exit /b 1
  )
  set "PYTHON_EXE=python"
  set "PIP_SCOPE=--user"
)

"%PYTHON_EXE%" -c "import dotenv, supabase, reportlab" >nul 2>nul
if errorlevel 1 (
  echo Installing required packages. This only takes time on first run...
  "%PYTHON_EXE%" -m pip install %PIP_SCOPE% --disable-pip-version-check -r requirements.txt
  if errorlevel 1 goto :failed
)

echo.
"%PYTHON_EXE%" generate_fee_register.py
if errorlevel 1 goto :failed

echo.
echo Fee register generation completed successfully.
pause
exit /b 0

:failed
echo.
echo Fee register generation failed. Please read the error shown above.
pause
exit /b 1


