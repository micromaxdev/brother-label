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
set PRINTER_NAME=Brother QL-810W
set PRINTER_DRIVER=Brother QL-810W
set STARTUP_DIR=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup
set DASHBOARD_CMD=%STARTUP_DIR%\dashboard-start.cmd

echo. > "%LOG%"
echo VMS Print Service Installer >> "%LOG%"
echo Started: %date% %time% >> "%LOG%"
echo. >> "%LOG%"

cls
echo ================================================
echo   VMS Print Service Installer
echo   Version: 3.0
echo ================================================
echo.
echo   This installer will guide you through 8 steps.
echo   Each step pauses for you to verify before
echo   continuing.
echo.
echo   Log file: %LOG%
echo.
echo   PRE-FLIGHT CHECK:
echo   - Brother QL-810W is plugged in via USB
echo   - Brother QL-810W is powered ON
echo   - Firefox is installed on this kiosk
echo   - USB stick or installer folder contains:
echo       bsq16aw1101cuk.exe
echo       bcciw32001.msi
echo       nssm.exe
echo       dashboard-start.cmd
echo     and ..\dist contains:
echo       print_server.exe
echo       QL-visitor-custom.lbx
echo.
pause


:: ============================================================
:: STEP 1 - Collect site-specific configuration
:: ============================================================
cls
echo ================================================
echo   STEP 1 of 8: Site Configuration
echo ================================================
echo.
echo   Before the install begins, you need to enter the
echo   dashboard URL for this specific site.
echo.
echo   Format : https://[server-ip]/dashboard/frontdesk
echo   Example: https://192.168.1.123/dashboard/frontdesk
echo.

:ask_url
set DASH_URL=
set /p DASH_URL=  Enter dashboard URL for this site: 

if "!DASH_URL!"=="" (
    echo.
    echo [ERROR] URL cannot be blank. Please try again.
    echo.
    goto :ask_url
)

:: Basic sanity check - must start with http
echo !DASH_URL! | findstr /i "^http" >nul
if %errorlevel% neq 0 (
    echo.
    echo [ERROR] URL must start with http:// or https://
    echo.
    goto :ask_url
)

echo.
echo   You entered: !DASH_URL!
echo.
set CONFIRM=
set /p CONFIRM=  Is this correct? (Y/N): 
if /i not "!CONFIRM!"=="Y" goto :ask_url

echo.
echo [OK] Dashboard URL set to: !DASH_URL!
echo [OK] Dashboard URL: !DASH_URL! >> "%LOG%"

echo.
echo ------------------------------------------------
echo   STEP 1 COMPLETE
echo ------------------------------------------------
echo   Dashboard URL confirmed: !DASH_URL!
echo ------------------------------------------------
echo.
pause


:: ============================================================
:: STEP 2 - Check for pre-existing installation
:: ============================================================
cls
echo ================================================
echo   STEP 2 of 8: Pre-Installation Cleanup
echo ================================================
echo.
echo Checking for existing BrotherPrintServer service...

sc query %SERVICE_NAME% >nul 2>&1
if %errorlevel% equ 0 (
    echo [FOUND] Existing service detected. Stopping and removing...
    echo [FOUND] Existing service - removing >> "%LOG%"
    "%NSSM%" stop %SERVICE_NAME% >nul 2>&1
    timeout /t 4 /nobreak >nul
    taskkill /f /im print_server.exe >nul 2>&1
    "%NSSM%" remove %SERVICE_NAME% confirm >nul 2>&1
    timeout /t 2 /nobreak >nul
    echo [OK] Existing service removed.
    echo [OK] Existing service removed >> "%LOG%"
) else (
    echo [OK] No existing service found. Clean install.
    echo [OK] No existing service found >> "%LOG%"
)

echo.
echo Checking for existing install directory...
if exist "%INSTALL_DIR%" (
    echo [FOUND] %INSTALL_DIR% exists. Removing...
    rmdir /s /q "%INSTALL_DIR%" >nul 2>&1
    if exist "%INSTALL_DIR%" (
        echo [ERROR] Could not remove %INSTALL_DIR% - a file may still be in use.
        echo [ERROR] Could not remove install dir >> "%LOG%"
        echo.
        echo ACTION REQUIRED: Please check Task Manager for a running
        echo print_server.exe process and end it, then press any key to retry.
        pause
        rmdir /s /q "%INSTALL_DIR%" >nul 2>&1
        if exist "%INSTALL_DIR%" goto :error
    )
    echo [OK] Old install directory removed.
) else (
    echo [OK] No existing install directory found.
)

