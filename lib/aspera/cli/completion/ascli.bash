# Bash completion for ascli
# Activate: eval "$(ascli config completion bash)"

_ascli_complete() {
    local line=${COMP_LINE:0:COMP_POINT}
    # Shell words up to the cursor: COMP_WORDS is also split on COMP_WORDBREAKS (e.g. `=`, `:`), join the parts not separated by blanks
    local -a words=()
    local i word blanks rest=$line
    for ((i = 0; i <= COMP_CWORD; i++)); do
        blanks=${rest%%[![:blank:]]*}
        rest=${rest#"$blanks"}
        if ((i == COMP_CWORD)); then word=$rest; else word=${COMP_WORDS[i]}; fi
        if ((i == 0)) || [[ -n $blanks ]]; then
            words+=("$word")
        else
            words[${#words[@]} - 1]+=$word
        fi
        rest=${rest#"$word"}
    done
    local cur=${words[${#words[@]} - 1]}
    # Readline replaces only the text after the last word break character, but with it if it is `@` or `$` (special prefixes)
    local prefix=${cur%"${line##*["$COMP_WORDBREAKS"]}"}
    [[ $prefix == *[@\$] ]] && prefix=${prefix%?}
    # words[0] is the program name itself: pass the words before the cursor, then the word at cursor
    local output directive entry files_prefix
    # A word that continues is not followed by a space: `key=`, `key.`, `folder/`, `@modifier:`
    local continues='([=./]|@[a-z0-9_]+:)$'
    output=$(ascli config completion candidates -- "${words[@]:1:${#words[@]}-2}" "$cur" 2>/dev/null)
    directive=${output##*$'\n'}
    output=${output%"$directive"}
    COMPREPLY=()
    while IFS= read -r entry; do
        # Remove the description
        word=${entry%%$'\t'*}
        [[ -n $word && $word == "$cur"* ]] || continue
        COMPREPLY+=("${word#"$prefix"}")
        [[ $word =~ $continues ]] && compopt -o nospace 2>/dev/null
    done <<<"$output"
    case $directive in
    :files | ":files "* | :folders | ":folders "*)
        # Beginning of the word that is not part of the path, e.g. `--key=@file:`
        files_prefix=${directive#:files}
        files_prefix=${files_prefix#:folders}
        files_prefix=${files_prefix# }
        local kind=file
        [[ $directive == :folders* ]] && kind=directory
        compopt -o filenames 2>/dev/null
        while IFS= read -r word; do
            word=$files_prefix$word
            COMPREPLY+=("${word#"$prefix"}")
        done < <(compgen -A "$kind" -- "${cur#"$files_prefix"}")
        ;;
    ":hint "*)
        # Two entries: bash displays them, but inserts nothing
        COMPREPLY=("${directive#:hint }" " ")
        ;;
    esac
}

complete -F _ascli_complete ascli
