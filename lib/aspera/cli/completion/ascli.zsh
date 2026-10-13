#compdef ascli
# Zsh completion for ascli
# Activate (after compinit): eval "$(ascli config completion zsh)"
# Or save as file `_ascli` in a folder of $fpath

_ascli() {
    local -a lines values opts
    local directive line entry
    # words[1] is 'ascli' itself: pass the words before the cursor, then the word at cursor
    lines=("${(@f)$(ascli config completion candidates -- "${(@)words[2,CURRENT-1]}" "$PREFIX" 2>/dev/null)}")
    directive=${lines[-1]}
    # Candidates `word<TAB>description` to `word:description`, as expected by _describe
    for line in "${(@)lines[1,-2]}"; do
        [[ -n $line ]] || continue
        entry=${${line%%$'\t'*}//:/\\:}
        [[ $line == *$'\t'* ]] && entry+=":${line#*$'\t'}"
        if [[ $line == -* ]]; then opts+=("$entry"); else values+=("$entry"); fi
    done
    case $directive in
    :files) _files ;;
    ":hint "*) _message -r "${directive#:hint }" ;;
    *)
        # Options are listed after the other candidates
        _alternative 'values:value: _describe -t values value values' 'options:option: _describe -t options option opts'
        ;;
    esac
}

if [[ "${funcstack[1]}" == _ascli ]]; then
    # Autoloaded from $fpath: this file is the body of function _ascli
    _ascli "$@"
else
    # Evaluated or sourced
    compdef _ascli ascli
fi
