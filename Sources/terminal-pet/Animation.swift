import CoreGraphics
import Foundation
import ImageIO

/// A decoded animated image (GIF, APNG, or a single-frame PNG).
struct Animation {
    let frames: [CGImage]
    let delays: [TimeInterval]

    var width: Int { frames.first?.width ?? 0 }
    var height: Int { frames.first?.height ?? 0 }

    static func load(url: URL) -> Animation? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let count = CGImageSourceGetCount(src)
        guard count > 0 else { return nil }
        var frames: [CGImage] = []
        var delays: [TimeInterval] = []
        for i in 0..<count {
            guard let img = CGImageSourceCreateImageAtIndex(src, i, nil) else { continue }
            frames.append(img)
            delays.append(frameDelay(src, i))
        }
        return frames.isEmpty ? nil : Animation(frames: frames, delays: delays)
    }

    private static func frameDelay(_ src: CGImageSource, _ index: Int) -> TimeInterval {
        let fallback = 0.1
        guard let props = CGImageSourceCopyPropertiesAtIndex(src, index, nil) as? [CFString: Any] else {
            return fallback
        }
        let candidates: [(CFString, CFString, CFString)] = [
            (kCGImagePropertyGIFDictionary, kCGImagePropertyGIFUnclampedDelayTime, kCGImagePropertyGIFDelayTime),
            (kCGImagePropertyPNGDictionary, kCGImagePropertyAPNGUnclampedDelayTime, kCGImagePropertyAPNGDelayTime),
        ]
        for (dict, unclamped, clamped) in candidates {
            guard let d = props[dict] as? [CFString: Any] else { continue }
            if let v = d[unclamped] as? Double, v > 0 { return max(v, 0.02) }
            if let v = d[clamped] as? Double, v > 0 { return max(v, 0.02) }
        }
        return fallback
    }
}
