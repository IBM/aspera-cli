#!/usr/bin/env pwsh
# Main installation script for Aspera CLI on Windows
#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$AllUsers
)
$ErrorActionPreference = "Stop"

Write-Host "=== Aspera CLI Installer for Windows ===" -ForegroundColor Cyan

# 1. Determine installation scope
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($AllUsers) {
    if (-not $isAdmin) {
        Write-Error "The -AllUsers switch requires administrator privileges. Re-run as Administrator."
        exit 1
    }
    $systemWide = $true
} elseif ($isAdmin) {
    $choice = Read-Host "Install for (A)ll users (system-wide) or (C)urrent user? [A/C]"
    $systemWide = $choice -match '^[Aa]'
} else {
    Write-Host "Running without admin rights: installing for current user only." -ForegroundColor Yellow
    $systemWide = $false
}

# 2. Setup Paths
if ($systemWide) {
    $targetFolder = Join-Path (Join-Path $env:ProgramFiles "Aspera") "cli"
    $pathScope = "Machine"
    $rubyUserFlag = ""
} else {
    $targetFolder = Join-Path (Join-Path $env:LOCALAPPDATA "Aspera") "cli"
    $pathScope = "User"
    $rubyUserFlag = "/currentuser"
}
$binFolder = Join-Path $targetFolder "bin"
$null = New-Item -Path $targetFolder -ItemType Directory -Force

# 3. Install Ruby
Write-Host "Installing Ruby to $targetFolder..."
$rubyArgs = @("/silent", "/dir=`"$targetFolder`"", "/noicons")
if ($rubyUserFlag) { $rubyArgs += $rubyUserFlag }
Start-Process -FilePath (Join-Path $PSScriptRoot "<%=ruby_installer_exe%>") -ArgumentList $rubyArgs -Wait

# 4. Update Environment (Persistent and Session)
$existingPath = [Environment]::GetEnvironmentVariable("Path", $pathScope)
if (($existingPath -split ';') -notcontains $binFolder) {
    [Environment]::SetEnvironmentVariable("Path", "$existingPath;$binFolder", $pathScope)
}
$env:Path += ";$binFolder"

# 5. Dependencies & Gems
Write-Host "Installing MSVC Redistributable..."
Start-Process -FilePath (Join-Path $PSScriptRoot "<%=vc_redist_exe%>") -ArgumentList "/install", "/quiet" -Wait

# 6. Gems & SDK
Write-Host "Installing CLI gems..."
# Use Join-Path to ensure the globbing pattern works correctly
gem install --no-document --silent --force --local (Join-Path $PSScriptRoot "*.gem")

Write-Host "Installing Aspera SDK..."
ascli conf ascp install --sdk-url="file:///$($PSScriptRoot -replace '\\','/')/<%=sdk_file%>"

Write-Host "Success! Aspera CLI is ready." -ForegroundColor Green
