# Bash completion for ascli
# Activate: eval "$(ascli config completion bash)"

_ascli_complete() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    # COMP_WORDS[0] is the program name itself; pass only the words typed before the cursor
    local candidates
    candidates=$(ascli config completion words "${COMP_WORDS[@]:1:COMP_CWORD-1}" 2>/dev/null)
    COMPREPLY=( $(compgen -W "${candidates}" -- "${cur}") )
}

complete -F _ascli_complete ascli
