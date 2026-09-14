import AppKit

let version = "0.1.0"

func usage() -> String {
    """
    terminal-pet \(version) - a little animated companion that sits on your terminal window

    usage:
      terminal-pet                   run the pet
      terminal-pet --pet NAME|DIR|FILE.gif    switch pet (live if one is running, else start with it)
      terminal-pet --scale N         change size
      terminal-pet --anchor POS      change position: \(Config.anchors.joined(separator: " | "))
      terminal-pet status            show what the running pet is doing
      terminal-pet pets              list pets found in the search paths
      terminal-pet send <event...>   raw event: preexec <cmd> | precmd <status> | poke | state <name> | quit
      terminal-pet socket            print the socket path
      terminal-pet --help | --version

    When a pet is already running, --pet / --scale / --anchor change it on the spot and are
    saved to the config file. When none is running, they start one with those settings.

    config: \(Config.configFile.path)
    states: \(PetState.allCases.map(\.rawValue).joined(separator: ", "))
    """
}

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
    fputs("terminal-pet: already running (use --pet/--scale/--anchor to change it, or `terminal-pet send quit`)\n", stderr)
    exit(1)
}

let pet: Pet
do {
    pet = try Pet.load(config.pet)
} catch {
    fputs("terminal-pet: \(error)\n", stderr)
    exit(1)
}

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
