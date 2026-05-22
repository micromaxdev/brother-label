@echo off&setlocal enabledelayedexpansion

rem Set dashboard target URL
set DashURL=https://dashboard.int.micromax.com.au/dashboard/frontdesk

rem Set Firefox as target dashboard application
set DashApp="%ProgramFiles%\Mozilla Firefox\firefox.exe"
set DashPrm=--kiosk
set DashTmr=15

set DashFQDN=!DashURL:*//=!
set DashPath=!DashFQDN:*/=!
set DashFQDN=!DashFQDN:/%DashPath%=!

echo Script-Path=%~dp0
echo Script-File=%~nx0
echo.
echo Dashboard-URL=!DashURL!

:DashRst
echo.
set /p echo="Script-(Re)Starting ... " <nul
timeout /nobreak /t !DashTmr! >nul
echo.

rem Forcefully kill any hung instances of Firefox
tasklist | find /i "firefox.exe" >nul
if not errorlevel 1 (
    echo.
    echo Killing hung instances of Firefox ...
    taskkill /F /IM "firefox.exe" /T
    echo.
    timeout /nobreak /t 5 >nul
)

rem Find active Firefox configuration profile folder
set MOZ_PROF_ROOT=%APPDATA%\Mozilla\Firefox\Profiles
set MOZ_PROF_TS=&for /d %%d in (%MOZ_PROF_ROOT%\*) do (
    set MOZ_PROF_FN=%%~nxd
    if not "!MOZ_PROF_FN:.default=!"=="!MOZ_PROF_FN!" (
        set MOZ_PROF_CHK=%%~td&set MOZ_PROF_CHK=!MOZ_PROF_CHK:/=!&set MOZ_PROF_CHK=!MOZ_PROF_CHK::=!&set MOZ_PROF_CHK=!MOZ_PROF_CHK: =!&&set MOZ_PROF_CHK=!MOZ_PROF_CHK:~4,4!!MOZ_PROF_CHK:~2,2!!MOZ_PROF_CHK:~0,2!!MOZ_PROF_CHK:~-2!!MOZ_PROF_CHK:~-6,4!
        if "!MOZ_PROF_CHK!" gtr "!MOZ_PROF_TS!" (
            set MOZ_PROF_TS=!MOZ_PROF_CHK!
            set MOZ_PROF_PATH=%%~dpnxd
        )
    )
)

rem Clear Firefox lock files left by force kill
if defined MOZ_PROF_PATH (
    echo Clearing Firefox lock files ...
    del /f /q "!MOZ_PROF_PATH!\lock" 2>nul
    del /f /q "!MOZ_PROF_PATH!\.parentlock" 2>nul
)

rem Check Firefox settings and flush cache
if not "!MOZ_PROF_TS!"=="" (
    echo.
    echo Checking Firefox settings ...

    pushd "!MOZ_PROF_PATH!"

    for %%v in ( ^
            user.js:app.update.auto:false ^
            user.js:app.update.enabled:false ^
            user.js:app.update.service.enabled:false ^
            user.js:browser.launcherProcess.enabled:false ^
            prefs.js:browser.launcherProcess.enabled:false
        ) do (
            for /f "tokens=1-3 delims=: " %%p in ('echo %%v') do (
                set mozcfgjs=%%p
                set mozcfgvar=%%q
                set mozcfgval=%%r
            )
            set mozcfgset=&set mozcfgupd=
            if exist "!mozcfgjs!" (
                for /f "tokens=1-3 delims=(,) " %%k in ('findstr /b "user_pref(\"!mozcfgvar!\"" "!mozcfgjs!"') do (set mozcfgset=%%m)
            )
            if "!mozcfgset!"=="" (
                set mozcfgupd=Add
            ) else (
            if not "!mozcfgset!"=="!mozcfgval!" (
                set mozcfgupd=^>!mozcfgval!-Edit
                >"%temp%\!mozcfgjs!" findstr /b /v "user_pref(\"!mozcfgvar!" "!mozcfgjs!"
                move /y "%temp%\!mozcfgjs!" "!mozcfgjs!" >nul
            ))
            if not "!mozcfgupd!"=="" (
                echo FireFox-!mozcfgjs!-!mozcfgvar!-!mozcfgupd!
                (echo user_pref^("!mozcfgvar!", !mozcfgval!^);)>>"!mozcfgjs!"
            )
        )

    rem Flush Firefox cache
    if exist "storage\*" for /d %%d in (storage\*) do (
        echo Deleting Firefox cached files in %%~d ...
        rd /q/s "%%~d" >nul
    )

    popd
)

rem Check that dashboard server is online
echo.
set /p echo="Checking Dashboard Online ... " <nul
curl -o- -k --retry 1 --max-time !DashTmr! --write-out "%%%{http_code}" !DashURL! 2>nul | findstr /b /r "200$" >nul
if errorlevel 1 (
    echo ERR-Offline, Retrying
    goto:DashRst
) else (
    echo OK
)

rem Start Firefox
echo.
echo Starting Dashboard ...
timeout /nobreak /t 3 >nul
start "Dashboard" !DashApp! !DashPrm! !DashURL!

rem Wait for Firefox to exit by polling
:WaitLoop
timeout /nobreak /t 5 >nul
tasklist | find /i "firefox.exe" >nul
if not errorlevel 1 goto:WaitLoop

rem Firefox has exited — begin restart cycle
echo.
echo Firefox exited — restarting ...
goto:DashRst