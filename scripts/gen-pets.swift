// Generates the bundled pets as transparent animated GIFs.
//
//   swiftc -O -o .build/gen-pets scripts/gen-pets.swift
//   .build/gen-pets pets                  # writes pets/<name>/{state}.gif + pet.json
//   .build/gen-pets pets --sheet out.png  # also renders a contact sheet for eyeballing
//
// Every sprite is drawn on a 24x24 canvas (the app scales it, nearest-neighbour).
// Bodies are ASCII art with a per-pet palette; faces and effects are drawn by the helpers below.
import CoreGraphics
import Foundation
import ImageIO

// MARK: - Canvas

struct Color { let r, g, b, a: UInt8 }
func rgb(_ r: Int, _ g: Int, _ b: Int) -> Color { Color(r: UInt8(r), g: UInt8(g), b: UInt8(b), a: 255) }

let size = 24
let ink = rgb(15, 23, 42)
let white = rgb(255, 255, 255)
let pink = rgb(251, 146, 178)
let tearBlue = rgb(56, 189, 248)

final class Canvas {
    let w: Int, h: Int
    var px: [UInt8]
    init(w: Int = size, h: Int = size) { self.w = w; self.h = h; px = [UInt8](repeating: 0, count: w * h * 4) }
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

/// Validates ASCII art: every row must have the same width.
func art(_ rows: [String]) -> [String] {
    let w = rows[0].count
    for (i, r) in rows.enumerated() where r.count != w {
        fatalError("row \(i) has width \(r.count), expected \(w): \(r)")
    }
    return rows
}

// MARK: - Shared face / effect helpers

enum Eyes { case open(Int), happy, closed, sad }
enum Mouth { case smile, frown, open, flat, none }

/// Two eyes whose top-left corners are at (lx, y) and (rx, y).
func drawEyes(_ c: Canvas, _ eyes: Eyes, lx: Int, rx: Int, y: Int, color: Color = ink, highlight: Color? = white, browColor: Color? = nil) {
    switch eyes {
    case let .open(dx):
        for x in [lx, rx] {
            c.rect(x + dx, y, 2, 3, color)
            if let h = highlight { c.set(x + dx, y, h) }
        }
    case .happy:
        for x in [lx - 1, rx] {
            c.set(x, y + 1, color); c.set(x + 1, y, color); c.set(x + 2, y + 1, color)
        }
    case .closed:
        for x in [lx, rx] { c.rect(x, y + 1, 2, 1, color) }
    case .sad:
        for x in [lx, rx] {
            c.rect(x, y + 1, 2, 2, color)
            if let h = highlight { c.set(x, y + 1, h) }
        }
        if let b = browColor {
            c.set(lx - 1, y - 1, b); c.set(lx, y - 1, b)
            c.set(rx + 1, y - 1, b); c.set(rx + 2, y - 1, b)
        }
    }
}

/// Mouth centred on cx, top row at y.
func drawMouth(_ c: Canvas, _ m: Mouth, cx: Int, y: Int, color: Color = ink, tongue: Color = pink) {
    switch m {
    case .smile:
        c.set(cx - 2, y, color); c.set(cx - 1, y + 1, color); c.set(cx, y + 1, color); c.set(cx + 1, y, color)
    case .frown:
        c.set(cx - 2, y + 1, color); c.set(cx - 1, y, color); c.set(cx, y, color); c.set(cx + 1, y + 1, color)
    case .open:
        c.rect(cx - 2, y, 4, 2, color); c.rect(cx - 1, y + 1, 2, 1, tongue)
    case .flat:
        c.rect(cx - 1, y, 2, 1, color)
    case .none:
        break
    }
}

let zGlyph = ["zzz", ".z.", "zzz"]
/// Up to three Zs drifting up and to the right from (x, y).
func drawZzz(_ c: Canvas, _ count: Int, x: Int, y: Int, color: Color) {
    let spots = [(x, y), (x + 2, y - 3), (x + 4, y - 6)]
    for k in 0..<min(count, spots.count) { c.blit(zGlyph, spots[k].0, spots[k].1, ["z": color]) }
}

func drawTear(_ c: Canvas, x: Int, y: Int, step: Int?) {
    if let t = step { c.rect(x, y + t, 1, 2, tearBlue) }
}

// MARK: - Pet definitions

struct Frame { let image: CGImage; let delay: Double }
struct PetDef { let name: String; let states: [String: [Frame]] }

func frame(_ delay: Double, _ draw: (Canvas) -> Void) -> Frame {
    let c = Canvas(); draw(c); return Frame(image: c.image(), delay: delay)
}

// --- Blob -----------------------------------------------------------------

func blob() -> PetDef {
    let body = rgb(125, 211, 252), outline = rgb(3, 105, 161)
    let pal: [Character: Color] = ["d": outline, "b": body]
    let normal = art([
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
    ])
    let squish = art([
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
    ])
    func f(_ delay: Double, squished: Bool = false, lift: Int = 0, eyes: Eyes = .open(0), mouth: Mouth = .smile,
           tear: Int? = nil, zzz: Int = 0, sweat: Bool = false) -> Frame {
        frame(delay) { c in
            let shape = squished ? squish : normal
            let bw = shape[0].count, bh = shape.count
            let ox = (size - bw) / 2, oy = size - bh - lift
            c.blit(shape, ox, oy, pal)
            let cx = ox + bw / 2, eyeY = oy + 4
            let lx = cx - 4, rx = cx + 2
            drawEyes(c, eyes, lx: lx, rx: rx, y: eyeY, browColor: outline)
            c.rect(lx - 2, eyeY + 3, 2, 1, pink); c.rect(rx + 2, eyeY + 3, 2, 1, pink)
            drawMouth(c, mouth, cx: cx, y: eyeY + 5)
            drawTear(c, x: lx, y: eyeY + 3, step: tear)
            if sweat { c.rect(ox + bw - 3, oy + 1, 1, 2, tearBlue) }
            drawZzz(c, zzz, x: 17, y: oy - 4, color: outline)
        }
    }
    return PetDef(name: "Blob", states: [
        "idle": [f(1.2), f(1.0, squished: true), f(0.4), f(0.12, eyes: .closed), f(0.6)],
        "working": [f(0.25, eyes: .open(-1), mouth: .flat, sweat: true), f(0.25, mouth: .flat),
                    f(0.25, eyes: .open(1), mouth: .flat, sweat: true), f(0.25, mouth: .flat)],
        "happy": [f(0.1, eyes: .happy, mouth: .open), f(0.1, lift: 3, eyes: .happy, mouth: .open),
                  f(0.15, lift: 5, eyes: .happy, mouth: .open), f(0.1, lift: 3, eyes: .happy, mouth: .open),
                  f(0.3, squished: true, eyes: .happy, mouth: .open)],
        "sad": [f(0.35, eyes: .sad, mouth: .frown, tear: 0), f(0.35, eyes: .sad, mouth: .frown, tear: 1),
                f(0.35, eyes: .sad, mouth: .frown, tear: 2), f(0.35, eyes: .sad, mouth: .frown)],
        "sleeping": [f(0.5, squished: true, eyes: .closed, mouth: .flat, zzz: 1),
                     f(0.5, squished: true, eyes: .closed, mouth: .flat, zzz: 2),
                     f(0.7, squished: true, eyes: .closed, mouth: .flat, zzz: 3),
                     f(0.4, squished: true, eyes: .closed, mouth: .flat)],
    ])
}

// --- Cat ------------------------------------------------------------------

func cat() -> PetDef {
    let fur = rgb(251, 146, 60), dark = rgb(124, 45, 18), belly = rgb(254, 235, 200), nose = rgb(244, 114, 182)
    let pal: [Character: Color] = ["k": dark, "o": fur, "w": belly, "p": nose]
    let head = [
        "...kk........kk.......",
        "..kpok......kopk......",
        "..kpook....koopk......",
        "..koooookkkkoook......",
        ".kooooooooooooook.....",
        ".kooooooooooooook.....",
        ".kooooooooooooook.....",
        ".kooooooooooooook.....",
        "..koooooowwoooook.....",
        "..kkoooowwwwoookk.....",
    ]
    let bodyTailUp = art(head + [
        "...kkooooooooookk..kk.",
        "..koowwwwwwwwwook.kook",
        "..koowwwwwwwwwook.koo.",   // tail
        "..koowwwwwwwwwookkkok.",
        "..koooooooooooooookok.",
        "..kkkkkkkkkkkkkkkkkk..",
    ])
    let bodyTailDown = art(head + [
        "...kkooooooooookk.....",
        "..koowwwwwwwwwook.....",
        "..koowwwwwwwwwookkk...",
        "..koowwwwwwwwwookook..",
        "..kooooooooooooookook.",
        "..kkkkkkkkkkkkkkkkkk..",
    ])
    func f(_ delay: Double, tailUp: Bool = true, lift: Int = 0, eyes: Eyes = .open(0), mouth: Mouth = .smile,
           tear: Int? = nil, zzz: Int = 0, sweat: Bool = false) -> Frame {
        frame(delay) { c in
            let shape = tailUp ? bodyTailUp : bodyTailDown
            let bw = shape[0].count, bh = shape.count
            let ox = (size - bw) / 2, oy = size - bh - lift
            c.blit(shape, ox, oy, pal)
            let cx = ox + 9, eyeY = oy + 5
            let lx = cx - 4, rx = cx + 2
            drawEyes(c, eyes, lx: lx, rx: rx, y: eyeY, browColor: dark)
            // whiskers
            for (x, y) in [(ox - 1, oy + 6), (ox, oy + 6), (ox + 17, oy + 6), (ox + 18, oy + 6)] { c.set(x, y, dark) }
            c.rect(cx - 1, oy + 8, 2, 1, nose)
            switch mouth {
            case .smile: c.set(cx - 2, oy + 9, dark); c.set(cx + 1, oy + 9, dark)
            default: drawMouth(c, mouth, cx: cx, y: oy + 9, color: dark)
            }
            drawTear(c, x: lx, y: eyeY + 3, step: tear)
            if sweat { c.rect(ox + bw - 6, oy + 2, 1, 2, tearBlue) }
            drawZzz(c, zzz, x: 17, y: oy - 3, color: dark)
        }
    }
    return PetDef(name: "Cat", states: [
        "idle": [f(0.9), f(0.9, tailUp: false), f(0.5), f(0.12, eyes: .closed), f(0.7, tailUp: false)],
        "working": [f(0.2, eyes: .open(-1), mouth: .flat, sweat: true), f(0.2, tailUp: false, mouth: .flat),
                    f(0.2, eyes: .open(1), mouth: .flat, sweat: true), f(0.2, tailUp: false, mouth: .flat)],
        "happy": [f(0.1, eyes: .happy, mouth: .open), f(0.1, lift: 3, eyes: .happy, mouth: .open),
                  f(0.15, tailUp: false, lift: 5, eyes: .happy, mouth: .open), f(0.1, lift: 3, eyes: .happy, mouth: .open),
                  f(0.3, eyes: .happy, mouth: .open)],
        "sad": [f(0.35, tailUp: false, eyes: .sad, mouth: .frown, tear: 0), f(0.35, tailUp: false, eyes: .sad, mouth: .frown, tear: 1),
                f(0.35, tailUp: false, eyes: .sad, mouth: .frown, tear: 2), f(0.35, tailUp: false, eyes: .sad, mouth: .frown)],
        "sleeping": [f(0.5, tailUp: false, eyes: .closed, mouth: .none, zzz: 1), f(0.5, tailUp: false, eyes: .closed, mouth: .none, zzz: 2),
                     f(0.7, tailUp: false, eyes: .closed, mouth: .none, zzz: 3), f(0.4, tailUp: false, eyes: .closed, mouth: .none)],
    ])
}

// --- Ghost ----------------------------------------------------------------

func ghost() -> PetDef {
    let sheet = rgb(241, 245, 249), shade = rgb(203, 213, 225), edge = rgb(100, 116, 139)
    let pal: [Character: Color] = ["k": edge, "w": sheet, "g": shade]
    let top = [
        ".....kkkkkk.....",
        "...kkwwwwwwkk...",
        "..kwwwwwwwwwwk..",
        ".kwwwwwwwwwwwwk.",
        ".kwwwwwwwwwwwwk.",
        "kwwwwwwwwwwwwwwk",
        "kwwwwwwwwwwwwwwk",
        "kwwwwwwwwwwwwwwk",
        "kwwwwwwwwwwwwwwk",
        "kwwwwwwwwwwwwwwk",
        "kwwwwwwwwwwwwwwk",
        "kwwwwwwwwwwwwwwk",
        "kwwwwwwwwwwwwwwk",
        "kwwwwwwwwwwwwwgk",
    ]
    let waveA = art(top + [
        "kwwwwwwwwwwwwggk",
        "kwwkwwwkkwwwkwwk",
        "kkk.kkk..kkk.kkk",
    ])
    let waveB = art(top + [
        "kwwwwwwwwwwwwggk",
        "kkwwkwwwkwwwkwkk",
        ".kkk.kkkkkkk.kk.",
    ])
    func f(_ delay: Double, alt: Bool = false, lift: Int = 0, eyes: Eyes = .open(0), mouth: Mouth = .open,
           tear: Int? = nil, zzz: Int = 0, sweat: Bool = false) -> Frame {
        frame(delay) { c in
            let shape = alt ? waveB : waveA
            let bw = shape[0].count, bh = shape.count
            let ox = (size - bw) / 2, oy = size - bh - 2 - lift   // floats a little off the ground
            c.blit(shape, ox, oy, pal)
            let cx = ox + 8, eyeY = oy + 5
            let lx = cx - 4, rx = cx + 2
            drawEyes(c, eyes, lx: lx, rx: rx, y: eyeY, highlight: nil, browColor: edge)
            switch mouth {
            case .open: c.rect(cx - 1, eyeY + 5, 2, 2, ink)
            default: drawMouth(c, mouth, cx: cx, y: eyeY + 5)
            }
            drawTear(c, x: lx, y: eyeY + 3, step: tear)
            if sweat { c.rect(ox + bw - 3, oy + 3, 1, 2, tearBlue) }
            drawZzz(c, zzz, x: 17, y: oy - 3, color: edge)
        }
    }
    return PetDef(name: "Ghost", states: [
        "idle": [f(0.5), f(0.5, alt: true, lift: 1), f(0.5, lift: 2), f(0.5, alt: true, lift: 1)],
        "working": [f(0.2, eyes: .open(-1), mouth: .flat, sweat: true), f(0.2, alt: true, lift: 1, mouth: .flat),
                    f(0.2, eyes: .open(1), mouth: .flat, sweat: true), f(0.2, alt: true, lift: 1, mouth: .flat)],
        "happy": [f(0.1, eyes: .happy), f(0.1, alt: true, lift: 3, eyes: .happy), f(0.15, lift: 6, eyes: .happy),
                  f(0.1, alt: true, lift: 3, eyes: .happy), f(0.3, eyes: .happy)],
        "sad": [f(0.35, lift: -2, eyes: .sad, mouth: .frown, tear: 0), f(0.35, alt: true, lift: -2, eyes: .sad, mouth: .frown, tear: 1),
                f(0.35, lift: -2, eyes: .sad, mouth: .frown, tear: 2), f(0.35, alt: true, lift: -2, eyes: .sad, mouth: .frown)],
        "sleeping": [f(0.5, lift: -2, eyes: .closed, mouth: .flat, zzz: 1), f(0.5, alt: true, lift: -2, eyes: .closed, mouth: .flat, zzz: 2),
                     f(0.7, lift: -2, eyes: .closed, mouth: .flat, zzz: 3), f(0.4, alt: true, lift: -2, eyes: .closed, mouth: .flat)],
    ])
}

// --- Robot ----------------------------------------------------------------

func robot() -> PetDef {
    let metal = rgb(148, 163, 184), dark = rgb(51, 65, 85), screen = rgb(15, 23, 42), glow = rgb(103, 232, 249)
    let dim = rgb(30, 58, 80)
    let pal: [Character: Color] = ["k": dark, "g": metal, "n": screen]
    let head = [
        ".........k..........",
        ".........k..........",
        "..kkkkkkkkkkkkkkkk..",
        "..kggggggggggggggk..",
        "..kgknnnnnnnnnnkgk..",
        "..kgknnnnnnnnnnkgk..",
        "..kgknnnnnnnnnnkgk..",
        "..kgknnnnnnnnnnkgk..",
        "..kgknnnnnnnnnnkgk..",
        "..kgknnnnnnnnnnkgk..",
        "..kgkkkkkkkkkkkkgk..",
        "..kggggggggggggggk..",
        "..kkkkkkkkkkkkkkkk..",
    ]
    let armsDown = art(head + [
        "........kkkk........",
        "....kkkkkkkkkkkk....",
        "kkk.kggggggggggk.kkk",
        "kgkkkggggggggggkkkgk",
        "kkk.kggggggggggk.kkk",
        "....kkkkkkkkkkkk....",
    ])
    let armsUp = art(head + [
        "kkk.....kkkk.....kkk",
        "kgk.kkkkkkkkkkkk.kgk",
        "kgkkkggggggggggkkkgk",
        "kkk.kggggggggggk.kkk",
        "....kggggggggggk....",
        "....kkkkkkkkkkkk....",
    ])
    enum Face { case eyes(Eyes, Mouth), dots(Int), off }
    func f(_ delay: Double, up: Bool = false, lift: Int = 0, face: Face = .eyes(.open(0), .flat), light: Color? = nil,
           spark: Bool = false, zzz: Int = 0) -> Frame {
        frame(delay) { c in
            let shape = up ? armsUp : armsDown
            let bw = shape[0].count, bh = shape.count
            let ox = (size - bw) / 2, oy = size - bh - lift
            c.blit(shape, ox, oy, pal)
            c.rect(ox + 8, oy - 1, 3, 2, light ?? dark)          // antenna bulb
            c.set(ox + 9, oy - 1, light == nil ? dark : white)
            let sx = ox + 5, sy = oy + 4                          // screen top-left (10x6)
            let cx = sx + 5
            switch face {
            case let .eyes(e, m):
                drawEyes(c, e, lx: sx + 1, rx: sx + 7, y: sy, color: glow, highlight: nil, browColor: glow)
                drawMouth(c, m, cx: cx, y: sy + 4, color: glow, tongue: glow)
            case let .dots(n):
                for i in 0..<3 { c.rect(sx + 2 + i * 3, sy + 2, 2, 2, i == n ? glow : dim) }
            case .off:
                c.rect(sx + 1, sy + 2, 2, 1, dim); c.rect(sx + 7, sy + 2, 2, 1, dim)
            }
            if spark {
                let yellow = rgb(250, 204, 21)
                c.set(ox + bw - 1, oy + 3, yellow); c.set(ox + bw, oy + 2, yellow); c.set(ox + bw + 1, oy + 4, yellow)
            }
            drawZzz(c, zzz, x: 17, y: oy - 4, color: dark)
        }
    }
    let green = rgb(74, 222, 128), red = rgb(248, 113, 113), amber = rgb(251, 191, 36)
    return PetDef(name: "Robot", states: [
        "idle": [f(1.0, light: glow), f(0.3), f(0.8, light: glow), f(0.12, face: .eyes(.closed, .flat), light: glow), f(0.6, light: glow)],
        "working": [f(0.2, face: .dots(0), light: amber), f(0.2, face: .dots(1), light: amber), f(0.2, face: .dots(2), light: amber), f(0.2, face: .dots(-1), light: amber)],
        "happy": [f(0.1, up: true, face: .eyes(.happy, .smile), light: green), f(0.1, up: true, lift: 3, face: .eyes(.happy, .smile), light: green),
                  f(0.15, up: true, lift: 5, face: .eyes(.happy, .smile), light: green), f(0.1, up: true, lift: 3, face: .eyes(.happy, .smile), light: green),
                  f(0.3, up: true, face: .eyes(.happy, .smile), light: green)],
        "sad": [f(0.3, face: .eyes(.sad, .frown), light: red, spark: true), f(0.3, face: .eyes(.sad, .frown)),
                f(0.3, face: .eyes(.sad, .frown), light: red), f(0.3, face: .eyes(.sad, .frown), spark: true)],
        "sleeping": [f(0.5, face: .off, zzz: 1), f(0.5, face: .off, zzz: 2), f(0.7, face: .off, zzz: 3), f(0.4, face: .off)],
    ])
}

// --- Chick ----------------------------------------------------------------

func chick() -> PetDef {
    let down = rgb(253, 224, 71), dark = rgb(161, 98, 7), beak = rgb(249, 115, 22), cheek = rgb(253, 164, 175)
    let pal: [Character: Color] = ["k": dark, "y": down, "o": beak]
    let body = art([
        "......kkkkkk......",
        "....kkyyyyyykk....",
        "...kyyyyyyyyyyk...",
        "..kyyyyyyyyyyyyk..",
        "..kyyyyyyyyyyyyk..",
        ".kyyyyyyyyyyyyyyk.",
        ".kyyyyyyyyyyyyyyk.",
        ".kyyyyyyyyyyyyyyk.",
        ".kyyyyyyyyyyyyyyk.",
        ".kyyyyyyyyyyyyyyk.",
        "..kyyyyyyyyyyyyk..",
        "..kyyyyyyyyyyyyk..",
        "...kkyyyyyyyykk...",
        ".....kkkkkkkk.....",
        "......oo..oo......",
    ])
    let wingDown = ["kk", "ky", "kk"]
    let wingUp = [".k", "kk", "ky"]
    func f(_ delay: Double, flap: Bool = false, lift: Int = 0, eyes: Eyes = .open(0), mouth: Mouth = .none,
           tear: Int? = nil, zzz: Int = 0, sweat: Bool = false) -> Frame {
        frame(delay) { c in
            let bw = body[0].count, bh = body.count
            let ox = (size - bw) / 2, oy = size - bh - lift
            c.blit(body, ox, oy, pal)
            // tuft
            c.set(ox + 9, oy - 1, dark); c.set(ox + 10, oy - 2, dark)
            // wings, mirrored
            let wing = flap ? wingUp : wingDown
            let wy = flap ? oy + 4 : oy + 7
            c.blit(wing, ox - 1, wy, pal)
            c.blit(wing.map { String($0.reversed()) }, ox + bw - 1, wy, pal)
            let cx = ox + 9, eyeY = oy + 5
            let lx = cx - 4, rx = cx + 2
            drawEyes(c, eyes, lx: lx, rx: rx, y: eyeY, browColor: dark)
            c.rect(lx - 2, eyeY + 3, 2, 1, cheek); c.rect(rx + 2, eyeY + 3, 2, 1, cheek)
            c.rect(cx - 1, eyeY + 4, 2, 1, beak); c.rect(cx - 1, eyeY + 5, 2, 1, mouth == .frown ? dark : beak)
            if mouth == .open { c.rect(cx - 1, eyeY + 5, 2, 1, ink) }
            drawTear(c, x: lx, y: eyeY + 3, step: tear)
            if sweat { c.rect(ox + bw - 4, oy + 2, 1, 2, tearBlue) }
            drawZzz(c, zzz, x: 17, y: oy - 3, color: dark)
        }
    }
    return PetDef(name: "Chick", states: [
        "idle": [f(0.8), f(0.8, lift: 1), f(0.4), f(0.12, eyes: .closed), f(0.6, lift: 1)],
        "working": [f(0.2, eyes: .open(-1), sweat: true), f(0.2, lift: 1), f(0.2, eyes: .open(1), sweat: true), f(0.2, lift: 1)],
        "happy": [f(0.1, flap: true, eyes: .happy, mouth: .open), f(0.1, lift: 3, eyes: .happy, mouth: .open),
                  f(0.15, flap: true, lift: 5, eyes: .happy, mouth: .open), f(0.1, lift: 3, eyes: .happy, mouth: .open),
                  f(0.3, flap: true, eyes: .happy, mouth: .open)],
        "sad": [f(0.35, eyes: .sad, mouth: .frown, tear: 0), f(0.35, eyes: .sad, mouth: .frown, tear: 1),
                f(0.35, eyes: .sad, mouth: .frown, tear: 2), f(0.35, eyes: .sad, mouth: .frown)],
        "sleeping": [f(0.5, eyes: .closed, zzz: 1), f(0.5, eyes: .closed, zzz: 2), f(0.7, eyes: .closed, zzz: 3), f(0.4, eyes: .closed)],
    ])
}

// MARK: - Output

let stateOrder = ["idle", "working", "happy", "sad", "sleeping"]
let pets = [blob(), cat(), ghost(), robot(), chick()]

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
        CGImageDestinationAddImage(dest, f.image, props)
    }
    guard CGImageDestinationFinalize(dest) else { fatalError("failed writing \(url.path)") }
}

