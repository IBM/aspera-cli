@echo off
REM ====================================================
REM Aspera CLI launcher (portable package)
REM Uses the Ruby, gems and SDK located next to this script
REM ====================================================
setlocal
set "ASCLI_ROOT=%~dp0"
set "GEM_HOME=%ASCLI_ROOT%gems"
if not defined ASCLI_SDK_FOLDER set "ASCLI_SDK_FOLDER=%ASCLI_ROOT%sdk"
"%ASCLI_ROOT%ruby\bin\ruby.exe" "%ASCLI_ROOT%gems\bin\ascli" %*
exit /b %ERRORLEVEL%
