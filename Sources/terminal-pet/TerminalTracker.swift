import AppKit

struct TerminalWindow: Equatable {
    let pid: pid_t
    /// Frame in AppKit screen coordinates (origin bottom-left of the primary display).
    let frame: CGRect
}

/// Finds the frontmost window of the frontmost terminal app using the public window list.
/// Needs no Accessibility or Screen Recording permission: window bounds are not gated.
final class TerminalTracker {
    private let terminals: [String]

    init(terminals: [String]) {
        self.terminals = terminals.map { $0.lowercased() }
    }

    func isTerminal(_ app: NSRunningApplication) -> Bool {
        let name = app.localizedName?.lowercased() ?? ""
        let bundle = app.bundleIdentifier?.lowercased() ?? ""
        return terminals.contains { $0 == name || $0 == bundle }
    }

    func frontmostTerminalWindow() -> TerminalWindow? {
        guard let app = NSWorkspace.shared.frontmostApplication, isTerminal(app) else { return nil }
        let pid = app.processIdentifier
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        // The list is ordered front to back, so the first match is the window the user is looking at.
        for info in list {
            guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  bounds.width > 100, bounds.height > 50
            else { continue }
            if let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue, alpha == 0 { continue }
            return TerminalWindow(pid: pid, frame: Self.toAppKit(bounds))
        }
        return nil
    }

    /// Core Graphics uses a top-left origin on the primary display; AppKit uses bottom-left.
    static func toAppKit(_ r: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }
}