func writeSheet(to url: URL, scale: Int = 5) {
    let cols = pets.flatMap { $0.states.values.map(\.count) }.max()!
    let rows = pets.count * stateOrder.count
    let cell = size * scale
    let w = cell * cols, h = cell * rows
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.interpolationQuality = .none
    var row = 0
    for pet in pets {
        for state in stateOrder {
            for (col, f) in (pet.states[state] ?? []).enumerated() {
                ctx.draw(f.image, in: CGRect(x: col * cell, y: h - (row + 1) * cell, width: cell, height: cell))
            }
            row += 1
        }
    }
    let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
    print("wrote \(url.path)")
}

var args = Array(CommandLine.arguments.dropFirst())
var sheetPath: String?
if let i = args.firstIndex(of: "--sheet"), i + 1 < args.count {
    sheetPath = args[i + 1]
    args.removeSubrange(i...i + 1)
}
let root = URL(fileURLWithPath: args.first ?? "pets")

for pet in pets {
    let dir = root.appendingPathComponent(pet.name.lowercased())
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for state in stateOrder {
        writeGIF(pet.states[state]!, to: dir.appendingPathComponent("\(state).gif"))
    }
    let manifest: [String: Any] = [
        "name": pet.name,
        "author": "terminal-pet",
        "states": Dictionary(uniqueKeysWithValues: stateOrder.map { ($0, "\($0).gif") }),
    ]
    let json = try! JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
    try! (String(data: json, encoding: .utf8)! + "\n").write(to: dir.appendingPathComponent("pet.json"), atomically: true, encoding: .utf8)
    print("wrote \(dir.path) (\(stateOrder.map { "\($0):\(pet.states[$0]!.count)" }.joined(separator: " ")))")
}
if let p = sheetPath { writeSheet(to: URL(fileURLWithPath: p)) }
