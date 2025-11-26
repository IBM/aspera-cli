#!/usr/bin/env pwsh

$ErrorActionPreference = 'Stop'

Write-Host "Uninstalling aspera-cli gem..."
gem uninstall aspera-cli -a -x
