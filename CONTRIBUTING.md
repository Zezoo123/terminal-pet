# Contributing

Thanks for wanting to help. The most valuable things you can add right now are **new pets**, **support for more terminals**, and eventually **other platforms**.

## Build and run

```bash
make run          # builds and runs in the foreground with the repo's pets (Ctrl-C to quit)
make install      # installs to ~/.local, or PREFIX=/usr/local
make pets         # regenerates every bundled pet + a contact sheet at .build/pets-sheet.png
make test         # checks the shell plugins against a mock socket server
```

Requires macOS 13+ and the Xcode Command Line Tools. No Xcode project, no dependencies. CI (`.github/workflows/ci.yml`) builds in release mode, smoke-tests the CLI, checks the pets regenerate byte-for-byte, and parses the zsh plugin. Run those steps locally before opening a PR.

## Adding a pet

Every bundled pet is drawn in code in [scripts/gen-pets.swift](scripts/gen-pets.swift): a body as ASCII art on a 24x24 canvas plus a per-frame function that adds eyes, mouth, effects and a snack.

1. Copy one of the existing definitions (`func chick()` is the shortest) and rename it.
2. Draw the body. Rows must all be the same width; `art([...])` checks that. Keep the sprite inside 24x24 with a few rows free above it for Zs and bounces.
3. Give it the standard states: `idle`, `working`, `happy`, `sad`, `sleeping`, `eating`. Reuse the helpers (`drawEyes`, `drawMouth`, `drawTear`, `drawZzz`, `drawFood`) so faces look consistent across pets.
4. Add it to the `pets` array and run `make pets`. Look at `.build/pets-sheet.png`.
5. Commit the generator change together with the new `pets/<name>/` folder, and attach the contact sheet (or a screenshot of it on your terminal) to the PR.

Hand-drawn pets are welcome too: a folder of GIF/APNG files named per state is all the app needs. If you go that route, add the source files (Aseprite, PNG frames) under `pets/<name>/src/` so others can edit them.

## Supporting another terminal

The pet follows whichever app is frontmost and whose name or bundle identifier is in the `terminals` list ([Config.swift](Sources/terminal-pet/Config.swift)). If your terminal isn't recognised, run `terminal-pet` with `TERMINAL_PET_DEBUG=1 terminal-pet --foreground`, focus your terminal, and check what is logged. Add the app's name to `defaultTerminals` and to the table in the README.

## Other shells and platforms

- **Other shells**: the protocol is one line over a Unix socket (`preexec <cmd>`, `precmd <status>`, see [EventServer.swift](Sources/terminal-pet/EventServer.swift)). A plugin only needs to send those two lines from the shell's equivalent hooks. The zsh, bash and fish plugins in `shell/` are the references; `make test` runs them against a mock server.
- **Linux / Windows**: the app is split so that only [PetPanel.swift](Sources/terminal-pet/PetPanel.swift) (the overlay window) and [TerminalTracker.swift](Sources/terminal-pet/TerminalTracker.swift) (finding the terminal window) are macOS-specific. Open an issue before starting so we can agree on an approach.

## Style

- Swift: follow the existing code, 4-space indent, no force unwraps outside the generator scripts.
- Commits: one concern per commit, imperative subject (`feat: add frog pet`, `fix: ...`, `docs: ...`).
- Keep the README honest: if you add a feature, document it in the same PR.
