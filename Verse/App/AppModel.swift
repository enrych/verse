import AppKit
import Combine
import SwiftUI

/// Wires playback, lyrics, colours and displays together.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let settings = Settings.shared
    let player = NowPlayingMonitor()
    let lock = LockMonitor()

    @Published private(set) var lyrics: Lyrics? {
        didSet { layout = lyrics.map(ConstellationLayout.init(lyrics:)) }
    }
    /// Precomputed star placement for the current lyrics.
    private(set) var layout: ConstellationLayout?
    @Published private(set) var status = "Waiting for music"
    @Published private(set) var artwork: NSImage?
    @Published private(set) var autoPalette: Palette?

    private let lyricsService = LyricsService()
    private let awake = ScreenAwake()
    private lazy var displays = DisplayController(model: self)
    private var lyricsTask: Task<Void, Never>?
    private var artworkTask: Task<Void, Never>?
    private var bag = Set<AnyCancellable>()

    var palette: Palette {
        if settings.starlight { return .starlight }
        return settings.autoColors ? (autoPalette ?? .default) : settings.manualPalette
    }

    /// Playback time used for rendering, including the user's sync offset.
    func playbackTime(at date: Date) -> TimeInterval {
        player.position(at: date) + settings.syncOffsetMs / 1000
    }

    func start() {
        player.start()

        player.$track
            .removeDuplicates()
            .sink { [weak self] in self?.trackChanged($0) }
            .store(in: &bag)

        Publishers.CombineLatest3(player.$isPlaying, settings.$keepAwake, lock.$isLocked)
            .sink { [weak self] playing, keepAwake, locked in
                self?.awake.set(on: playing && keepAwake, locked: locked && (self?.settings.lockScreenEnabled ?? false))
            }
            .store(in: &bag)

        // @Published fires before the value is stored; hop to the next runloop
        // turn so the controller reads the new values.
        Publishers.Merge4(
            lock.$isLocked.map { _ in () },
            settings.$lockScreenEnabled.map { _ in () },
            settings.$stageDisplayID.map { _ in () },
            NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification).map { _ in () }
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] in self?.displays.update(locked: self?.lock.isLocked ?? false) }
        .store(in: &bag)
    }

    private func trackChanged(_ track: Track?) {
        lyricsTask?.cancel()
        artworkTask?.cancel()
        lyrics = nil
        artwork = nil
        autoPalette = nil
        guard let track else { status = "Nothing playing"; return }

        status = "Finding lyrics…"
        lyricsTask = Task { [weak self] in
            guard let self else { return }
            let found = await lyricsService.lyrics(for: track)
            guard !Task.isCancelled, player.track == track else { return }
            lyrics = found
            status = found.map { "\($0.source) · \($0.timing == .word ? "word sync" : "line sync")" } ?? "No synced lyrics found"
        }
        artworkTask = Task { [weak self] in
            guard let self else { return }
            let image = await player.artwork(for: track)
            guard !Task.isCancelled, player.track == track else { return }
            artwork = image
            autoPalette = image.flatMap(PaletteExtractor.palette(from:))
        }
    }
}
