// Generates the bundled "blob" pet as transparent animated GIFs.
// Usage: swiftc -O -o .build/gen-default-pet scripts/gen-default-pet.swift && .build/gen-default-pet pets/blob
import CoreGraphics
import Foundation
import ImageIO

struct Color { let r, g, b, a: UInt8 }
let clear = Color(r: 0, g: 0, b: 0, a: 0)
let body = Color(r: 125, g: 211, b: 252, a: 255)
let outline = Color(r: 3, g: 105, b: 161, a: 255)
let ink = Color(r: 15, g: 23, b: 42, a: 255)
let white = Color(r: 255, g: 255, b: 255, a: 255)
let pink = Color(r: 251, g: 146, b: 178, a: 255)
let tear = Color(r: 56, g: 189, b: 248, a: 255)

let palette: [Character: Color] = ["d": outline, "b": body]

let normalBody = [
    "......dddddddd......",
    "....ddbbbbbbbbdd....",
    "...dbbbbbbbbbbbbd...",
    "..dbbbbbbbbbbbbbbd..",
    ".dbbbbbbbbbbbbbbbbd.",
    ".dbbbbbbbbbbbbbbbbd.",
    "dbbbbbbbbbbbbbbbbbbd",
    "dbbbbbbbbbbbbbbbbbbd",
    "dbbbbbbbbbbbbbbbbbbd",
    "dbbbbbbbbbbbbbbbbbbd",
    ".dbbbbbbbbbbbbbbbbd.",
    ".dbbbbbbbbbbbbbbbbd.",
    "..ddbbbbbbbbbbbbdd..",
    "....dddddddddddd....",
]
let squishBody = [
    ".....dddddddddddd.....",
    "...dddbbbbbbbbbbddd...",
    "..dbbbbbbbbbbbbbbbbd..",
    ".dbbbbbbbbbbbbbbbbbbd.",
    "dbbbbbbbbbbbbbbbbbbbbd",
    "dbbbbbbbbbbbbbbbbbbbbd",
    "dbbbbbbbbbbbbbbbbbbbbd",
    "dbbbbbbbbbbbbbbbbbbbbd",
    "dbbbbbbbbbbbbbbbbbbbbd",
    ".dbbbbbbbbbbbbbbbbbbd.",
    ".dbbbbbbbbbbbbbbbbbbd.",
    "..ddbbbbbbbbbbbbbbdd..",
    "....dddddddddddddd....",
]
let zGlyph = ["zzz", ".z.", "zzz"]

