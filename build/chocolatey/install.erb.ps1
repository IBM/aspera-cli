$ErrorActionPreference = 'Stop'

$gemName = 'aspera-cli'
$gemVersion = '4.25.5'

Write-Host "Installing $gemName version $gemVersion..."

# Check if already installed
$installed = gem list -i $gemName -v $gemVersion

if (-not $installed) {
    gem install $gemName -v $gemVersion --no-document
}
else {
    Write-Host "$gemName $gemVersion already installed."
}
