@if "%DEBUG%" == "" @echo off
@rem ##########################################################################
@rem
@rem  Hvigor startup script for Windows
@rem
@rem ##########################################################################

@rem Set local scope for the variables with windows NT shell
if "%OS%"=="Windows_NT" setlocal

set DIRNAME=%~dp0
if "%DIRNAME%" == "" set DIRNAME=.
set APP_BASE_NAME=%~n0
set APP_HOME=%DIRNAME%

@rem Resolve any "." and ".." in APP_HOME to make it shorter.
for %%i in ("%APP_HOME%") do set APP_HOME=%%~fi

@rem ---------------------------------------------------------------------------
@rem Locate DevEco Studio so this wrapper works outside the IDE.
@rem The IDE normally injects these variables; when they are missing we derive
@rem them from the installed toolchain (env var, common paths, then registry).
@rem ---------------------------------------------------------------------------
if not defined DEVECO_SDK_HOME if defined DEVECO_STUDIO_PATH if exist "%DEVECO_STUDIO_PATH%\sdk" set DEVECO_SDK_HOME=%DEVECO_STUDIO_PATH%\sdk
if not defined DEVECO_SDK_HOME if exist "%ProgramFiles%\Huawei\DevEco Studio\sdk" set DEVECO_SDK_HOME=%ProgramFiles%\Huawei\DevEco Studio\sdk
if not defined DEVECO_SDK_HOME if exist "D:\HUAWEI\DevEco Studio\sdk" set DEVECO_SDK_HOME=D:\HUAWEI\DevEco Studio\sdk
if not defined DEVECO_SDK_HOME for /f "tokens=2,*" %%a in ('reg query "HKCU\Software\Huawei\DevEcoStudio" /v "DevEcoStudioPath" 2^>nul') do if exist "%%b\sdk" set DEVECO_SDK_HOME=%%b\sdk
if not defined DEVECO_SDK_HOME for /f "tokens=2,*" %%a in ('reg query "HKLM\Software\Huawei\DevEcoStudio" /v "DevEcoStudioPath" 2^>nul') do if exist "%%b\sdk" set DEVECO_SDK_HOME=%%b\sdk
if not defined DEVECO_SDK_HOME for /f "tokens=*" %%a in ('reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall" /s /f "DevEco Studio" /d 2^>nul ^| findstr /i /c:"InstallLocation"') do call :setSdkFromReg "%%a"
if not defined DEVECO_SDK_HOME for /f "tokens=*" %%a in ('reg query "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall" /s /f "DevEco Studio" /d 2^>nul ^| findstr /i /c:"InstallLocation"') do call :setSdkFromReg "%%a"
goto afterSdkProbe

:setSdkFromReg
set "_REG_LINE=%~1"
set "_REG_LINE=%_REG_LINE:*REG_SZ=%"
for /f "tokens=* delims= " %%p in ("%_REG_LINE%") do if not defined DEVECO_SDK_HOME if exist "%%p\sdk" set DEVECO_SDK_HOME=%%p\sdk
goto :eof

:afterSdkProbe

if not defined NODE_HOME if defined DEVECO_SDK_HOME if exist "%DEVECO_SDK_HOME%\..\tools\node\node.exe" set NODE_HOME=%DEVECO_SDK_HOME%\..\tools\node
if not defined HVIGOR_TOOLS_HOME if defined DEVECO_SDK_HOME if exist "%DEVECO_SDK_HOME%\..\tools\hvigor\hvigor" set HVIGOR_TOOLS_HOME=%DEVECO_SDK_HOME%\..\tools\hvigor

if not defined DEVECO_SDK_HOME echo WARN: DevEco Studio was not found; set DEVECO_SDK_HOME to its "sdk" directory.
if not defined NODE_HOME echo WARN: node was not found; set NODE_HOME to the DevEco Studio node directory.

set WRAPPER_MODULE_PATH=%DIRNAME%\hvigorw.js
set NODE_EXE=node.exe
@rem set NODE_OPTS="--max-old-space-size=8192 --expose-gc"

goto start

:start
if not defined NODE_OPTS set NODE_OPTS="--"

@rem Find node.exe
if defined NODE_HOME goto findNodeFromNodeHome

%NODE_EXE% --version >NUL 2>&1
if "%ERRORLEVEL%" == "0" goto execute

echo.
echo ERROR: NODE_HOME is not set and no 'node' command could be found in your PATH.
echo.
echo Please set the NODE_HOME variable in your environment to match the
echo location of your NodeJs installation.

goto fail

:findNodeFromNodeHome
set NODE_HOME=%NODE_HOME:"=%
set NODE_EXE_PATH=%NODE_HOME%/%NODE_EXE%

if exist "%NODE_EXE_PATH%" goto execute
echo.
echo ERROR: NODE_HOME is not set and no 'node' command could be found in your PATH.
echo.
echo Please set the NODE_HOME variable in your environment to match the
echo location of your NodeJs installation.

goto fail

:execute
@rem Execute hvigor
"%NODE_EXE%" "%NODE_OPTS%" "%WRAPPER_MODULE_PATH%" %*

if "%ERRORLEVEL%" == "0" goto hvigorwEnd

:fail
exit /b 1

:hvigorwEnd
if "%OS%" == "Windows_NT" endlocal

:end
