@echo off

set VERSION=1.1

rem printing greetings

echo C3Pool mining uninstall script v%VERSION%.
echo ^(please report issues to support@c3pool.com email^)
echo.

net session >nul 2>&1
if %errorLevel% == 0 (set ADMIN=1) else (set ADMIN=0)

if ["%USERPROFILE%"] == [""] (
  echo ERROR: Please define USERPROFILE environment variable to your user directory
  exit /b 1
)

if not exist "%USERPROFILE%" (
  echo ERROR: Please make sure user directory %USERPROFILE% exists
  exit /b 1
)

echo [*] Removing c3pool miner
set REMOVE_TRIES=0

if %ADMIN% == 0 goto SKIP_ADMIN_PART

sc stop c3pool_miner
sc delete c3pool_miner

:SKIP_ADMIN_PART

rem kill only the miner installed by this script, not other xmrig instances
powershell -Command "Get-Process xmrig -ErrorAction SilentlyContinue | ?{$_.Path -and $_.Path.StartsWith($env:USERPROFILE + '\c3pool\', 'OrdinalIgnoreCase')} | Stop-Process -Force"

if exist "%USERPROFILE%\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup" (
  set "STARTUP_DIR=%USERPROFILE%\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup"
  goto STARTUP_DIR_OK
)
if exist "%USERPROFILE%\Start Menu\Programs\Startup" (
  set "STARTUP_DIR=%USERPROFILE%\Start Menu\Programs\Startup"
  goto STARTUP_DIR_OK  
)

echo WARNING: Can't find Windows startup directory
goto REMOVE_DIR

:STARTUP_DIR_OK
del "%STARTUP_DIR%\c3pool_miner.bat"

:REMOVE_DIR
echo [*] Removing "%USERPROFILE%\c3pool" directory
timeout 5
rmdir /q /s "%USERPROFILE%\c3pool" >NUL 2>NUL
if not exist "%USERPROFILE%\c3pool" goto REMOVE_DIR_OK
set /a "REMOVE_TRIES += 1"
if %REMOVE_TRIES% lss 12 goto REMOVE_DIR
echo WARNING: Can't remove "%USERPROFILE%\c3pool" directory ^(files still in use?^), please remove it manually after reboot
:REMOVE_DIR_OK

echo [*] Uninstall complete
pause
exit /b 0
