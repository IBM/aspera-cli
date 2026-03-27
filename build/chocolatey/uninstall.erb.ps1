$ErrorActionPreference = 'Stop'

$gemName = '<%=Aspera::Cli::Info::GEM_NAME%>'

Write-Host "Uninstalling $gemName..."

gem uninstall $gemName -a -x -I
