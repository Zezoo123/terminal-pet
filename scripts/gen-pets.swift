// Generates the bundled pets as transparent animated GIFs.
//
//   swiftc -O -o .build/gen-pets scripts/gen-pets.swift
//   .build/gen-pets pets                  # writes pets/<name>/{state}.gif + pet.json
//   .build/gen-pets pets --sheet out.png  # also renders a contact sheet for eyeballing
//   .build/gen-pets pets --showcase docs/showcase.gif   # animated strip of every pet for the README
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

enum Food { case cookie, fish, candy, battery, seed, bone, fly }
/// A snack held beside the mouth at (x, y). stage 0 = whole, 1 = half eaten, 2+ = gone.
func drawFood(_ c: Canvas, _ kind: Food, x: Int, y: Int, stage: Int) {
    guard stage < 2 else { return }
    let half = stage == 1
    switch kind {
    case .cookie:
        let dough = rgb(217, 160, 91), chip = rgb(92, 54, 30)
        c.blit(half ? ["dd..", "ddd.", "dd..", ".d.."] : [".dd.", "dddd", "dddd", ".dd."], x, y, ["d": dough])
        c.set(x + 1, y + 1, chip); if !half { c.set(x + 2, y + 2, chip) }
    case .fish:
        let scale = rgb(125, 168, 196), fin = rgb(71, 111, 140)
        c.blit(half ? ["f..", "ss.", "f.."] : ["f..s.", "sssss", "f..s."], x, y, ["s": scale, "f": fin])
    case .candy:
        let wrap = rgb(244, 114, 182), shine = rgb(253, 224, 71)
        c.blit(half ? [".w.", "ww.", ".w."] : ["w.ww.w", "wwwwww", "w.ww.w"], x, y, ["w": wrap])
        if !half { c.set(x + 2, y + 1, shine) }
    case .battery:
        let body = rgb(74, 222, 128), cap = rgb(148, 163, 184), dark = rgb(22, 101, 52)
        c.blit(half ? [".c.", "bbb", "bbb"] : [".c.", "bbb", "bbb", "bbb", "bbb", "bbb"], x, y, ["c": cap, "b": body])
        c.set(x + 1, y + (half ? 2 : 3), dark)
    case .seed:
        let hull = rgb(120, 72, 32)
        c.blit(half ? ["h"] : ["h.", "hh", ".h"], x, y, ["h": hull])
    case .bone:
        let bone = rgb(241, 245, 249), shade = rgb(148, 163, 184)
        c.blit(half ? ["bb.", "bbb", "bb."] : ["bb..bb", "bbbbbb", "bb..bb"], x, y, ["b": bone])
        if !half { c.set(x + 2, y + 1, shade); c.set(x + 3, y + 1, shade) }
    case .fly:
        let wing = rgb(203, 213, 225)
        c.blit(half ? ["k"] : ["wkw", ".k."], x, y, ["k": ink, "w": wing])
    }
}

