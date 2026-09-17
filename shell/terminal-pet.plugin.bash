# terminal-pet bash plugin
# Tells the running terminal-pet app when a command starts and how it ended.
#
#   source /path/to/terminal-pet.plugin.bash     (from ~/.bashrc or ~/.bash_profile;
#                                                 `terminal-pet setup` adds this for you)
#
# Set TERMINAL_PET_DISABLE=1 before sourcing to turn it off.
# Works on its own (DEBUG trap + PROMPT_COMMAND) or on top of bash-preexec if you have it.

[[ -n "$TERMINAL_PET_DISABLE" ]] && return 0
[[ $- == *i* ]] || return 0

: "${TERMINAL_PET_SOCKET:=/tmp/terminal-pet-$(id -u).sock}"
if [[ -z "$TERMINAL_PET_BIN" ]]; then
    if command -v terminal-pet >/dev/null 2>&1; then
        TERMINAL_PET_BIN=$(command -v terminal-pet)
    elif [[ -x "$HOME/.local/bin/terminal-pet" ]]; then
        TERMINAL_PET_BIN="$HOME/.local/bin/terminal-pet"
    fi
fi

# bash has no unix-socket builtin, so the CLI does the talking, in the background so the prompt never waits.
_terminal_pet_send() {
    [[ -S "$TERMINAL_PET_SOCKET" && -n "$TERMINAL_PET_BIN" ]] || return 0
    ( "$TERMINAL_PET_BIN" send "$@" >/dev/null 2>&1 & )
}

_terminal_pet_preexec() { _terminal_pet_send "preexec ${1:0:200}"; }
_terminal_pet_precmd()  { _terminal_pet_send "precmd $1"; }

if [[ -n "$bash_preexec_imported" || -n "$__bp_imported" ]] || declare -p preexec_functions >/dev/null 2>&1; then
    # bash-preexec (or something compatible) is installed: use its hook arrays.
    __terminal_pet_bp_preexec() { _terminal_pet_preexec "$1"; }
    __terminal_pet_bp_precmd()  { _terminal_pet_precmd "$?"; }
    preexec_functions+=(__terminal_pet_bp_preexec)
    precmd_functions+=(__terminal_pet_bp_precmd)
else
    # Minimal preexec/precmd: the DEBUG trap fires before every command; only the first one
    # after a prompt (when "armed") is the command the user typed.
    __terminal_pet_armed=
    __terminal_pet_ran=
    __terminal_pet_debug() {
        [[ -n "$COMP_LINE" ]] && return 0                    # tab completion
        [[ "$BASH_COMMAND" == __terminal_pet_* ]] && return 0
        [[ -n "$__terminal_pet_armed" ]] || return 0
        __terminal_pet_armed=
        __terminal_pet_ran=1
        # BASH_COMMAND is only the first simple command; history has the whole line.
        local _num line
        read -r _num line <<< "$(HISTTIMEFORMAT= builtin history 1 2>/dev/null)"
        _terminal_pet_preexec "${line:-$BASH_COMMAND}"
        return 0
    }
    __terminal_pet_precmd_hook() {
        local st=$?
        __terminal_pet_armed=                                 # ignore the rest of PROMPT_COMMAND
        [[ -n "$__terminal_pet_ran" ]] && _terminal_pet_precmd "$st"
        __terminal_pet_ran=
        return 0
    }
    __terminal_pet_arm() { __terminal_pet_armed=1; }
    trap '__terminal_pet_debug' DEBUG
    if [[ "$(declare -p PROMPT_COMMAND 2>/dev/null)" == "declare -a"* ]]; then
        PROMPT_COMMAND=(__terminal_pet_precmd_hook "${PROMPT_COMMAND[@]}" __terminal_pet_arm)
    else
        PROMPT_COMMAND="__terminal_pet_precmd_hook${PROMPT_COMMAND:+; $PROMPT_COMMAND}; __terminal_pet_arm"
    fi
fi

# Convenience command, same as the zsh one:
#   pet | pet feed | pet say hi | pet name Bob | pet stats | pet ghost | pet sad | pet scale 4 | pet list | pet quit
pet() {
    [[ -n "$TERMINAL_PET_BIN" ]] || { echo "terminal-pet is not installed" >&2; return 1; }
    case "${1:-poke}" in
        poke|feed|quit|status|stats) "$TERMINAL_PET_BIN" "$1" ;;
        say|name) "$TERMINAL_PET_BIN" "$1" "${@:2}" ;;
        idle|working|happy|sad|sleeping|eating|hungry|celebrate|pushing|scared) "$TERMINAL_PET_BIN" send "state $1" ;;
        scale|anchor) "$TERMINAL_PET_BIN" "--$1" "$2" ;;
        list|pets) "$TERMINAL_PET_BIN" pets ;;
        help|-h|--help) "$TERMINAL_PET_BIN" --help ;;
        *) "$TERMINAL_PET_BIN" --pet "$1" ;;
    esac
}
