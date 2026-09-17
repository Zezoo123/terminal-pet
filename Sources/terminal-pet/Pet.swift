import Foundation

enum PetState: String, CaseIterable {
    case idle, working, happy, sad, sleeping, eating, hungry, celebrate, pushing, scared

    /// What to show when a pet has no animation for a state.
    var fallback: PetState? {
        switch self {
        case .idle: return nil
        case .eating, .celebrate: return .happy
        case .pushing, .scared: return .working
        default: return .idle
        }
    }
}

/// Optional pet.json inside a pet directory.
struct PetManifest: Codable {
    var name: String?
    var author: String?
    var states: [String: String]?
}

final class Pet {
    let name: String
    let animations: [PetState: Animation]

    init(name: String, animations: [PetState: Animation]) {
        self.name = name
        self.animations = animations
    }

    /// Walks the fallback chain (eating -> happy -> idle, everything else -> idle).
    func animation(for state: PetState) -> Animation? {
        var s: PetState? = state
        while let current = s {
            if let a = animations[current] { return a }
            s = current.fallback
        }
        return animations[.idle]
    }

    enum LoadError: Error, CustomStringConvertible {
        case notFound(String, [URL])
        case noIdle(String)

        var description: String {
            switch self {
            case let .notFound(spec, paths):
                let list = paths.map { "  - " + $0.path }.joined(separator: "\n")
                return "pet '\(spec)' not found. Searched:\n\(list)"
            case let .noIdle(path):
                return "no usable idle animation in \(path) (need idle.gif / idle.png or a pet.json)"
            }
        }
    }

    /// `spec` is a pet name (looked up in `searchPaths()`), a directory path, or a single image file.
    static func load(_ spec: String) throws -> Pet {
        let fm = FileManager.default
        let expanded = (spec as NSString).expandingTildeInPath
        var isDir: ObjCBool = false
        if spec.contains("/"), fm.fileExists(atPath: expanded, isDirectory: &isDir) {
            let url = URL(fileURLWithPath: expanded)
            return isDir.boolValue ? try load(directory: url) : try load(singleFile: url)
        }
        for dir in searchPaths() {
            let candidate = dir.appendingPathComponent(spec)
            if fm.fileExists(atPath: candidate.path, isDirectory: &isDir), isDir.boolValue {
                return try load(directory: candidate)
            }
        }
        throw LoadError.notFound(spec, searchPaths())
    }

    /// Directories that may contain pet folders, in priority order.
    static func searchPaths() -> [URL] {
        var paths: [URL] = []
        if let env = ProcessInfo.processInfo.environment["TERMINAL_PET_PETS_DIR"], !env.isEmpty {
            paths.append(URL(fileURLWithPath: (env as NSString).expandingTildeInPath))
        }
        paths.append(Config.configDir.appendingPathComponent("pets"))
        if let exe = Bundle.main.executableURL?.resolvingSymlinksInPath() {
            let bin = exe.deletingLastPathComponent()
            // Installed layout: <prefix>/bin/terminal-pet + <prefix>/share/terminal-pet/pets
            paths.append(bin.appendingPathComponent("../share/terminal-pet/pets").standardized)
            // Dev layout: .build/<triple>/debug/terminal-pet + ./pets
            paths.append(bin.appendingPathComponent("../../../pets").standardized)
        }
        var seen = Set<String>()
        return paths.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    /// Lists pet names found across the search paths.
    static func available() -> [(name: String, location: URL)] {
        let fm = FileManager.default
        var seen = Set<String>()
        var result: [(String, URL)] = []
        for dir in searchPaths() {
            guard let entries = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            for entry in entries.sorted() where !seen.contains(entry) {
                var isDir: ObjCBool = false
                let url = dir.appendingPathComponent(entry)
                if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue,
                   (try? load(directory: url)) != nil {
                    seen.insert(entry)
                    result.append((entry, url))
                }
            }
        }
        return result
    }

    static func load(directory url: URL) throws -> Pet {
        var name = url.lastPathComponent
        var states: [String: String] = [:]
        let manifestURL = url.appendingPathComponent("pet.json")
        if let data = try? Data(contentsOf: manifestURL) {
            let m = try JSONDecoder().decode(PetManifest.self, from: data)
            name = m.name ?? name
            states = m.states ?? [:]
        }
        // Auto-discover <state>.gif / <state>.png for anything the manifest didn't mention.
        let files = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        let imageExts: Set<String> = ["gif", "png", "apng"]
        for state in PetState.allCases where states[state.rawValue] == nil {
            if let f = files.first(where: {
                ($0 as NSString).deletingPathExtension == state.rawValue
                    && imageExts.contains(($0 as NSString).pathExtension.lowercased())
            }) {
                states[state.rawValue] = f
            }
        }
        var animations: [PetState: Animation] = [:]
        for (key, file) in states {
            guard let state = PetState(rawValue: key) else {
                fputs("terminal-pet: \(name): ignoring unknown state '\(key)'\n", stderr)
                continue
            }
            guard let anim = Animation.load(url: url.appendingPathComponent(file)) else {
                fputs("terminal-pet: \(name): could not load \(file) for state '\(key)'\n", stderr)
                continue
            }
            animations[state] = anim
        }
        guard animations[.idle] != nil else { throw LoadError.noIdle(url.path) }
        return Pet(name: name, animations: animations)
    }

    static func load(singleFile url: URL) throws -> Pet {
        guard let anim = Animation.load(url: url) else { throw LoadError.noIdle(url.path) }
        return Pet(name: url.deletingPathExtension().lastPathComponent, animations: [.idle: anim])
    }
}
