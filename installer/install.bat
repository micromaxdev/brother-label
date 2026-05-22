@echo off
setlocal EnableDelayedExpansion
title VMS Print Service Installer

:: ============================================================
:: Self-elevate to Administrator if not already
:: ============================================================
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Requesting administrator privileges...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

:: ============================================================
:: Setup paths
:: ============================================================
set SCRIPT_DIR=%~dp0
set DIST_DIR=%~dp0..\dist
set INSTALL_DIR=C:\VMS\PrintService
set SERVICE_NAME=BrotherPrintServer
set SERVICE_PORT=5050
set NSSM=%SCRIPT_DIR%nssm.exe
set LOG=%SCRIPT_DIR%install_log.txt

echo. > "%LOG%"
echo VMS Print Service Installer > "%LOG%"
echo Started: %date% %time% >> "%LOG%"
echo. >> "%LOG%"

cls
echo ================================================
echo   VMS Print Service Installer
echo ================================================
echo.
echo This will install all required components.
echo Please do not close this window.
echo.
echo Log file: %SCRIPT_DIR%install_log.txt
echo.
pause


:: ============================================================
:: STEP 1 - Brother QL-810W Printer Driver
:: ============================================================
cls
echo ================================================
echo   STEP 1 of 5: Brother QL-810W Printer Driver
echo ================================================
echo.
echo Installing printer driver...
echo Please wait - this may take up to 60 seconds.
echo.

if not exist "%SCRIPT_DIR%bsq16aw1101cuk.exe" (
    echo [ERROR] Driver installer not found: bsq16aw1101cuk.exe
    echo [ERROR] Driver installer not found >> "%LOG%"
    goto :error
)

"%SCRIPT_DIR%bsq16aw1101cuk.exe" /a QL-810W /s
echo Driver installer finished with code: %errorlevel% >> "%LOG%"
echo [OK] Printer driver installed.
echo.
timeout /t 3 /nobreak >nul


:: ============================================================
:: STEP 2 - bPAC Client Component
:: ============================================================
cls
echo ================================================
echo   STEP 2 of 5: Brother bPAC Client Component
echo ================================================
echo.
echo Installing bPAC component...
echo Please wait - this may take up to 60 seconds.
echo.

if not exist "%SCRIPT_DIR%bcciw32001.msi" (
    echo [ERROR] bPAC MSI not found: bcciw32001.msi
    echo [ERROR] bPAC MSI not found >> "%LOG%"
    goto :error
)

msiexec /i "%SCRIPT_DIR%bcciw32001.msi" /quiet /norestart ALLUSERS=1
set BPAC_EXIT=%errorlevel%
echo bPAC installer finished with code: %BPAC_EXIT% >> "%LOG%"

if %BPAC_EXIT% neq 0 if %BPAC_EXIT% neq 1603 (
    echo [ERROR] bPAC installation failed. Code: %BPAC_EXIT%
    echo [ERROR] bPAC installation failed. Code: %BPAC_EXIT% >> "%LOG%"
    goto :error
)
echo [OK] bPAC Client Component installed.
echo.
timeout /t 3 /nobreak >nul


:: ============================================================
:: STEP 3 - USB Power Settings
:: ============================================================
cls
echo ================================================
echo   STEP 3 of 5: USB Power Settings
echo ================================================
echo.
echo Disabling USB selective suspend...
echo (Prevents Windows from powering down the printer USB port)
echo.

powercfg /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
powercfg /setdcvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
powercfg /setactive SCHEME_CURRENT
echo USB power settings configured >> "%LOG%"
echo [OK] USB selective suspend disabled.
echo.
timeout /t 2 /nobreak >nul


:: ============================================================
:: STEP 4 - Copy Service Files
:: ============================================================
cls
echo ================================================
echo   STEP 4 of 5: Installing Print Service
echo ================================================
echo.

:: Stop and remove existing service if present
echo Checking for existing service...
sc query %SERVICE_NAME% >nul 2>&1
if %errorlevel% equ 0 (
    echo Found existing service. Removing...
    "%NSSM%" stop %SERVICE_NAME% 2>nul
    timeout /t 3 /nobreak >nul
    taskkill /f /im print_server.exe >nul 2>&1
    "%NSSM%" remove %SERVICE_NAME% confirm
    timeout /t 2 /nobreak >nul
    echo Existing service removed. >> "%LOG%"
)

