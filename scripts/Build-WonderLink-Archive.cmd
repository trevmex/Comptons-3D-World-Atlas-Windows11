@echo off
setlocal
set "ROOT=%~dp0.."
set "BUILD=%ROOT%\build"
if not exist "%BUILD%" mkdir "%BUILD%"

if defined VSDEVCMD (
  call "%VSDEVCMD%" -no_logo -arch=x86 -host_arch=x64
) else (
  set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
  if exist "%VSWHERE%" (
    for /f "usebackq delims=" %%V in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSROOT=%%V"
  )
  if defined VSROOT (
    call "%VSROOT%\Common7\Tools\VsDevCmd.bat" -no_logo -arch=x86 -host_arch=x64
  ) else if exist "C:\VSBT\Common7\Tools\VsDevCmd.bat" (
    call "C:\VSBT\Common7\Tools\VsDevCmd.bat" -no_logo -arch=x86 -host_arch=x64
  ) else if defined VCToolsInstallDir (
    rem The caller already initialized an MSVC developer environment.
  ) else if defined VCINSTALLDIR (
    rem The caller already initialized an MSVC developer environment.
  ) else (
    echo Visual Studio Build Tools with the x86 C++ workload is required. 1>&2
    exit /b 2
  )
)
if errorlevel 1 exit /b %errorlevel%

cl.exe /nologo /O2 /W4 /GS /DUNICODE /D_UNICODE /LD /MT ^
  /Fo"%BUILD%\Atlas-WonderLink-Archive.obj" /Fe"%BUILD%\Wlbrw32.dll" ^
  "%ROOT%\src\Atlas-WonderLink-Archive.c" ^
  /link /DEF:"%ROOT%\src\Wlbrw32.def" /OUT:"%BUILD%\Wlbrw32.dll" user32.lib shell32.lib
exit /b %errorlevel%
