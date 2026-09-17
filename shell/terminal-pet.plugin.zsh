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

# Like _terminal_pet_send, but waits for and prints the reply.
_terminal_pet_call() {
    if [[ ! -S "$TERMINAL_PET_SOCKET" ]]; then
        print -u2 "terminal-pet is not running"
        return 1
    fi
    if (( $+builtins[zsocket] )); then
        local fd reply
        zsocket "$TERMINAL_PET_SOCKET" 2>/dev/null || { print -u2 "terminal-pet: could not connect to $TERMINAL_PET_SOCKET"; return 1 }
        fd=$REPLY
        print -u $fd -r -- "$*"
        read -t 5 -u $fd -r reply
        exec {fd}>&-
        print -r -- "$reply"
        [[ "$reply" != error* ]]
    else
        command terminal-pet send "$@"
    fi
}

# Convenience command:
#   pet                 poke it
#   pet feed            feed it (it gets hungry over ~8 hours)
#   pet say hello       speech bubble;  pet name Bob   give it a name
#   pet stats           level, xp, hunger, streaks, age
#   pet ghost           switch to another pet (name, directory, or .gif); saved to config
#   pet sad             force a state: idle | working | happy | sad | sleeping | eating | hungry | celebrate | pushing | scared
#   pet scale 4         resize;  pet anchor inside-bottom-left   move
#   pet list            list available pets;  pet status;  pet quit
pet() {
    case "${1:-poke}" in
        poke|feed|quit|status) _terminal_pet_call "$1" ;;
        stats) command terminal-pet stats 2>/dev/null || _terminal_pet_call stats ;;
        say|name) _terminal_pet_call "$1" "${@:2}" ;;
        idle|working|happy|sad|sleeping|eating|hungry|celebrate|pushing|scared) _terminal_pet_call "state $1" ;;
        scale|anchor) _terminal_pet_call "$1" "$2" ;;
        list|pets) command terminal-pet pets 2>/dev/null || print -u2 "terminal-pet is not on your PATH" ;;
        help|-h|--help) command terminal-pet --help 2>/dev/null || print -u2 "terminal-pet is not on your PATH" ;;
        *) _terminal_pet_call "pet $1" ;;
    esac
}
