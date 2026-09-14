import Foundation

/// `terminal-pet setup [--shell zsh|bash|fish] [--print]`
/// Hooks the matching plugin into the user's shell and makes sure the binary is on PATH.
enum ShellSetup {
    static let shells = ["zsh", "bash", "fish"]

    static func run(args: [String]) -> Int32 {
        var shell = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh").lastPathComponent
        var printOnly = false
        var i = 0
        while i < args.count {
            switch args[i] {
            case "--shell", "-s":
                i += 1
                guard i < args.count else { fputs("terminal-pet setup: --shell needs a value\n", stderr); return 2 }
                shell = args[i]
            case "--print", "-n":
                printOnly = true
            case "-h", "--help":
                print(usage)
                return 0
            default:
                fputs("terminal-pet setup: unknown argument '\(args[i])'\n\(usage)\n", stderr)
                return 2
            }
            i += 1
        }
        guard shells.contains(shell) else {
            fputs("terminal-pet setup: unsupported shell '\(shell)' (supported: \(shells.joined(separator: ", ")))\n", stderr)
            return 1
        }
        guard let share = shareDir() else {
            fputs("terminal-pet setup: cannot find the shell plugins next to this binary (run `make install` first)\n", stderr)
            return 1
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let bin = (Bundle.main.executableURL.map { stableHomebrewPath($0.resolvingSymlinksInPath()) }?.deletingLastPathComponent().path) ?? ""
        let onPath = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init).contains(bin)

        let target: URL
        var lines: [String] = []
        switch shell {
        case "zsh":
            target = home.appendingPathComponent(".zshrc")
            if !onPath { lines.append("export PATH=\"\(dollarHome(bin)):$PATH\"") }
            lines.append("source \"\(dollarHome(share.appendingPathComponent("terminal-pet.plugin.zsh").path))\"")
        case "bash":
            let profile = home.appendingPathComponent(".bash_profile")
            let rc = home.appendingPathComponent(".bashrc")
            // macOS terminals open login shells, which read .bash_profile; prefer it when it exists.
            target = FileManager.default.fileExists(atPath: profile.path) || !FileManager.default.fileExists(atPath: rc.path) ? profile : rc
            if !onPath { lines.append("export PATH=\"\(dollarHome(bin)):$PATH\"") }
            lines.append("source \"\(dollarHome(share.appendingPathComponent("terminal-pet.plugin.bash").path))\"")
        default: // fish: conf.d files are auto-loaded, no rc editing needed
            target = home.appendingPathComponent(".config/fish/conf.d/terminal-pet.fish")
            if !onPath { lines.append("fish_add_path -g \"\(bin)\"") }
            lines.append("source \"\(share.appendingPathComponent("terminal-pet.fish").path)\"")
        }

        let block = "\n# terminal-pet\n" + lines.joined(separator: "\n") + "\n"
        if printOnly {
            print("# add to \(tilde(target.path)):")
            print(lines.joined(separator: "\n"))
            return 0
        }

        let existing = (try? String(contentsOf: target, encoding: .utf8)) ?? ""
        if existing.contains("terminal-pet.plugin.\(shell)") || existing.contains("terminal-pet.fish") {
            print("\(tilde(target.path)) already loads the terminal-pet plugin, nothing to do.")
            return 0
        }
        do {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let handle: FileHandle
            if FileManager.default.fileExists(atPath: target.path) {
                handle = try FileHandle(forWritingTo: target)
                handle.seekToEndOfFile()
            } else {
                FileManager.default.createFile(atPath: target.path, contents: nil)
                handle = try FileHandle(forWritingTo: target)
            }
            handle.write(Data(block.utf8))
            try handle.close()
        } catch {
            fputs("terminal-pet setup: could not write \(target.path): \(error)\n", stderr)
            return 1
        }
        print("added to \(tilde(target.path)):")
        print(lines.map { "  " + $0 }.joined(separator: "\n"))
        print("open a new terminal (or `source` that file), start the pet with `terminal-pet`, and run a command.")
        return 0
    }

    /// Where the shell plugins live: <prefix>/share/terminal-pet next to an installed binary, or ./shell in a checkout.
    static func shareDir() -> URL? {
        guard let exe = Bundle.main.executableURL?.resolvingSymlinksInPath() else { return nil }
        let bin = stableHomebrewPath(exe).deletingLastPathComponent()
        let candidates = [
            bin.appendingPathComponent("../share/terminal-pet").standardized,
            bin.appendingPathComponent("../../../shell").standardized,
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("terminal-pet.plugin.zsh").path) }
    }

    /// Homebrew installs into a versioned Cellar directory; the opt/ symlink survives upgrades, so write that.
    /// /opt/homebrew/Cellar/terminal-pet/0.2.1/bin/terminal-pet -> /opt/homebrew/opt/terminal-pet/bin/terminal-pet
    static func stableHomebrewPath(_ url: URL) -> URL {
        let parts = url.pathComponents
        guard let i = parts.firstIndex(of: "Cellar"), i + 2 < parts.count else { return url }
        let stable = parts[..<i] + ["opt", parts[i + 1]] + parts[(i + 3)...]
        return URL(fileURLWithPath: stable.joined(separator: "/").replacingOccurrences(of: "//", with: "/"))
    }

    /// "$HOME/..." expands inside double quotes; "~/..." does not.
    static func dollarHome(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "$HOME" + path.dropFirst(home.count) : path
    }

    static func tilde(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    static let usage = """
    terminal-pet setup [--shell zsh|bash|fish] [--print]
      Adds the plugin for your shell (from $SHELL unless --shell is given) to its startup file and
      puts terminal-pet on your PATH if needed. --print only shows the lines it would add.
    """
}
