# PowerShell completion for ascli
# Activate, in $PROFILE: ascli config completion powershell | Out-String | Invoke-Expression
# Or save as a file with extension .ps1, and dot-source it in $PROFILE

& {
    # Output of ascli, per words typed: it depends only on the version of ascli, so it is kept for the session
    $cache = @{}
    # Also applies to ascli.cmd and ascli.bat, and to a path to them: PowerShell matches the name without folder and extension
    Register-ArgumentCompleter -Native -CommandName ascli -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        # Run ascli as typed, e.g. .\ascli.cmd when not in PATH
        $command = $commandAst.GetCommandName()
        # CommandElements[0] is the command itself; pass only the words typed before the cursor, unquoted (e.g. '@:')
        $words = @($commandAst.CommandElements | Select-Object -Skip 1 |
                Where-Object { $_.Extent.EndOffset -lt $cursorPosition } |
                ForEach-Object { if ($_ -is [System.Management.Automation.Language.StringConstantExpressionAst]) { $_.Value } else { $_.Extent.Text } })
        # Only the beginning of the word at cursor matters: `-` (option names), `--name.` (keys) or `--name=` (values), candidates are filtered here.
        # Other words give the same candidates: `.` is passed, as Windows PowerShell does not pass an empty argument.
        $current = if ($wordToComplete -match '^--[^=]*[=.]') { $Matches[0] } elseif ($wordToComplete.StartsWith('-')) { '-' } else { '.' }
        $key = (@($command) + $words + $current) -join ' '
        if (-not $cache.ContainsKey($key)) {
            $cache[$key] = @(& $command config completion candidates -- @words $current 2>$null)
        }
        $lines = $cache[$key]
        # Directive `:files`: no result, so that PowerShell completes file paths
        if ($lines.Count -eq 0 -or $lines[-1] -eq ':files') { return }
        # Lines `word<TAB>description`, then the directive
        $results = @($lines | Select-Object -First ($lines.Count - 1) | ForEach-Object {
                $word, $description = $_ -split "`t", 2
                if ($word -and $word.StartsWith($wordToComplete, [System.StringComparison]::OrdinalIgnoreCase)) {
                    [System.Management.Automation.CompletionResult]::new($word, $word, 'ParameterValue', $(if ($description) { $description } else { $word }))
                }
            })
        if ($results.Count -gt 0) { return $results }
        # No result: one that does not change the word (a space for an empty word), so that PowerShell does not complete file paths.
        # It shows the hint in the list, if any (e.g. `<String>`)
        $text = if ($wordToComplete) { $wordToComplete } else { ' ' }
        $hint = if ($lines[-1] -like ':hint *') { $lines[-1].Substring(6) } else { $text }
        [System.Management.Automation.CompletionResult]::new($text, $hint, 'ParameterValue', $hint)
    }.GetNewClosure()
}
