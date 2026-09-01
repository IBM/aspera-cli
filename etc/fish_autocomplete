# Fish shell completion for ascli
# Install: cp this file to ~/.config/fish/completions/ascli.fish

# Disable file completion entirely — ascli manages its own argument tree
complete --command ascli --no-files

# Dynamic completion: pass all words already typed (excluding 'ascli' itself)
# to `ascli config completion bash` and return the result as completions.
complete --command ascli --arguments '(
    set -l words (commandline -opc)
    ascli config completion bash $words[2..] 2>/dev/null
)'