echo.
echo Checking for existing dashboard startup entry...
if exist "%DASHBOARD_CMD%" (
    echo [FOUND] Existing dashboard-start.cmd in Startup folder. Removing...
    del /f /q "%DASHBOARD_CMD%" >nul 2>&1
    echo [OK] Old dashboard startup entry removed.
) else (
    echo [OK] No existing dashboard startup entry found.
)

echo.
echo Checking spooler for stuck jobs...
net stop spooler >nul 2>&1
del /q /f /s "%SystemRoot%\System32\spool\PRINTERS\*.*" >nul 2>&1
net start spooler >nul 2>&1
echo [OK] Print spooler cleared and restarted.
echo [OK] Spooler cleared >> "%LOG%"

echo.
echo ------------------------------------------------
echo   STEP 2 COMPLETE
echo ------------------------------------------------
echo   Verified:
echo     Service removed (or was not present)
echo     Install directory cleared
echo     Old dashboard startup entry cleared
echo     Print spooler cleared
echo ------------------------------------------------
echo.
pause


:: ============================================================
:: STEP 3 - Brother QL-810W Printer Driver
:: ============================================================
cls
echo ================================================
echo   STEP 3 of 8: Brother QL-810W Printer Driver
echo ================================================
echo.
echo Checking required files...
if not exist "%SCRIPT_DIR%bsq16aw1101cuk.exe" (
    echo [ERROR] Driver installer not found: %SCRIPT_DIR%bsq16aw1101cuk.exe
    echo [ERROR] Driver installer not found >> "%LOG%"
    goto :error
)
echo [OK] Driver installer found.
echo.

echo Removing any existing Brother printer entries before installing...
powershell -Command "Get-Printer | Where-Object { $_.Name -like '*Brother*' } | ForEach-Object { Remove-Printer -Name $_.Name -ErrorAction SilentlyContinue; Write-Host 'Removed printer:' $_.Name }"
timeout /t 2 /nobreak >nul

echo.
echo Installing Brother QL-810W driver...
echo This will open the Brother installer GUI.
echo.
echo WHAT TO DO IN THE INSTALLER:
echo   1. Select QL-810W when asked for printer model
echo   2. Select Local Connection (USB)
echo   3. Complete the installation
echo   4. If prompted to restart, select NO or RESTART LATER
echo      (we will reboot at the end)
echo.
echo Press any key to launch the driver installer now...
pause >nul

"%SCRIPT_DIR%bsq16aw1101cuk.exe"
echo Driver installer exited with code: %errorlevel% >> "%LOG%"

echo.
echo Waiting 5 seconds for driver registration to settle...
timeout /t 5 /nobreak >nul

echo.
echo Verifying driver was registered in the driver store...
pnputil /enum-drivers | findstr /i "Brother" >nul
if %errorlevel% neq 0 (
    echo [ERROR] Brother driver not found in driver store after installation.
    echo [ERROR] Driver not in store after install >> "%LOG%"
    echo.
    echo The driver installer may have failed silently.
    echo Check Device Manager for the printer before continuing.
    goto :error
)
echo [OK] Brother driver found in driver store.
echo [OK] Driver registered in store >> "%LOG%"

echo.
echo Verifying printer appears in Windows...
powershell -Command "Get-Printer | Where-Object { $_.Name -like '*Brother*' }" >nul 2>&1
if %errorlevel% neq 0 (
    echo [WARNING] Brother printer not yet visible in Windows.
    echo This may be normal if the driver needs a moment to bind.
    echo We will force-bind the correct driver in the next step.
) else (
    echo [OK] Brother printer visible in Windows.
)

echo.
echo ------------------------------------------------
echo   STEP 3 COMPLETE
echo ------------------------------------------------
echo   CHECK NOW:
echo   Open Device Manager (devmgmt.msc) and confirm:
echo     - Brother QL-810W appears under "Print queues"
echo     - There is NO yellow warning triangle on it
echo     - It does NOT appear under "Other devices"
echo ------------------------------------------------
echo.
pause


