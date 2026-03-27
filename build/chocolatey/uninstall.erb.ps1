$ErrorActionPreference = 'Stop'

$gemName = '<%=choco_package%>'

Write-Host "Uninstalling $gemName..."

gem uninstall $gemName -a -x -I
