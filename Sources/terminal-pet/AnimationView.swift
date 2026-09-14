import AppKit

/// Draws the sprite (nearest-neighbour scaled by default) plus an optional speech bubble above it.
/// The view is wider than the sprite so bubbles have room; the sprite hugs one side.
final class AnimationView: NSView {
    static let bubbleSpace: CGFloat = 30
    static let minWidth: CGFloat = 170

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
            .font: NSFont.boldSystemFont(ofSize: 11),
            .foregroundColor: ink,
        ]
        let textSize = (text as NSString).size(withAttributes: attrs)
        let padX: CGFloat = 7, padY: CGFloat = 3
        let w = min(ceil(textSize.width) + padX * 2, bounds.width - 4)
        let h = ceil(textSize.height) + padY * 2
        let sprite = spriteRect
        var x = sprite.midX - w / 2
        x = max(2, min(x, bounds.width - w - 2))
        let y = sprite.maxY + 5
        let rect = NSRect(x: x, y: y, width: w, height: h)

        let bubble = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        let tailX = max(rect.minX + 8, min(sprite.midX, rect.maxX - 8))
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: tailX - 4, y: rect.minY + 1))
        tail.line(to: NSPoint(x: tailX, y: rect.minY - 5))
        tail.line(to: NSPoint(x: tailX + 4, y: rect.minY + 1))
        tail.close()
        bubble.append(tail)

        NSColor.white.setFill()
        bubble.fill()
        ink.setStroke()
        bubble.lineWidth = 1
        bubble.stroke()

        let textRect = NSRect(x: rect.minX + padX, y: rect.minY + padY, width: w - padX * 2, height: h - padY * 2)
        (text as NSString).draw(in: textRect, withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if spriteRect.contains(p) { onPoke?() }
    }
}