:: ============================================================
:: STEP 4 - Force Correct Driver Binding
:: ============================================================
cls
echo ================================================
echo   STEP 4 of 8: Force Correct Driver Binding
echo ================================================
echo.
echo Windows 11 (build 19041+) automatically assigns its own
echo generic "Microsoft IPP Class Driver" to USB printers.
echo This silently breaks bPAC printing.
echo.
echo Checking current driver binding...

for /f "tokens=*" %%D in ('powershell -Command "Get-Printer | Where-Object { $_.Name -eq '%PRINTER_NAME%' } | Select-Object -ExpandProperty DriverName"') do (
    set CURRENT_DRIVER=%%D
)

echo Current driver: !CURRENT_DRIVER!
echo Current driver: !CURRENT_DRIVER! >> "%LOG%"

if /i "!CURRENT_DRIVER!"=="Microsoft IPP Class Driver" (
    echo [WARNING] Windows IPP generic driver is active. Forcing Brother driver...
) else if /i "!CURRENT_DRIVER!"=="%PRINTER_DRIVER%" (
    echo [OK] Correct Brother driver already active.
    goto :driver_ok
) else (
    echo [INFO] Driver is: !CURRENT_DRIVER! - will attempt to set correct driver.
)

printui.exe /Xs /n "%PRINTER_NAME%" DriverName "%PRINTER_DRIVER%"
timeout /t 3 /nobreak >nul

for /f "tokens=*" %%D in ('powershell -Command "Get-Printer | Where-Object { $_.Name -eq '%PRINTER_NAME%' } | Select-Object -ExpandProperty DriverName"') do (
    set NEW_DRIVER=%%D
)

echo Driver after fix: !NEW_DRIVER!
echo Driver after fix: !NEW_DRIVER! >> "%LOG%"

if /i "!NEW_DRIVER!"=="%PRINTER_DRIVER%" (
    echo [OK] Correct driver successfully bound.
    echo [OK] Correct driver bound >> "%LOG%"
) else (
    echo [ERROR] Driver binding failed. Expected "%PRINTER_DRIVER%"
    echo [ERROR] Expected "%PRINTER_DRIVER%", got "!NEW_DRIVER!" >> "%LOG%"
    echo.
    echo This is usually caused by the driver not being installed correctly.
    echo Go back and re-run the Brother installer from Step 3.
    goto :error
)

:driver_ok
echo.
echo Final printer configuration:
powershell -Command "Get-Printer | Where-Object { $_.Name -eq '%PRINTER_NAME%' } | Select-Object Name, DriverName, PortName | Format-List"

echo.
echo ------------------------------------------------
echo   STEP 4 COMPLETE
echo ------------------------------------------------
echo   VERIFY the output above shows:
echo     Name       : Brother QL-810W
echo     DriverName : Brother QL-810W      ^<-- must NOT say Microsoft IPP
echo     PortName   : USB001
echo ------------------------------------------------
echo.
pause


:: ============================================================
:: STEP 5 - bPAC Client Component
:: ============================================================
cls
echo ================================================
echo   STEP 5 of 8: Brother bPAC Client Component
echo ================================================
echo.
echo Checking required files...
if not exist "%SCRIPT_DIR%bcciw32001.msi" (
    echo [ERROR] bPAC MSI not found: %SCRIPT_DIR%bcciw32001.msi
    echo [ERROR] bPAC MSI not found >> "%LOG%"
    goto :error
)
echo [OK] bPAC MSI found.
echo.

echo Checking if bPAC is already installed...
powershell -Command "$app = Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like '*bPAC*' }; if ($app) { Write-Host '[FOUND] bPAC already installed:' $app.DisplayName $app.DisplayVersion }" 2>nul

echo.
echo Installing bPAC Client Component...
msiexec /i "%SCRIPT_DIR%bcciw32001.msi" /quiet /norestart ALLUSERS=1
set BPAC_EXIT=%errorlevel%
echo bPAC installer exit code: %BPAC_EXIT% >> "%LOG%"

if %BPAC_EXIT% equ 0 (
    echo [OK] bPAC installed successfully.
) else if %BPAC_EXIT% equ 1603 (
    echo [OK] bPAC already installed ^(exit code 1603^).
) else (
    echo [ERROR] bPAC installation failed with exit code: %BPAC_EXIT%
    echo [ERROR] bPAC failed, exit code: %BPAC_EXIT% >> "%LOG%"
    goto :error
)

