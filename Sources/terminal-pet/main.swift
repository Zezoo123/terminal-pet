import AppKit

let version = "0.1.0"

func usage() -> String {
    """
    terminal-pet \(version) - a little animated companion that sits on your terminal window

    usage:
      terminal-pet [--pet NAME|DIR|FILE.gif] [--scale N] [--anchor POS]   run the pet
      terminal-pet send <event...>   send an event to the running pet
                                     (preexec <cmd> | precmd <status> | poke | state <name> | quit)
      terminal-pet pets              list pets found in the search paths
      terminal-pet socket            print the socket path
      terminal-pet --help | --version

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
        if EventServer.send(message, path: EventServer.defaultPath) { exit(0) }
        fputs("terminal-pet: no pet listening on \(EventServer.defaultPath)\n", stderr)
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

var i = 0
while i < args.count {
    let flag = args[i]
    func value() -> String {
        i += 1
        guard i < args.count else { fputs("terminal-pet: \(flag) needs a value\n", stderr); exit(2) }
        return args[i]
    }
    switch flag {
    case "--pet": config.pet = value()
    case "--scale": config.scale = Double(value()) ?? config.scale
    case "--anchor": config.anchor = value()
    default:
        fputs("terminal-pet: unknown argument '\(flag)'\n\n\(usage())\n", stderr)
        exit(2)
    }
    i += 1
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
