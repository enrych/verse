import AppKit
import SwiftUI

enum LyricStyle: String, CaseIterable, Identifiable {
    /// Words land as stars joined in sung order.
    case constellation
    /// One big line at a time; each word lights up as it's sung.
    case focus

    var id: String { rawValue }
    var title: String {
        switch self {
        case .constellation: "Constellation"
        case .focus: "Focus"
        }
    }
}

enum LockBackground: String, CaseIterable, Identifiable {
    /// Near-black with faint dust stars and grain (default).
    case night
    /// Plain black.
    case black
    /// The current song's cover, blurred and dimmed.
    case album
    /// The user's own wallpaper, darkened (lock screen only).
    case wallpaper

    var id: String { rawValue }
    var title: String {
        switch self {
        case .night: "Night"
        case .black: "Black"
        case .album: "Album art"
        case .wallpaper: "Wallpaper"
        }
    }
}

/// User preferences, persisted to UserDefaults.
@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()
    private let defaults: UserDefaults

    @Published var style: LyricStyle { didSet { defaults.set(style.rawValue, forKey: "style") } }
    /// Extra sync offset per song (ms), keyed by Track.cacheKey.
    @Published var songOffsets: [String: Double] { didSet { defaults.set(songOffsets, forKey: "songOffsets") } }
    @Published var lockScreenEnabled: Bool { didSet { defaults.set(lockScreenEnabled, forKey: "lockScreenEnabled") } }
    /// Warm starlight colours instead of the album/manual palette.
    @Published var starlight: Bool { didSet { defaults.set(starlight, forKey: "starlight") } }
    @Published var lockBackground: LockBackground { didSet { defaults.set(lockBackground.rawValue, forKey: "lockBackground") } }
    /// Display that shows the full-screen stage while unlocked. nil = off.
    @Published var stageDisplayID: CGDirectDisplayID? {
        didSet { defaults.set(stageDisplayID.map { Int($0) }, forKey: "stageDisplayID") }
    }
    @Published var autoColors: Bool { didSet { defaults.set(autoColors, forKey: "autoColors") } }
    @Published var lyricColor: Color { didSet { defaults.set(lyricColor.hex, forKey: "lyricColor") } }
    @Published var highlightColor: Color { didSet { defaults.set(highlightColor.hex, forKey: "highlightColor") } }
    @Published var secondaryColor: Color { didSet { defaults.set(secondaryColor.hex, forKey: "secondaryColor") } }
    /// Multiplier on the base text size.
    @Published var textScale: Double { didSet { defaults.set(textScale, forKey: "textScale") } }
    /// Shifts lyrics earlier (+) or later (−), in milliseconds.
    @Published var syncOffsetMs: Double { didSet { defaults.set(syncOffsetMs, forKey: "syncOffsetMs") } }
    @Published var keepAwake: Bool { didSet { defaults.set(keepAwake, forKey: "keepAwake") } }

    private init() {
        let defaults = UserDefaults.standard
        self.defaults = defaults
        defaults.register(defaults: [
            "style": LyricStyle.constellation.rawValue,
            "starlight": true,
            "lockBackground": LockBackground.night.rawValue,
            "lockScreenEnabled": true,
            "autoColors": true,
            "lyricColor": "#FFFFFF",
            "highlightColor": "#FFD36E",
            "secondaryColor": "#FFFFFF59",
            "textScale": 1.0,
            "syncOffsetMs": 150.0,
            "keepAwake": true,
        ])
        style = LyricStyle(rawValue: defaults.string(forKey: "style") ?? "") ?? .constellation
        songOffsets = defaults.dictionary(forKey: "songOffsets") as? [String: Double] ?? [:]
        starlight = defaults.bool(forKey: "starlight")
        lockScreenEnabled = defaults.bool(forKey: "lockScreenEnabled")
        lockBackground = LockBackground(rawValue: defaults.string(forKey: "lockBackground") ?? "") ?? .night
        stageDisplayID = (defaults.object(forKey: "stageDisplayID") as? Int).map { CGDirectDisplayID($0) }
        autoColors = defaults.bool(forKey: "autoColors")
        lyricColor = Color(hex: defaults.string(forKey: "lyricColor")) ?? .white
        highlightColor = Color(hex: defaults.string(forKey: "highlightColor")) ?? .yellow
        secondaryColor = Color(hex: defaults.string(forKey: "secondaryColor")) ?? .white.opacity(0.35)
        textScale = defaults.double(forKey: "textScale")
        syncOffsetMs = defaults.double(forKey: "syncOffsetMs")
        keepAwake = defaults.bool(forKey: "keepAwake")
    }

    var manualPalette: Palette {
        Palette(lyric: lyricColor, highlight: highlightColor, secondary: secondaryColor, background: .black)
    }
}

extension Color {
    init?(hex: String?) {
        guard var s = hex?.trimmingCharacters(in: .whitespaces), s.hasPrefix("#") else { return nil }
        s.removeFirst()
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        let rgba = s.count == 6 ? (v << 8 | 0xFF) : v
        self = Color(.sRGB,
                     red: Double((rgba >> 24) & 0xFF) / 255,
                     green: Double((rgba >> 16) & 0xFF) / 255,
                     blue: Double((rgba >> 8) & 0xFF) / 255,
                     opacity: Double(rgba & 0xFF) / 255)
    }

    var hex: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .white
        let parts = [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent]
        return "#" + parts.map { String(format: "%02X", Int(($0 * 255).rounded())) }.joined()
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
