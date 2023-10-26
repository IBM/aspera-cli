REM Automated installation of ascli on windows
REM Refer to the manual
@ECHO off
ECHO Aspera CLI Installer script for Windows
REM This is the installation folder
SET TARGET_FOLDER=%USERPROFILE%\aspera-cli
ECHO Installing Aspera CLI in %TARGET_FOLDER%
rubyinstaller-devkit-3.2.2-1-x64.exe /silent /currentuser /noicons /dir=%TARGET_FOLDER%
ECHO Installing CLI gems
REM On Windows, this is a wrapper script, so use CALL, else the script will exit
CALL %TARGET_FOLDER%\bin\gem install --no-document --silent --force --local cli-gems\*.gem
ECHO Installing MS redis libs
vc_redist.x64.exe /install /passive
ECHO Installing Aspera SDK
CALL %TARGET_FOLDER%\bin\ascli conf ascp install --sdk-url=file:///sdk.zip
ECHO Aspera Cli is installed at: %TARGET_FOLDER%\bin
ECHO SET PATH=%%PATH%%;%TARGET_FOLDER%\bin
