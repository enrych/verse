import SwiftUI

/// The quiet-moment sky: a few dust stars twinkle and some specks drift slowly
/// across. `amount` (0…1) fades it in during intros and breaks.
struct AmbientSky: View {
    let amount: Double
    let time: TimeInterval

    private struct Speck { var x, y, size, phase, speed, dx, dy: Double }

    private static let twinkles: [Speck] = specks(seed: 5, count: 34, drifting: false)
    private static let drifters: [Speck] = specks(seed: 9, count: 7, drifting: true)

    var body: some View {
        Canvas { ctx, size in
            guard amount > 0.01 else { return }
            let cream = Color(red: 234 / 255, green: 220 / 255, blue: 180 / 255)
            for s in Self.twinkles {
                let pulse = 0.5 + 0.5 * sin(time * s.speed + s.phase)
                let a = amount * (0.08 + 0.42 * pulse * pulse)
                let r = s.size * (0.8 + 0.4 * pulse)
                let p = CGPoint(x: s.x * size.width, y: s.y * size.height)
                var c = ctx; c.opacity = a
                if pulse > 0.85 { c.addFilter(.shadow(color: cream, radius: 3)) }
                c.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(cream))
            }
            for s in Self.drifters {
                let x = (s.x + time * s.dx).truncatingRemainder(dividingBy: 1)
                let y = (s.y + time * s.dy).truncatingRemainder(dividingBy: 1)
                let p = CGPoint(x: (x < 0 ? x + 1 : x) * size.width, y: (y < 0 ? y + 1 : y) * size.height)
                var c = ctx; c.opacity = amount * 0.35
                c.fill(Path(ellipseIn: CGRect(x: p.x - s.size, y: p.y - s.size, width: s.size * 2, height: s.size * 2)), with: .color(cream))
            }
        }
        .allowsHitTesting(false)
    }

    private static func specks(seed start: UInt32, count: Int, drifting: Bool) -> [Speck] {
        var seed = start
        func rand() -> Double { seed = seed &* 1664525 &+ 1013904223; return Double(seed) / 4294967296 }
        return (0..<count).map { _ in
            Speck(x: rand(), y: rand(), size: 0.7 + rand() * 1.1, phase: rand() * .pi * 2, speed: 0.6 + rand() * 1.4,
                  dx: drifting ? (rand() - 0.5) * 0.006 : 0, dy: drifting ? (rand() * 0.004 + 0.001) : 0)
        }
    }
}
