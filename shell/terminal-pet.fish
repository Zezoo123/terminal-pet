# terminal-pet fish plugin
# Tells the running terminal-pet app when a command starts and how it ended.
#
#   Put this file (or a `source` of it) in ~/.config/fish/conf.d/ — `terminal-pet setup` does that.
#
# Set TERMINAL_PET_DISABLE=1 to turn it off.

if status is-interactive; and not set -q TERMINAL_PET_DISABLE
    set -q TERMINAL_PET_SOCKET; or set -g TERMINAL_PET_SOCKET /tmp/terminal-pet-(id -u).sock
    if not set -q TERMINAL_PET_BIN
        if command -q terminal-pet
            set -g TERMINAL_PET_BIN (command -v terminal-pet)
        else if test -x ~/.local/bin/terminal-pet
            set -g TERMINAL_PET_BIN ~/.local/bin/terminal-pet
        end
    end

    function __terminal_pet_send
        test -S "$TERMINAL_PET_SOCKET"; or return 0
        set -q TERMINAL_PET_BIN; or return 0
        command $TERMINAL_PET_BIN send $argv >/dev/null 2>&1 &
        disown 2>/dev/null
    end

    function __terminal_pet_preexec --on-event fish_preexec
        __terminal_pet_send preexec (string sub -l 200 -- "$argv")
    end

    function __terminal_pet_postexec --on-event fish_postexec
        set -l st $status
        __terminal_pet_send precmd $st
    end

    # pet | pet feed | pet say hi | pet name Bob | pet stats | pet ghost | pet sad | pet scale 4 | pet list | pet quit
    function pet
        set -q TERMINAL_PET_BIN; or begin; echo "terminal-pet is not installed" >&2; return 1; end
        set -l cmd $argv[1]
        test -n "$cmd"; or set cmd poke
        switch $cmd
            case poke feed quit status stats
                command $TERMINAL_PET_BIN $cmd
            case say name
                command $TERMINAL_PET_BIN $cmd $argv[2..]
            case idle working happy sad sleeping eating hungry
                command $TERMINAL_PET_BIN send state $cmd
            case scale anchor
                command $TERMINAL_PET_BIN --$cmd $argv[2]
            case list pets
                command $TERMINAL_PET_BIN pets
            case help -h --help
                command $TERMINAL_PET_BIN --help
            case '*'
                command $TERMINAL_PET_BIN --pet $cmd
        end
    end
end
