#!/bin/zsh
# Records a short demo of terminal-pet reacting inside a real Terminal.app window, then converts it
# to an animated GIF for the README.
#
#   scripts/record-demo.sh [docs/demo.gif]        record + convert (needs Screen Recording permission
#                                                 for the app you run this from: Terminal, iTerm2, ...)
#   scripts/record-demo.sh --from clip.mov [out]  only convert a recording you made with QuickTime/Kap
#
# Env: DEMO_SECONDS (default 16), DEMO_PET (temporarily switch pet, restored afterwards),
#      DEMO_APP Terminal (default) or iTerm2,
#      DEMO_CMDS newline-separated "command|seconds" lines to run instead of the default session,
#      DEMO_BOUNDS "x,y,w,h" of the window in screen points (default 200,140,820,520).
set -euo pipefail
cd "$(dirname "$0")/.."

convert_gif() {   # .mov -> .gif with AVFoundation + ImageIO, no external tools needed
    local src=$1 out=$2
    mkdir -p .build "$(dirname "$out")"
    [[ .build/mov-to-gif -nt scripts/mov-to-gif.swift ]] || swiftc -O -o .build/mov-to-gif scripts/mov-to-gif.swift
    .build/mov-to-gif "$src" "$out" "${DEMO_FPS:-12}" "${DEMO_WIDTH:-820}"
}

if [[ "${1:-}" == "--from" ]]; then
    convert_gif "$2" "${3:-docs/demo.gif}"
    exit 0
fi

OUT=${1:-docs/demo.gif}
SECS=${DEMO_SECONDS:-16}
APP=${DEMO_APP:-Terminal}
BOUNDS=${DEMO_BOUNDS:-200,140,820,520}
PET_BIN=$(command -v terminal-pet || echo "$HOME/.local/bin/terminal-pet")
[[ -x "$PET_BIN" ]] || { echo "terminal-pet is not installed (make install)" >&2; exit 1 }
grep -q terminal-pet.plugin.zsh ~/.zshrc || echo "warning: the zsh plugin is not sourced in ~/.zshrc, the pet won't react to commands" >&2

MOV=$(mktemp -t terminal-pet-demo).mov
IFS=, read -r X Y W H <<< "$BOUNDS"

# 1. Make sure a pet is running, optionally swap in the demo pet.
"$PET_BIN" status >/dev/null 2>&1 || "$PET_BIN"
ORIGINAL_PET=""
if [[ -n "${DEMO_PET:-}" ]]; then
    ORIGINAL_PET=$(python3 -c 'import json,os;print(json.load(open(os.path.expanduser("~/.config/terminal-pet/config.json"))).get("pet","blob"))' 2>/dev/null || echo blob)
    "$PET_BIN" --pet "$DEMO_PET" >/dev/null
fi
restore() { [[ -n "$ORIGINAL_PET" ]] && "$PET_BIN" --pet "$ORIGINAL_PET" >/dev/null 2>&1 || true }
trap restore EXIT
"$PET_BIN" feed >/dev/null && sleep 3.5   # a hungry pet would show its hungry pose between commands

# 2. Open a fresh terminal window at a known place.
if [[ "$APP" == "iTerm2" || "$APP" == "iTerm" ]]; then
    open -a iTerm && sleep 2      # its AppleScript terms only resolve once it is running
    osascript >/dev/null <<APPLESCRIPT
tell application "iTerm2"
    activate
    set w to (create window with default profile)
    delay 0.5
    set bounds of w to {$X, $Y, $((X + W)), $((Y + H))}
    tell current session of w to write text "cd $(pwd) && clear"
end tell
APPLESCRIPT
    type_cmd() {
        local cmd=${1//\\/\\\\}; cmd=${cmd//\"/\\\"}
        osascript -e "tell application \"iTerm2\" to tell current session of current window to write text \"$cmd\"" >/dev/null
        sleep "${2:-2}"
    }
else
    osascript >/dev/null <<APPLESCRIPT
tell application "Terminal"
    activate
    do script "cd $(pwd) && clear"
    delay 0.5
    set bounds of front window to {$X, $Y, $((X + W)), $((Y + H))}
end tell
APPLESCRIPT
    type_cmd() {   # runs a command in the demo window so the hooks fire and the text shows up
        local cmd=${1//\\/\\\\}; cmd=${cmd//\"/\\\"}
        osascript -e "tell application \"Terminal\" to do script \"$cmd\" in front window" >/dev/null
        sleep "${2:-2}"
    }
fi
sleep 1.5

# 3. Record the window region while a scripted session plays out.
echo "recording ${SECS}s ..."
screencapture -x -V "$SECS" -R "$X,$Y,$W,$H" "$MOV" &
REC=$!
sleep 1.5
if [[ -n "${DEMO_CMDS:-}" ]]; then
    while IFS='|' read -r cmd secs; do
        [[ -n "$cmd" ]] && type_cmd "$cmd" "${secs:-2.5}"
    done <<< "$DEMO_CMDS"
else
    type_cmd 'echo "hello, world"' 2
    type_cmd 'ls' 2.5
    type_cmd 'cat does-not-exist.txt' 3
    type_cmd 'pet feed' 3.5
    type_cmd 'pet say "star me on github"' 3
fi
wait $REC || true

type_cmd 'exit' 0

if [[ ! -s "$MOV" ]]; then
    cat >&2 <<MSG
no recording was produced. macOS needs Screen Recording permission for the app this script runs from:
  System Settings -> Privacy & Security -> Screen & System Audio Recording -> enable your terminal app
then run it again. Or record with QuickTime (File -> New Screen Recording) and convert with:
  scripts/record-demo.sh --from ~/Desktop/clip.mov
MSG
    exit 1
fi

convert_gif "$MOV" "$OUT"
rm -f "$MOV"
