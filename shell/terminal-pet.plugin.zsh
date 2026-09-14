# terminal-pet zsh plugin
# Tells the running terminal-pet app when a command starts and how it ended.
#
#   source /path/to/terminal-pet.plugin.zsh   (or load it with your plugin manager)
#
# Set TERMINAL_PET_DISABLE=1 before sourcing to turn it off.
# The socket path must match the app's: /tmp/terminal-pet-<uid>.sock unless TERMINAL_PET_SOCKET is set.

[[ -n "$TERMINAL_PET_DISABLE" ]] && return 0

: ${TERMINAL_PET_SOCKET:="/tmp/terminal-pet-$UID.sock"}

# zsh can talk to unix sockets natively, so no process is spawned per prompt.
zmodload zsh/net/socket 2>/dev/null

_terminal_pet_send() {
    [[ -S "$TERMINAL_PET_SOCKET" ]] || return 0
    if (( $+builtins[zsocket] )); then
        local fd
        zsocket "$TERMINAL_PET_SOCKET" 2>/dev/null || return 0
        fd=$REPLY
        print -u $fd -r -- "$*" 2>/dev/null
        exec {fd}>&-
    elif (( $+commands[terminal-pet] )); then
        command terminal-pet send "$@" 2>/dev/null &!
    fi
}

_terminal_pet_preexec() {
    # $1 is the command line as typed; keep it short, the pet only cares that something started.
    _terminal_pet_send "preexec ${1[1,200]}"
}

_terminal_pet_precmd() {
    local status_code=$?   # must be the very first thing in the hook
    _terminal_pet_send "precmd $status_code"
}

autoload -Uz add-zsh-hook
add-zsh-hook preexec _terminal_pet_preexec
add-zsh-hook precmd _terminal_pet_precmd

# Convenience: `pet happy`, `pet sleeping`, `pet poke`, `pet quit`
pet() {
    case "$1" in
        poke|quit) _terminal_pet_send "$1" ;;
        "") _terminal_pet_send poke ;;
        *)  _terminal_pet_send "state $1" ;;
    esac
}
