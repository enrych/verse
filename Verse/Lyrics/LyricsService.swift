import CryptoKit
import Foundation

/// Tries providers in order, preferring real word timings, and caches results on disk.
@MainActor
final class LyricsService {
    private let providers: [LyricsProvider] = [NetEaseProvider(), LRCLIBProvider()]
    private var memory: [String: Lyrics?] = [:]

    private lazy var cacheDirectory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("com.enrych.verse/lyrics", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    func lyrics(for track: Track) async -> Lyrics? {
        if let hit = memory[track.cacheKey] { return hit }

        let file = cacheFile(for: track)
        if let data = try? Data(contentsOf: file), let cached = try? JSONDecoder().decode(Lyrics.self, from: data) {
            memory[track.cacheKey] = cached
            return cached
        }

        var fallback: Lyrics?
        for provider in providers {
            guard !Task.isCancelled else { return nil }
            guard let found = try? await provider.lyrics(for: track) else { continue }
            if found.timing == .word { fallback = found; break }
            if fallback == nil { fallback = found }
        }

        memory[track.cacheKey] = fallback
        if let fallback, let data = try? JSONEncoder().encode(fallback) {
            try? data.write(to: file, options: .atomic)
        }
        return fallback
    }

    private func cacheFile(for track: Track) -> URL {
        let digest = SHA256.hash(data: Data(track.cacheKey.utf8)).map { String(format: "%02x", $0) }.joined()
        return cacheDirectory.appendingPathComponent(String(digest.prefix(32)) + ".json")
    }
}
