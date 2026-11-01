import Foundation

enum Player: String, CaseIterable, Codable {
    case spotify, music

    var bundleID: String {
        switch self {
        case .spotify: "com.spotify.client"
        case .music: "com.apple.Music"
        }
    }

    var displayName: String {
        switch self {
        case .spotify: "Spotify"
        case .music: "Apple Music"
        }
    }
}

struct Track: Equatable {
    var player: Player
    var title: String
    var artist: String
    var album: String
    /// Seconds.
    var duration: TimeInterval
    var artworkURL: URL?

    var cacheKey: String {
        "\(title.lowercased())|\(artist.lowercased())|\(Int(duration.rounded()))"
    }
}