/// A 9x7 thought bubble at (x, y) with a snack inside, plus two dots trailing toward (dotX, dotY).
func drawThought(_ c: Canvas, _ kind: Food, x: Int, y: Int, dots: [(Int, Int)], outline: Color) {
    let bubble = [
        ".ooooooo.",
        "owwwwwwwo",
        "owwwwwwwo",
        "owwwwwwwo",
        "owwwwwwwo",
        "owwwwwwwo",
        ".ooooooo.",
    ]
    c.blit(bubble, x, y, ["o": outline, "w": white])
    switch kind {
    case .cookie: drawFood(c, .cookie, x: x + 3, y: y + 2, stage: 0)
    case .fish: drawFood(c, .fish, x: x + 2, y: y + 2, stage: 0)
    case .candy: drawFood(c, .candy, x: x + 2, y: y + 2, stage: 0)
    case .battery: drawFood(c, .battery, x: x + 3, y: y + 2, stage: 1)
    case .seed: drawFood(c, .seed, x: x + 4, y: y + 2, stage: 0)
    case .bone: drawFood(c, .bone, x: x + 2, y: y + 2, stage: 0)
    case .fly: drawFood(c, .fly, x: x + 3, y: y + 2, stage: 0)
    }
    for (dx, dy) in dots { c.set(dx, dy, outline) }
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
           tear: Int? = nil, zzz: Int = 0, sweat: Bool = false, food: Int? = nil, thought: Bool = false, shift: Int = 0) -> Frame {
        frame(delay) { c in
            let shape = squished ? squish : normal
            let bw = shape[0].count, bh = shape.count
            let ox = (size - bw) / 2 + shift, oy = size - bh - lift
            c.blit(shape, ox, oy, pal)
            let cx = ox + bw / 2, eyeY = oy + 4
            let lx = cx - 4, rx = cx + 2
            drawEyes(c, eyes, lx: lx, rx: rx, y: eyeY, browColor: outline)
            c.rect(lx - 2, eyeY + 3, 2, 1, pink); c.rect(rx + 2, eyeY + 3, 2, 1, pink)
            drawMouth(c, mouth, cx: cx, y: eyeY + 5)
            drawTear(c, x: lx, y: eyeY + 3, step: tear)
            if sweat { c.rect(ox + bw - 3, oy + 1, 1, 2, tearBlue) }
            drawZzz(c, zzz, x: 17, y: oy - 4, color: outline)
            if let st = food { drawFood(c, .cookie, x: ox - 2, y: oy + 6, stage: st) }
            if thought { drawThought(c, .cookie, x: 1, y: 1, dots: [(9, 8), (10, 9)], outline: outline) }
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
        "eating": [f(0.25, mouth: .open, food: 0), f(0.25, squished: true, mouth: .flat, food: 0),
                   f(0.25, mouth: .open, food: 1), f(0.25, squished: true, mouth: .flat, food: 1),
                   f(0.3, eyes: .happy, mouth: .open, food: 2), f(0.5, squished: true, eyes: .happy, mouth: .smile, food: 2)],
        "hungry": [f(0.6, eyes: .sad, mouth: .flat, thought: true), f(0.12, eyes: .sad, mouth: .flat, thought: true, shift: -1),
                   f(0.12, eyes: .sad, mouth: .flat, thought: true, shift: 1), f(0.6, eyes: .sad, mouth: .flat, thought: true),
                   f(0.5, squished: true, eyes: .closed, mouth: .flat)],
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
           tear: Int? = nil, zzz: Int = 0, sweat: Bool = false, food: Int? = nil, thought: Bool = false, shift: Int = 0) -> Frame {
        frame(delay) { c in
            let shape = tailUp ? bodyTailUp : bodyTailDown
            let bw = shape[0].count, bh = shape.count
            let ox = (size - bw) / 2 + shift, oy = size - bh - lift
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
            if let st = food { drawFood(c, .fish, x: ox - 2, y: oy + 8, stage: st) }
            if thought { drawThought(c, .fish, x: 0, y: 0, dots: [(9, 7), (10, 8)], outline: dark) }
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
        "eating": [f(0.25, mouth: .open, food: 0), f(0.25, tailUp: false, mouth: .flat, food: 0),
                   f(0.25, mouth: .open, food: 1), f(0.25, tailUp: false, mouth: .flat, food: 1),
                   f(0.3, eyes: .happy, mouth: .open, food: 2), f(0.5, tailUp: false, eyes: .happy, food: 2)],
        "hungry": [f(0.6, tailUp: false, eyes: .sad, mouth: .flat, thought: true), f(0.12, tailUp: false, eyes: .sad, mouth: .flat, thought: true, shift: -1),
                   f(0.12, tailUp: false, eyes: .sad, mouth: .flat, thought: true, shift: 1), f(0.6, tailUp: false, eyes: .sad, mouth: .flat, thought: true),
                   f(0.5, tailUp: false, eyes: .closed, mouth: .flat)],
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
           tear: Int? = nil, zzz: Int = 0, sweat: Bool = false, food: Int? = nil, thought: Bool = false, shift: Int = 0) -> Frame {
        frame(delay) { c in
            let shape = alt ? waveB : waveA
            let bw = shape[0].count, bh = shape.count
            let ox = (size - bw) / 2 + shift, oy = size - bh - 2 - lift   // floats a little off the ground
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
            if let st = food { drawFood(c, .candy, x: ox - 3, y: oy + 9, stage: st) }
            if thought { drawThought(c, .candy, x: 0, y: 0, dots: [(9, 7), (10, 8)], outline: edge) }
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
        "eating": [f(0.25, mouth: .open, food: 0), f(0.25, alt: true, lift: 1, mouth: .flat, food: 0),
                   f(0.25, mouth: .open, food: 1), f(0.25, alt: true, lift: 1, mouth: .flat, food: 1),
                   f(0.3, eyes: .happy, mouth: .open, food: 2), f(0.5, alt: true, lift: 1, eyes: .happy, mouth: .smile, food: 2)],
        "hungry": [f(0.6, lift: -2, eyes: .sad, mouth: .flat, thought: true), f(0.12, alt: true, lift: -2, eyes: .sad, mouth: .flat, thought: true, shift: -1),
                   f(0.12, lift: -2, eyes: .sad, mouth: .flat, thought: true, shift: 1), f(0.6, alt: true, lift: -2, eyes: .sad, mouth: .flat, thought: true),
                   f(0.5, lift: -2, eyes: .closed, mouth: .flat)],
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
           spark: Bool = false, zzz: Int = 0, food: Int? = nil, thought: Bool = false, shift: Int = 0) -> Frame {
        frame(delay) { c in
            let shape = up ? armsUp : armsDown
            let bw = shape[0].count, bh = shape.count
            let ox = (size - bw) / 2 + shift, oy = size - bh - lift
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
            if let st = food { drawFood(c, .battery, x: ox - 2, y: oy + 7, stage: st) }
            if thought { drawThought(c, .battery, x: 14, y: 0, dots: [(13, 6)], outline: dark) }
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
        "eating": [f(0.25, face: .eyes(.open(0), .open), light: amber, food: 0), f(0.25, face: .eyes(.open(0), .flat), light: green, food: 0),
                   f(0.25, face: .eyes(.open(0), .open), light: amber, food: 1), f(0.25, face: .eyes(.open(0), .flat), light: green, food: 1),
                   f(0.3, up: true, face: .eyes(.happy, .smile), light: green, food: 2), f(0.5, up: true, face: .eyes(.happy, .smile), light: green, food: 2)],
        "hungry": [f(0.6, face: .eyes(.sad, .flat), light: red, thought: true), f(0.12, face: .eyes(.sad, .flat), thought: true, shift: -1),
                   f(0.12, face: .eyes(.sad, .flat), light: red, thought: true, shift: 1), f(0.6, face: .eyes(.sad, .flat), thought: true),
                   f(0.5, face: .off, light: red)],
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
           tear: Int? = nil, zzz: Int = 0, sweat: Bool = false, food: Int? = nil, thought: Bool = false, shift: Int = 0) -> Frame {
        frame(delay) { c in
            let bw = body[0].count, bh = body.count
            let ox = (size - bw) / 2 + shift, oy = size - bh - lift
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
            if let st = food { drawFood(c, .seed, x: ox - 1, y: oy + 10, stage: st) }
            if thought { drawThought(c, .seed, x: 0, y: 0, dots: [(9, 7), (10, 8)], outline: dark) }
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
        "eating": [f(0.25, mouth: .open, food: 0), f(0.25, lift: 1, food: 0),
                   f(0.25, mouth: .open, food: 1), f(0.25, lift: 1, food: 1),
                   f(0.3, flap: true, eyes: .happy, mouth: .open, food: 2), f(0.5, eyes: .happy, food: 2)],
        "hungry": [f(0.6, eyes: .sad, mouth: .flat, thought: true), f(0.12, eyes: .sad, mouth: .flat, thought: true, shift: -1),
                   f(0.12, eyes: .sad, mouth: .flat, thought: true, shift: 1), f(0.6, eyes: .sad, mouth: .flat, thought: true),
                   f(0.5, eyes: .closed, mouth: .flat)],
    ])
}


// --- Dog ------------------------------------------------------------------

func dog() -> PetDef {
    let fur = rgb(222, 170, 100), dark = rgb(101, 67, 33), ear = rgb(176, 120, 60), snout = rgb(250, 232, 200), belly = rgb(250, 232, 200)
    let pal: [Character: Color] = ["k": dark, "o": fur, "e": ear, "s": snout, "w": belly]
    let head = [
        "......kkkkkkkkkk......",
        ".....kooooooooook.....",
        ".kkkkkooooooooookkkkk.",
        ".keeekooooooooookeeek.",
        ".keeekooooooooookeeek.",
        ".keeekooooooooookeeek.",
        ".keeekooooooooookeeek.",
        ".keeekooooooooookeeek.",
        ".keeekoossssssookeeek.",
        ".keeekoossssssookeeek.",
        ".kkkkkooossssoookkkkk.",
        "......kkooooookk......",
    ]
    let tailUp = art(head + [
        ".....kkkkkkkkkkkk.....",
        "....koowwwwwwwwook.kk.",
        "....koowwwwwwwwook.ko.",
        "....kooooooooooookkko.",
        "....kkkkkkkkkkkkkkkk..",
    ])
    let tailDown = art(head + [
        ".....kkkkkkkkkkkk.....",
        "....koowwwwwwwwook....",
        "....koowwwwwwwwookk...",
        "....kooooooooooookkk..",
        "....kkkkkkkkkkkkkkkk..",
    ])
    func f(_ delay: Double, tailUp up: Bool = true, lift: Int = 0, eyes: Eyes = .open(0), mouth: Mouth = .smile, tongue: Bool = false,
           tear: Int? = nil, zzz: Int = 0, sweat: Bool = false, food: Int? = nil, thought: Bool = false, shift: Int = 0) -> Frame {
        frame(delay) { c in
            let shape = up ? tailUp : tailDown
            let bw = shape[0].count, bh = shape.count
            let ox = (size - bw) / 2 + shift, oy = size - bh - lift
            c.blit(shape, ox, oy, pal)
            let cx = ox + 11, eyeY = oy + 3
            let lx = cx - 4, rx = cx + 2
            drawEyes(c, eyes, lx: lx, rx: rx, y: eyeY, browColor: dark)
            c.rect(cx - 1, oy + 8, 2, 1, ink)                       // nose
            drawMouth(c, mouth, cx: cx, y: oy + 9, color: dark)
            if tongue { c.rect(cx - 1, oy + 10, 2, 2, pink) }
            drawTear(c, x: lx, y: eyeY + 3, step: tear)
            if sweat { c.rect(ox + 16, oy, 1, 2, tearBlue) }
            drawZzz(c, zzz, x: 17, y: oy - 3, color: dark)
            if let st = food { drawFood(c, .bone, x: cx - 3, y: oy + 9, stage: st) }   // carried in the mouth
            if thought { drawThought(c, .bone, x: 0, y: 0, dots: [(9, 6)], outline: dark) }
        }
    }
    return PetDef(name: "Dog", states: [
        "idle": [f(0.5), f(0.5, tailUp: false), f(0.5), f(0.12, eyes: .closed), f(0.5, tailUp: false)],
        "working": [f(0.2, eyes: .open(-1), mouth: .flat, sweat: true), f(0.2, tailUp: false, mouth: .flat),
                    f(0.2, eyes: .open(1), mouth: .flat, sweat: true), f(0.2, tailUp: false, mouth: .flat)],
        "happy": [f(0.1, eyes: .happy, tongue: true), f(0.1, tailUp: false, lift: 3, eyes: .happy, tongue: true),
                  f(0.15, lift: 5, eyes: .happy, tongue: true), f(0.1, tailUp: false, lift: 3, eyes: .happy, tongue: true),
                  f(0.3, eyes: .happy, tongue: true)],
        "sad": [f(0.35, tailUp: false, eyes: .sad, mouth: .frown, tear: 0), f(0.35, tailUp: false, eyes: .sad, mouth: .frown, tear: 1),
                f(0.35, tailUp: false, eyes: .sad, mouth: .frown, tear: 2), f(0.35, tailUp: false, eyes: .sad, mouth: .frown)],
        "sleeping": [f(0.5, tailUp: false, eyes: .closed, mouth: .flat, zzz: 1), f(0.5, tailUp: false, eyes: .closed, mouth: .flat, zzz: 2),
                     f(0.7, tailUp: false, eyes: .closed, mouth: .flat, zzz: 3), f(0.4, tailUp: false, eyes: .closed, mouth: .flat)],
        "eating": [f(0.25, mouth: .open, food: 0), f(0.25, tailUp: false, mouth: .flat, food: 0),
                   f(0.25, mouth: .open, food: 1), f(0.25, tailUp: false, mouth: .flat, food: 1),
                   f(0.3, eyes: .happy, tongue: true, food: 2), f(0.5, tailUp: false, eyes: .happy, tongue: true, food: 2)],
        "hungry": [f(0.6, tailUp: false, eyes: .sad, mouth: .flat, thought: true), f(0.12, tailUp: false, eyes: .sad, mouth: .flat, thought: true, shift: -1),
                   f(0.12, tailUp: false, eyes: .sad, mouth: .flat, thought: true, shift: 1), f(0.6, tailUp: false, eyes: .sad, mouth: .flat, thought: true),
                   f(0.5, tailUp: false, eyes: .closed, mouth: .flat)],
    ])
}

// --- Frog -----------------------------------------------------------------

func frog() -> PetDef {
    let skin = rgb(110, 200, 110), dark = rgb(30, 90, 45), belly = rgb(205, 240, 190)
    let pal: [Character: Color] = ["k": dark, "g": skin, "b": belly, "w": white]
    let body = art([
        "..kkkk......kkkk..",
        ".kwwwwk....kwwwwk.",
        ".kwwwwk....kwwwwk.",
        ".kwwwwkkkkkkwwwwk.",
        "kgwwwwggggggwwwwgk",
        "kggggggggggggggggk",
        "kggggggggggggggggk",
        "kggggggggggggggggk",
        "kgggbbbbbbbbbbgggk",
        "kggbbbbbbbbbbbbggk",
        ".kgbbbbbbbbbbbbgk.",
        ".kkkgggggggggggkkk",
        "kkk..kkkkkkkk..kkk",
    ])
    enum FrogEyes { case open(Int), closed, happy, sad }
    func f(_ delay: Double, lift: Int = 0, eyes: FrogEyes = .open(0), mouth: Mouth = .smile,
           tear: Int? = nil, zzz: Int = 0, sweat: Bool = false, food: Int? = nil, thought: Bool = false, shift: Int = 0) -> Frame {
        frame(delay) { c in
            let bw = body[0].count, bh = body.count
            let ox = (size - bw) / 2 + shift, oy = size - bh - lift
            c.blit(body, ox, oy, pal)
            let cx = ox + 9
            for ex in [ox + 2, ox + 12] {          // eye whites are 4x3 at rows 1-3
                switch eyes {
                case let .open(dx):
                    c.rect(ex + 1 + dx, oy + 2, 2, 2, ink); c.set(ex + 1 + dx, oy + 2, white)
                case .closed:
                    c.rect(ex, oy + 1, 4, 3, skin); c.rect(ex, oy + 2, 4, 1, dark)
                case .happy:
                    c.rect(ex, oy + 1, 4, 3, skin)
                    c.set(ex, oy + 2, dark); c.set(ex + 1, oy + 1, dark); c.set(ex + 2, oy + 1, dark); c.set(ex + 3, oy + 2, dark)
                case .sad:
                    c.rect(ex + 1, oy + 3, 2, 2, ink); c.set(ex + 1, oy + 3, white)
                    c.rect(ex, oy + 1, 4, 1, dark)
                }
            }
            let my = oy + 7
            switch mouth {
            case .smile: c.set(cx - 5, my - 1, dark); c.rect(cx - 4, my, 8, 1, dark); c.set(cx + 4, my - 1, dark)
            case .frown: c.set(cx - 5, my + 1, dark); c.rect(cx - 4, my, 8, 1, dark); c.set(cx + 4, my + 1, dark)
            case .open: c.rect(cx - 3, my, 6, 2, ink); c.rect(cx - 2, my + 1, 4, 1, pink)
            case .flat: c.rect(cx - 3, my, 6, 1, dark)
            case .none: break
            }
            c.rect(cx - 6, oy + 5, 2, 1, pink); c.rect(cx + 4, oy + 5, 2, 1, pink)   // cheeks
            drawTear(c, x: ox + 3, y: oy + 4, step: tear)
            if sweat { c.rect(ox + bw - 2, oy + 3, 1, 2, tearBlue) }
            drawZzz(c, zzz, x: 17, y: oy - 3, color: dark)
            if let st = food { drawFood(c, .fly, x: ox - 2, y: oy + 6, stage: st) }
            if thought { drawThought(c, .fly, x: 0, y: 0, dots: [(9, 8), (10, 9)], outline: dark) }
        }
    }
    return PetDef(name: "Frog", states: [
        "idle": [f(1.0), f(0.12, eyes: .closed), f(1.2), f(0.25, eyes: .open(1)), f(0.6)],
        "working": [f(0.2, eyes: .open(-1), mouth: .flat, sweat: true), f(0.2, mouth: .flat),
                    f(0.2, eyes: .open(1), mouth: .flat, sweat: true), f(0.2, mouth: .flat)],
        "happy": [f(0.1, eyes: .happy, mouth: .open), f(0.1, lift: 4, eyes: .happy, mouth: .open),
                  f(0.15, lift: 7, eyes: .happy, mouth: .open), f(0.1, lift: 4, eyes: .happy, mouth: .open),
                  f(0.3, eyes: .happy, mouth: .smile)],
        "sad": [f(0.35, eyes: .sad, mouth: .frown, tear: 0), f(0.35, eyes: .sad, mouth: .frown, tear: 1),
                f(0.35, eyes: .sad, mouth: .frown, tear: 2), f(0.35, eyes: .sad, mouth: .frown)],
        "sleeping": [f(0.5, eyes: .closed, mouth: .flat, zzz: 1), f(0.5, eyes: .closed, mouth: .flat, zzz: 2),
                     f(0.7, eyes: .closed, mouth: .flat, zzz: 3), f(0.4, eyes: .closed, mouth: .flat)],
        "eating": [f(0.25, mouth: .open, food: 0), f(0.25, mouth: .flat, food: 0),
                   f(0.25, mouth: .open, food: 1), f(0.25, mouth: .flat, food: 1),
                   f(0.3, eyes: .happy, mouth: .smile, food: 2), f(0.5, eyes: .happy, mouth: .smile, food: 2)],
        "hungry": [f(0.6, eyes: .sad, mouth: .flat, thought: true), f(0.12, eyes: .sad, mouth: .flat, thought: true, shift: -1),
                   f(0.12, eyes: .sad, mouth: .flat, thought: true, shift: 1), f(0.6, eyes: .sad, mouth: .flat, thought: true),
                   f(0.5, eyes: .closed, mouth: .flat)],
    ])
}

// --- Penguin --------------------------------------------------------------

func penguin() -> PetDef {
    let coat = rgb(51, 65, 85), dark = rgb(15, 23, 42), beak = rgb(249, 115, 22)
    let pal: [Character: Color] = ["k": dark, "b": coat, "w": white, "o": beak]
    let body = art([
        ".....kkkkkk.....",
        "...kkbbbbbbkk...",
        "..kbbbbbbbbbbk..",
        ".kbbbbbbbbbbbbk.",
        ".kbbwwwwwwwwbbk.",
        ".kbbwwwwwwwwbbk.",
        ".kbbwwwwwwwwbbk.",
        "kbbbwwwwwwwwbbbk",
        "kbbbwwwwwwwwbbbk",
        "kbbbwwwwwwwwbbbk",
        "kbbbwwwwwwwwbbbk",
        "kbbbwwwwwwwwbbbk",
        "kbbbwwwwwwwwbbbk",
        ".kbbwwwwwwwwbbk.",
        ".kbbbwwwwwwbbbk.",
        "..kkbbbbbbbbkk..",
        "...oo.kkkk.oo...",
    ])
    let flipperDown = ["kb", "kb", "kb", "kb", "kk"]
    let flipperUp = [".k", "kb", "kb", "kb", "kk"]
    func f(_ delay: Double, flap: Bool = false, lift: Int = 0, eyes: Eyes = .open(0), mouth: Mouth = .none,
           tear: Int? = nil, zzz: Int = 0, sweat: Bool = false, food: Int? = nil, thought: Bool = false, shift: Int = 0) -> Frame {
        frame(delay) { c in
            let bw = body[0].count, bh = body.count
            let ox = (size - bw) / 2 + shift, oy = size - bh - lift
            c.blit(body, ox, oy, pal)
            let wing = flap ? flipperUp : flipperDown
            let wy = flap ? oy + 4 : oy + 7
            c.blit(wing, ox - 1, wy, pal)
            c.blit(wing.map { String($0.reversed()) }, ox + bw - 1, wy, pal)
            let cx = ox + 8, eyeY = oy + 5
            let lx = cx - 4, rx = cx + 2
            drawEyes(c, eyes, lx: lx, rx: rx, y: eyeY, browColor: dark)
            c.rect(cx - 1, eyeY + 3, 2, 1, beak); c.rect(cx - 1, eyeY + 4, 2, 1, mouth == .frown ? dark : beak)
            if mouth == .open { c.rect(cx - 1, eyeY + 4, 2, 1, ink) }
            drawTear(c, x: lx, y: eyeY + 3, step: tear)
            if sweat { c.rect(ox + bw - 3, oy + 2, 1, 2, tearBlue) }
            drawZzz(c, zzz, x: 17, y: oy - 3, color: dark)
            if let st = food { drawFood(c, .fish, x: ox - 4, y: oy + 9, stage: st) }
            if thought { drawThought(c, .fish, x: 0, y: 0, dots: [(8, 7)], outline: dark) }
        }
    }
    return PetDef(name: "Penguin", states: [
        "idle": [f(0.8), f(0.8, lift: 1), f(0.4), f(0.12, eyes: .closed), f(0.6, lift: 1)],
        "working": [f(0.2, eyes: .open(-1), sweat: true, shift: -1), f(0.2, lift: 1), f(0.2, eyes: .open(1), sweat: true, shift: 1), f(0.2, lift: 1)],
        "happy": [f(0.1, flap: true, eyes: .happy, mouth: .open), f(0.1, lift: 3, eyes: .happy, mouth: .open),
                  f(0.15, flap: true, lift: 5, eyes: .happy, mouth: .open), f(0.1, lift: 3, eyes: .happy, mouth: .open),
                  f(0.3, flap: true, eyes: .happy, mouth: .open)],
        "sad": [f(0.35, eyes: .sad, mouth: .frown, tear: 0), f(0.35, eyes: .sad, mouth: .frown, tear: 1),
                f(0.35, eyes: .sad, mouth: .frown, tear: 2), f(0.35, eyes: .sad, mouth: .frown)],
        "sleeping": [f(0.5, eyes: .closed, zzz: 1), f(0.5, eyes: .closed, zzz: 2), f(0.7, eyes: .closed, zzz: 3), f(0.4, eyes: .closed)],
        "eating": [f(0.25, mouth: .open, food: 0), f(0.25, lift: 1, food: 0),
                   f(0.25, mouth: .open, food: 1), f(0.25, lift: 1, food: 1),
                   f(0.3, flap: true, eyes: .happy, mouth: .open, food: 2), f(0.5, eyes: .happy, food: 2)],
        "hungry": [f(0.6, eyes: .sad, mouth: .frown, thought: true), f(0.12, eyes: .sad, mouth: .frown, thought: true, shift: -1),
                   f(0.12, eyes: .sad, mouth: .frown, thought: true, shift: 1), f(0.6, eyes: .sad, mouth: .frown, thought: true),
                   f(0.5, eyes: .closed)],
    ])
}

// MARK: - Output

let stateOrder = ["idle", "working", "happy", "sad", "sleeping", "eating", "hungry"]
let pets = [blob(), cat(), ghost(), robot(), chick(), dog(), frog(), penguin()]

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

/// One animated GIF with every pet side by side cycling through its states (README hero).
func writeShowcase(to url: URL, scale: Int = 4, secondsPerState: Double = 2.4, step: Double = 0.1) {
    let gap = 2, cell = size * scale
    let w = (size * pets.count + gap * (pets.count - 1)) * scale, h = cell
    var frames: [Frame] = []
    for state in stateOrder {
        var t = 0.0
        while t < secondsPerState {
            let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.interpolationQuality = .none
            for (i, pet) in pets.enumerated() {
                let anim = pet.states[state]!
                let total = anim.reduce(0) { $0 + $1.delay }
                var local = t.truncatingRemainder(dividingBy: total), idx = 0
                while idx < anim.count - 1, local >= anim[idx].delay { local -= anim[idx].delay; idx += 1 }
                ctx.draw(anim[idx].image, in: CGRect(x: i * (size + gap) * scale, y: 0, width: cell, height: cell))
            }
            frames.append(Frame(image: ctx.makeImage()!, delay: step))
            t += step
        }
    }
    writeGIF(frames, to: url)
    print("wrote \(url.path) (\(frames.count) frames)")
}

var args = Array(CommandLine.arguments.dropFirst())
var sheetPath: String?
var showcasePath: String?
if let i = args.firstIndex(of: "--sheet"), i + 1 < args.count {
    sheetPath = args[i + 1]
    args.removeSubrange(i...i + 1)
}
if let i = args.firstIndex(of: "--showcase"), i + 1 < args.count {
    showcasePath = args[i + 1]
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
if let p = showcasePath { writeShowcase(to: URL(fileURLWithPath: p)) }
