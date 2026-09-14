# terminal-pet

A little animated companion that lives on top of your terminal window and reacts to what you do in the shell.

- Sits in the corner of whichever terminal window is in front (or perched on its title bar, if you prefer), and follows it when you move or resize it.
- Hides when the terminal isn't the active app, so it never gets in the way.
- Watches your zsh session: **working** while a command runs, **happy** when it succeeds, **sad** when it fails, **sleeping** when you've been away for a while. Click it to make it happy.
- Fully customisable: drop in your own animated GIFs (or APNGs) for each state, or point it at a single GIF and it'll just loop that.

macOS only for now (native Swift/AppKit, no dependencies). Linux and Windows are on the roadmap.

## Install

Requires Xcode Command Line Tools (`xcode-select --install`), macOS 13 or later.

```bash
git clone https://github.com/Zezoo123/terminal-pet.git
cd terminal-pet
make install            # builds and installs to ~/.local (override with PREFIX=/usr/local)
```

Then add the plugin to `~/.zshrc`:

```zsh
source ~/.local/share/terminal-pet/terminal-pet.plugin.zsh
```

Start the pet (it detaches and gives you the prompt back):

```bash
terminal-pet            # or `make launchd` to start it at login
terminal-pet stop       # when you've had enough
```

Open a new zsh session, run a command, and watch it react.

### Try it without installing

```bash
make run                # runs in the foreground with the repo's pets, Ctrl-C to quit
```

## Shell integration

The zsh plugin hooks `preexec` and `precmd` and sends one line over a Unix socket (`/tmp/terminal-pet-<uid>.sock`) using zsh's built-in `zsocket`, so nothing is spawned per prompt. It is a no-op when the pet isn't running.

It also gives you a `pet` command:

```zsh
pet            # poke it
pet ghost      # switch to another pet (any name from `pet list`, a folder, or a .gif)
pet sad        # force a state: idle | working | happy | sad | sleeping
pet scale 4    # resize
pet anchor inside-bottom-left
pet list       # what's installed
pet status
pet quit
```

## Changing things on the fly

While a pet is running, the CLI talks to it instead of starting another one, and every change is written to the config file so it sticks:

```bash
terminal-pet --pet ghost                 # ok now showing Ghost (saved to config)
terminal-pet --scale 4
terminal-pet --anchor top-right
terminal-pet status                      # pet=Ghost state=idle anchor=top-right scale=4.0 ...
```

The same flags with no pet running start one with those settings.

Anything else can send raw events with `terminal-pet send <event>`, e.g. from a Makefile, a CI script, or bash:

```bash
terminal-pet send preexec make
terminal-pet send precmd 1      # exit status
```

## Bundled pets

| name    | who |
|---------|-----|
| `blob`  | a round blue blob (default) |
| `cat`   | an orange tabby that wags its tail |
| `ghost` | a floating ghost that bobs up and down |
| `robot` | a boxy robot whose screen face and antenna light change with its mood |
| `chick` | a yellow chick that flaps its wings when a command succeeds |

Pick one with `"pet": "cat"` in the config or `terminal-pet --pet cat`. `terminal-pet pets` lists everything installed.

## Configuration

`~/.config/terminal-pet/config.json` (created by `make install`, every key optional):

| key               | default       | meaning |
|-------------------|---------------|---------|
| `pet`             | `"blob"`      | pet name, a directory, or a single `.gif` file |
| `scale`           | `3`           | size multiplier for the sprite |
| `anchor`          | `"inside-bottom-right"` | `inside-bottom-right`, `inside-bottom-left`, `inside-top-right`, `inside-top-left` (over the window content), or `top-right`, `top-left` (perched on the title bar) |
| `offsetX` / `offsetY` | `16` / `16` | nudge from the anchor, in points |
| `idleAfter`       | `90`          | seconds of inactivity before it falls asleep |
| `reactionSeconds` | `2.5`         | how long happy/sad is shown |
| `pollHz`          | `30`          | how often it checks where the terminal window is |
| `smooth`          | `false`       | bilinear scaling instead of crisp pixels (for photo-like GIFs) |
| `terminals`       | see example   | app names or bundle IDs treated as terminals |

Flags override the file for one run: `terminal-pet --pet ~/Downloads/cat.gif --scale 1 --anchor top-right`.

## Making your own pet

A pet is a folder with one animated image per state. Unknown states fall back to `idle`, so a single `idle.gif` is enough.

```
~/.config/terminal-pet/pets/cat/
├── pet.json      (optional)
├── idle.gif
├── working.gif
├── happy.gif
├── sad.gif
└── sleeping.gif
```

`pet.json` lets you name it and use different file names:

```json
{ "name": "Cat", "states": { "idle": "sit.gif", "working": "typing.gif" } }
```

GIF and APNG are both supported and per-frame delays are respected. Pixel art is drawn with nearest-neighbour scaling, so a 24x24 sprite at `scale: 3` is crisp. `terminal-pet pets` lists everything it can find. Pets are searched in `$TERMINAL_PET_PETS_DIR`, `~/.config/terminal-pet/pets`, then the installed share directory.

The bundled pets are all generated from [scripts/gen-pets.swift](scripts/gen-pets.swift): each one is a small ASCII-art body plus shared helpers for eyes, mouths, tears and Zs. `make pets` regenerates them and writes a contact sheet to `.build/pets-sheet.png`. Copy one of the `func cat()`-style definitions to make a new character.

## How it works

- `Sources/terminal-pet/TerminalTracker.swift` finds the frontmost terminal window through `CGWindowListCopyWindowInfo`. Window bounds aren't permission-gated, so no Accessibility or Screen Recording prompts.
- `PetPanel.swift` is a borderless, transparent, non-activating `NSPanel` at floating level. Clicking it never steals focus.
- `AnimationView.swift` decodes frames with ImageIO and drives the timing itself, so state changes restart cleanly.
- `EventServer.swift` is a ~100-line Unix socket listener; `shell/terminal-pet.plugin.zsh` is the client.

## Roadmap

- [ ] Sound / notification on long command completion
- [ ] tmux awareness (which pane is active)
- [ ] Linux (X11/Wayland overlay) and Windows
- [ ] bash / fish plugins

## License

MIT
