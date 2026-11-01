import SwiftUI

/// Fills the quiet moments: before the first line, long instrumental breaks,
/// the outro, and pauses. Shows the song, plus three dots that fill as the
/// next line approaches. Fades away as soon as singing starts.
struct WaitingOverlay: View {
    let time: TimeInterval
    let lyrics: Lyrics
    let track: Track?
    let isPlaying: Bool
    let palette: Palette

    /// Gaps shorter than this (seconds) are left alone.
    private let minimumGap: TimeInterval = 4

    var body: some View {
        let state = gap()
        VStack(spacing: 14) {
            if let track {
                Text(track.title)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                Text(track.artist)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .opacity(0.6)
            }
            if !isPlaying {
                Text("Paused").font(.system(size: 14, weight: .medium)).opacity(0.5).padding(.top, 6)
            } else if let progress = state.progress {
                HStack(spacing: 10) {
                    ForEach(0..<3, id: \.self) { i in
                        let lit = min(max(progress * 3 - Double(i), 0), 1)
                        Circle()
                            .fill(palette.lyric)
                            .frame(width: 9, height: 9)
                            .opacity(0.18 + 0.82 * lit)
                            .scaleEffect(0.8 + 0.25 * lit)
                    }
                }
                .padding(.top, 10)
            }
        }
        .foregroundStyle(palette.lyric)
        .multilineTextAlignment(.center)
        .opacity(isPlaying ? state.visibility : 1)
        .allowsHitTesting(false)
    }

    /// How visible the overlay should be (0…1) and how far through the gap we are.
    private func gap() -> (visibility: Double, progress: Double?) {
        let lines = lyrics.lines.filter { !$0.isBlank }
        guard let first = lines.first else { return (0, nil) }

        // Intro: before the first line.
        if time < first.start {
            guard first.start >= minimumGap else { return (0, nil) }
            return (fade(from: 0, to: first.start), time / first.start)
        }
        // Between lines.
        for (a, b) in zip(lines, lines.dropFirst()) where time > a.end && time < b.start {
            let start = a.end + 0.8, length = b.start - start
            guard length >= minimumGap - 0.8, time > start else { return (0, nil) }
            return (fade(from: start, to: b.start), (time - start) / length)
        }
        // Outro: after the last line, just the song name.
        if let last = lines.last, time > last.end + 3 {
            return (min((time - last.end - 3) / 0.8, 1), nil)
        }
        return (0, nil)
    }

    /// Fade in over 0.8 s after `from`, out over 0.5 s before `to`.
    private func fade(from: TimeInterval, to: TimeInterval) -> Double {
        min(min((time - from) / 0.8, 1), max((to - time) / 0.5, 0))
    }
}
