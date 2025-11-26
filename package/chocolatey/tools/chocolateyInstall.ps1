#!/usr/bin/env pwsh

$ErrorActionPreference = 'Stop'

Write-Host "Installing Ruby..."
choco install ruby -y

# Ensure Ruby bin directory is in PATH
$rubyPath = (Get-Command ruby).Source | Split-Path
if (-not ($env:PATH -like "*$rubyPath*")) {
    Write-Host "Adding Ruby to PATH..."
    $env:PATH += ";$rubyPath"
}

Write-Host "Installing aspera-cli gem (latest)..."
gem install aspera-cli

Write-Host "Configuring transfer daemon..."
ascli conf transferd install
