#!/usr/bin/env pwsh
$ErrorActionPreference = "Stop"

Write-Host "=== Aspera CLI Installer for Windows ==="

# Get the directory where the script resides
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

# Paths to required files (relative to script)
$rubyInstaller = Join-Path $scriptDir "rubyinstaller-devkit-3.3.8-1-x64.exe"
$vcRedist = Join-Path $scriptDir "vc_redist.x64.exe"
$cliGemsZip = Join-Path $scriptDir "cli-gems.zip"
$asperaSdkZip = Join-Path $scriptDir "ibm-aspera-transfer-sdk-windows-amd64-1.1.5.zip"

# Set target install directory
$targetFolder = "$env:ProgramFiles\Aspera\cli"
$binFolder = Join-Path $targetFolder "bin"
Write-Host "Installing Aspera CLI in: $targetFolder"

# Ensure install folder exists
if (!(Test-Path -Path $targetFolder)) {
    New-Item -Path $targetFolder -ItemType Directory -Force | Out-Null
}

# Install Ruby silently
Start-Process -FilePath $rubyInstaller `
    -ArgumentList "/silent", "/noicons", "/dir=$targetFolder" `
    -Wait

# Extract CLI gems to a temp directory
$tempGemDir = Join-Path $env:TEMP "cli_gems_temp"
if (Test-Path $tempGemDir) {
    Remove-Item -Recurse -Force $tempGemDir
}
Expand-Archive -Path $cliGemsZip -DestinationPath $tempGemDir -Force

# Install all gems at once
$gemExe = Join-Path $binFolder "gem"
Write-Host "Installing CLI gems from zip..."
& $gemExe install --no-document --silent --force --local "$tempGemDir\*.gem"

# Clean up temp files
Remove-Item -Recurse -Force $tempGemDir

# Install MSVC redistributables
Write-Host "Installing MS Visual C++ redistributables..."
Start-Process -FilePath $vcRedist -ArgumentList "/install", "/passive" -Wait

# Install Aspera SDK
$ascliExe = Join-Path $binFolder "ascli"
Write-Host "Installing Aspera SDK..."
& $ascliExe conf ascp install --sdk-url="file:///$asperaSdkZip"

# Add to system-wide PATH if not already present
$sysPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
if ($sysPath -notlike "*$binFolder*") {
    Write-Host "Adding $binFolder to system PATH..."
    $newSysPath = "$sysPath;$binFolder"
    [Environment]::SetEnvironmentVariable("Path", $newSysPath, "Machine")
}
else {
    Write-Host "Path already contains $binFolder"
}

# Done
Write-Host "✅ Aspera CLI installed in: $binFolder"
Write-Host "🖥️ You may need to restart your terminal or log out/in for PATH changes to take effect."
