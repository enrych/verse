import CryptoKit
import Foundation

/// Tries providers in order, preferring real word timings, and caches results on disk.
///
/// Only real answers are remembered: lyrics forever (on disk), "no lyrics anywhere"
/// for 30 minutes. Network errors and busy servers are never cached, so the next
/// attempt (or Retry) asks again.
@MainActor
final class LyricsService {
    struct Result {
        var lyrics: Lyrics?
        /// Why nothing was found, when a provider failed, e.g. "LRCLIB busy".
        var problem: String?
    }

    private let providers: [LyricsProvider] = [NetEaseProvider(), LRCLIBProvider()]
    private var found: [String: Lyrics] = [:]
    private var missedAt: [String: Date] = [:]
    private let missMemory: TimeInterval = 30 * 60

    private lazy var cacheDirectory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("com.enrych.verse/lyrics", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    func lyrics(for track: Track) async -> Result {
        let key = track.cacheKey
        if let hit = found[key] { return Result(lyrics: hit) }
        if let missed = missedAt[key], Date().timeIntervalSince(missed) < missMemory { return Result(lyrics: nil) }

        let file = cacheFile(for: track)
        if let data = try? Data(contentsOf: file), let cached = try? JSONDecoder().decode(Lyrics.self, from: data) {
            found[key] = cached
            return Result(lyrics: cached)
        }

        var best: Lyrics?
        var problems: [String] = []
        for provider in providers {
            guard !Task.isCancelled else { return Result(lyrics: nil) }
            do {
                guard let lyrics = try await provider.lyrics(for: track) else { continue }
                if lyrics.timing == .word { best = lyrics; break }
                if best == nil || (best?.timing == .estimated && lyrics.timing == .line) { best = lyrics }
            } catch let error as LyricsLookupError {
                problems.append(error.message)
            } catch {
                problems.append("\(provider.name) unreachable")
            }
        }
        guard !Task.isCancelled else { return Result(lyrics: nil) }

        if let best {
            found[key] = best
            if let data = try? JSONEncoder().encode(best) { try? data.write(to: file, options: .atomic) }
            return Result(lyrics: best)
        }
        // Remember a miss only when every provider answered cleanly.
        if problems.isEmpty { missedAt[key] = Date() }
        return Result(lyrics: nil, problem: problems.isEmpty ? nil : problems.joined(separator: ", "))
    }

    /// Forget a remembered miss so the next lookup asks the providers again.
    func forget(_ track: Track) {
        missedAt[track.cacheKey] = nil
    }

    private func cacheFile(for track: Track) -> URL {
        let digest = SHA256.hash(data: Data(track.cacheKey.utf8)).map { String(format: "%02x", $0) }.joined()
        return cacheDirectory.appendingPathComponent(String(digest.prefix(32)) + ".json")
    }
}
