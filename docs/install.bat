@echo off
echo Aspera CLI Installer script for Windows
rem This is the installation folder
SET TARGET_FOLDER=%USERPROFILE%\aspera-cli
echo Installing Aspera CLI in %TARGET_FOLDER%
rubyinstaller-devkit-3.2.2-1-x64.exe /silent /currentuser /noicons /dir=%TARGET_FOLDER%
echo Installing CLI gems
call %TARGET_FOLDER%\bin\gem install --no-document --silent --force --local cli-gems\*.gem
echo Installing MS redis libs
vc_redist.x64.exe /install /passive
echo Installing Aspera SDK
call %TARGET_FOLDER%\bin\ascli conf ascp install --sdk-url=file:///sdk.zip
echo Aspera Cli is installed at: %TARGET_FOLDER%\bin
echo SET PATH=%%PATH%%;C:\Users\Administrator\aspera-cli\bin
