# PowerShell completion for ascli
# Activate, in $PROFILE: ascli config completion powershell | Out-String | Invoke-Expression
# Or save as a file with extension .ps1, and dot-source it in $PROFILE

& {
    # Words proposed, per words typed: they depend only on the version of ascli, so they are kept for the session
    $cache = @{}
    # Also applies to ascli.cmd and ascli.bat, and to a path to them: PowerShell matches the name without folder and extension
    Register-ArgumentCompleter -Native -CommandName ascli -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        # Run ascli as typed, e.g. .\ascli.cmd when not in PATH
        $command = $commandAst.GetCommandName()
        # CommandElements[0] is the command itself; pass only the words typed before the cursor
        $words = @($commandAst.CommandElements | Select-Object -Skip 1 |
                Where-Object { $_.Extent.EndOffset -lt $cursorPosition } |
                ForEach-Object { $_.Extent.Text })
        $key = (@($command) + $words) -join ' '
        if (-not $cache.ContainsKey($key)) {
            $cache[$key] = @(& $command config completion words @words 2>$null)
        }
        $cache[$key] | Where-Object { $_.StartsWith($wordToComplete, [System.StringComparison]::OrdinalIgnoreCase) } |
            ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
    }.GetNewClosure()
}
