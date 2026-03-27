$ErrorActionPreference = 'Stop'

$gemName = '<%=Aspera::Cli::Info::GEM_NAME%>'
$gemVersion = '<%=gem_version_build%>'

Write-Host "Installing $gemName version $gemVersion..."

# Check if already installed
$installed = gem list -i $gemName -v $gemVersion

if ($installed -eq "false") {
    gem install $gemName -v $gemVersion --no-document
}
else {
    Write-Host "$gemName $gemVersion already installed."
}

# Capture the output of ascli -v
$output = ascli -v

# Display it in a message
Write-Host "Installed ascli version $output"
