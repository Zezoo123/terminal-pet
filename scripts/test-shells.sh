#!/bin/bash
# Checks that each shell plugin sends the right events, against a mock socket server (no GUI needed).
#   scripts/test-shells.sh [path/to/terminal-pet binary]
set -uo pipefail
cd "$(dirname "$0")/.."
BIN=${1:-$(ls .build/release/terminal-pet .build/debug/terminal-pet 2>/dev/null | head -1)}
[[ -x "$BIN" ]] || { echo "build first (swift build)"; exit 1; }
BIN=$(cd "$(dirname "$BIN")" && pwd)/$(basename "$BIN")

export TERMINAL_PET_SOCKET=/tmp/terminal-pet-test-$$.sock
export TERMINAL_PET_BIN=$BIN
LOG=$(mktemp -t terminal-pet-shells)
python3 - "$TERMINAL_PET_SOCKET" "$LOG" <<'PY' &
import os, socket, sys
path, log = sys.argv[1], sys.argv[2]
try: os.unlink(path)
except FileNotFoundError: pass
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); s.bind(path); s.listen(64)
while True:
    c, _ = s.accept(); c.settimeout(2); data = b""
    try:
        while not data.endswith(b"\n"):
            chunk = c.recv(4096)
            if not chunk: break
            data += chunk
    except socket.timeout: pass
    with open(log, "a") as f: f.write(data.decode(errors="replace"))
    try: c.sendall(b"ok\n")
    except OSError: pass
    c.close()
PY
SERVER=$!
disown $SERVER 2>/dev/null
trap '{ kill $SERVER; wait $SERVER; } 2>/dev/null; rm -f "$TERMINAL_PET_SOCKET" "$LOG"' EXIT
for _ in 1 2 3 4 5 6 7 8 9 10; do [[ -S "$TERMINAL_PET_SOCKET" ]] && break; sleep 0.2; done

fail=0
check() {   # check <shell> <expected lines...>
    local shell=$1; shift
    sleep 1   # background senders
    local ok=1
    for want in "$@"; do
        grep -qF -- "$want" "$LOG" || { echo "  missing: $want"; ok=0; }
    done
    if (( ok )); then echo "PASS $shell"; else echo "FAIL $shell"; echo "  got:"; sed 's/^/    /' "$LOG"; fail=1; fi
    : > "$LOG"
}

# Each shell is driven through a pseudo-terminal (fish only fires its hooks on a tty).
run() { python3 scripts/pty-run.py "$@" >/dev/null 2>&1; }

echo "== zsh"
run zsh -f -i -- 'source shell/terminal-pet.plugin.zsh' 'true' 'false' 'echo hi | cat'
check zsh "preexec true" "precmd 0" "preexec false" "precmd 1" "preexec echo hi | cat"

echo "== bash"
run bash --norc -i -- 'source shell/terminal-pet.plugin.bash' 'true' 'false' 'echo hi | cat' ''
check bash "preexec true" "precmd 0" "preexec false" "precmd 1" "preexec echo hi | cat"

if command -v fish >/dev/null; then
    echo "== fish"
    run fish --no-config -i -- 'source shell/terminal-pet.fish' 'true' 'false' 'echo hi | cat'
    check fish "preexec true" "precmd 0" "preexec false" "precmd 1" "preexec echo hi | cat"
else
    echo "== fish: not installed, skipped"
fi

echo "== send round-trip via CLI"
"$BIN" send poke >/dev/null; check cli "poke"

exit $fail
