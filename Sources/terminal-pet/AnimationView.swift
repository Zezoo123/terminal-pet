import AppKit

/// Draws the sprite (nearest-neighbour scaled by default) plus an optional speech bubble above it.
/// The view is wider than the sprite so bubbles have room; the sprite hugs one side.
final class AnimationView: NSView {
    /// The pet's scale; bubble typography and spacing follow it (designed at scale 3).
    var scale: CGFloat = 3
    private var factor: CGFloat { max(0.75, scale / 3) }
    var fontSize: CGFloat { (11 * factor).rounded() }
    /// Room reserved above the sprite for the bubble.
    var bubbleSpace: CGFloat { (fontSize + 6 * factor + 5 * factor + 8 * factor).rounded(.up) }
    /// Panel width so bubbles have somewhere to go.
    var minWidth: CGFloat { max(spriteSize.width, (170 * factor).rounded()) }

    var smooth = false
    var alignRight = true { didSet { needsDisplay = true } }
    var spriteSize = NSSize(width: 72, height: 72)
    var bubbleText: String? { didSet { needsDisplay = true } }
    var onPoke: (() -> Void)?

    private var animation: Animation?
    private var index = 0
    private var timer: Timer?

    override var isOpaque: Bool { false }

    var spriteRect: NSRect {
        let x = alignRight ? bounds.width - spriteSize.width : 0
        return NSRect(x: x, y: 0, width: spriteSize.width, height: spriteSize.height)
    }

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
        if let a = animation {
            ctx.interpolationQuality = smooth ? .high : .none
            ctx.draw(a.frames[index], in: spriteRect)
        }
        if let text = bubbleText, !text.isEmpty { drawBubble(text) }
    }

    private func drawBubble(_ text: String) {
        let ink = NSColor(red: 15 / 255, green: 23 / 255, blue: 42 / 255, alpha: 1)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: fontSize),
            .foregroundColor: ink,
        ]
        let f = factor
        let textSize = (text as NSString).size(withAttributes: attrs)
        let padX = (7 * f).rounded(), padY = (3 * f).rounded()
        let w = min(ceil(textSize.width) + padX * 2, bounds.width - 4)
        let h = ceil(textSize.height) + padY * 2
        let sprite = spriteRect
        var x = sprite.midX - w / 2
        x = max(2, min(x, bounds.width - w - 2))
        let tailLen = (5 * f).rounded()
        let y = sprite.maxY + tailLen
        let rect = NSRect(x: x, y: y, width: w, height: h)

        let radius = (6 * f).rounded()
        let bubble = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        let tailHalf = (4 * f).rounded()
        let tailX = max(rect.minX + radius + tailHalf, min(sprite.midX, rect.maxX - radius - tailHalf))
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: tailX - tailHalf, y: rect.minY + 1))
        tail.line(to: NSPoint(x: tailX, y: rect.minY - tailLen))
        tail.line(to: NSPoint(x: tailX + tailHalf, y: rect.minY + 1))
        tail.close()
        bubble.append(tail)

        NSColor.white.setFill()
        bubble.fill()
        ink.setStroke()
        bubble.lineWidth = max(1, (1 * f).rounded())
        bubble.stroke()

        let textRect = NSRect(x: rect.minX + padX, y: rect.minY + padY, width: w - padX * 2, height: h - padY * 2)
        (text as NSString).draw(in: textRect, withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if spriteRect.contains(p) { onPoke?() }
    }
}