echo.
echo Verifying bPAC COM object registration...
powershell -Command "Get-ItemProperty 'HKLM:\SOFTWARE\Classes\bpac.Document\CLSID' -ErrorAction Stop | Out-Null; Write-Host '[OK] bPAC COM object registered.'" 2>nul
if %errorlevel% neq 0 (
    echo [ERROR] bPAC COM object not found in registry.
    echo [ERROR] bPAC CLSID missing >> "%LOG%"
    echo.
    echo bPAC may not have installed correctly.
    echo Try right-clicking bcciw32001.msi and selecting Install.
    goto :error
)
echo [OK] bPAC COM object verified. >> "%LOG%"

echo.
echo ------------------------------------------------
echo   STEP 5 COMPLETE
echo ------------------------------------------------
echo   Verified:
echo     bPAC installed
echo     COM object registered (required for printing)
echo ------------------------------------------------
echo.
pause


:: ============================================================
:: STEP 6 - USB Power Settings + Copy Files + Install Service
:: ============================================================
cls
echo ================================================
echo   STEP 6 of 8: Print Service Installation
echo ================================================
echo.

echo Disabling USB selective suspend...
echo (Prevents Windows powering down the printer USB port during idle)
powercfg /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
powercfg /setdcvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
powercfg /setactive SCHEME_CURRENT
echo [OK] USB selective suspend disabled.
echo [OK] USB power settings applied >> "%LOG%"
echo.

echo Checking service files in dist folder...
if not exist "%DIST_DIR%\print_server.exe" (
    echo [ERROR] print_server.exe not found at: %DIST_DIR%\print_server.exe
    echo [ERROR] print_server.exe missing >> "%LOG%"
    goto :error
)
if not exist "%DIST_DIR%\QL-visitor-custom.lbx" (
    echo [ERROR] QL-visitor-custom.lbx not found at: %DIST_DIR%\QL-visitor-custom.lbx
    echo [ERROR] QL-visitor-custom.lbx missing >> "%LOG%"
    goto :error
)
echo [OK] Both service files found in dist.
echo.

if not exist "%NSSM%" (
    echo [ERROR] nssm.exe not found at: %NSSM%
    echo [ERROR] nssm.exe missing >> "%LOG%"
    goto :error
)
echo [OK] nssm.exe found.
echo.

echo Creating install directory: %INSTALL_DIR%
mkdir "%INSTALL_DIR%"
copy /y "%DIST_DIR%\print_server.exe" "%INSTALL_DIR%\" >nul
copy /y "%DIST_DIR%\QL-visitor-custom.lbx" "%INSTALL_DIR%\" >nul

if not exist "%INSTALL_DIR%\print_server.exe" (
    echo [ERROR] File copy failed - print_server.exe not at destination.
    echo [ERROR] File copy failed >> "%LOG%"
    goto :error
)
echo [OK] Files copied to %INSTALL_DIR%
echo [OK] Files copied >> "%LOG%"
echo.

echo Registering Windows service with NSSM...
"%NSSM%" install %SERVICE_NAME% "%INSTALL_DIR%\print_server.exe" >nul 2>&1
"%NSSM%" set %SERVICE_NAME% AppDirectory "%INSTALL_DIR%" >nul 2>&1
"%NSSM%" set %SERVICE_NAME% AppStdout "%INSTALL_DIR%\print_server.log" >nul 2>&1
"%NSSM%" set %SERVICE_NAME% AppStderr "%INSTALL_DIR%\print_server.log" >nul 2>&1
"%NSSM%" set %SERVICE_NAME% AppRestartDelay 3000 >nul 2>&1
"%NSSM%" set %SERVICE_NAME% Start SERVICE_AUTO_START >nul 2>&1
"%NSSM%" set %SERVICE_NAME% ObjectName "LocalSystem" >nul 2>&1
echo [OK] Service registered.
echo [OK] Service registered >> "%LOG%"
echo.

echo Starting service...
"%NSSM%" start %SERVICE_NAME% >nul 2>&1
echo Waiting 6 seconds for service to initialise...
timeout /t 6 /nobreak >nul

echo.
echo ------------------------------------------------
echo   STEP 6 COMPLETE
echo ------------------------------------------------
echo   USB power, file copy, and service registered.
echo ------------------------------------------------
echo.
pause


:: ============================================================
:: STEP 7 - Firefox Configuration
:: ============================================================
cls
echo ================================================
echo   STEP 7 of 8: Firefox Configuration
echo ================================================
echo.
echo Configuring Firefox for kiosk mode...
echo   - Disabling auto-updates
echo   - Disabling session restore
echo   - Granting camera permissions for this site
echo   - Writing installation-level policy
echo.

