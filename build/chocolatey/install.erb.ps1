$ErrorActionPreference = 'Stop'

# Installs the Windows portable package of <%=Aspera::Cli::Info::CMD_NAME%> (Ruby, gems and Aspera Transfer SDK included):
# no Ruby installation, no compilation, no administrator rights needed by ascli itself.
$toolsDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$installDir = Join-Path $toolsDir '<%=Aspera::Cli::Info::CMD_NAME%>'

$packageArgs = @{
  packageName    = $env:ChocolateyPackageName
  unzipLocation  = $installDir
  url64bit       = '<%=zip_url%>'
  checksum64     = '<%=zip_sha256%>'
  checksumType64 = 'sha256'
}
Install-ChocolateyZipPackage @packageArgs

# Only ascli on the PATH: no shim for the executables of the package (ruby, ascp, transferd...),
# they would hide the ones of the user
Get-ChildItem -Path $installDir -Recurse -Filter '*.exe' | ForEach-Object {
  New-Item -Path "$($_.FullName).ignore" -ItemType File -Force | Out-Null
}
Install-BinFile -Name '<%=Aspera::Cli::Info::CMD_NAME%>' -Path (Join-Path $installDir '<%=Aspera::Cli::Info::CMD_NAME%>.cmd')

Write-Host "Installed: $(& (Join-Path $installDir '<%=Aspera::Cli::Info::CMD_NAME%>.cmd') -v)"
