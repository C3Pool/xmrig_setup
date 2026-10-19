@echo off

set VERSION=2.5

rem printing greetings

echo C3Pool mining setup script v%VERSION%.
echo ^(please report issues to support@c3pool.com email^)
echo.

net session >nul 2>&1
if %errorLevel% == 0 (set ADMIN=1) else (set ADMIN=0)

rem command line arguments
set WALLET=%1
rem this one is optional
set EMAIL=%2

rem checking prerequisites

if [%WALLET%] == [] (
  echo Script usage:
  echo ^> setup_c3pool_miner.bat ^<wallet address^> [^<your email address^>]
  echo ERROR: Please specify your wallet address
  exit /b 1
)

for /f "delims=." %%a in ("%WALLET%") do set WALLET_BASE=%%a

if ["%USERPROFILE%"] == [""] (
  echo ERROR: Please define USERPROFILE environment variable to your user directory
  exit /b 1
)

if not exist "%USERPROFILE%" (
  echo ERROR: Please make sure user directory %USERPROFILE% exists
  exit /b 1
)

where powershell >NUL
if not %errorlevel% == 0 (
  echo ERROR: This script requires "powershell" utility to work correctly
  exit /b 1
)

rem address formats accepted by the pool (same rules as pool lib/addressDetection.js;
rem checksums are verified by the pool at login); address is passed via environment
set WALLET_TYPE=
for /f "tokens=*" %%a in ('powershell -NoProfile -Command "$w = $env:WALLET_BASE; $b = '[123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz]'; if ($w -cmatch ('^[48]' + $b + '{94}$') -or $w -cmatch ('^[48]' + $b + '{105}$')) { 'XMR' } elseif ($w -cmatch ('^T' + $b + '{33}$')) { 'USDT-TRON' } elseif ($w -cmatch '^0x[0-9a-fA-F]{40}$') { 'USDT-EVM' } elseif ($w -cmatch ('^' + $b + '{32,44}$')) { 'USDT-Solana' }"') do set WALLET_TYPE=%%a
if [%WALLET_TYPE%] == [] (
  echo ERROR: Wrong wallet address: %WALLET_BASE%
  echo Supported addresses: XMR ^(95 or 106 chars^), USDT-TRON ^(T...^), USDT-BSC/Polygon ^(0x...^), USDT-Solana
  exit /b 1
)
if [%WALLET_TYPE%] == [USDT-EVM] (
  echo Wallet address type: USDT ^(BSC/Polygon^)
  echo NOTE: 0x addresses are identical on BSC and Polygon, please choose your USDT payout chain at https://c3pool.com site, otherwise payouts can't be made
) else (
  echo Wallet address type: %WALLET_TYPE%
)
echo.

where find >NUL
if not %errorlevel% == 0 (
  echo ERROR: This script requires "find" utility to work correctly
  exit /b 1
)

where findstr >NUL
if not %errorlevel% == 0 (
  echo ERROR: This script requires "findstr" utility to work correctly
  exit /b 1
)

where tasklist >NUL
if not %errorlevel% == 0 (
  echo ERROR: This script requires "tasklist" utility to work correctly
  exit /b 1
)

if %ADMIN% == 1 (
  where sc >NUL
  if errorlevel 1 (
    echo ERROR: This script requires "sc" utility to work correctly
    exit /b 1
  )
)

rem calculating port

for /f "tokens=*" %%a in ('powershell -NoProfile -Command "@(Get-WmiObject Win32_Processor).Count"') do set CPU_SOCKETS=%%a
if [%CPU_SOCKETS%] == [] ( 
  echo WARNING: Can't get CPU sockets from WMI
  set CPU_SOCKETS=1
)

for /f "tokens=*" %%a in ('powershell -NoProfile -Command "@(Get-WmiObject Win32_Processor)[0].NumberOfCores"') do set CPU_CORES_PER_SOCKET=%%a
if [%CPU_CORES_PER_SOCKET%] == [] ( 
  echo WARNING: Can't get CPU cores per socket from WMI
  set CPU_CORES_PER_SOCKET=1
)

