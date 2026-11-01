import AppKit
import SwiftUI

/// The default background: near-black with a soft vignette, faint dust stars
/// and a fine film grain. Matches the website's hero.
struct NightBackground: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                RadialGradient(
                    colors: [Color(hex: "#08080A")!, Color(hex: "#030304")!, .black],
                    center: UnitPoint(x: 0.5, y: 0.45),
                    startRadius: 0,
                    endRadius: max(geo.size.width, geo.size.height) * 0.75
                )
                DustStars()
                Image(nsImage: GrainTexture.image)
                    .resizable(resizingMode: .tile)
                    .opacity(0.035)
                    .blendMode(.screen)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// The current song's cover, blurred and dimmed, with the same grain on top.
/// Falls back to Night when there's no artwork.
struct AlbumBackground: View {
    let artwork: NSImage?

    var body: some View {
        if let artwork {
            GeometryReader { geo in
                ZStack {
                    Color.black
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .blur(radius: 70)
                        .saturation(0.9)
                        .opacity(0.55)
                        .clipped()
                    LinearGradient(colors: [.black.opacity(0.35), .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                    Image(nsImage: GrainTexture.image)
                        .resizable(resizingMode: .tile)
                        .opacity(0.035)
                        .blendMode(.screen)
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .transition(.opacity)
        } else {
            NightBackground()
        }
    }
}

/// A few hundred tiny, dim specks, placed deterministically so they never jump.
private struct DustStars: View {
    var body: some View {
        Canvas { ctx, size in
            var seed: UInt32 = 3
            func rand() -> Double {
                seed = seed &* 1664525 &+ 1013904223
                return Double(seed) / 4294967296
            }
            let count = Int(size.width * size.height / 3200)
            for _ in 0..<count {
                let x = rand() * size.width, y = rand() * size.height, b = rand()
                let alpha = 0.05 + b * b * 0.28
                let r = 0.35 + b * 0.75
                ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                         with: .color(Color(red: 234 / 255, green: 220 / 255, blue: 180 / 255).opacity(alpha)))
            }
        }
    }
}

/// A small tileable noise image, generated once.
private enum GrainTexture {
    static let image: NSImage = {
        let side = 220
        var bytes = [UInt8](repeating: 0, count: side * side)
        var rng = SystemRandomNumberGenerator()
        for i in bytes.indices { bytes[i] = UInt8.random(in: 0...255, using: &rng) }
        let cg: CGImage? = bytes.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side,
                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)?.makeImage()
        }
        guard let cg else { return NSImage(size: NSSize(width: 1, height: 1)) }
        return NSImage(cgImage: cg, size: NSSize(width: side, height: side))
    }()
}
