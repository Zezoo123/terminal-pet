#!/usr/bin/env python3
"""Run an interactive shell in a pseudo-terminal and type lines into it, like a person would.
   pty-run.py <shell> [shell args...] -- <line> [<line> ...]
Prints everything the shell wrote. Used by test-shells.sh (fish only fires its hooks on a tty)."""
import os, pty, select, sys, time

argv = sys.argv[1:]
sep = argv.index("--")
cmd, lines = argv[:sep], argv[sep + 1:]
pid, fd = pty.fork()
if pid == 0:
    os.environ["TERM"] = "dumb"
    os.execvp(cmd[0], cmd)

def drain(timeout):
    out = b""
    end = time.time() + timeout
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.05)
        if r:
            try:
                chunk = os.read(fd, 4096)
            except OSError:
                return out, True
            if not chunk:
                return out, True
            out += chunk
    return out, False

output = b""
out, _ = drain(0.8)              # let the shell start
output += out
for line in lines + ["exit"]:
    os.write(fd, (line + "\n").encode())
    out, closed = drain(0.6)
    output += out
    if closed:
        break
out, _ = drain(0.5)
output += out
try:
    os.waitpid(pid, 0)
except ChildProcessError:
    pass
sys.stdout.write(output.decode(errors="replace"))
