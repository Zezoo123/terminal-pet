import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let config: Config
    private let pet: Pet
    private let panel = PetPanel()
    private let view = AnimationView()
    private let tracker: TerminalTracker
    private var server: EventServer?

    private(set) var state: PetState = .idle
    private var lastActivity = Date()
    private var reactionTimer: Timer?
    private var pollTimer: Timer?
    private var lastTerminal: TerminalWindow?
    private let debug = ProcessInfo.processInfo.environment["TERMINAL_PET_DEBUG"] != nil

    private func log(_ msg: @autoclosure () -> String) {
        if debug { fputs("terminal-pet: \(msg())\n", stderr) }
    }

    init(config: Config, pet: Pet) {
        self.config = config
        self.pet = pet
        self.tracker = TerminalTracker(terminals: config.terminals)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        view.smooth = config.smooth
        view.onPoke = { [weak self] in self?.handle(event: "poke") }
        panel.contentView = view
        setState(.idle)

        let socketPath = EventServer.defaultPath
        do {
            let s = EventServer(path: socketPath) { [weak self] line in self?.handle(event: line) }
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
        server?.stop()
    }

    // MARK: - Events

    /// Lines from the zsh plugin / CLI: `preexec <cmd>`, `precmd <status>`, `poke`, `state <name>`, `quit`.
    func handle(event: String) {
        let parts = event.split(separator: " ", maxSplits: 1).map(String.init)
        guard let kind = parts.first else { return }
        let arg = parts.count > 1 ? parts[1] : ""
        lastActivity = Date()
        reactionTimer?.invalidate()
        log("event '\(event)' (state was \(state.rawValue))")

        switch kind {
        case "preexec":
            setState(.working)
        case "precmd":
            let status = Int(arg) ?? 0
            if state == .working {
                react(status == 0 ? .happy : .sad)
            } else if state != .idle {
                // Plain Enter on an empty prompt: wake up, but don't re-celebrate an old status.
                setState(.idle)
            }
        case "poke":
            react(.happy)
        case "state":
            if let s = PetState(rawValue: arg) { setState(s) }
        case "quit":
            NSApp.terminate(nil)
        default:
            break
        }
    }

    private func react(_ s: PetState) {
        setState(s)
        let t = Timer(timeInterval: config.reactionSeconds, repeats: false) { [weak self] _ in
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
            let size = NSSize(width: CGFloat(a.width) * config.scale, height: CGFloat(a.height) * config.scale)
            if panel.frame.size != size {
                panel.setContentSize(size)
                reposition(force: true)
            }
        }
    }

    // MARK: - Following the terminal

    private func tick() {
        if state == .idle, Date().timeIntervalSince(lastActivity) > config.idleAfter {
            setState(.sleeping)
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

        let size = panel.frame.size
        let f = term.frame
        let ox = CGFloat(config.offsetX)
        let oy = CGFloat(config.offsetY)
        var origin: CGPoint
        switch config.anchor {
        case "top-left":
            origin = CGPoint(x: f.minX + ox, y: f.maxY + oy)
        case "inside-top-left":
            origin = CGPoint(x: f.minX + ox, y: f.maxY - size.height - oy)
        case "inside-top-right":
            origin = CGPoint(x: f.maxX - size.width - ox, y: f.maxY - size.height - oy)
        case "inside-bottom-left":
            origin = CGPoint(x: f.minX + ox, y: f.minY + oy)
        case "inside-bottom-right":
            origin = CGPoint(x: f.maxX - size.width - ox, y: f.minY + oy)
        default: // top-right
            origin = CGPoint(x: f.maxX - size.width - ox, y: f.maxY + oy)
        }

        // No room above the window (menu bar, maximised, full screen)? Tuck the pet inside instead.
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(f) }) ?? NSScreen.main {
            let vis = screen.visibleFrame
            if origin.y + size.height > vis.maxY { origin.y = f.maxY - size.height - oy }
            origin.x = min(max(origin.x, vis.minX), vis.maxX - size.width)
        }

        log("terminal pid \(term.pid) at \(f.integral) -> pet at \(origin) size \(size)")
        panel.setFrameOrigin(origin)
        if !panel.isVisible { panel.orderFrontRegardless() }
    }
}