final class Canvas {
    let w: Int, h: Int
    var px: [UInt8]
    init(w: Int, h: Int) { self.w = w; self.h = h; px = [UInt8](repeating: 0, count: w * h * 4) }
    func set(_ x: Int, _ y: Int, _ c: Color) {
        guard x >= 0, x < w, y >= 0, y < h else { return }
        let i = (y * w + x) * 4
        px[i] = c.r; px[i + 1] = c.g; px[i + 2] = c.b; px[i + 3] = c.a
    }
    func rect(_ x: Int, _ y: Int, _ rw: Int, _ rh: Int, _ c: Color) {
        for dy in 0..<rh { for dx in 0..<rw { set(x + dx, y + dy, c) } }
    }
    func blit(_ rows: [String], _ ox: Int, _ oy: Int, _ pal: [Character: Color]) {
        for (dy, row) in rows.enumerated() {
            for (dx, ch) in row.enumerated() { if let c = pal[ch] { set(ox + dx, oy + dy, c) } }
        }
    }
    func image() -> CGImage {
        let provider = CGDataProvider(data: Data(px) as CFData)!
        return CGImage(
            width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
    }
}

enum Eyes { case open(Int), happy, closed, sad }
enum Mouth { case smile, frown, open, flat }

struct Frame {
    var squish = false
    var lift = 0
    var eyes: Eyes = .open(0)
    var mouth: Mouth = .smile
    var tear: Int? = nil
    var zzz = 0
    var sweat = false
    var delay = 0.5
}

let size = 24

func render(_ f: Frame) -> CGImage {
    let c = Canvas(w: size, h: size)
    let shape = f.squish ? squishBody : normalBody
    let bw = shape[0].count, bh = shape.count
    let ox = (size - bw) / 2
    let oy = size - bh - f.lift
    c.blit(shape, ox, oy, palette)

    let cx = ox + bw / 2
    let eyeY = oy + 4
    let lx = cx - 4, rx = cx + 2
    switch f.eyes {
    case let .open(dx):
        for x in [lx, rx] {
            c.rect(x + dx, eyeY, 2, 3, ink)
            c.set(x + dx, eyeY, white)
        }
    case .happy:
        for x in [lx - 1, rx] {
            c.set(x, eyeY + 1, ink); c.set(x + 1, eyeY, ink); c.set(x + 2, eyeY + 1, ink)
        }
    case .closed:
        for x in [lx, rx] { c.rect(x, eyeY + 1, 2, 1, ink) }
    case .sad:
        for x in [lx, rx] {
            c.rect(x, eyeY + 1, 2, 2, ink)
            c.set(x, eyeY + 1, white)
        }
        c.set(lx - 1, eyeY - 1, outline); c.set(lx, eyeY - 1, outline)   // brows slanting down
        c.set(rx + 1, eyeY - 1, outline); c.set(rx + 2, eyeY - 1, outline)
    }
    c.rect(lx - 2, eyeY + 3, 2, 1, pink)
    c.rect(rx + 2, eyeY + 3, 2, 1, pink)

    let my = eyeY + 5
    switch f.mouth {
    case .smile:
        c.set(cx - 2, my, ink); c.set(cx - 1, my + 1, ink); c.set(cx, my + 1, ink); c.set(cx + 1, my, ink)
    case .frown:
        c.set(cx - 2, my + 1, ink); c.set(cx - 1, my, ink); c.set(cx, my, ink); c.set(cx + 1, my + 1, ink)
    case .open:
        c.rect(cx - 2, my, 4, 2, ink); c.rect(cx - 1, my + 1, 2, 1, pink)
    case .flat:
        c.rect(cx - 1, my, 2, 1, ink)
    }

    if let t = f.tear { c.rect(lx, eyeY + 3 + t, 1, 2, tear) }
    if f.sweat { c.rect(ox + bw - 3, oy + 1, 1, 2, tear) }
    let zSpots = [(17, oy - 4), (19, oy - 7), (21, oy - 10)]
    for k in 0..<min(f.zzz, zSpots.count) { c.blit(zGlyph, zSpots[k].0, zSpots[k].1, ["z": outline]) }
    return c.image()
}

func writeGIF(_ frames: [Frame], to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "com.compuserve.gif" as CFString, frames.count, nil) else {
        fatalError("cannot create \(url.path)")
    }
    CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    for f in frames {
        let props = [kCGImagePropertyGIFDictionary: [
            kCGImagePropertyGIFDelayTime: f.delay,
            kCGImagePropertyGIFUnclampedDelayTime: f.delay,
        ]] as CFDictionary
        CGImageDestinationAddImage(dest, render(f), props)
    }
    guard CGImageDestinationFinalize(dest) else { fatalError("failed writing \(url.path)") }
    print("wrote \(url.path) (\(frames.count) frames)")
}

let animations: [String: [Frame]] = [
    "idle": [
        Frame(delay: 1.2),
        Frame(squish: true, delay: 1.0),
        Frame(delay: 0.4),
        Frame(eyes: .closed, delay: 0.12),
        Frame(delay: 0.6),
    ],
    "working": [
        Frame(eyes: .open(-1), mouth: .flat, sweat: true, delay: 0.25),
        Frame(eyes: .open(0), mouth: .flat, delay: 0.25),
        Frame(eyes: .open(1), mouth: .flat, sweat: true, delay: 0.25),
        Frame(eyes: .open(0), mouth: .flat, delay: 0.25),
    ],
    "happy": [
        Frame(lift: 0, eyes: .happy, mouth: .open, delay: 0.1),
        Frame(lift: 3, eyes: .happy, mouth: .open, delay: 0.1),
        Frame(lift: 5, eyes: .happy, mouth: .open, delay: 0.15),
        Frame(lift: 3, eyes: .happy, mouth: .open, delay: 0.1),
        Frame(squish: true, eyes: .happy, mouth: .open, delay: 0.3),
    ],
    "sad": [
        Frame(eyes: .sad, mouth: .frown, tear: 0, delay: 0.35),
        Frame(eyes: .sad, mouth: .frown, tear: 1, delay: 0.35),
        Frame(eyes: .sad, mouth: .frown, tear: 2, delay: 0.35),
        Frame(eyes: .sad, mouth: .frown, tear: nil, delay: 0.35),
    ],
    "sleeping": [
        Frame(squish: true, eyes: .closed, mouth: .flat, zzz: 1, delay: 0.5),
        Frame(squish: true, eyes: .closed, mouth: .flat, zzz: 2, delay: 0.5),
        Frame(squish: true, eyes: .closed, mouth: .flat, zzz: 3, delay: 0.7),
        Frame(squish: true, eyes: .closed, mouth: .flat, zzz: 0, delay: 0.4),
    ],
]

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "pets/blob")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
for (name, frames) in animations.sorted(by: { $0.key < $1.key }) {
    writeGIF(frames, to: outDir.appendingPathComponent("\(name).gif"))
}
