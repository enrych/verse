import SwiftUI

/// Constellation layout: words gather into groups of up to ~12 (whole lyric
/// lines). Each group is a constellation of stars in a fixed band across the
/// screen, joined in sung order; it clears just before the next group begins.
///
/// Deterministic, and mirrors prototype/style-lab.template.html.
/// Positions are in band space (0…1 × 0…1).
final class ConstellationLayout {
    struct Star {
        var x: Double
        var y: Double
        var word: LyricWord
        /// Index of the previous star in the same constellation, if any.
        var previous: Int?
        var segStart: Double = 0
        var segEnd: Double = 0
        var clearAt: Double = .infinity
    }

    let stars: [Star]

    init(lyrics: Lyrics) {
        var seed: UInt32 = 11
        func rand() -> Double {
            seed = seed &* 1664525 &+ 1013904223
            return Double(seed) / 4294967296
        }

        // Group whole lyric lines; a blank line always starts a new group.
        var groups: [[LyricWord]] = []
        var current: [LyricWord] = []
        for line in lyrics.lines {
            if line.words.isEmpty {
                if !current.isEmpty { groups.append(current) }
                current = []
                continue
            }
            if !current.isEmpty && current.count + line.words.count > 12 {
                groups.append(current)
                current = []
            }
            current += line.words
        }
        if !current.isEmpty { groups.append(current) }

        var stars: [Star] = []
        for group in groups {
            let first = stars.count
            for (k, word) in group.enumerated() {
                var best = (x: 0.5, y: 0.5)
                var bestScore = -Double.infinity
                for _ in 0..<24 {
                    let cx = 0.04 + rand() * 0.92
                    let cy = 0.06 + rand() * 0.88
                    // The band is ~3:1 and labels are wide, so x distances count extra.
                    let crowd = min(1, stars[first..<stars.count].map { hypot(($0.x - cx) * 2.2, $0.y - cy) }.min() ?? 1)
                    let reach = k > 0 ? hypot((stars[stars.count - 1].x - cx) * 3, stars[stars.count - 1].y - cy) : 1
                    let score = min(crowd, 0.5) - abs(reach - 0.9) * 0.25 + rand() * 0.05
                    if score > bestScore { bestScore = score; best = (cx, cy) }
                }
                var star = Star(x: best.x, y: best.y, word: word, previous: k > 0 ? stars.count - 1 : nil)
                if k > 0 {
                    let p = stars[stars.count - 1].word.start
                    star.segEnd = word.start
                    star.segStart = max(p + (word.start - p) * 0.3, word.start - 0.9)
                }
                stars.append(star)
            }
        }

        // Each constellation fades out just before the next one's first word.
        var index = 0
        for (gi, group) in groups.enumerated() {
            let clear = gi + 1 < groups.count ? groups[gi + 1][0].start - 0.35 : .infinity
            for _ in group { stars[index].clearAt = clear; index += 1 }
        }
        self.stars = stars
    }
}

struct ConstellationStyle: View {
    let time: TimeInterval
    let layout: ConstellationLayout
    let palette: Palette
    let scale: Double

    var body: some View {
        Canvas { ctx, size in
            let t = time
            let stars = layout.stars
            let unit = min(size.width, size.height) * scale
            let band = CGRect(x: size.width * 0.16, y: size.height * 0.36, width: size.width * 0.68, height: size.height * 0.34)
            func point(_ s: ConstellationLayout.Star) -> CGPoint {
                CGPoint(x: band.minX + s.x * band.width, y: band.minY + s.y * band.height)
            }
            func groupAlpha(_ s: ConstellationLayout.Star) -> Double {
                t < s.clearAt ? 1 : max(0, 1 - (t - s.clearAt) / 0.35)
            }

            // Lines between consecutive stars.
            for s in stars {
                guard let pi = s.previous, t >= s.segStart else { continue }
                let ga = groupAlpha(s)
                guard ga > 0 else { continue }
                let a = point(stars[pi]), b = point(s)
                let e = smoothstep((t - s.segStart) / max(s.segEnd - s.segStart, 0.001))
                var path = Path()
                path.move(to: a)
                path.addLine(to: CGPoint(x: a.x + (b.x - a.x) * e, y: a.y + (b.y - a.y) * e))
                var c = ctx; c.opacity = ga * 0.75
                c.stroke(path, with: .color(palette.lyric), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
            }

            // Stars and labels.
            for s in stars where t >= s.word.start {
                let ga = groupAlpha(s)
                guard ga > 0 else { continue }
                let p = point(s)
                let singing = t < s.word.end
                let pop = smoothstep((t - s.word.start) / 0.25)
                // The newest star is big and glowing; it settles over ~1.5 s after its word.
                let settle = singing ? 1 : smoothstep(1 - (t - s.word.end) / 1.5)
                let r = unit * (0.008 + 0.012 * settle) * (0.4 + 0.6 * pop)
                let color = settle > 0.05 ? palette.highlight : palette.lyric

                var c = ctx; c.opacity = ga
                if settle > 0.05 { c.addFilter(.shadow(color: palette.highlight.opacity(settle), radius: r * 0.8)) }
                c.fill(Self.sparkle(at: p, radius: r), with: .color(color))

                let small = unit * 0.021, big = unit * 0.06
                let fontSize = small + (big - small) * settle * pop
                var label = ctx
                label.opacity = ga * (0.72 + 0.28 * settle)
                let text = label.resolve(
                    Text(s.word.text.trimmingCharacters(in: .whitespaces))
                        .font(.system(size: fontSize, weight: settle > 0.5 ? .heavy : .semibold))
                        .foregroundStyle(color)
                )
                label.draw(text, at: CGPoint(x: p.x, y: p.y + unit * 0.012 + r * 0.4), anchor: .top)
            }
        }
    }

    /// Four-point sparkle with concave sides.
    static func sparkle(at p: CGPoint, radius r: CGFloat) -> Path {
        let k = r * 0.16
        var path = Path()
        path.move(to: CGPoint(x: p.x, y: p.y - r))
        path.addQuadCurve(to: CGPoint(x: p.x + r, y: p.y), control: CGPoint(x: p.x + k, y: p.y - k))
        path.addQuadCurve(to: CGPoint(x: p.x, y: p.y + r), control: CGPoint(x: p.x + k, y: p.y + k))
        path.addQuadCurve(to: CGPoint(x: p.x - r, y: p.y), control: CGPoint(x: p.x - k, y: p.y + k))
        path.addQuadCurve(to: CGPoint(x: p.x, y: p.y - r), control: CGPoint(x: p.x - k, y: p.y - k))
        path.closeSubpath()
        return path
    }
}

func smoothstep(_ x: Double) -> Double {
    let u = min(max(x, 0), 1)
    return u * u * (3 - 2 * u)
}
