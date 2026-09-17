import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var config: Config
    private var pet: Pet
    private var stats = Stats.load()
    private let panel = PetPanel()
    private let view = AnimationView()
    private let tracker: TerminalTracker
    private var server: EventServer?

    private(set) var state: PetState = .idle
    private var lastActivity = Date()
    private var reactions: [CompiledReaction] = []
    private var commandRunning = false
    private var currentReaction: Reaction?
    private var lastHungerNag = Date.distantPast
    /// After `state <name>` is forced from the shell, automatic idle/hungry/sleep transitions pause until this time.
    private var manualUntil = Date.distantPast
    private var reactionTimer: Timer?
    private var bubbleTimer: Timer?
    private var pollTimer: Timer?
    private var saveTimer: Timer?
    private var lastTerminal: TerminalWindow?
    private let debug = ProcessInfo.processInfo.environment["TERMINAL_PET_DEBUG"] != nil

    /// What the user calls the pet.
    private var petName: String { config.name ?? pet.name }

    init(config: Config, pet: Pet) {
        self.config = config
        self.pet = pet
        self.tracker = TerminalTracker(terminals: config.terminals)
        super.init()
        reactions = Reactions.compile(user: config.reactions)
    }

    private func log(_ msg: @autoclosure () -> String) {
        if debug { fputs("terminal-pet: \(msg())\n", stderr) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        view.smooth = config.smooth
        view.onPoke = { [weak self] in self?.handle(event: "poke") }
        panel.contentView = view
        setState(.idle)

        let socketPath = EventServer.defaultPath
        do {
            let s = EventServer(path: socketPath) { [weak self] line in self?.handle(event: line) ?? "error: shutting down" }
            try s.start()
            server = s
        } catch {
            fputs("terminal-pet: could not listen on \(socketPath): \(error)\n", stderr)
        }

        let interval = 1.0 / max(config.pollHz, 1)
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        pollTimer = t

        fputs("terminal-pet: showing '\(pet.name)', listening on \(socketPath)\n", stderr)
    }

    func applicationWillTerminate(_ notification: Notification) {
        stats.save()
        server?.stop()
    }

    /// Stats change on every command; write them at most once every couple of seconds.
    private func scheduleSave() {
        guard saveTimer == nil else { return }
        let t = Timer(timeInterval: 2, repeats: false) { [weak self] _ in
            self?.saveTimer = nil
            self?.stats.save()
        }
        RunLoop.main.add(t, forMode: .common)
        saveTimer = t
    }

    // MARK: - Events

    /// Lines from the zsh plugin / CLI. Returns one reply line.
    ///   shell activity:  preexec <cmd> | precmd <status>
    ///   interaction:     poke | feed | say <text> | state <name>
    ///   live settings:   pet <name|dir|file> | scale <n> | anchor <pos> | name <name>   (saved to config.json)
    ///   info:            status | stats | quit
    @discardableResult
    func handle(event: String) -> String {
        let parts = event.split(separator: " ", maxSplits: 1).map(String.init)
        guard let kind = parts.first else { return "error: empty event" }
        let arg = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
        log("event '\(event)' (state was \(state.rawValue))")

        switch kind {
        case "status":
            return "pet=\(pet.name) name=\(petName) state=\(state.rawValue) hunger=\(stats.hunger)% level=\(stats.level) "
                + "anchor=\(config.anchor) scale=\(config.scale) config=\(Config.configFile.path)"
        case "stats":
            return stats.summary(name: petName, state: state)
        case "pet":
            guard !arg.isEmpty else { return "error: pet needs a name, directory or image file" }
            do {
                pet = try Pet.load(arg)
            } catch {
                return "error: \(error)"
            }
            config.pet = arg
            setState(state)
            return "ok now showing \(pet.name)" + persist("pet", arg)
        case "name":
            guard !arg.isEmpty else { return "error: name needs a value" }
            config.name = arg
            say("hi, I'm \(arg)!")
            return "ok named \(arg)" + persist("name", arg)
        case "scale":
            guard let v = Double(arg), v > 0, v <= 20 else { return "error: scale must be a number between 0 and 20" }
            config.scale = v
            setState(state)
            return "ok scale \(v)" + persist("scale", v)
        case "anchor":
            guard Config.anchors.contains(arg) else { return "error: anchor must be one of " + Config.anchors.joined(separator: ", ") }
            config.anchor = arg
            view.alignRight = !config.anchor.hasSuffix("left")
            reposition(force: true)
            return "ok anchor \(arg)" + persist("anchor", arg)
        default:
            break
        }

        lastActivity = Date()
        reactionTimer?.invalidate()
        switch kind {
        case "preexec":
            commandRunning = true
            currentReaction = reactions.first { $0.matches(arg) }?.reaction
            if let start = currentReaction?.start {
                setState(PetState(rawValue: start.state ?? "") ?? .working)
                if let text = start.say { say(text, for: 60) }   // stays up until the command ends
            } else {
                setState(.working)
            }
        case "precmd":
            let status = Int(arg) ?? 0
            if commandRunning {
                commandRunning = false
                commandFinished(status: status)
            } else if state != .idle {
                // Plain Enter on an empty prompt: wake up, but don't re-celebrate an old status.
                setState(.idle)
            }
        case "poke":
            stats.pokes += 1
            if stats.pokes % 10 == 0 { stats.xp += 1 }
            scheduleSave()
            react(.happy)
            say(pick(["hi!", "hehe", ":)", "that tickles", "hello!"]))
        case "feed":
            let wasHungry = stats.isHungry
            stats.fedAt = Date().timeIntervalSince1970
            stats.timesFed += 1
            gainXP(5)
            react(.eating, for: 3)
            say(pick(wasHungry ? ["finally!", "so hungry...", "yum!!"] : ["yum!", "nom nom", "thanks!"]))
            return "ok \(petName) is fed (hunger 100%, +5 xp)"
        case "say":
            guard !arg.isEmpty else { return "error: say needs some text" }
            say(String(arg.prefix(60)), for: 4)
        case "state":
            guard let s = PetState(rawValue: arg) else {
                return "error: state must be one of " + PetState.allCases.map(\.rawValue).joined(separator: ", ")
            }
            manualUntil = Date().addingTimeInterval(8)
            setState(s)
        case "quit":
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return "ok bye"
        default:
            return "error: unknown event '\(kind)'"
        }
        return "ok"
    }

    private func commandFinished(status: Int) {
        stats.commandsRun += 1
        let step = status == 0 ? currentReaction?.success : currentReaction?.failure
        currentReaction = nil
        view.bubbleText = nil
        if status == 0 {
            stats.streak += 1
            stats.bestStreak = max(stats.bestStreak, stats.streak)
            react(PetState(rawValue: step?.state ?? "") ?? .happy)
            gainXP(1)
            if [5, 10, 25, 50, 100, 250, 500, 1000].contains(stats.streak) {
                say("\(stats.streak) in a row!")
            } else if stats.streak == stats.bestStreak, stats.streak > 10, stats.streak % 50 == 0 {
                say("new record!")
            } else if let text = step?.say {
                say(text)
            }
        } else {
            stats.commandsFailed += 1
            let lost = stats.streak
            stats.streak = 0
            react(PetState(rawValue: step?.state ?? "") ?? .sad)
            if lost >= 5 {
                say("streak of \(lost) lost")
            } else if let text = step?.say {
                say(text)
            } else if Int.random(in: 0..<4) == 0 {
                say(pick(["oops", "hmm", "exit \(status)", "try again"]))
            }
        }
        scheduleSave()
    }

    private func gainXP(_ amount: Int) {
        let before = stats.level
        stats.xp += amount
        if stats.level > before {
            say("level \(stats.level)!", for: 4)
        }
        scheduleSave()
    }

    private func persist(_ key: String, _ value: Any) -> String {
        do {
            try Config.save(key, value)
            return " (saved to config)"
        } catch {
            return " (could not save config: \(error))"
        }
    }

    private func pick(_ options: [String]) -> String { options.randomElement() ?? "" }

    // MARK: - Speech bubble

    private func say(_ text: String, for seconds: TimeInterval = 2.5) {
        bubbleTimer?.invalidate()
        view.bubbleText = text
        let t = Timer(timeInterval: seconds, repeats: false) { [weak self] _ in self?.view.bubbleText = nil }
        RunLoop.main.add(t, forMode: .common)
        bubbleTimer = t
    }

    // MARK: - State

    private func react(_ s: PetState, for seconds: TimeInterval? = nil) {
        setState(s)
        let t = Timer(timeInterval: seconds ?? config.reactionSeconds, repeats: false) { [weak self] _ in
            self?.setState(.idle)
        }
        RunLoop.main.add(t, forMode: .common)
        reactionTimer = t
    }

    private func setState(_ s: PetState) {
        if s != state { log("state -> \(s.rawValue)") }
        state = s
        let anim = pet.animation(for: s)
        view.play(anim)
        if let a = anim {
            let sprite = NSSize(width: CGFloat(a.width) * config.scale, height: CGFloat(a.height) * config.scale)
            view.spriteSize = sprite
            view.scale = CGFloat(config.scale)
            view.alignRight = !config.anchor.hasSuffix("left")
            let size = NSSize(width: view.minWidth, height: sprite.height + view.bubbleSpace)
            if panel.frame.size != size {
                panel.setContentSize(size)
                reposition(force: true)
            }
        }
    }

    // MARK: - Following the terminal

    private func tick() {
        let idleFor = Date().timeIntervalSince(lastActivity)
        if Date() < manualUntil {
            // a forced state stays put for a moment
        } else if state == .idle || state == .hungry {
            if idleFor > config.idleAfter {
                setState(.sleeping)
            } else if stats.isHungry, state == .idle {
                setState(.hungry)
                if Date().timeIntervalSince(lastHungerNag) > 300 {
                    lastHungerNag = Date()
                    say(pick(["feed me", "hungry...", "snack?", "so hungry"]), for: 4)
                }
            } else if !stats.isHungry, state == .hungry {
                setState(.idle)
            }
        }
        reposition(force: false)
    }

    private func reposition(force: Bool) {
        guard let term = tracker.frontmostTerminalWindow() else {
            if panel.isVisible { log("no terminal in front, hiding"); panel.orderOut(nil) }
            lastTerminal = nil
            return
        }
        if !force, term == lastTerminal, panel.isVisible { return }
        lastTerminal = term

        // Offsets apply to the sprite; the panel is wider (bubble room) and hugs the same side.
        let size = panel.frame.size
        let sprite = view.spriteSize
        let f = term.frame
        let ox = CGFloat(config.offsetX)
        let oy = CGFloat(config.offsetY)
        let left = config.anchor.hasSuffix("left")
        var origin = CGPoint.zero
        origin.x = left ? f.minX + ox : f.maxX - ox - size.width
        switch config.anchor {
        case "inside-top-left", "inside-top-right":
            origin.y = f.maxY - size.height - oy
        case "inside-bottom-left", "inside-bottom-right":
            origin.y = f.minY + oy
        default: // top-left / top-right: perched on the title bar
            origin.y = f.maxY + oy
        }

        // No room above the window (menu bar, maximised, full screen)? Tuck the pet inside instead.
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(f) }) ?? NSScreen.main {
            let vis = screen.visibleFrame
            if origin.y + size.height > vis.maxY { origin.y = f.maxY - size.height - oy }
            origin.x = min(max(origin.x, vis.minX), vis.maxX - size.width)
        }

        log("terminal pid \(term.pid) at \(f.integral) -> panel at \(origin) size \(size), sprite \(sprite)")
        panel.setFrameOrigin(origin)
        if !panel.isVisible { panel.orderFrontRegardless() }
    }
}