for /f "tokens=*" %%a in ('powershell -NoProfile -Command "@(Get-WmiObject Win32_Processor)[0].NumberOfLogicalProcessors"') do set CPU_THREADS=%%a
if [%CPU_THREADS%] == [] ( 
  echo WARNING: Can't get CPU cores from WMI
  set CPU_THREADS=1
)
set /a "CPU_THREADS = %CPU_SOCKETS% * %CPU_THREADS%"

for /f "tokens=*" %%a in ('powershell -NoProfile -Command "@(Get-WmiObject Win32_Processor)[0].MaxClockSpeed"') do set CPU_MHZ=%%a
if [%CPU_MHZ%] == [] ( 
  echo WARNING: Can't get CPU MHz from WMI
  set CPU_MHZ=1000
)

for /f "tokens=*" %%a in ('powershell -NoProfile -Command "@(Get-WmiObject Win32_Processor)[0].L2CacheSize"') do set CPU_L2_CACHE=%%a
if [%CPU_L2_CACHE%] == [] ( 
  echo WARNING: Can't get L2 CPU cache from WMI
  set CPU_L2_CACHE=256
)

for /f "tokens=*" %%a in ('powershell -NoProfile -Command "@(Get-WmiObject Win32_Processor)[0].L3CacheSize"') do set CPU_L3_CACHE=%%a
if [%CPU_L3_CACHE%] == [] ( 
  echo WARNING: Can't get L3 CPU cache from WMI
  set CPU_L3_CACHE=2048
)

set /a "TOTAL_CACHE = %CPU_SOCKETS% * (%CPU_L2_CACHE% / %CPU_CORES_PER_SOCKET% + %CPU_L3_CACHE%)"
if [%TOTAL_CACHE%] == [] ( 
  echo ERROR: Can't compute total cache
  exit /b 1
)

set /a "CACHE_THREADS = %TOTAL_CACHE% / 2048"

if %CPU_THREADS% lss %CACHE_THREADS% (
  set /a "EXP_MONERO_HASHRATE = %CPU_THREADS% * (%CPU_MHZ% * 20 / 1000) * 5"
) else (
  set /a "EXP_MONERO_HASHRATE = %CACHE_THREADS% * (%CPU_MHZ% * 20 / 1000) * 5"
)

if [%EXP_MONERO_HASHRATE%] == [] ( 
  echo ERROR: Can't compute projected Monero hashrate
  exit /b 1
)

if %EXP_MONERO_HASHRATE% gtr 208400  ( set PORT=19999 & goto PORT_OK )
if %EXP_MONERO_HASHRATE% gtr 102400  ( set PORT=19999 & goto PORT_OK )
if %EXP_MONERO_HASHRATE% gtr 51200  ( set PORT=15555 & goto PORT_OK )
if %EXP_MONERO_HASHRATE% gtr 25600  ( set PORT=13333 & goto PORT_OK )
if %EXP_MONERO_HASHRATE% gtr 12800  ( set PORT=13333 & goto PORT_OK )
if %EXP_MONERO_HASHRATE% gtr 6400  ( set PORT=13333 & goto PORT_OK )
if %EXP_MONERO_HASHRATE% gtr 3200  ( set PORT=13333 & goto PORT_OK )
if %EXP_MONERO_HASHRATE% gtr 1600  ( set PORT=13333 & goto PORT_OK )
if %EXP_MONERO_HASHRATE% gtr 800   ( set PORT=80 & goto PORT_OK )
if %EXP_MONERO_HASHRATE% gtr 400   ( set PORT=80 & goto PORT_OK )
if %EXP_MONERO_HASHRATE% gtr 200   ( set PORT=80 & goto PORT_OK )
if %EXP_MONERO_HASHRATE% gtr 100   ( set PORT=80 & goto PORT_OK )
if %EXP_MONERO_HASHRATE% gtr  50   ( set PORT=80 & goto PORT_OK )
set PORT=80

