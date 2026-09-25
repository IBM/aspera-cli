# Fish completion for ascli
# Activate: ascli config completion fish | source
# Or save as file ~/.config/fish/completions/ascli.fish

# Remove completions of a previous activation
complete --command ascli --erase

# Disable file completion entirely — ascli manages its own argument tree
complete --command ascli --no-files

# Dynamic completion: pass all words already typed (excluding 'ascli' itself)
# to `ascli config completion words` and return the result as completions.
complete --command ascli --arguments '(
    set -l words (commandline -opc)
    ascli config completion words $words[2..] 2>/dev/null
)'
