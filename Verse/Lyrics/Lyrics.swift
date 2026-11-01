import Foundation

/// One sung word (or syllable) with absolute start/end times in seconds.
/// `text` keeps its trailing whitespace so words can be joined back verbatim.
struct LyricWord: Codable, Hashable {
    var text: String
    var start: TimeInterval
    var end: TimeInterval
}

struct LyricLine: Codable, Hashable {
    var start: TimeInterval
    var end: TimeInterval
    var words: [LyricWord]

    var text: String { words.map(\.text).joined() }
    var isBlank: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

struct Lyrics: Codable, Hashable {
    enum Timing: String, Codable {
        /// Real per-word timings from the source.
        case word
        /// Line timings only; word timings are estimated.
        case line
        /// Plain lyrics with no timings; lines are spread across the song.
        case estimated
    }

    var lines: [LyricLine]
    var timing: Timing
    var source: String
}

/// Where playback is inside a set of lyrics.
struct LyricPosition: Equatable {
    /// Index of the current line, or -1 before the first line starts.
    var line: Int
    /// Index of the current word in that line, or -1 before its first word.
    var word: Int
}

extension Lyrics {
    func position(at time: TimeInterval) -> LyricPosition {
        var lo = 0, hi = lines.count - 1, found = -1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if lines[mid].start <= time { found = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        guard found >= 0 else { return LyricPosition(line: -1, word: -1) }
        var word = -1
        for (index, w) in lines[found].words.enumerated() where w.start <= time { word = index }
        return LyricPosition(line: found, word: word)
    }

    /// 0 = not sung yet, 0<x<1 = being sung, 1 = already sung.
    func fill(line: Int, word: Int, at time: TimeInterval) -> Double {
        guard lines.indices.contains(line), lines[line].words.indices.contains(word) else { return 0 }
        let w = lines[line].words[word]
        if time <= w.start { return 0 }
        if time >= w.end { return 1 }
        return (time - w.start) / max(w.end - w.start, 0.001)
    }
}
