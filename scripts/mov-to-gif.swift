// Converts a screen recording (.mov/.mp4) to an animated GIF using only AVFoundation + ImageIO.
//   swiftc -O -o .build/mov-to-gif scripts/mov-to-gif.swift
//   .build/mov-to-gif in.mov out.gif [fps=12] [width=820]
import AVFoundation
import CoreGraphics
import Foundation
import ImageIO

let args = CommandLine.arguments
guard args.count >= 3 else {
    fputs("usage: mov-to-gif in.mov out.gif [fps] [width]\n", stderr)
    exit(2)
}
let input = URL(fileURLWithPath: args[1])
let output = URL(fileURLWithPath: args[2])
let fps = args.count > 3 ? Double(args[3]) ?? 12 : 12
let width = args.count > 4 ? Int(args[4]) ?? 820 : 820

let asset = AVURLAsset(url: input)
let semaphore = DispatchSemaphore(value: 0)
var duration = CMTime.zero
var track: AVAssetTrack?
Task {
    duration = (try? await asset.load(.duration)) ?? .zero
    track = try? await asset.loadTracks(withMediaType: .video).first
    semaphore.signal()
}
semaphore.wait()
guard let track, duration.seconds > 0 else {
    fputs("mov-to-gif: no video track in \(input.path)\n", stderr)
    exit(1)
}

let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 60)
generator.maximumSize = CGSize(width: width, height: 0)

let frameCount = Int(duration.seconds * fps)
let times = (0..<frameCount).map { NSValue(time: CMTime(seconds: Double($0) / fps, preferredTimescale: 600)) }

guard let dest = CGImageDestinationCreateWithURL(output as CFURL, "com.compuserve.gif" as CFString, frameCount, nil) else {
    fputs("mov-to-gif: cannot create \(output.path)\n", stderr)
    exit(1)
}
CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
let frameProps = [kCGImagePropertyGIFDictionary: [
    kCGImagePropertyGIFDelayTime: 1 / fps,
    kCGImagePropertyGIFUnclampedDelayTime: 1 / fps,
]] as CFDictionary

var written = 0
for t in times {
    var actual = CMTime.zero
    guard let img = try? generator.copyCGImage(at: t.timeValue, actualTime: &actual) else { continue }
    CGImageDestinationAddImage(dest, img, frameProps)
    written += 1
}
guard written > 0, CGImageDestinationFinalize(dest) else {
    fputs("mov-to-gif: failed to write \(output.path)\n", stderr)
    exit(1)
}
let size = (try? FileManager.default.attributesOfItem(atPath: output.path)[.size] as? Int) ?? 0
print("wrote \(output.path): \(written) frames at \(Int(fps)) fps, \(size / 1024) KB")