:: --- Find Firefox profile ---
set MOZ_PROF_ROOT=%APPDATA%\Mozilla\Firefox\Profiles
set MOZ_PROF_TS=
set MOZ_PROF_PATH=

for /d %%d in ("%MOZ_PROF_ROOT%\*") do (
    set MOZ_PROF_FN=%%~nxd
    if not "!MOZ_PROF_FN:.default=!"=="!MOZ_PROF_FN!" (
        set MOZ_PROF_CHK=%%~td
        set MOZ_PROF_CHK=!MOZ_PROF_CHK:/=!
        set MOZ_PROF_CHK=!MOZ_PROF_CHK::=!
        set MOZ_PROF_CHK=!MOZ_PROF_CHK: =!
        set MOZ_PROF_CHK=!MOZ_PROF_CHK:~4,4!!MOZ_PROF_CHK:~2,2!!MOZ_PROF_CHK:~0,2!!MOZ_PROF_CHK:~-2!!MOZ_PROF_CHK:~-6,4!
        if "!MOZ_PROF_CHK!" gtr "!MOZ_PROF_TS!" (
            set MOZ_PROF_TS=!MOZ_PROF_CHK!
            set MOZ_PROF_PATH=%%~dpnxd
        )
    )
)

if "!MOZ_PROF_PATH!"=="" (
    echo [ERROR] No Firefox profile found.
    echo         Firefox must be launched at least once before running this installer.
    echo [ERROR] No Firefox profile found >> "%LOG%"
    goto :error
)
echo [OK] Firefox profile found:
echo       !MOZ_PROF_PATH!
echo.

:: --- Kill Firefox if open ---
tasklist | find /i "firefox.exe" >nul
if not errorlevel 1 (
    echo Firefox is running. Closing it to apply settings...
    taskkill /F /IM "firefox.exe" /T >nul
    timeout /t 3 /nobreak >nul
    del /f /q "!MOZ_PROF_PATH!\lock" 2>nul
    del /f /q "!MOZ_PROF_PATH!\.parentlock" 2>nul
    echo [OK] Firefox closed.
    echo.
)

:: --- Write user.js and prefs.js settings ---
echo Writing Firefox profile settings...
pushd "!MOZ_PROF_PATH!"

for %%v in (
    "user.js|app.update.auto|false"
    "user.js|app.update.enabled|false"
    "user.js|app.update.service.enabled|false"
    "user.js|browser.launcherProcess.enabled|false"
    "user.js|browser.sessionstore.resume_from_crash|false"
    "user.js|browser.sessionstore.max_resumed_crashes|0"
    "user.js|browser.sessionstore.enabled|false"
    "user.js|browser.sessionstore.restore_on_demand|false"
    "prefs.js|browser.launcherProcess.enabled|false"
) do (
    for /f "tokens=1-3 delims=|" %%p in ('echo %%~v') do (
        set cfgfile=%%p
        set cfgvar=%%q
        set cfgval=%%r
    )
    set cfgset=
    set cfgupd=
    if exist "!cfgfile!" (
        for /f "tokens=1-3 delims=(,) " %%k in (
            'findstr /b "user_pref(\"!cfgvar!\"" "!cfgfile!"'
        ) do ( set cfgset=%%m )
    )
    if "!cfgset!"=="" (
        set cfgupd=ADD
    ) else if not "!cfgset!"=="!cfgval!" (
        set cfgupd=UPDATE
        if exist "%temp%\!cfgfile!" del /f /q "%temp%\!cfgfile!"
        findstr /b /v "user_pref(\"!cfgvar!" "!cfgfile!" >"%temp%\!cfgfile!"
        move /y "%temp%\!cfgfile!" "!cfgfile!" >nul
    ) else (
        set cfgupd=OK
    )
    if not "!cfgupd!"=="OK" (
        echo   [!cfgupd!] !cfgfile! ^| !cfgvar! = !cfgval!
        (echo user_pref^("!cfgvar!", !cfgval!^);)>>"!cfgfile!"
    ) else (
        echo   [OK]     !cfgfile! ^| !cfgvar!
    )
)

popd
echo.
echo [OK] Firefox profile settings written.
echo [OK] Firefox profile settings written >> "%LOG%"

