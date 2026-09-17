import Foundation

/// What the pet does when a command line matches: at start, on exit 0, on any other exit.
struct Reaction: Codable {
    var match: String
    var start: ReactionStep?
    var success: ReactionStep?
    var failure: ReactionStep?
}

struct ReactionStep: Codable {
    var state: String?
    var say: String?
}

struct CompiledReaction {
    let regex: NSRegularExpression
    let reaction: Reaction

    func matches(_ command: String) -> Bool {
        regex.firstMatch(in: command, range: NSRange(command.startIndex..., in: command)) != nil
    }
}

enum Reactions {
    /// Built-in rules. First match wins; user rules from config.json are checked before these.
    static let defaults: [Reaction] = [
        r(#"^(sudo )?git push\b.*(--force|-f\b|\+)"#, start: ("scared", "force push?!"), success: ("celebrate", "force pushed"), failure: ("sad", "rejected")),
        r(#"^(sudo )?git push\b"#, start: ("pushing", "pushing..."), success: ("celebrate", "pushed!"), failure: ("sad", "push rejected")),
        r(#"^git commit\b"#, success: ("happy", "committed")),
        r(#"^git (pull|fetch)\b"#, start: ("working", "pulling..."), success: ("happy", "up to date")),
        r(#"^git merge\b"#, success: ("celebrate", "merged!"), failure: ("sad", "conflicts...")),
        r(#"^git rebase\b"#, start: ("scared", "rebasing..."), success: ("happy", "rebased"), failure: ("sad", "conflicts...")),
        r(#"^git stash\b"#, success: ("happy", "stashed")),
        r(#"^git (checkout|switch)\b"#, success: ("happy", "switched")),
        r(#"^git clone\b"#, start: ("working", "cloning..."), success: ("celebrate", "new repo!")),
        r(#"^git tag\b"#, success: ("happy", "tagged")),
        r(#"^gh pr create\b"#, success: ("celebrate", "PR opened!")),
        r(#"^gh pr merge\b"#, success: ("celebrate", "merged!")),
        r(#"^gh release create\b"#, success: ("celebrate", "released!")),
        r(#"^gh repo create\b"#, success: ("celebrate", "new repo!")),
        r(#"(^|\s)rm\s+-[a-z]*r"#, start: ("scared", "careful..."), success: ("happy", "gone.")),
        r(#"^sudo\b"#, start: ("scared", "sudo?!")),
        r(#"^(make|cargo build|swift build|go build|npm run build|yarn build|pnpm build|xcodebuild|gradle|mvn)\b"#,
          start: ("working", "building..."), success: ("celebrate", "build ok!"), failure: ("sad", "build failed")),
        r(#"^(pytest|npm test|yarn test|pnpm test|cargo test|go test|swift test|jest|vitest|rspec|phpunit|make test|make check)\b"#,
          start: ("working", "testing..."), success: ("celebrate", "tests pass!"), failure: ("sad", "tests failed")),
        r(#"^(brew|npm|pnpm|yarn|pip3?|cargo|gem|apt|apt-get|dnf|pacman) (install|add|-S)\b"#,
          start: ("working", "installing..."), success: ("happy", "installed")),
        r(#"^terraform (apply|destroy)\b"#, start: ("scared", "deploying..."), success: ("celebrate", "applied"), failure: ("sad", "apply failed")),
        r(#"^(vim|nvim|vi|nano|emacs|hx)\b"#, start: ("working", "editing...")),
        r(#"^ssh\b"#, start: ("working", "off to the server")),
        r(#"^(docker|docker-compose|podman|kubectl)\b"#, start: ("working", "containers...")),
    ]

    private static func r(_ match: String, start: (String, String)? = nil, success: (String, String)? = nil, failure: (String, String)? = nil) -> Reaction {
        Reaction(match: match,
                 start: start.map { ReactionStep(state: $0.0, say: $0.1) },
                 success: success.map { ReactionStep(state: $0.0, say: $0.1) },
                 failure: failure.map { ReactionStep(state: $0.0, say: $0.1) })
    }

    /// Compiles user rules (first) and defaults; bad regexes are reported and skipped.
    static func compile(user: [Reaction]) -> [CompiledReaction] {
        (user + defaults).compactMap { rule in
            do {
                return CompiledReaction(regex: try NSRegularExpression(pattern: rule.match, options: [.caseInsensitive]), reaction: rule)
            } catch {
                fputs("terminal-pet: ignoring reaction with bad pattern '\(rule.match)': \(error)\n", stderr)
                return nil
            }
        }
    }
}
