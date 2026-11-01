import Foundation

protocol LyricsProvider {
    var name: String { get }
    func lyrics(for track: Track) async throws -> Lyrics?
}

enum HTTP {
    static func get<T: Decodable>(_ url: URL, headers: [String: String] = [:]) async throws -> T? {
        var request = URLRequest(url: url, timeoutInterval: 10)
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 404 { return nil }
        guard (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(T.self, from: data)
    }

    static func url(_ base: String, _ query: [(String, String)]) -> URL {
        var c = URLComponents(string: base)!
        c.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        return c.url!
    }
}

/// Fuzzy matching between what the player reports and what a provider returns.
enum TrackMatch {
    static func normalize(_ s: String) -> String {
        var s = s.lowercased()
        // Drop "(feat. …)", "[Remastered]", " - 2011 Remaster" and similar decorations.
        for (open, close) in [("(", ")"), ("[", "]")] {
            while let a = s.range(of: open), let b = s.range(of: close, range: a.upperBound..<s.endIndex) {
                s.removeSubrange(a.lowerBound..<b.upperBound)
            }
        }
        if let dash = s.range(of: " - ") { s = String(s[..<dash.lowerBound]) }
        return s.filter { $0.isLetter || $0.isNumber }
    }

    static func score(title: String, artists: [String], duration: TimeInterval?, against track: Track) -> Int {
        let a = normalize(title), b = normalize(track.title)
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        var score = a == b ? 4 : (a.contains(b) || b.contains(a) ? 2 : 0)
        guard score > 0 else { return 0 }
        let wanted = normalize(track.artist)
        if artists.map(normalize).contains(where: { !$0.isEmpty && (wanted.contains($0) || $0.contains(wanted)) }) { score += 3 }
        if let d = duration, track.duration > 0 {
            let diff = abs(d - track.duration)
            score += diff < 3 ? 3 : (diff < 8 ? 1 : -3)
        }
        return score
    }
}

// MARK: - NetEase Cloud Music (unofficial API, has word-level "yrc" lyrics)

struct NetEaseProvider: LyricsProvider {
    let name = "NetEase"
    private let headers = [
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko)",
        "Referer": "https://music.163.com/",
    ]

    private struct SearchResponse: Decodable {
        struct Result: Decodable { var songs: [Song]? }
        struct Song: Decodable {
            struct Artist: Decodable { var name: String }
            var id: Int
            var name: String
            var artists: [Artist]?
            var duration: Double?
        }
        var result: Result?
    }

    private struct LyricResponse: Decodable {
        struct Body: Decodable { var lyric: String? }
        var lrc: Body?
        var yrc: Body?
    }

    func lyrics(for track: Track) async throws -> Lyrics? {
        let searchURL = HTTP.url("https://music.163.com/api/search/get", [
            ("s", "\(track.title) \(track.artist)"), ("type", "1"), ("limit", "10"),
        ])
        guard let search: SearchResponse = try await HTTP.get(searchURL, headers: headers) else { return nil }
        let ranked = (search.result?.songs ?? [])
            .map { song in
                (song, TrackMatch.score(title: song.name,
                                        artists: song.artists?.map(\.name) ?? [],
                                        duration: song.duration.map { $0 / 1000 },
                                        against: track))
            }
            .filter { $0.1 >= 5 }
            .sorted { $0.1 > $1.1 }
        guard let song = ranked.first?.0 else { return nil }

        let lyricURL = HTTP.url("https://music.163.com/api/song/lyric/v1", [
            ("id", String(song.id)), ("lv", "-1"), ("kv", "-1"), ("tv", "-1"), ("yv", "-1"),
        ])
        guard let body: LyricResponse = try await HTTP.get(lyricURL, headers: headers) else { return nil }

        if let yrc = body.yrc?.lyric {
            let lines = LyricsParser.parseYRC(yrc)
            if !lines.isEmpty { return Lyrics(lines: lines, timing: .word, source: name) }
        }
        if let lrc = body.lrc?.lyric {
            let parsed = LyricsParser.parseLRC(lrc)
            if !parsed.lines.isEmpty {
                return Lyrics(lines: parsed.lines, timing: parsed.wordTimed ? .word : .line, source: name)
            }
        }
        return nil
    }
}

// MARK: - LRCLIB (free, open, mostly line-level)

struct LRCLIBProvider: LyricsProvider {
    let name = "LRCLIB"
    private let headers = ["User-Agent": "Verse (https://github.com/enrych/verse)"]

    private struct Record: Decodable {
        var trackName: String?
        var artistName: String?
        var duration: Double?
        var syncedLyrics: String?
        var plainLyrics: String?
    }

    func lyrics(for track: Track) async throws -> Lyrics? {
        var query = [("track_name", track.title), ("artist_name", track.artist)]
        if !track.album.isEmpty { query.append(("album_name", track.album)) }
        if track.duration > 0 { query.append(("duration", String(Int(track.duration.rounded())))) }

        var synced: String?
        var plain: String?
        if let exact: Record = try await HTTP.get(HTTP.url("https://lrclib.net/api/get", query), headers: headers) {
            synced = exact.syncedLyrics
            plain = exact.plainLyrics
        }
        if synced == nil {
            let results: [Record] = try await HTTP.get(
                HTTP.url("https://lrclib.net/api/search", [("track_name", track.title), ("artist_name", track.artist)]),
                headers: headers) ?? []
            synced = results
                .filter { $0.syncedLyrics != nil }
                .max { a, b in
                    TrackMatch.score(title: a.trackName ?? "", artists: [a.artistName ?? ""], duration: a.duration, against: track)
                        < TrackMatch.score(title: b.trackName ?? "", artists: [b.artistName ?? ""], duration: b.duration, against: track)
                }?.syncedLyrics
        }
        guard let synced else {
            // No timings anywhere: spread plain lyrics across the song so there's still something to read.
            guard let plain, track.duration > 0 else { return nil }
            let lines = LyricsParser.spreadPlain(plain, duration: track.duration)
            return lines.isEmpty ? nil : Lyrics(lines: lines, timing: .estimated, source: name)
        }
        let parsed = LyricsParser.parseLRC(synced)
        guard !parsed.lines.isEmpty else { return nil }
        return Lyrics(lines: parsed.lines, timing: parsed.wordTimed ? .word : .line, source: name)
    }
}
