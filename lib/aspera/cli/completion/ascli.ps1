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
        # Word at cursor, unquoted: a word starting with `@` is quoted (else it is splatting)
        $word = $wordToComplete -replace '^[''"]|[''"]$', ''
        # Only the beginning of the word at cursor matters: up to its last `=`, `.`, `:` or `@` (values, keys, extended values),
        # or `-` (option names). Candidates are filtered here.
        # Other words give the same candidates: `_` is passed, as Windows PowerShell does not pass an empty argument.
        $current = if ($word -match '^.*[=.:@]') { $Matches[0] } elseif ($word.StartsWith('-')) { '-' } else { '_' }
        $key = (@($command) + $words + $current) -join ' '
        if (-not $cache.ContainsKey($key)) {
            $cache[$key] = @(& $command config completion candidates -- @words $current 2>$null)
        }
        $lines = $cache[$key]
        if ($lines.Count -eq 0) { return }
        $directive = $lines[-1]
        # Text inserted: quoted if it starts with `@`, or contains a space or a special character
        $quote = { param($text) if ($text -match '^@|[\s''"`$;,(){}|&<>]') { "'" + ($text -replace "'", "''") + "'" } else { $text } }
        # Directive `:files` or `:folders`, followed by the beginning of the word that is not part of the path, if any
        if ($directive -match '^:(files|folders)(?: (.*))?$') {
            $folders = $Matches[1] -eq 'folders'
            $prefix = [string]$Matches[2]
            # No prefix: no result, so that PowerShell completes file paths
            if (-not $prefix -or -not $word.StartsWith($prefix)) { return }
            $path = $word.Substring($prefix.Length)
            $parent = $path.Substring(0, $path.LastIndexOfAny([char[]]'/\') + 1)
            $leaf = $path.Substring($parent.Length)
            $folder = if ($parent) { [WildcardPattern]::Escape($parent) } else { '.' }
            return @(Get-ChildItem -Path $folder -Force -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name.StartsWith($leaf, [System.StringComparison]::OrdinalIgnoreCase) -and ($_.PSIsContainer -or -not $folders) } |
                    ForEach-Object {
                        $text = $prefix + $parent + $_.Name + $(if ($_.PSIsContainer) { [System.IO.Path]::DirectorySeparatorChar } else { '' })
                        [System.Management.Automation.CompletionResult]::new((& $quote $text), $_.Name, 'ParameterValue', $text)
                    })
        }
        # Lines `word<TAB>description`, then the directive
        $results = @($lines | Select-Object -First ($lines.Count - 1) | ForEach-Object {
                $candidate, $description = $_ -split "`t", 2
                if ($candidate -and $candidate.StartsWith($word, [System.StringComparison]::OrdinalIgnoreCase)) {
                    [System.Management.Automation.CompletionResult]::new((& $quote $candidate), $candidate, 'ParameterValue', $(if ($description) { $description } else { $candidate }))
                }
            })
        if ($results.Count -gt 0) { return $results }
        # No result: one that does not change the word (a space for an empty word), so that PowerShell does not complete file paths.
        # It shows the hint in the list, if any (e.g. `<String>`)
        $text = if ($wordToComplete) { $wordToComplete } else { ' ' }
        $hint = if ($directive -like ':hint *') { $directive.Substring(6) } else { $text }
        [System.Management.Automation.CompletionResult]::new($text, $hint, 'ParameterValue', $hint)
    }.GetNewClosure()
}
