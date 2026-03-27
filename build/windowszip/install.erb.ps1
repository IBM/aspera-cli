#!/usr/bin/env pwsh
# Main installation script for Aspera CLI on Windows
$ErrorActionPreference = "Stop"

Write-Host "=== Aspera CLI Installer for Windows ===" -ForegroundColor Cyan

# 1. Setup Paths
$targetFolder = Join-Path $env:LOCALAPPDATA "Aspera", "cli"
$binFolder = Join-Path $targetFolder "bin"
$null = New-Item -Path $targetFolder -ItemType Directory -Force

# 2. Install Ruby
Write-Host "Installing Ruby to $targetFolder..."
Start-Process -FilePath (Join-Path $PSScriptRoot "<%=ruby_installer_exe%>") `
    -ArgumentList "/silent", "/currentuser", "/dir=`"$targetFolder`"", "/noicons" -Wait

# 3. Update Environment (Persistent and Session)
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if (($userPath -split ';') -notin $binFolder) {
    [Environment]::SetEnvironmentVariable("Path", "$userPath;$binFolder", "User")
}
$env:Path += ";$binFolder"

# 4. Dependencies & Gems
Write-Host "Installing MSVC Redistributable..."
Start-Process -FilePath (Join-Path $PSScriptRoot "<%=vc_redist_exe%>") -ArgumentList "/install", "/quiet" -Wait

Write-Host "Installing CLI gems..."
# Use Join-Path to ensure the globbing pattern works correctly
gem install --no-document --silent --force --local (Join-Path $PSScriptRoot "*.gem")

# 5. SDK Setup
Write-Host "Installing Aspera SDK..."
ascli conf ascp install --sdk-url="file:///$($PSScriptRoot -replace '\\','/')/<%=sdk_file%>"

Write-Host "Success! Aspera CLI is ready." -ForegroundColor Green
