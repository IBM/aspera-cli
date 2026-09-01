#compdef ascli

_ascli() {
    local -a completions
    local words_before_cursor

    # words[1] is 'ascli' itself; pass only the sub-words typed so far
    # (excluding the current incomplete word at cursor position)
    words_before_cursor=("${words[@]:1:$((CURRENT - 2))}")

    # Ask ascli for completions at the current depth
    completions=(${(f)"$(ascli config completion bash "${words_before_cursor[@]}" 2>/dev/null)"})

    compadd -a completions
}

_ascli "$@"