:: --- Write installation-level camera policy ---
echo.
echo Writing Firefox camera policy for this site...

:: Extract just the origin (scheme + host) from the full dashboard URL
:: e.g. https://192.168.1.123/dashboard/frontdesk -> https://192.168.1.123
for /f "tokens=1,2,3 delims=/" %%a in ("!DASH_URL!") do set DASH_ORIGIN=%%a//%%b

set FF_DIST=C:\Program Files\Mozilla Firefox\distribution
if not exist "%FF_DIST%" mkdir "%FF_DIST%"

(
echo {
echo   "policies": {
echo     "Permissions": {
echo       "Camera": {
echo         "Allow": ["!DASH_ORIGIN!"],
echo         "BlockNewRequests": false,
echo         "Locked": false
echo       }
echo     }
echo   }
echo }
) > "%FF_DIST%\policies.json"

if not exist "%FF_DIST%\policies.json" (
    echo [ERROR] Failed to write Firefox policy file.
    echo [ERROR] Firefox policy write failed >> "%LOG%"
    goto :error
)
echo [OK] Camera permission granted for: !DASH_ORIGIN!
echo [OK] Firefox policy written for !DASH_ORIGIN! >> "%LOG%"

echo.
echo ------------------------------------------------
echo   STEP 7 COMPLETE
echo ------------------------------------------------
echo   Verified:
echo     Firefox profile settings written
echo     Camera policy written for !DASH_ORIGIN!
echo ------------------------------------------------
echo.
pause


:: ============================================================
:: STEP 8 - Dashboard Startup Script
:: ============================================================
cls
echo ================================================
echo   STEP 8 of 8: Dashboard Auto-Start
echo ================================================
echo.
echo Installing dashboard startup script...
echo   URL  : !DASH_URL!
echo   Dest : !DASHBOARD_CMD!
echo.

if not exist "%SCRIPT_DIR%dashboard-start.cmd" (
    echo [ERROR] dashboard-start.cmd not found in installer folder.
    echo [ERROR] dashboard-start.cmd missing >> "%LOG%"
    goto :error
)

:: Copy and inject the site URL into the startup script
:: Replace the DashURL line with the URL entered in Step 1
set TEMP_CMD=%TEMP%\dashboard-start-patched.cmd
if exist "%TEMP_CMD%" del /f /q "%TEMP_CMD%"

for /f "usebackq delims=" %%L in ("%SCRIPT_DIR%dashboard-start.cmd") do (
    set LINE=%%L
    echo !LINE! | findstr /b "set DashURL=" >nul
    if not errorlevel 1 (
        echo set DashURL=!DASH_URL!>> "%TEMP_CMD%"
    ) else (
        echo !LINE!>> "%TEMP_CMD%"
    )
)

copy /y "%TEMP_CMD%" "!DASHBOARD_CMD!" >nul
del /f /q "%TEMP_CMD%" >nul

if not exist "!DASHBOARD_CMD!" (
    echo [ERROR] Failed to copy dashboard-start.cmd to Startup folder.
    echo [ERROR] Dashboard startup copy failed >> "%LOG%"
    goto :error
)
echo [OK] dashboard-start.cmd installed to Startup folder.
echo [OK] Dashboard startup installed >> "%LOG%"

echo.
echo Verifying URL was written correctly...
findstr /i "DashURL" "!DASHBOARD_CMD!" | findstr /i "!DASH_URL!" >nul
if %errorlevel% neq 0 (
    echo [ERROR] URL not found in installed startup script.
    echo [ERROR] URL verification failed >> "%LOG%"
    goto :error
)
echo [OK] URL verified in startup script.

echo.
echo ------------------------------------------------
echo   STEP 8 COMPLETE
echo ------------------------------------------------
echo   Verified:
echo     dashboard-start.cmd installed to Shell:Startup
echo     DashURL correctly set to: !DASH_URL!
echo   On next login this script will auto-launch
echo   Firefox in kiosk mode pointed at the dashboard.
echo ------------------------------------------------
echo.
pause

goto :verify


:: ============================================================
:: FINAL VERIFICATION
:: ============================================================
:verify
cls
echo ================================================
echo   Final Verification
echo ================================================
echo.

