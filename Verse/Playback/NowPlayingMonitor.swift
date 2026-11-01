import AppKit
import Combine

/// Polls Spotify / Music twice a second and turns the samples into a smooth
/// clock that views can read at 60/120 fps.
@MainActor
final class NowPlayingMonitor: ObservableObject {
    @Published private(set) var track: Track?
    @Published private(set) var isPlaying = false
    @Published private(set) var permissionDenied: Player?

    private var anchorPosition: TimeInterval = 0
    private var anchorDate = Date()

    private let scripts = PlayerScripts()
    private let queue = DispatchQueue(label: "com.enrych.verse.applescript", qos: .userInitiated)
    private var pollTask: Task<Void, Never>?

    func start() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    /// Estimated playback position (seconds) at `date`.
    func position(at date: Date) -> TimeInterval {
        guard isPlaying else { return anchorPosition }
        return anchorPosition + date.timeIntervalSince(anchorDate)
    }

    func artwork(for track: Track) async -> NSImage? {
        switch track.player {
        case .spotify:
            guard let url = track.artworkURL,
                  let result = try? await URLSession.shared.data(from: url) else { return nil }
            return NSImage(data: result.0)
        case .music:
            let scripts = self.scripts
            let data: Data? = await withCheckedContinuation { cont in
                queue.async { cont.resume(returning: scripts.musicArtworkData()) }
            }
            return data.flatMap(NSImage.init(data:))
        }
    }

    private func poll() async {
        let running = Player.allCases.filter {
            !NSRunningApplication.runningApplications(withBundleIdentifier: $0.bundleID).isEmpty
        }
        let scripts = self.scripts
        let results: [(Player, Result<PlayerSnapshot?, ScriptError>)] = await withCheckedContinuation { cont in
            queue.async { cont.resume(returning: running.map { ($0, scripts.snapshot(for: $0)) }) }
        }
        apply(results, sampledAt: Date())
    }

    private func apply(_ results: [(Player, Result<PlayerSnapshot?, ScriptError>)], sampledAt: Date) {
        var snapshots: [PlayerSnapshot] = []
        var denied: Player?
        for (player, result) in results {
            switch result {
            case .success(let s?): snapshots.append(s)
            case .success(nil): break
            case .failure(.notPermitted): denied = player
            case .failure: break
            }
        }
        permissionDenied = denied

        guard let s = snapshots.first(where: \.isPlaying) ?? snapshots.first else {
            if track != nil { track = nil }
            isPlaying = false
            return
        }

        let newTrack = Track(
            player: s.player, title: s.title, artist: s.artist, album: s.album,
            duration: s.durationMs / 1000, artworkURL: s.artworkURL.flatMap(URL.init(string:))
        )
        let changed = newTrack != track
        if changed { track = newTrack }

        let measured = s.positionMs / 1000
        let predicted = position(at: sampledAt)
        let wasPlaying = isPlaying
        isPlaying = s.isPlaying

        if changed || !s.isPlaying || !wasPlaying || abs(predicted - measured) > 0.35 {
            // Seek, pause, or new song: jump.
            anchorPosition = measured
            anchorDate = sampledAt
        } else {
            // Small drift: ease toward the measurement so words never stutter.
            anchorPosition += (measured - predicted) * 0.25
        }
    }
}
