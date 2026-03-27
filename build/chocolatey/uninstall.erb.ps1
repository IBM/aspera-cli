$ErrorActionPreference = 'Stop'

$gemName = 'aspera-cli'

Write-Host "Uninstalling $gemName..."

gem uninstall $gemName -a -x -I
