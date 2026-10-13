# Fish completion for ascli
# Activate: ascli config completion fish | source
# Or save as file ~/.config/fish/completions/ascli.fish

# Remove completions of a previous activation
complete --command ascli --erase

# Candidates proposed by ascli, as lines `word<TAB>description`, as expected by fish
function __ascli_complete
    # Words before the cursor (ascli itself excluded), then the word at cursor
    set -l words (commandline -opc)
    set -l current (commandline -ct)
    set -l lines (ascli config completion candidates -- $words[2..] "$current" 2>/dev/null)
    set -q lines[1]; or return
    # Last line is the directive: `:files`, `:hint <text>` (cannot be displayed without being inserted), or `:`
    set -l directive $lines[-1]
    set -e lines[-1]
    test "$directive" = :files; and __fish_complete_path "$current"
    # printf without argument would output an empty line
    set -q lines[1]; and printf '%s\n' $lines
end

# File completion only where proposed by ascli
complete --command ascli --no-files --arguments '(__ascli_complete)'
