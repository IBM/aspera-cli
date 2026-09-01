#!/bin/bash

_bash_autocomplete() {
    local cur opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    # COMP_WORDS[0] is the program name itself; pass only the typed sub-words
    opts=$(ascli config completion bash "${COMP_WORDS[@]:1:$COMP_CWORD-1}")
    COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
    return 0
}

PROGS=("ascli")
for p in "${PROGS[@]}"; do
    complete -F _bash_autocomplete "$p"
done
