#!/usr/bin/env pwsh
$ErrorActionPreference = "Stop"

Write-Host "=== Aspera CLI Installer for Windows ==="

# Get the directory where the script resides
# Paths to required files (relative to script)
$resourcesDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$rubyInstaller = Join-Path $resourcesDir "<%=ruby_installer_exe%>"
$vcRedist = Join-Path $resourcesDir "<%=vc_redist_exe%>"
$asperaSdkZip = Join-Path $resourcesDir "<%=sdk_file%>"

# User or Machine
$installFor = "User"

# Set target install directory
$targetFolder = "$HOME\AppData\Local\Aspera\cli"
$binFolder = Join-Path $targetFolder "bin"
Write-Host "Installing Aspera CLI in: $targetFolder"

# Ensure install folder exists
if (!(Test-Path -Path $targetFolder)) {
    New-Item -Path $targetFolder -ItemType Directory -Force | Out-Null
}

# Install Ruby silently
Write-Host "Installing Ruby..."
Start-Process -FilePath $rubyInstaller -ArgumentList "/suppressmsgboxes", "/currentuser", "/silent", "/noicons", "/dir=$targetFolder" -Wait

# Add to PATH if not already present : User -> Machine
$sysPath = [Environment]::GetEnvironmentVariable("Path", $installFor)
if ($sysPath -notlike "*$binFolder*") {
    Write-Host "Adding $binFolder to $installFor PATH..."
    $newSysPath = "$sysPath;$binFolder"
    [Environment]::SetEnvironmentVariable("Path", $newSysPath, $installFor)
}
else {
    Write-Host "Path already contains $binFolder"
}
# Add path for this script for `gem` and `ascli`
$env:Path = "$env:Path;$binFolder"

# Install MSVC redistributables
Write-Host "Installing MS Visual C++ redistributables..."
Start-Process -FilePath $vcRedist -ArgumentList "/install", "/quiet" -Wait

# Install all gems at once
Write-Host "Installing CLI gems..."
gem install --no-document --silent --force --local "$resourcesDir\*.gem"

# Install Aspera SDK
Write-Host "Installing Aspera SDK..."
ascli conf ascp install --sdk-url="file:///$asperaSdkZip"

# Done
Write-Host "Aspera CLI installed in: $binFolder"
Write-Host "You may need to restart your terminal or log out/in for PATH changes to take effect."