echo [1/4] Checking print service status...
sc query %SERVICE_NAME% | find "RUNNING" >nul
if %errorlevel% neq 0 (
    echo [ERROR] Service is not in RUNNING state.
    echo [ERROR] Service not running >> "%LOG%"
    echo.
    echo Check the service log: %INSTALL_DIR%\print_server.log
    goto :error
)
echo [OK] Print service is RUNNING.
echo [OK] Service running >> "%LOG%"
echo.

echo [2/4] Checking health endpoint...
powershell -Command "try { $r = Invoke-WebRequest -UseBasicParsing http://localhost:%SERVICE_PORT%/health -TimeoutSec 10; Write-Host '[OK] Health endpoint responded:' $r.Content } catch { Write-Host '[ERROR] Health check failed:' $_.Exception.Message; exit 1 }"
if %errorlevel% neq 0 (
    echo [ERROR] Health check failed. Check %INSTALL_DIR%\print_server.log
    echo [ERROR] Health check failed >> "%LOG%"
    goto :error
)
echo [OK] Health check passed >> "%LOG%"
echo.

echo [3/4] Re-confirming printer driver binding...
for /f "tokens=*" %%D in ('powershell -Command "Get-Printer | Where-Object { $_.Name -eq '%PRINTER_NAME%' } | Select-Object -ExpandProperty DriverName"') do set FINAL_DRIVER=%%D
if /i "!FINAL_DRIVER!"=="%PRINTER_DRIVER%" (
    echo [OK] Driver confirmed: !FINAL_DRIVER!
    echo [OK] Driver confirmed correct >> "%LOG%"
) else (
    echo [WARNING] Driver is: !FINAL_DRIVER!
    echo [WARNING] Driver may have reverted to IPP >> "%LOG%"
    echo.
    echo Windows may have swapped back to the generic IPP driver.
    echo Run this in admin CMD after reboot if printing fails:
    echo   printui.exe /Xs /n "Brother QL-810W" DriverName "Brother QL-810W"
)
echo.

echo [4/4] Sending test print job...
echo The printer should print a test badge label now.
echo.
powershell -Command "try { $body = '{\"visitorName\":\"Install Test\",\"visitorCompany\":\"Micromax\",\"visitorDate\":\"%date%\",\"visitorType\":\"Visitor\",\"visitorId\":\"\",\"visitorHost\":\"\"}'; $r = Invoke-WebRequest -UseBasicParsing -Uri http://localhost:%SERVICE_PORT%/print -Method POST -ContentType 'application/json' -Body $body -TimeoutSec 15; Write-Host '[OK] Print job response:' $r.Content } catch { Write-Host '[ERROR] Print job failed:' $_.Exception.Message; exit 1 }"
if %errorlevel% neq 0 (
    echo [ERROR] Test print failed. Check %INSTALL_DIR%\print_server.log
    echo [ERROR] Test print failed >> "%LOG%"
    goto :error
)
echo [OK] Test print sent >> "%LOG%"

echo.
echo ------------------------------------------------
echo   CHECK NOW:
echo     Did a label print from the Brother QL-810W?
echo     If YES  - press any key for success screen
echo     If NO   - check printer is on and USB connected
echo               check %INSTALL_DIR%\print_server.log
echo               refer to PRINTER-SETUP-CHECKLIST.md
echo ------------------------------------------------
echo.
pause

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
echo   Installed to  : %INSTALL_DIR%
echo   Service name  : %SERVICE_NAME%
echo   Port          : %SERVICE_PORT%
echo   Dashboard URL : !DASH_URL!
echo   Service log   : %INSTALL_DIR%\print_server.log
echo   Install log   : %LOG%
echo.
echo ------------------------------------------------
echo   IMPORTANT - One manual step required:
echo ------------------------------------------------
echo.
echo   Disable Auto Power Off on the Brother QL-810W
echo   using the Printer Setting Tool (stw16013b.exe).
echo   See PRINTER-SETUP-CHECKLIST.md for instructions.
echo.
echo ------------------------------------------------
echo   REBOOT REMINDER:
echo ------------------------------------------------
echo.
echo   Please reboot this kiosk now.
echo   After reboot, verify:
echo     1. Print service starts automatically
echo     2. Firefox launches and opens the dashboard
echo     3. A full test check-in prints a badge
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
echo An error occurred during installation.
echo.
echo Log file : %LOG%
echo.
echo Refer to PRINTER-SETUP-CHECKLIST.md for manual
echo steps and troubleshooting guidance.
echo.
echo FAILED: %date% %time% >> "%LOG%"
pause
exit /b 1