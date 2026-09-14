#!/bin/zsh
# Records a short demo of terminal-pet reacting inside a real Terminal.app window, then converts it
# to an animated GIF for the README.
#
#   scripts/record-demo.sh [docs/demo.gif]        record + convert (needs Screen Recording permission
#                                                 for the app you run this from: Terminal, iTerm2, ...)
#   scripts/record-demo.sh --from clip.mov [out]  only convert a recording you made with QuickTime/Kap
#
# Env: DEMO_SECONDS (default 16), DEMO_PET (temporarily switch pet, restored afterwards),
#      DEMO_BOUNDS "x,y,w,h" of the window in screen points (default 200,140,820,520).
set -euo pipefail
cd "$(dirname "$0")/.."

convert_gif() {
    local src=$1 out=$2
    command -v ffmpeg >/dev/null || { echo "ffmpeg is needed for the GIF conversion: brew install ffmpeg" >&2; exit 1 }
    mkdir -p "$(dirname "$out")"
    ffmpeg -loglevel error -y -i "$src" \
        -vf "fps=12,scale=820:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" \
        -loop 0 "$out"
    echo "wrote $out ($(du -h "$out" | cut -f1))"
}

if [[ "${1:-}" == "--from" ]]; then
    convert_gif "$2" "${3:-docs/demo.gif}"
    exit 0
fi

OUT=${1:-docs/demo.gif}
SECS=${DEMO_SECONDS:-16}
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

# 2. Open a fresh Terminal window at a known place.
osascript >/dev/null <<APPLESCRIPT
tell application "Terminal"
    activate
    do script "clear"
    delay 0.5
    set bounds of front window to {$X, $Y, $((X + W)), $((Y + H))}
end tell
APPLESCRIPT
sleep 1.5

type_cmd() {   # runs a command in the demo window so the hooks fire and the text shows up
    local cmd=${1//\\/\\\\}; cmd=${cmd//\"/\\\"}
    osascript -e "tell application \"Terminal\" to do script \"$cmd\" in front window" >/dev/null
    sleep "${2:-2}"
}

# 3. Record the window region while a scripted session plays out.
echo "recording ${SECS}s ..."
screencapture -x -V "$SECS" -R "$X,$Y,$W,$H" "$MOV" &
REC=$!
sleep 1.5
type_cmd 'echo "hello, world"' 2
type_cmd 'git status --short | head -3' 2.5
type_cmd 'cat does-not-exist.txt' 3
type_cmd 'pet feed' 3.5
type_cmd 'pet say "star me on github"' 3
wait $REC || true

osascript -e 'tell application "Terminal" to do script "exit" in front window' >/dev/null 2>&1 || true

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
