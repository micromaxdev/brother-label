@echo off
setlocal enabledelayedexpansion

echo ============================================
echo   Firefox Kiosk Profile Configurator
echo ============================================
echo.

rem Find active Firefox profile folder
set MOZ_PROF_ROOT=%APPDATA%\Mozilla\Firefox\Profiles
set MOZ_PROF_TS=
set MOZ_PROF_PATH=

for /d %%d in (%MOZ_PROF_ROOT%\*) do (
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

rem Bail out if no profile found
if "!MOZ_PROF_PATH!"=="" (
    echo [ERROR] No Firefox profile found.
    echo         Has Firefox been launched at least once on this machine?
    echo.
    pause
    exit /b 1
)

echo Profile found:
echo   !MOZ_PROF_PATH!
echo.

rem Kill Firefox if running so file writes aren't blocked
tasklist | find /i "firefox.exe" >nul
if not errorlevel 1 (
    echo Firefox is running — closing it before applying settings ...
    taskkill /F /IM "firefox.exe" /T >nul
    timeout /nobreak /t 3 >nul
    rem Clear lock files
    del /f /q "!MOZ_PROF_PATH!\lock" 2>nul
    del /f /q "!MOZ_PROF_PATH!\.parentlock" 2>nul
    echo Done.
    echo.
)

rem Settings to apply
rem Format: filename|preference_name|value
set SETTINGS=^
user.js|app.update.auto|false ^
user.js|app.update.enabled|false ^
user.js|app.update.service.enabled|false ^
user.js|browser.launcherProcess.enabled|false ^
user.js|browser.sessionstore.resume_from_crash|false ^
user.js|browser.sessionstore.max_resumed_crashes|0 ^
user.js|browser.sessionstore.enabled|false ^
user.js|browser.sessionstore.restore_on_demand|false ^
prefs.js|browser.launcherProcess.enabled|false

echo Applying Firefox kiosk settings ...
echo.

pushd "!MOZ_PROF_PATH!"

for %%v in (%SETTINGS%) do (
    for /f "tokens=1-3 delims=|" %%p in ('echo %%v') do (
        set cfgfile=%%p
        set cfgvar=%%q
        set cfgval=%%r
    )

    set cfgset=
    set cfgupd=

    rem Check if preference already exists in the file
    if exist "!cfgfile!" (
        for /f "tokens=1-3 delims=(,) " %%k in (
            'findstr /b "user_pref(\"!cfgvar!\"" "!cfgfile!"'
        ) do (
            set cfgset=%%m
        )
    )

    rem Determine action needed
    if "!cfgset!"=="" (
        set cfgupd=ADD
    ) else if not "!cfgset!"=="!cfgval!" (
        set cfgupd=UPDATE
        rem Remove old line
        if exist "%temp%\!cfgfile!" del /f /q "%temp%\!cfgfile!"
        findstr /b /v "user_pref(\"!cfgvar!" "!cfgfile!" >"%temp%\!cfgfile!"
        move /y "%temp%\!cfgfile!" "!cfgfile!" >nul
    ) else (
        set cfgupd=OK
    )

    rem Write the setting if needed
    if not "!cfgupd!"=="OK" (
        echo   [!cfgupd!] !cfgfile! ^| !cfgvar! = !cfgval!
        (echo user_pref^("!cfgvar!", !cfgval!^);)>>"!cfgfile!"
    ) else (
        echo   [OK]     !cfgfile! ^| !cfgvar!
    )
)

popd

echo.
echo ============================================
echo   All settings applied successfully.
echo ============================================
echo.
echo You can now close this window.
echo Firefox will pick up these settings on next launch.
echo.
pause