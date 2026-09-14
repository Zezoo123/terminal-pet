import AppKit

let version = "0.2.0"

func usage() -> String {
    """
    terminal-pet \(version) - a little animated companion that sits on your terminal window

    usage:
      terminal-pet [start]           start the pet in the background (detached from this shell)
      terminal-pet stop              stop it
      terminal-pet setup             hook it into your shell (zsh, bash or fish) and PATH
      terminal-pet --foreground      run attached to this shell (Ctrl-C to quit); used by launchd
      terminal-pet --pet NAME|DIR|FILE.gif    switch pet (live if one is running, else start with it)
      terminal-pet --scale N         change size
      terminal-pet --anchor POS      change position: \(Config.anchors.joined(separator: " | "))
      terminal-pet feed              feed it (hunger runs out over ~8 hours)
      terminal-pet poke              pet it
      terminal-pet say <text>        make it say something (great from scripts and CI)
      terminal-pet name <name>       give it a name
      terminal-pet stats             level, xp, hunger, streaks, age
      terminal-pet status            what the running pet is doing right now
      terminal-pet pets              list pets found in the search paths
      terminal-pet send <event...>   raw event: preexec <cmd> | precmd <status> | state <name> | quit
      terminal-pet socket            print the socket path
      terminal-pet --help | --version

    When a pet is already running, --pet / --scale / --anchor change it on the spot and are
    saved to the config file. When none is running, they start one with those settings.

    config: \(Config.configFile.path)
    states: \(PetState.allCases.map(\.rawValue).joined(separator: ", "))
    """
}


// Clients (the zsh hooks) often close before reading our reply. Writing to them must not kill us.
signal(SIGPIPE, SIG_IGN)

var args = Array(CommandLine.arguments.dropFirst())
var config = Config.load()

if let first = args.first {
    switch first {
    case "send":
        let message = args.dropFirst().joined(separator: " ")
        guard !message.isEmpty else { fputs("terminal-pet send: missing event\n", stderr); exit(2) }
        if let reply = EventServer.send(message, path: EventServer.defaultPath) {
            print(reply)
            exit(reply.hasPrefix("error") ? 1 : 0)
        }
        fputs("terminal-pet: no pet listening on \(EventServer.defaultPath)\n", stderr)
        exit(1)
    case "status":
        if let reply = EventServer.send("status", path: EventServer.defaultPath) { print(reply); exit(0) }
        print("not running")
        exit(1)
    case "feed", "poke", "say", "name":
        let message = ([first] + args.dropFirst()).joined(separator: " ")
        guard let reply = EventServer.send(message, path: EventServer.defaultPath) else {
            print("not running")
            exit(1)
        }
        print(reply)
        exit(reply.hasPrefix("error") ? 1 : 0)
    case "stats":
        guard let reply = EventServer.send("stats", path: EventServer.defaultPath) else {
            print("not running")
            exit(1)
        }
        let pairs = reply.split(separator: " ").map { $0.split(separator: "=", maxSplits: 1).map(String.init) }
        let width = pairs.map { $0[0].count }.max() ?? 0
        for p in pairs where p.count == 2 {
            print(p[0].padding(toLength: width, withPad: " ", startingAt: 0) + "  " + p[1])
        }
        exit(0)
    case "setup":
        exit(ShellSetup.run(args: Array(args.dropFirst())))
    case "stop":
        if let reply = EventServer.send("quit", path: EventServer.defaultPath) { print(reply); exit(0) }
        print("not running")
        exit(1)
    case "start":
        args.removeFirst()
    case "pets":
        let pets = Pet.available()
        if pets.isEmpty { print("no pets found in:\n" + Pet.searchPaths().map { "  " + $0.path }.joined(separator: "\n")) }
        for p in pets { print("\(p.name)\t\(p.location.path)") }
        exit(0)
    case "socket":
        print(EventServer.defaultPath)
        exit(0)
    case "-h", "--help", "help":
        print(usage())
        exit(0)
    case "--version", "-V":
        print("terminal-pet \(version)")
        exit(0)
    default:
        break
    }
}

