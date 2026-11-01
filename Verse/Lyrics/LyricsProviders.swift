import Foundation

protocol LyricsProvider {
    var name: String { get }
    func lyrics(for track: Track) async throws -> Lyrics?
}

/// A provider couldn't answer (network error, busy server). Different from "no lyrics".
struct LyricsLookupError: Error {
    let message: String
}

enum HTTP {
    /// GET + decode JSON. Returns nil on 404; retries once on timeouts, 429 and 5xx;
    /// throws `LyricsLookupError` if the service still can't answer.
    static func get<T: Decodable>(_ url: URL, headers: [String: String] = [:], service: String) async throws -> T? {
        var lastProblem = "unreachable"
        for attempt in 0..<2 {
            if attempt > 0 { try? await Task.sleep(for: .milliseconds(900)) }
            var request = URLRequest(url: url, timeoutInterval: 10)
            for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else { lastProblem = "bad response"; continue }
                if http.statusCode == 404 { return nil }
                if http.statusCode == 429 || http.statusCode >= 500 { lastProblem = "busy"; continue }
                guard (200..<300).contains(http.statusCode) else { lastProblem = "error \(http.statusCode)"; continue }
                return try JSONDecoder().decode(T.self, from: data)
            } catch is DecodingError {
                lastProblem = "unexpected reply"
            } catch {
                if Task.isCancelled { throw error }
                lastProblem = (error as? URLError)?.code == .timedOut ? "timed out" : "unreachable"
            }
        }
        throw LyricsLookupError(message: "\(service) \(lastProblem)")
    }

    static func url(_ base: String, _ query: [(String, String)]) -> URL {
        var c = URLComponents(string: base)!
        c.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        return c.url!
    }
}

/// Fuzzy matching between what the player reports and what a provider returns.
enum TrackMatch {
    private static let decorations = [" feat. ", " feat ", " ft. ", " ft ", " featuring ", " with "]

    /// Comparable form: lowercase letters/digits only, without "(feat. …)", "[Live]",
    /// " - 2011 Remaster" and similar.
    static func normalize(_ s: String) -> String {
        clean(s).lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Readable title for searching: same decorations removed, original casing kept.
    static func clean(_ s: String) -> String {
        var s = s
        for (open, close) in [("(", ")"), ("[", "]")] {
            while let a = s.range(of: open), let b = s.range(of: close, range: a.upperBound..<s.endIndex) {
                s.removeSubrange(a.lowerBound..<b.upperBound)
            }
        }
        if let dash = s.range(of: " - ") { s = String(s[..<dash.lowerBound]) }
        for d in decorations {
            if let r = s.range(of: d, options: .caseInsensitive) { s = String(s[..<r.lowerBound]) }
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// First credited artist: "A, B & C feat. D" → "A".
    static func primaryArtist(_ s: String) -> String {
        var s = s
        for sep in [",", " & ", " x ", " X "] + decorations {
            if let r = s.range(of: sep, options: .caseInsensitive) { s = String(s[..<r.lowerBound]) }
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// Search queries to try, most specific first, without duplicates.
    static func queries(for track: Track) -> [String] {
        let title = clean(track.title), artist = primaryArtist(track.artist)
        var seen = Set<String>()
        return ["\(title) \(artist)", "\(track.title) \(track.artist)", title].filter { seen.insert($0.lowercased()).inserted }
    }

    static func score(title: String, artists: [String], duration: TimeInterval?, against track: Track) -> Int {
        let a = normalize(title), b = normalize(track.title)
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        var score = a == b ? 4 : (a.contains(b) || b.contains(a) ? 2 : 0)
        guard score > 0 else { return 0 }
        let wanted = normalize(track.artist), primary = normalize(primaryArtist(track.artist))
        let names = artists.flatMap { [normalize($0), normalize(primaryArtist($0))] }.filter { !$0.isEmpty }
        if names.contains(where: { wanted.contains($0) || $0.contains(primary) }) { score += 3 }
        if let d = duration, d > 0, track.duration > 0 {
            let diff = abs(d - track.duration)
            score += diff < 3 ? 3 : (diff < 8 ? 1 : (diff < 20 ? -1 : -3))
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
        "Cookie": "os=pc; appver=2.10.13",
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
        var code: Int?
        var result: Result?
    }

    private struct LyricResponse: Decodable {
        struct Body: Decodable { var lyric: String? }
        var code: Int?
        var lrc: Body?
        var yrc: Body?
    }

    func lyrics(for track: Track) async throws -> Lyrics? {
        // Gather candidates across a few query variants, best match first.
        var candidates: [(id: Int, score: Int)] = []
        for query in TrackMatch.queries(for: track) {
            let url = HTTP.url("https://music.163.com/api/search/get", [("s", query), ("type", "1"), ("limit", "10")])
            guard let search: SearchResponse = try await HTTP.get(url, headers: headers, service: name) else { continue }
            if let code = search.code, code != 200 { throw LyricsLookupError(message: "\(name) refused (\(code))") }
            for song in search.result?.songs ?? [] where !candidates.contains(where: { $0.id == song.id }) {
                let score = TrackMatch.score(title: song.name, artists: song.artists?.map(\.name) ?? [],
                                             duration: song.duration.map { $0 / 1000 }, against: track)
                if score >= 5 { candidates.append((song.id, score)) }
            }
            if candidates.contains(where: { $0.score >= 9 }) { break }   // confident match; no need to search more
        }

        // Several versions of a song (single, album, deluxe) often exist; take the first with lyrics.
        for candidate in candidates.sorted(by: { $0.score > $1.score }).prefix(3) {
            let url = HTTP.url("https://music.163.com/api/song/lyric/v1", [
                ("id", String(candidate.id)), ("lv", "-1"), ("kv", "-1"), ("tv", "-1"), ("yv", "-1"),
            ])
            guard let body: LyricResponse = try await HTTP.get(url, headers: headers, service: name) else { continue }
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
        let title = TrackMatch.clean(track.title), artist = TrackMatch.primaryArtist(track.artist)
        var query = [("track_name", title), ("artist_name", artist)]
        if !track.album.isEmpty { query.append(("album_name", track.album)) }
        if track.duration > 0 { query.append(("duration", String(Int(track.duration.rounded())))) }

        var synced: String?
        var plain: String?
        if let exact: Record = try await HTTP.get(HTTP.url("https://lrclib.net/api/get", query), headers: headers, service: name) {
            synced = exact.syncedLyrics
            plain = exact.plainLyrics
        }
        if synced == nil {
            // Fuzzy: by fields, then free text.
            var results: [Record] = try await HTTP.get(
                HTTP.url("https://lrclib.net/api/search", [("track_name", title), ("artist_name", artist)]),
                headers: headers, service: name) ?? []
            if results.isEmpty {
                results = try await HTTP.get(HTTP.url("https://lrclib.net/api/search", [("q", "\(title) \(artist)")]),
                                             headers: headers, service: name) ?? []
            }
            let best = results
                .map { ($0, TrackMatch.score(title: $0.trackName ?? "", artists: [$0.artistName ?? ""], duration: $0.duration, against: track)) }
                .filter { $0.1 >= 5 }
                .sorted { a, b in (a.0.syncedLyrics != nil ? 1 : 0, a.1) > (b.0.syncedLyrics != nil ? 1 : 0, b.1) }
                .first?.0
            synced = best?.syncedLyrics
            if plain == nil { plain = best?.plainLyrics }
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
