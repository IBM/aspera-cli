#compdef ascli
# Zsh completion for ascli
# Activate (after compinit): eval "$(ascli config completion zsh)"
# Or save as file `_ascli` in a folder of $fpath

_ascli() {
    local -a candidates
    # words[1] is 'ascli' itself; pass only the words typed before the cursor
    candidates=(${(f)"$(ascli config completion words "${(@)words[2,CURRENT-1]}" 2>/dev/null)"})
    compadd -a candidates
}

if [[ "${funcstack[1]}" == _ascli ]]; then
    # Autoloaded from $fpath: this file is the body of function _ascli
    _ascli "$@"
else
    # Evaluated or sourced
    compdef _ascli ascli
fi
