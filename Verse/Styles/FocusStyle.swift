import SwiftUI

/// One big line at a time. Words light up as they're sung; the previous and
/// next lines sit small and dim above and below.
struct FocusStyle: View {
    let time: TimeInterval
    let lyrics: Lyrics
    let palette: Palette
    let scale: Double

    var body: some View {
        GeometryReader { geo in
            let unit = min(geo.size.width, geo.size.height) * scale
            let current = max(lyrics.position(at: time).line, 0)
            VStack(spacing: unit * 0.035) {
                line(current - 1, size: unit * 0.032, emphasis: false)
                line(current, size: unit * 0.068, emphasis: true)
                    .id(current)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: unit * 0.02)), removal: .opacity))
                line(current + 1, size: unit * 0.032, emphasis: false)
            }
            .frame(maxWidth: geo.size.width * 0.82)
            .frame(width: geo.size.width, height: geo.size.height)
            .offset(y: geo.size.height * 0.06)
            .animation(.easeOut(duration: 0.45), value: current)
        }
    }

    @ViewBuilder
    private func line(_ index: Int, size: CGFloat, emphasis: Bool) -> some View {
        if lyrics.lines.indices.contains(index), !lyrics.lines[index].isBlank {
            words(index)
                .font(.system(size: size, weight: emphasis ? .bold : .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.6)
                .opacity(emphasis ? 1 : 0.38)
        } else {
            Text(" ").font(.system(size: size))
        }
    }

    /// The line as one Text, each word coloured by whether it's sung, being sung, or upcoming.
    private func words(_ index: Int) -> Text {
        let line = lyrics.lines[index]
        return line.words.enumerated().reduce(Text("")) { text, item in
            let fill = lyrics.fill(line: index, word: item.offset, at: time)
            let color: Color = fill >= 1 ? palette.lyric : (fill > 0 ? palette.highlight : palette.lyric.opacity(0.35))
            return text + Text(item.element.text).foregroundColor(color)
        }
    }
}
