#!/usr/bin/env pwsh
$ErrorActionPreference = "Stop"

Write-Host "=== Aspera CLI Installer for Windows ==="

# Get the directory where the script resides
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

# Paths to required files (relative to script)
$archiveDir = Join-Path $scriptDir "resources"
$rubyInstaller = Join-Path $archiveDir "<%=ruby_installer_exe%>"
$vcRedist = Join-Path $archiveDir "<%=vc_redist_exe%>"
$asperaSdkZip = Join-Path $archiveDir "<%=sdk_file%>"
$gemArchiveDir = $archiveDir
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
# Install all gems at once
$gemExe = Join-Path $binFolder "gem"
Write-Host "Installing CLI gems..."
& $gemExe install --no-document --silent --force --local "$gemArchiveDir\*.gem"

# Install MSVC redistributables
Write-Host "Installing MS Visual C++ redistributables..."
Start-Process -FilePath $vcRedist -ArgumentList "/install", "/passive" -Wait

# Install Aspera SDK
$ascliExe = Join-Path $binFolder "ascli"
Write-Host "Installing Aspera SDK..."
& $ascliExe conf ascp install --sdk-url="file:///$asperaSdkZip"

# Done
Write-Host "Aspera CLI installed in: $binFolder"
Write-Host "You may need to restart your terminal or log out/in for PATH changes to take effect."
