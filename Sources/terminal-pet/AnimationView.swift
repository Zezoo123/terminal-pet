import AppKit

/// Draws an Animation frame by frame with its own timing, nearest-neighbour scaled by default.
final class AnimationView: NSView {
    var smooth = false
    var onPoke: (() -> Void)?

    private var animation: Animation?
    private var index = 0
    private var timer: Timer?

    override var isOpaque: Bool { false }

    func play(_ animation: Animation?) {
        timer?.invalidate()
        timer = nil
        self.animation = animation
        index = 0
        needsDisplay = true
        scheduleNext()
    }

    private func scheduleNext() {
        guard let a = animation, a.frames.count > 1 else { return }
        let t = Timer(timeInterval: a.delays[index], repeats: false) { [weak self] _ in
            self?.advance()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func advance() {
        guard let a = animation else { return }
        index = (index + 1) % a.frames.count
        needsDisplay = true
        scheduleNext()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)
        guard let a = animation else { return }
        ctx.interpolationQuality = smooth ? .high : .none
        ctx.draw(a.frames[index], in: bounds)
    }

    override func mouseDown(with event: NSEvent) {
        onPoke?()
    }
}
