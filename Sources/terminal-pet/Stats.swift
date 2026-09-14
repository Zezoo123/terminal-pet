import Foundation

/// The pet's life so far. Persisted to ~/.config/terminal-pet/stats.json.
struct Stats: Codable {
    var xp = 0
    var commandsRun = 0
    var commandsFailed = 0
    var streak = 0
    var bestStreak = 0
    var timesFed = 0
    var pokes = 0
    var fedAt = Date().timeIntervalSince1970
    var bornAt = Date().timeIntervalSince1970

    /// Hours from completely full to starving.
    static let hungerHours = 8.0
    static let hungryBelow = 25

    /// 100 = just fed, 0 = starving. Decays linearly with wall-clock time.
    var hunger: Int {
        let hours = (Date().timeIntervalSince1970 - fedAt) / 3600
        return max(0, min(100, Int(((1 - hours / Stats.hungerHours) * 100).rounded())))
    }
    var isHungry: Bool { hunger < Stats.hungryBelow }

    /// Level 1 at 0 xp, 2 at 20, 3 at 80, 4 at 180, 5 at 320 ...
    var level: Int { Int((Double(xp) / 20).squareRoot()) + 1 }
    var xpForNextLevel: Int { level * level * 20 }

    var age: String {
        let secs = Int(Date().timeIntervalSince1970 - bornAt)
        let d = secs / 86400, h = (secs % 86400) / 3600, m = (secs % 3600) / 60
        if d > 0 { return "\(d)d\(h)h" }
        if h > 0 { return "\(h)h\(m)m" }
        return "\(m)m"
    }

    static var file: URL { Config.configDir.appendingPathComponent("stats.json") }

    enum CodingKeys: String, CodingKey {
        case xp, commandsRun, commandsFailed, streak, bestStreak, timesFed, pokes, fedAt, bornAt
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        xp = try c.decodeIfPresent(Int.self, forKey: .xp) ?? xp
        commandsRun = try c.decodeIfPresent(Int.self, forKey: .commandsRun) ?? commandsRun
        commandsFailed = try c.decodeIfPresent(Int.self, forKey: .commandsFailed) ?? commandsFailed
        streak = try c.decodeIfPresent(Int.self, forKey: .streak) ?? streak
        bestStreak = try c.decodeIfPresent(Int.self, forKey: .bestStreak) ?? bestStreak
        timesFed = try c.decodeIfPresent(Int.self, forKey: .timesFed) ?? timesFed
        pokes = try c.decodeIfPresent(Int.self, forKey: .pokes) ?? pokes
        fedAt = try c.decodeIfPresent(Double.self, forKey: .fedAt) ?? fedAt
        bornAt = try c.decodeIfPresent(Double.self, forKey: .bornAt) ?? bornAt
    }

    static func load() -> Stats {
        guard let data = try? Data(contentsOf: file) else { return Stats() }
        do {
            return try JSONDecoder().decode(Stats.self, from: data)
        } catch {
            fputs("terminal-pet: could not parse \(file.path): \(error)\n", stderr)
            return Stats()
        }
    }

    func save() {
        do {
            try FileManager.default.createDirectory(at: Config.configDir, withIntermediateDirectories: true)
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try (try enc.encode(self) + Data("\n".utf8)).write(to: Stats.file)
        } catch {
            fputs("terminal-pet: could not save stats: \(error)\n", stderr)
        }
    }

    /// One line, `key=value` pairs, no spaces inside values. Parsed by the CLI for `terminal-pet stats`.
    func summary(name: String, state: PetState) -> String {
        "name=\(name) level=\(level) xp=\(xp)/\(xpForNextLevel) hunger=\(hunger)% mood=\(state.rawValue) "
            + "commands=\(commandsRun) failed=\(commandsFailed) streak=\(streak) best=\(bestStreak) fed=\(timesFed) pokes=\(pokes) age=\(age)"
    }
}