:: Create install directory
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"

:: Copy files
if not exist "%DIST_DIR%\print_server.exe" (
    echo [ERROR] print_server.exe not found in dist folder.
    echo [ERROR] print_server.exe not found >> "%LOG%"
    goto :error
)
if not exist "%DIST_DIR%\QL-visitor-custom.lbx" (
    echo [ERROR] QL-visitor-custom.lbx not found in dist folder.
    echo [ERROR] QL-visitor-custom.lbx not found >> "%LOG%"
    goto :error
)

copy /y "%DIST_DIR%\print_server.exe" "%INSTALL_DIR%\" >nul
copy /y "%DIST_DIR%\QL-visitor-custom.lbx" "%INSTALL_DIR%\" >nul
echo Files copied to %INSTALL_DIR% >> "%LOG%"
echo [OK] Service files copied to %INSTALL_DIR%

:: Register service with NSSM
echo.
echo Registering Windows Service...
"%NSSM%" install %SERVICE_NAME% "%INSTALL_DIR%\print_server.exe"
"%NSSM%" set %SERVICE_NAME% AppDirectory "%INSTALL_DIR%"
"%NSSM%" set %SERVICE_NAME% AppStdout "%INSTALL_DIR%\print_server.log"
"%NSSM%" set %SERVICE_NAME% AppStderr "%INSTALL_DIR%\print_server.log"
"%NSSM%" set %SERVICE_NAME% AppRestartDelay 3000
"%NSSM%" set %SERVICE_NAME% Start SERVICE_AUTO_START
"%NSSM%" set %SERVICE_NAME% ObjectName "LocalSystem"
echo Service registered >> "%LOG%"

:: Start service
echo.
echo Starting service...
"%NSSM%" start %SERVICE_NAME%
timeout /t 5 /nobreak >nul

echo [OK] Print service installed and started.
echo.
timeout /t 2 /nobreak >nul


:: ============================================================
:: STEP 5 - Verify
:: ============================================================
cls
echo ================================================
echo   STEP 5 of 5: Verifying Installation
echo ================================================
echo.
echo Checking service status...

sc query %SERVICE_NAME% | find "RUNNING" >nul
if %errorlevel% neq 0 (
    echo [ERROR] Service is not running.
    echo [ERROR] Service not running after install >> "%LOG%"
    goto :error
)
echo [OK] Service is running.

echo.
echo Checking health endpoint...
powershell -Command "try { $r = Invoke-WebRequest -UseBasicParsing http://localhost:%SERVICE_PORT%/health -TimeoutSec 10; Write-Host '[OK] Health check passed:' $r.Content } catch { Write-Host '[ERROR] Health check failed:' $_.Exception.Message; exit 1 }"
if %errorlevel% neq 0 (
    echo [ERROR] Health check failed. Check %INSTALL_DIR%\print_server.log
    goto :error
)

echo.
echo Health check passed >> "%LOG%"
goto :success


:: ============================================================
:: SUCCESS
:: ============================================================
:success
cls
echo.
echo ================================================
echo   Installation Complete!
echo ================================================
echo.
echo   Installed to : %INSTALL_DIR%
echo   Service name : %SERVICE_NAME%
echo   Port         : %SERVICE_PORT%
echo   Log file     : %INSTALL_DIR%\print_server.log
echo.
echo ------------------------------------------------
echo   IMPORTANT - One manual step required:
echo ------------------------------------------------
echo.
echo   Disable Auto Power Off on the Brother QL-810W
echo   using the Printer Setting Tool (stw16013b.exe).
echo   See PRINTER-SETUP-CHECKLIST.md for instructions.
echo.
echo ================================================
echo.
echo Installation finished: %date% %time% >> "%LOG%"
echo SUCCESS >> "%LOG%"
pause
exit /b 0


:: ============================================================
:: ERROR
:: ============================================================
:error
echo.
echo ================================================
echo   Installation Failed
echo ================================================
echo.
echo An error occurred. Check the log file for details:
echo %SCRIPT_DIR%install_log.txt
echo.
echo FAILED: %date% %time% >> "%LOG%"
pause
exit /b 1
