import AppKit

/// Raw state read from a player via AppleScript.
struct PlayerSnapshot: Sendable {
    var player: Player
    var isPlaying: Bool
    var title: String
    var artist: String
    var album: String
    var durationMs: Double
    var positionMs: Double
    var artworkURL: String?
}

enum ScriptError: Error, Sendable {
    /// The user hasn't allowed Verse to control this app (System Settings → Privacy & Security → Automation).
    case notPermitted
    case failed(String)
}

/// Compiles and runs player scripts. Only ever used from one serial queue.
final class PlayerScripts: @unchecked Sendable {
    private var compiled: [String: NSAppleScript] = [:]

    // Times are converted to whole milliseconds inside AppleScript so the
    // result never depends on the user's locale decimal separator.
    private static let spotify = """
    tell application "Spotify"
        if player state is stopped then return "stopped"
        set t to current track
        set pos to (round ((player position) * 1000)) as integer
        return (player state as string) & tab & (name of t) & tab & (artist of t) & tab & (album of t) & tab & ((duration of t) as integer as string) & tab & (pos as string) & tab & (artwork url of t)
    end tell
    """

    private static let music = """
    tell application "Music"
        if player state is stopped then return "stopped"
        set t to current track
        set dur to (round ((duration of t) * 1000)) as integer
        set pos to (round ((player position) * 1000)) as integer
        return (player state as string) & tab & (name of t) & tab & (artist of t) & tab & (album of t) & tab & (dur as string) & tab & (pos as string)
    end tell
    """

    private static let musicArtwork = """
    tell application "Music" to get raw data of artwork 1 of current track
    """

    func snapshot(for player: Player) -> Result<PlayerSnapshot?, ScriptError> {
        let source = player == .spotify ? Self.spotify : Self.music
        switch run(source) {
        case .failure(let error):
            return .failure(error)
        case .success(let descriptor):
            guard let text = descriptor.stringValue, text != "stopped" else { return .success(nil) }
            let f = text.components(separatedBy: "\t")
            guard f.count >= 6 else { return .success(nil) }
            return .success(PlayerSnapshot(
                player: player,
                isPlaying: f[0] == "playing",
                title: f[1], artist: f[2], album: f[3],
                durationMs: Double(f[4]) ?? 0,
                positionMs: Double(f[5]) ?? 0,
                artworkURL: f.count > 6 && !f[6].isEmpty ? f[6] : nil
            ))
        }
    }

    func musicArtworkData() -> Data? {
        guard case .success(let descriptor) = run(Self.musicArtwork) else { return nil }
        let data = descriptor.data
        return data.isEmpty ? nil : data
    }

    private func run(_ source: String) -> Result<NSAppleEventDescriptor, ScriptError> {
        let script: NSAppleScript
        if let cached = compiled[source] {
            script = cached
        } else {
            script = NSAppleScript(source: source)!
            compiled[source] = script
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            return .failure(code == -1743 ? .notPermitted : .failed(error.description))
        }
        return .success(result)
    }
}
