#compdef ascli
# Zsh completion for ascli
# Activate (after compinit): eval "$(ascli config completion zsh)"
# Or save as file `_ascli` in a folder of $fpath

_ascli() {
    local -a lines values values_cont opts opts_cont
    local directive line word entry files_prefix
    # words[1] is 'ascli' itself: pass the words before the cursor, then the word at cursor
    lines=("${(@f)$(ascli config completion candidates -- "${(@)words[2,CURRENT-1]}" "$PREFIX" 2>/dev/null)}")
    directive=${lines[-1]}
    # Candidates `word<TAB>description` to `word:description`, as expected by _describe
    for line in "${(@)lines[1,-2]}"; do
        [[ -n $line ]] || continue
        word=${line%%$'\t'*}
        entry=${word//:/\\:}
        [[ $line == *$'\t'* ]] && entry+=":${line#*$'\t'}"
        # Option names (`--name`, `--name.key=`), else values (`--name=value`)
        # A word that continues is not followed by a space: `key=`, `key.`, `folder/`, `@modifier:`
        if [[ $word =~ '^-[^=]*=?$' ]]; then
            if [[ $word =~ '[=.]$' ]]; then opts_cont+=("$entry"); else opts+=("$entry"); fi
        elif [[ $word =~ '([=./]|@[a-z0-9_]+:)$' ]]; then
            values_cont+=("$entry")
        else
            values+=("$entry")
        fi
    done
    case $directive in
    :files | ':files '* | :folders | ':folders '*)
        # Beginning of the word that is not part of the path, e.g. `--key=@file:`
        files_prefix=${${${directive#:files}#:folders}# }
        [[ -n $files_prefix ]] && compset -P "${(b)files_prefix}"
        if [[ $directive == :folders* ]]; then _files -/; else _files; fi
        ;;
    ":hint "*) _message -r "${directive#:hint }" ;;
    *)
        # Options are listed after the other candidates
        _alternative \
            'values:value: _describe -t values value values -- values_cont -S ""' \
            'options:option: _describe -t options option opts -- opts_cont -S ""'
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
