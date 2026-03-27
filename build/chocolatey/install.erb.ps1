$ErrorActionPreference = 'Stop'

$gemName = '<%=Aspera::Cli::Info::GEM_NAME%>'
$gemVersion = '<%=nuget_version_build%>'

Write-Host "Installing $gemName version $gemVersion..."

# Check if already installed
$installed = gem list -i $gemName -v $gemVersion

if (-not $installed) {
    gem install $gemName -v $gemVersion --no-document
}
else {
    Write-Host "$gemName $gemVersion already installed."
}