var overrides: [(String, String)] = []
var foreground = false
var i = 0
while i < args.count {
    let flag = args[i]
    func value() -> String {
        i += 1
        guard i < args.count else { fputs("terminal-pet: \(flag) needs a value\n", stderr); exit(2) }
        return args[i]
    }
    switch flag {
    case "--pet": config.pet = value(); overrides.append(("pet", config.pet))
    case "--scale": config.scale = Double(value()) ?? config.scale; overrides.append(("scale", args[i]))
    case "--anchor": config.anchor = value(); overrides.append(("anchor", config.anchor))
    case "--foreground", "-f": foreground = true
    default:
        fputs("terminal-pet: unknown argument '\(flag)'\n\n\(usage())\n", stderr)
        exit(2)
    }
    i += 1
}

// A pet is already running: apply the flags to it instead of starting a second one.
if !overrides.isEmpty, EventServer.send("status", path: EventServer.defaultPath) != nil {
    var failed = false
    for (key, value) in overrides {
        let reply = EventServer.send("\(key) \(value)", path: EventServer.defaultPath) ?? "error: lost connection"
        print(reply)
        if reply.hasPrefix("error") { failed = true }
    }
    exit(failed ? 1 : 0)
}
if EventServer.send("status", path: EventServer.defaultPath) != nil {
    fputs("terminal-pet: already running (use --pet/--scale/--anchor to change it, or `terminal-pet stop`)\n", stderr)
    exit(1)
}

let pet: Pet
do {
    pet = try Pet.load(config.pet)
} catch {
    fputs("terminal-pet: \(error)\n", stderr)
    exit(1)
}

let isDaemonChild = ProcessInfo.processInfo.environment["TERMINAL_PET_DAEMON"] != nil

// Flags given at start are remembered, same as when they are applied to a running pet.
if !isDaemonChild {
    for (key, value) in overrides {
        try? Config.save(key, key == "scale" ? (Double(value) ?? config.scale) as Any : value)
    }
}

// Default: relaunch ourselves detached so the shell gets its prompt back.
if !foreground && !isDaemonChild {
    let logURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/terminal-pet.log")
    if !FileManager.default.fileExists(atPath: logURL.path) {
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
    }
    let child = Process()
    child.executableURL = Bundle.main.executableURL
    child.arguments = ["--foreground"] + overrides.flatMap { ["--\($0.0)", $0.1] }
    var env = ProcessInfo.processInfo.environment
    env["TERMINAL_PET_DAEMON"] = "1"
    child.environment = env
    child.standardInput = FileHandle.nullDevice
    if let log = try? FileHandle(forWritingTo: logURL) {
        log.seekToEndOfFile()
        child.standardOutput = log
        child.standardError = log
    }
    do {
        try child.run()
    } catch {
        fputs("terminal-pet: could not start background process: \(error)\n", stderr)
        exit(1)
    }
    // Only report success once the child is actually answering on the socket.
    for _ in 0..<100 {
        usleep(50_000)
        if EventServer.send("status", path: EventServer.defaultPath) != nil {
            print("terminal-pet started (\(pet.name), pid \(child.processIdentifier)). Log: \(logURL.path)")
            exit(0)
        }
        if !child.isRunning {
            fputs("terminal-pet: background process exited, see \(logURL.path)\n", stderr)
            exit(1)
        }
    }
    fputs("terminal-pet: background process did not come up, see \(logURL.path)\n", stderr)
    exit(1)
}

// One instance per user: hold an exclusive lock for as long as we run.
let lockPath = "/tmp/terminal-pet-\(getuid()).lock"
let lockFD = open(lockPath, O_CREAT | O_RDWR, 0o600)
if lockFD < 0 || flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
    fputs("terminal-pet: already running\n", stderr)
    exit(1)
}
if isDaemonChild {
    setsid()   // own session: closing the terminal that started us must not take us down
}
signal(SIGHUP, SIG_IGN)

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // no Dock icon, no menu bar
let delegate = AppDelegate(config: config, pet: pet)
app.delegate = delegate

// Ctrl-C / launchd stop: exit cleanly so the socket file is removed.
var signalSources: [DispatchSourceSignal] = []
for sig in [SIGINT, SIGTERM] {
    signal(sig, SIG_IGN)
    let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    src.setEventHandler { NSApp.terminate(nil) }
    src.resume()
    signalSources.append(src)
}

app.run()
