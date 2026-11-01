import AppKit
import Carbon
import Combine
import SwiftUI

/// Wires playback, lyrics, colours and displays together.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let settings = Settings.shared
    let player = NowPlayingMonitor()
    let lock = LockMonitor()
    let updates = UpdateChecker()
    let launchAtLogin = LaunchAtLogin()
    private var stageHotKey: HotKey?

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

    /// Playback time used for rendering, including the global and per-song sync offsets.
    func playbackTime(at date: Date) -> TimeInterval {
        player.position(at: date) + (settings.syncOffsetMs + songOffsetMs) / 1000
    }

    /// Extra offset for the current song only (ms).
    var songOffsetMs: Double {
        get { player.track.map { settings.songOffsets[$0.cacheKey] ?? 0 } ?? 0 }
        set {
            guard let key = player.track?.cacheKey else { return }
            settings.songOffsets[key] = newValue == 0 ? nil : newValue
        }
    }

    /// ⌃⌥⌘L: show or hide the full-screen stage on the display under the pointer.
    func toggleStage() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let id = screen?.displayID else { return }
        settings.stageDisplayID = settings.stageDisplayID == id ? nil : id
    }

    func start() {
        player.start()
        updates.start()
        launchAtLogin.refresh()
        stageHotKey = HotKey(keyCode: kVK_ANSI_L, modifiers: cmdKey | optionKey | controlKey) { [weak self] in
            self?.toggleStage()
        }

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

    /// True when the last lookup for this song came back empty.
    @Published private(set) var lyricsMissing = false

    /// Ask the providers again for the current song (menu: Retry).
    func retryLyrics() {
        guard let track = player.track else { return }
        lyricsService.forget(track)
        loadLyrics(for: track)
    }

    private func loadLyrics(for track: Track, attempt: Int = 0) {
        lyricsTask?.cancel()
        lyricsMissing = false
        status = "Finding lyrics…"
        lyricsTask = Task { [weak self] in
            guard let self else { return }
            let result = await lyricsService.lyrics(for: track)
            guard !Task.isCancelled, player.track == track else { return }
            lyrics = result.lyrics
            lyricsMissing = result.lyrics == nil
            if let lyrics = result.lyrics {
                switch lyrics.timing {
                case .word: status = "\(lyrics.source) · word sync"
                case .line: status = "\(lyrics.source) · line sync"
                case .estimated: status = "\(lyrics.source) · plain lyrics, timing estimated"
                }
            } else {
                status = result.problem.map { "No lyrics yet · \($0)" } ?? "No lyrics found for this song"
                // A service was down or busy: try again once by ourselves.
                if result.problem != nil, attempt == 0 {
                    try? await Task.sleep(for: .seconds(20))
                    guard !Task.isCancelled, player.track == track, lyrics == nil else { return }
                    loadLyrics(for: track, attempt: 1)
                }
            }
        }
    }

    private func trackChanged(_ track: Track?) {
        lyricsTask?.cancel()
        artworkTask?.cancel()
        lyrics = nil
        artwork = nil
        autoPalette = nil
        guard let track else { status = "Nothing playing"; lyricsMissing = false; return }

        loadLyrics(for: track)
        artworkTask = Task { [weak self] in
            guard let self else { return }
            let image = await player.artwork(for: track)
            guard !Task.isCancelled, player.track == track else { return }
            artwork = image
            autoPalette = image.flatMap(PaletteExtractor.palette(from:))
        }
    }
}
