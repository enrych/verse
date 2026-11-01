import Foundation

enum LyricsParser {

    // MARK: NetEase YRC
    //
    // [lineStartMs,lineDurMs](wordStartMs,wordDurMs,0)word(…)word
    // Lines that start with "{" are JSON credits and are skipped.

    static func parseYRC(_ source: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        for raw in source.split(whereSeparator: \.isNewline) {
            let line = Substring(raw)
            guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { continue }
            let header = line[line.index(after: line.startIndex)..<close].split(separator: ",")
            guard header.count >= 2, let lineStart = Double(header[0]), let lineDur = Double(header[1]) else { continue }

            var words: [LyricWord] = []
            var rest = line[line.index(after: close)...]
            while let open = rest.firstIndex(of: "(") {
                guard let shut = rest[open...].firstIndex(of: ")") else { break }
                let inside = rest[rest.index(after: open)..<shut]
                let afterShut = rest.index(after: shut)
                let nextOpen = rest[afterShut...].firstIndex(of: "(") ?? rest.endIndex
                let text = String(rest[afterShut..<nextOpen])
                let nums = inside.split(separator: ",")
                if nums.count == 3, let s = Double(nums[0]), let d = Double(nums[1]) {
                    words.append(LyricWord(text: text, start: s / 1000, end: (s + d) / 1000))
                } else if !words.isEmpty {
                    // A literal "(…)" in the lyric text, not a timestamp.
                    words[words.count - 1].text += "(\(inside))" + text
                }
                rest = rest[nextOpen...]
            }
            guard !words.isEmpty else { continue }
            lines.append(LyricLine(start: lineStart / 1000, end: (lineStart + lineDur) / 1000, words: words))
        }
        return lines.sorted { $0.start < $1.start }
    }

    // MARK: LRC (+ enhanced "A2" word tags <mm:ss.xx>)

    static func parseLRC(_ source: String) -> (lines: [LyricLine], wordTimed: Bool) {
        var entries: [(time: TimeInterval, text: Substring)] = []
        for raw in source.split(whereSeparator: \.isNewline) {
            var rest = Substring(raw)
            var times: [TimeInterval] = []
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]"),
                  let t = timestamp(rest[rest.index(after: rest.startIndex)..<close]) {
                times.append(t)
                rest = rest[rest.index(after: close)...]
            }
            for t in times { entries.append((t, rest)) }
        }
        entries.sort { $0.time < $1.time }

        var lines: [LyricLine] = []
        var wordTimed = false
        for (i, entry) in entries.enumerated() {
            let next = i + 1 < entries.count ? entries[i + 1].time : entry.time + 6
            if entry.text.contains("<"), let words = enhancedWords(entry.text, lineEnd: next), !words.isEmpty {
                wordTimed = true
                lines.append(LyricLine(start: entry.time, end: words.last!.end, words: words))
            } else {
                let words = estimatedWords(String(entry.text), start: entry.time, next: next)
                lines.append(LyricLine(start: entry.time, end: words.last?.end ?? next, words: words))
            }
        }
        return (lines, wordTimed)
    }

    /// "mm:ss.xx" / "mm:ss" → seconds.
    static func timestamp(_ s: Substring) -> TimeInterval? {
        let parts = s.split(separator: ":")
        guard parts.count == 2, let m = Double(parts[0]), let sec = Double(parts[1]) else { return nil }
        return m * 60 + sec
    }

    private static func enhancedWords(_ text: Substring, lineEnd: TimeInterval) -> [LyricWord]? {
        var stamps: [(TimeInterval, String)] = []
        var rest = text
        while let open = rest.firstIndex(of: "<"), let close = rest[open...].firstIndex(of: ">") {
            guard let t = timestamp(rest[rest.index(after: open)..<close]) else { return nil }
            let after = rest.index(after: close)
            let next = rest[after...].firstIndex(of: "<") ?? rest.endIndex
            stamps.append((t, String(rest[after..<next])))
            rest = rest[next...]
        }
        var words: [LyricWord] = []
        for (i, stamp) in stamps.enumerated() where !stamp.1.isEmpty {
            let end = i + 1 < stamps.count ? stamps[i + 1].0 : min(lineEnd, stamp.0 + 1.5)
            words.append(LyricWord(text: stamp.1, start: stamp.0, end: max(end, stamp.0)))
        }
        return words
    }

    /// Spreads a line's time across its words, weighted by length.
    /// Singers usually finish before the next line starts, so the span is capped.
    static func estimatedWords(_ text: String, start: TimeInterval, next: TimeInterval) -> [LyricWord] {
        let tokens = tokenize(text)
        guard !tokens.isEmpty else { return [] }
        let letters = tokens.reduce(0) { $0 + max($1.trimmingCharacters(in: .whitespaces).count, 1) }
        let span = min((next - start) * 0.92, Double(letters) * 0.11 + 0.6)
        var t = start
        return tokens.map { token in
            let weight = Double(max(token.trimmingCharacters(in: .whitespaces).count, 1)) / Double(letters)
            let word = LyricWord(text: token, start: t, end: t + span * weight)
            t = word.end
            return word
        }
    }

    /// Plain (untimed) lyrics: lines are spaced evenly between 8% and 92% of the
    /// song, blank lines become short pauses, and words are estimated per line.
    static func spreadPlain(_ text: String, duration: TimeInterval) -> [LyricLine] {
        let raw = text.split(separator: "\n", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        let weights = raw.map { $0.isEmpty ? 0.5 : 1.0 }
        let total = weights.reduce(0, +)
        guard total > 0 else { return [] }
        let start = duration * 0.08, span = duration * 0.84
        var t = start
        var lines: [LyricLine] = []
        for (i, line) in raw.enumerated() {
            let length = span * weights[i] / total
            if !line.isEmpty {
                let words = estimatedWords(line, start: t, next: t + length)
                lines.append(LyricLine(start: t, end: words.last?.end ?? t + length, words: words))
            }
            t += length
        }
        return lines
    }

    /// Words keep trailing spaces. Text with no spaces (e.g. CJK) splits per character.
    static func tokenize(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        if !trimmed.contains(" ") && trimmed.unicodeScalars.contains(where: { $0.value > 0x2E80 }) {
            return trimmed.map(String.init)
        }
        var tokens: [String] = []
        var current = ""
        for ch in trimmed {
            if ch == " " { current.append(ch) }
            else if current.last == " " { tokens.append(current); current = String(ch) }
            else { current.append(ch) }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }
}
