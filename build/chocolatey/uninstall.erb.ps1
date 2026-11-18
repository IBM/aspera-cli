$ErrorActionPreference = 'Stop'

# The folder of the package is deleted by Chocolatey: only the command on the PATH is removed here.
# The configuration (%USERPROFILE%\.aspera\ascli) is kept.
Uninstall-BinFile -Name '<%=Aspera::Cli::Info::CMD_NAME%>'
