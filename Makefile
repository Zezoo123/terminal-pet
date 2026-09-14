PREFIX ?= $(HOME)/.local
BIN     = $(PREFIX)/bin
SHARE   = $(PREFIX)/share/terminal-pet
CONFIG  = $(HOME)/.config/terminal-pet
AGENT   = $(HOME)/Library/LaunchAgents/com.terminal-pet.plist

.PHONY: build run release install uninstall pets launchd unlaunchd clean

build:
	swift build

## Run from the repo without installing (uses ./pets).
run: build
	TERMINAL_PET_PETS_DIR=$(CURDIR)/pets swift run terminal-pet

release:
	swift build -c release

## Install the binary, bundled pets and the zsh plugin.
install: release
	install -d "$(BIN)" "$(SHARE)" "$(CONFIG)"
	install -m 755 .build/release/terminal-pet "$(BIN)/terminal-pet"
	rm -rf "$(SHARE)/pets" && cp -R pets "$(SHARE)/pets"
	install -m 644 shell/terminal-pet.plugin.zsh "$(SHARE)/terminal-pet.plugin.zsh"
	@test -f "$(CONFIG)/config.json" || cp config.example.json "$(CONFIG)/config.json"
	@echo
	@echo "installed to $(BIN)/terminal-pet"
	@echo "add to ~/.zshrc:   source $(SHARE)/terminal-pet.plugin.zsh"
	@echo "config lives at:   $(CONFIG)/config.json"
	@echo "start it with:     $(BIN)/terminal-pet &   (or: make launchd)"

uninstall: unlaunchd
	rm -f "$(BIN)/terminal-pet"
	rm -rf "$(SHARE)"
	@echo "left your config in $(CONFIG)"

## Regenerate the bundled blob pet from scripts/gen-default-pet.swift.
pets:
	mkdir -p .build
	swiftc -O -o .build/gen-default-pet scripts/gen-default-pet.swift
	.build/gen-default-pet pets/blob

## Start the pet at login via launchd.
launchd:
	@test -x "$(BIN)/terminal-pet" || (echo "run 'make install' first" && exit 1)
	sed -e 's|@BIN@|$(BIN)/terminal-pet|g' -e 's|@HOME@|$(HOME)|g' scripts/com.terminal-pet.plist > "$(AGENT)"
	-launchctl bootout gui/$$(id -u) "$(AGENT)" 2>/dev/null
	launchctl bootstrap gui/$$(id -u) "$(AGENT)"
	@echo "launch agent installed: $(AGENT)"

unlaunchd:
	-launchctl bootout gui/$$(id -u) "$(AGENT)" 2>/dev/null
	rm -f "$(AGENT)"

clean:
	rm -rf .build
