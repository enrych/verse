import AppKit
import SwiftUI

struct Palette: Equatable {
    /// Words already sung.
    var lyric: Color
    /// The word being sung right now.
    var highlight: Color
    /// Words not sung yet, and surrounding lines.
    var secondary: Color
    /// Stage background tint.
    var background: Color

    /// Warm cream on black, for Constellation.
    static let starlight = Palette(
        lyric: Color(hex: "#EADCB4")!,
        highlight: Color(hex: "#FFF1C9")!,
        secondary: Color(hex: "#EADCB48C")!,
        background: .black
    )

    static let `default` = Palette(
        lyric: .white,
        highlight: Color(hex: "#FFD36E")!,
        secondary: .white.opacity(0.35),
        background: .black
    )
}

/// Pulls a palette out of album art: buckets pixels by hue and picks the
/// most vivid, most common colours.
enum PaletteExtractor {
    private struct Bucket {
        var count = 0
        var r = 0.0, g = 0.0, b = 0.0
        var score = 0.0
        var color: NSColor { NSColor(srgbRed: r / Double(count), green: g / Double(count), blue: b / Double(count), alpha: 1) }
    }

    static func palette(from image: NSImage) -> Palette? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let side = 32
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: side * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }

        var buckets = [Bucket](repeating: Bucket(), count: 12)
        var avg = (r: 0.0, g: 0.0, b: 0.0)
        let n = Double(side * side)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[i]) / 255, g = Double(pixels[i + 1]) / 255, b = Double(pixels[i + 2]) / 255
            avg.r += r / n; avg.g += g / n; avg.b += b / n
            let c = NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
            let (s, v) = (c.saturationComponent, c.brightnessComponent)
            guard s > 0.18, v > 0.22 else { continue }
            let index = min(Int(c.hueComponent * 12), 11)
            buckets[index].count += 1
            buckets[index].r += r; buckets[index].g += g; buckets[index].b += b
            buckets[index].score += (0.3 + s) * (0.3 + v)
        }

        let ranked = buckets.filter { $0.count > 0 }.sorted { $0.score > $1.score }
        let average = NSColor(srgbRed: avg.r, green: avg.g, blue: avg.b, alpha: 1)

        let highlight = adjust(ranked.first?.color ?? .systemYellow, minSaturation: 0.5, minBrightness: 0.92)
        let second = ranked.dropFirst().first?.color ?? highlight
        return Palette(
            lyric: Color(nsColor: highlight.blended(withFraction: 0.82, of: .white) ?? .white),
            highlight: Color(nsColor: highlight),
            secondary: Color(nsColor: adjust(second, minSaturation: 0.25, minBrightness: 0.85)).opacity(0.4),
            background: Color(nsColor: NSColor(hue: average.hueComponent,
                                               saturation: min(average.saturationComponent, 0.6),
                                               brightness: min(average.brightnessComponent, 0.22), alpha: 1))
        )
    }

    private static func adjust(_ c: NSColor, minSaturation: CGFloat, minBrightness: CGFloat) -> NSColor {
        let c = c.usingColorSpace(.sRGB) ?? c
        return NSColor(hue: c.hueComponent,
                       saturation: max(c.saturationComponent, minSaturation),
                       brightness: max(c.brightnessComponent, minBrightness),
                       alpha: 1)
    }
}