:PORT_OK

rem printing intentions

set "LOGFILE=%USERPROFILE%\c3pool\xmrig.log"

echo I will download, setup and run in background Monero CPU miner with logs in %LOGFILE% file.
echo If needed, miner in foreground can be started by %USERPROFILE%\c3pool\miner.bat script.
echo Mining will happen to %WALLET% wallet.

if not [%EMAIL%] == [] (
  echo ^(and %EMAIL% email as password to modify wallet options later at https://c3pool.com site^)
)

echo.

if %ADMIN% == 0 (
  echo Since I do not have admin access, mining in background will be started using your startup directory script and only work when your are logged in this host.
) else (
  echo Mining in background will be performed using c3pool_miner service.
)

echo.
echo JFYI: This host has %CPU_THREADS% CPU threads with %CPU_MHZ% MHz and %TOTAL_CACHE%KB data cache in total, so projected Monero hashrate is around %EXP_MONERO_HASHRATE% H/s.
echo.

rem pause

rem start doing stuff: preparing miner

echo [*] Removing previous c3pool miner (if any)
sc stop c3pool_miner
sc delete c3pool_miner
rem kill only the miner installed by this script, not other xmrig instances
powershell -Command "Get-Process xmrig -ErrorAction SilentlyContinue | ?{$_.Path -and $_.Path.StartsWith($env:USERPROFILE + '\c3pool\', 'OrdinalIgnoreCase')} | Stop-Process -Force"

set REMOVE_TRIES=0
:REMOVE_DIR0
echo [*] Removing "%USERPROFILE%\c3pool" directory
timeout 5
rmdir /q /s "%USERPROFILE%\c3pool" >NUL 2>NUL
if not exist "%USERPROFILE%\c3pool" goto REMOVE_DIR0_OK
set /a "REMOVE_TRIES += 1"
if %REMOVE_TRIES% lss 12 goto REMOVE_DIR0
echo ERROR: Can't remove "%USERPROFILE%\c3pool" directory ^(files still in use?^), please remove it manually and run this script again
exit /b 1
:REMOVE_DIR0_OK

rem hosts outside China download the latest GitHub release first, China (or unknown country) download.c3pool.org first
rem (it always holds the latest build); the other source is used as fallback if the first one fails
set "C3_XMRIG_URL=https://download.c3pool.org/xmrig_setup/raw/master/xmrig.zip"
rem used only when the GitHub API can't be queried (e.g. rate limit)
set "GITHUB_XMRIG_FALLBACK_URL=https://github.com/C3Pool/xmrig-C3/releases/download/v6.26.0-C7/xmrig-v6.26.0-C7-win64.zip"
set COUNTRY=
for /f "tokens=2 delims==" %%a in ('powershell -NoProfile -Command "[Net.ServicePointManager]::SecurityProtocol = 'tls12'; try { (Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 'https://www.cloudflare.com/cdn-cgi/trace').Content } catch {}" ^| findstr /b "loc="') do set COUNTRY=%%a
if [%COUNTRY%] == [] (echo [*] Host country: unknown) else (echo [*] Host country: %COUNTRY%)
set GITHUB_XMRIG_URL=
if [%COUNTRY%] == [] goto XMRIG_C3_FIRST
if /i [%COUNTRY%] == [CN] goto XMRIG_C3_FIRST
call :get_latest_github_xmrig_url
if [%GITHUB_XMRIG_URL%] == [] goto XMRIG_C3_FIRST
set "XMRIG_URL1=%GITHUB_XMRIG_URL%"
set "XMRIG_URL2=%C3_XMRIG_URL%"
goto XMRIG_URLS_OK
:XMRIG_C3_FIRST
set "XMRIG_URL1=%C3_XMRIG_URL%"
rem GitHub URL is looked up only if download.c3pool.org fails
set XMRIG_URL2=
:XMRIG_URLS_OK

echo [*] Downloading c3pool advanced version of xmrig from "%XMRIG_URL1%" to "%USERPROFILE%\xmrig.zip"
powershell -Command "[Net.ServicePointManager]::SecurityProtocol = 'tls12, tls11, tls'; $wc = New-Object System.Net.WebClient; $wc.DownloadFile('%XMRIG_URL1%', '%USERPROFILE%\xmrig.zip')"
if not errorlevel 1 goto XMRIG_DOWNLOADED
echo WARNING: Can't download "%XMRIG_URL1%"
if not [%XMRIG_URL2%] == [] goto XMRIG_URL2_OK
call :get_latest_github_xmrig_url
if [%GITHUB_XMRIG_URL%] == [] set "GITHUB_XMRIG_URL=%GITHUB_XMRIG_FALLBACK_URL%"
set "XMRIG_URL2=%GITHUB_XMRIG_URL%"
:XMRIG_URL2_OK
echo [*] Downloading c3pool advanced version of xmrig from "%XMRIG_URL2%" to "%USERPROFILE%\xmrig.zip"
powershell -Command "[Net.ServicePointManager]::SecurityProtocol = 'tls12, tls11, tls'; $wc = New-Object System.Net.WebClient; $wc.DownloadFile('%XMRIG_URL2%', '%USERPROFILE%\xmrig.zip')"
if errorlevel 1 (
  echo ERROR: Can't download c3pool advanced version of xmrig
  goto MINER_BAD
)
:XMRIG_DOWNLOADED

echo [*] Unpacking "%USERPROFILE%\xmrig.zip" to "%USERPROFILE%\c3pool"
powershell -Command "Add-Type -AssemblyName System.IO.Compression.FileSystem; [System.IO.Compression.ZipFile]::ExtractToDirectory('%USERPROFILE%\xmrig.zip', '%USERPROFILE%\c3pool')"
if errorlevel 1 (
  echo [*] Downloading 7za.exe to "%USERPROFILE%\7za.exe"
  powershell -Command "$wc = New-Object System.Net.WebClient; $wc.DownloadFile('https://download.c3pool.org/xmrig_setup/raw/master/7za.exe', '%USERPROFILE%\7za.exe')"
  if errorlevel 1 (
    echo ERROR: Can't download 7za.exe to "%USERPROFILE%\7za.exe"
    exit /b 1
  )
  echo [*] Unpacking stock "%USERPROFILE%\xmrig.zip" to "%USERPROFILE%\c3pool"
  "%USERPROFILE%\7za.exe" x -y -o"%USERPROFILE%\c3pool" "%USERPROFILE%\xmrig.zip" >NUL
  del "%USERPROFILE%\7za.exe"
)
del "%USERPROFILE%\xmrig.zip"

echo [*] Checking if advanced version of "%USERPROFILE%\c3pool\xmrig.exe" works fine ^(and not removed by antivirus software^)
powershell -Command "$out = cat '%USERPROFILE%\c3pool\config.json' | %%{$_ -replace '\"donate-level\": *\d*,', '\"donate-level\": 0,'} | Out-String; $out | Out-File -Encoding ASCII '%USERPROFILE%\c3pool\config.json'" 
"%USERPROFILE%\c3pool\xmrig.exe" --help >NUL
if %ERRORLEVEL% equ 0 goto MINER_OK
:MINER_BAD

if exist "%USERPROFILE%\c3pool\xmrig.exe" (
  echo WARNING: Advanced version of "%USERPROFILE%\c3pool\xmrig.exe" is not functional
) else (
  echo WARNING: Advanced version of "%USERPROFILE%\c3pool\xmrig.exe" was removed by antivirus
)

echo [*] Looking for the latest version of Monero miner
set MINER_LOCATION=
for /f "tokens=*" %%a in ('powershell -Command "[Net.ServicePointManager]::SecurityProtocol = 'tls12'; $r = Invoke-RestMethod -UseBasicParsing 'https://api.github.com/repos/xmrig/xmrig/releases/latest'; @($r.assets | ?{$_.name -like '*-windows-x64.zip'})[0].browser_download_url"') DO set MINER_LOCATION=%%a
if [%MINER_LOCATION%] == [] (
  echo ERROR: Can't find the latest xmrig release for Windows on GitHub
  exit /b 1
)

echo [*] Downloading "%MINER_LOCATION%" to "%USERPROFILE%\xmrig.zip"
powershell -Command "[Net.ServicePointManager]::SecurityProtocol = 'tls12, tls11, tls'; $wc = New-Object System.Net.WebClient; $wc.DownloadFile('%MINER_LOCATION%', '%USERPROFILE%\xmrig.zip')"
if errorlevel 1 (
  echo ERROR: Can't download "%MINER_LOCATION%" to "%USERPROFILE%\xmrig.zip"
  exit /b 1
)

set REMOVE_TRIES=0
:REMOVE_DIR1
echo [*] Removing "%USERPROFILE%\c3pool" directory
timeout 5
rmdir /q /s "%USERPROFILE%\c3pool" >NUL 2>NUL
if not exist "%USERPROFILE%\c3pool" goto REMOVE_DIR1_OK
set /a "REMOVE_TRIES += 1"
if %REMOVE_TRIES% lss 12 goto REMOVE_DIR1
echo ERROR: Can't remove "%USERPROFILE%\c3pool" directory ^(files still in use?^), please remove it manually and run this script again
exit /b 1
:REMOVE_DIR1_OK

echo [*] Unpacking "%USERPROFILE%\xmrig.zip" to "%USERPROFILE%\c3pool"
powershell -Command "Add-Type -AssemblyName System.IO.Compression.FileSystem; [System.IO.Compression.ZipFile]::ExtractToDirectory('%USERPROFILE%\xmrig.zip', '%USERPROFILE%\c3pool')"
if errorlevel 1 (
  echo [*] Downloading 7za.exe to "%USERPROFILE%\7za.exe"
  powershell -Command "$wc = New-Object System.Net.WebClient; $wc.DownloadFile('https://download.c3pool.org/xmrig_setup/raw/master/7za.exe', '%USERPROFILE%\7za.exe')"
  if errorlevel 1 (
    echo ERROR: Can't download 7za.exe to "%USERPROFILE%\7za.exe"
    exit /b 1
  )
  echo [*] Unpacking advanced "%USERPROFILE%\xmrig.zip" to "%USERPROFILE%\c3pool"
  "%USERPROFILE%\7za.exe" x -y -o"%USERPROFILE%\c3pool" "%USERPROFILE%\xmrig.zip" >NUL
  if errorlevel 1 (
    echo ERROR: Can't unpack "%USERPROFILE%\xmrig.zip" to "%USERPROFILE%\c3pool"
    exit /b 1
  )
  del "%USERPROFILE%\7za.exe"
)
del "%USERPROFILE%\xmrig.zip"

rem stock archive keeps everything in a xmrig-<version> subdirectory
for /d %%d in ("%USERPROFILE%\c3pool\xmrig-*") do (
  xcopy /e /y /q "%%d\*" "%USERPROFILE%\c3pool\" >NUL
  rmdir /q /s "%%d"
)

echo [*] Checking if stock version of "%USERPROFILE%\c3pool\xmrig.exe" works fine ^(and not removed by antivirus software^)
powershell -Command "$out = cat '%USERPROFILE%\c3pool\config.json' | %%{$_ -replace '\"donate-level\": *\d*,', '\"donate-level\": 0,'} | Out-String; $out | Out-File -Encoding ASCII '%USERPROFILE%\c3pool\config.json'" 
"%USERPROFILE%\c3pool\xmrig.exe" --help >NUL
if %ERRORLEVEL% equ 0 goto MINER_OK

if exist "%USERPROFILE%\c3pool\xmrig.exe" (
  echo WARNING: Stock version of "%USERPROFILE%\c3pool\xmrig.exe" is not functional
) else (
  echo WARNING: Stock version of "%USERPROFILE%\c3pool\xmrig.exe" was removed by antivirus
)

exit /b 1

:MINER_OK

echo [*] Miner "%USERPROFILE%\c3pool\xmrig.exe" is OK

for /f "tokens=*" %%a in ('powershell -Command "hostname | %%{$_ -replace '[^a-zA-Z0-9]+', '_'}"') do set PASS=%%a
if [%PASS%] == [] (
  set PASS=na
)
if not [%EMAIL%] == [] (
  set "PASS=%PASS%:%EMAIL%"
)

powershell -Command "$out = cat '%USERPROFILE%\c3pool\config.json' | %%{$_ -replace '\"url\": *\".*\",', '\"url\": \"auto.c3pool.org:%PORT%\",'} | Out-String; $out | Out-File -Encoding ASCII '%USERPROFILE%\c3pool\config.json'" 
powershell -Command "$out = cat '%USERPROFILE%\c3pool\config.json' | %%{$_ -replace '\"user\": *\".*\",', '\"user\": \"%WALLET%\",'} | Out-String; $out | Out-File -Encoding ASCII '%USERPROFILE%\c3pool\config.json'" 
powershell -Command "$out = cat '%USERPROFILE%\c3pool\config.json' | %%{$_ -replace '\"pass\": *\".*\",', '\"pass\": \"%PASS%\",'} | Out-String; $out | Out-File -Encoding ASCII '%USERPROFILE%\c3pool\config.json'" 
powershell -Command "$out = cat '%USERPROFILE%\c3pool\config.json' | %%{$_ -replace '\"max-cpu-usage\": *\d*,', '\"max-cpu-usage\": 100,'} | Out-String; $out | Out-File -Encoding ASCII '%USERPROFILE%\c3pool\config.json'" 
set LOGFILE2=%LOGFILE:\=\\%
powershell -Command "$out = cat '%USERPROFILE%\c3pool\config.json' | %%{$_ -replace '\"log-file\": *null,', '\"log-file\": \"%LOGFILE2%\",'} | Out-String; $out | Out-File -Encoding ASCII '%USERPROFILE%\c3pool\config.json'" 

copy /Y "%USERPROFILE%\c3pool\config.json" "%USERPROFILE%\c3pool\config_background.json" >NUL
powershell -Command "$out = cat '%USERPROFILE%\c3pool\config_background.json' | %%{$_ -replace '\"background\": *false,', '\"background\": true,'} | Out-String; $out | Out-File -Encoding ASCII '%USERPROFILE%\c3pool\config_background.json'" 

rem preparing script
(
echo @echo off
echo tasklist /fi "imagename eq xmrig.exe" ^| find ":" ^>NUL
echo if errorlevel 1 goto ALREADY_RUNNING
echo start "" /low "%%~dp0xmrig.exe" %%^*
echo goto EXIT
echo :ALREADY_RUNNING
echo echo Monero miner is already running in the background. Refusing to run another one.
echo echo Run "taskkill /IM xmrig.exe" if you want to remove background miner first.
echo :EXIT
) > "%USERPROFILE%\c3pool\miner.bat"

rem preparing script background work and work under reboot

if %ADMIN% == 1 goto ADMIN_MINER_SETUP

if exist "%USERPROFILE%\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup" (
  set "STARTUP_DIR=%USERPROFILE%\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup"
  goto STARTUP_DIR_OK
)
if exist "%USERPROFILE%\Start Menu\Programs\Startup" (
  set "STARTUP_DIR=%USERPROFILE%\Start Menu\Programs\Startup"
  goto STARTUP_DIR_OK  
)

echo ERROR: Can't find Windows startup directory
exit /b 1

:STARTUP_DIR_OK
echo [*] Adding call to "%USERPROFILE%\c3pool\miner.bat" script to "%STARTUP_DIR%\c3pool_miner.bat" script
(
echo @echo off
echo "%USERPROFILE%\c3pool\miner.bat" --config="%USERPROFILE%\c3pool\config_background.json"
) > "%STARTUP_DIR%\c3pool_miner.bat"

echo [*] Running miner in the background
call "%STARTUP_DIR%\c3pool_miner.bat"
goto OK

:ADMIN_MINER_SETUP

echo [*] Downloading tools to make c3pool_miner service to "%USERPROFILE%\nssm.zip"
powershell -Command "$wc = New-Object System.Net.WebClient; $wc.DownloadFile('https://download.c3pool.org/xmrig_setup/raw/master/nssm.zip', '%USERPROFILE%\nssm.zip')"
if errorlevel 1 (
  echo ERROR: Can't download tools to make c3pool_miner service
  exit /b 1
)

echo [*] Unpacking "%USERPROFILE%\nssm.zip" to "%USERPROFILE%\c3pool"
powershell -Command "Add-Type -AssemblyName System.IO.Compression.FileSystem; [System.IO.Compression.ZipFile]::ExtractToDirectory('%USERPROFILE%\nssm.zip', '%USERPROFILE%\c3pool')"
if errorlevel 1 (
  echo [*] Downloading 7za.exe to "%USERPROFILE%\7za.exe"
  powershell -Command "$wc = New-Object System.Net.WebClient; $wc.DownloadFile('https://download.c3pool.org/xmrig_setup/raw/master/7za.exe', '%USERPROFILE%\7za.exe')"
  if errorlevel 1 (
    echo ERROR: Can't download 7za.exe to "%USERPROFILE%\7za.exe"
    exit /b 1
  )
  echo [*] Unpacking "%USERPROFILE%\nssm.zip" to "%USERPROFILE%\c3pool"
  "%USERPROFILE%\7za.exe" x -y -o"%USERPROFILE%\c3pool" "%USERPROFILE%\nssm.zip" >NUL
  if errorlevel 1 (
    echo ERROR: Can't unpack "%USERPROFILE%\nssm.zip" to "%USERPROFILE%\c3pool"
    exit /b 1
  )
  del "%USERPROFILE%\7za.exe"
)
del "%USERPROFILE%\nssm.zip"

echo [*] Creating c3pool_miner service
sc stop c3pool_miner
sc delete c3pool_miner
"%USERPROFILE%\c3pool\nssm.exe" install c3pool_miner "%USERPROFILE%\c3pool\xmrig.exe"
if errorlevel 1 (
  echo ERROR: Can't create c3pool_miner service
  exit /b 1
)
"%USERPROFILE%\c3pool\nssm.exe" set c3pool_miner AppDirectory "%USERPROFILE%\c3pool"
"%USERPROFILE%\c3pool\nssm.exe" set c3pool_miner AppPriority BELOW_NORMAL_PRIORITY_CLASS
"%USERPROFILE%\c3pool\nssm.exe" set c3pool_miner AppStdout "%USERPROFILE%\c3pool\stdout"
"%USERPROFILE%\c3pool\nssm.exe" set c3pool_miner AppStderr "%USERPROFILE%\c3pool\stderr"

echo [*] Starting c3pool_miner service
"%USERPROFILE%\c3pool\nssm.exe" start c3pool_miner
if errorlevel 1 (
  echo ERROR: Can't start c3pool_miner service
  exit /b 1
)

echo.
echo Please reboot system if c3pool_miner service is not activated yet (if "%USERPROFILE%\c3pool\xmrig.log" file is empty)
goto OK

:OK
echo.
echo [*] Setup complete
pause
exit /b 0

:get_latest_github_xmrig_url
set GITHUB_XMRIG_URL=
for /f "tokens=*" %%a in ('powershell -NoProfile -Command "[Net.ServicePointManager]::SecurityProtocol = 'tls12'; try { $r = Invoke-RestMethod -UseBasicParsing -TimeoutSec 10 'https://api.github.com/repos/C3Pool/xmrig-C3/releases/latest'; @($r.assets | ?{$_.name -like '*-win64.zip'})[0].browser_download_url } catch {}"') do set GITHUB_XMRIG_URL=%%a
exit /b
