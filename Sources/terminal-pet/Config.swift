import Foundation

/// User configuration, read from ~/.config/terminal-pet/config.json.
/// Every key is optional; missing keys fall back to the defaults below.
struct Config: Codable {
    /// Pet to show: a name looked up in the pet search paths, a directory, or a single .gif file.
    var pet: String = "blob"
    /// What you call it. Defaults to the pet's own name.
    var name: String? = nil
    /// Integer-ish multiplier applied to the sprite size (pixel art looks best at 2-4).
    var scale: Double = 3
    /// Where the pet sits relative to the terminal window:
    /// top-right | top-left (perched on the title bar)
    /// inside-top-right | inside-top-left | inside-bottom-right | inside-bottom-left
    var anchor: String = "inside-bottom-right"
    var offsetX: Double = 16
    var offsetY: Double = 16
    /// Seconds without shell activity before the pet falls asleep.
    var idleAfter: Double = 90
    /// How long a happy/sad reaction is shown before returning to idle.
    var reactionSeconds: Double = 2.5
    /// How often per second the pet checks where the terminal window is.
    var pollHz: Double = 30
    /// Smooth (bilinear) scaling instead of crisp nearest-neighbour. Use for photo-like GIFs.
    var smooth: Bool = false
    /// App names or bundle identifiers that count as a terminal.
    var terminals: [String] = Config.defaultTerminals

    static let defaultTerminals = [
        "Terminal", "iTerm2", "iTerm", "kitty", "Alacritty", "WezTerm",
        "Ghostty", "Warp", "Hyper", "Tabby", "Rio",
    ]

    static var configDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/terminal-pet")
    }
    static var configFile: URL { configDir.appendingPathComponent("config.json") }

    enum CodingKeys: String, CodingKey {
        case pet, name, scale, anchor, offsetX, offsetY, idleAfter, reactionSeconds, pollHz, smooth, terminals
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pet = try c.decodeIfPresent(String.self, forKey: .pet) ?? pet
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? name
        scale = try c.decodeIfPresent(Double.self, forKey: .scale) ?? scale
        anchor = try c.decodeIfPresent(String.self, forKey: .anchor) ?? anchor
        offsetX = try c.decodeIfPresent(Double.self, forKey: .offsetX) ?? offsetX
        offsetY = try c.decodeIfPresent(Double.self, forKey: .offsetY) ?? offsetY
        idleAfter = try c.decodeIfPresent(Double.self, forKey: .idleAfter) ?? idleAfter
        reactionSeconds = try c.decodeIfPresent(Double.self, forKey: .reactionSeconds) ?? reactionSeconds
        pollHz = try c.decodeIfPresent(Double.self, forKey: .pollHz) ?? pollHz
        smooth = try c.decodeIfPresent(Bool.self, forKey: .smooth) ?? smooth
        terminals = try c.decodeIfPresent([String].self, forKey: .terminals) ?? terminals
    }

    static let anchors = ["top-right", "top-left", "inside-top-right", "inside-top-left",
                          "inside-bottom-right", "inside-bottom-left"]

    /// Writes a single key into config.json, keeping every other key (and unknown ones) intact.
    static func save(_ key: String, _ value: Any) throws {
        var dict: [String: Any] = [:]
        if let data = try? Data(contentsOf: configFile),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            dict = existing
        }
        dict[key] = value
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
        try (data + Data("\n".utf8)).write(to: configFile)
    }

    static func load() -> Config {
        guard let data = try? Data(contentsOf: configFile) else { return Config() }
        do {
            return try JSONDecoder().decode(Config.self, from: data)
        } catch {
            fputs("terminal-pet: could not parse \(configFile.path): \(error)\n", stderr)
            return Config()
        }
    }
}
