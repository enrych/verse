import AppKit
import Foundation

/// Checks GitHub Releases for a newer Verse at launch and every 6 hours.
@MainActor
final class UpdateChecker: ObservableObject {
    /// The newer version available, e.g. "0.3.0", or nil when up to date.
    @Published private(set) var available: String?

    static let downloadURL = URL(string: "https://verse-6gy.pages.dev/download")!
    private let api = URL(string: "https://api.github.com/repos/enrych/verse/releases/latest")!
    private var task: Task<Void, Never>?

    var current: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    func start() {
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.check()
                try? await Task.sleep(for: .seconds(6 * 60 * 60))
            }
        }
    }

    func check() async {
        var request = URLRequest(url: api, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Verse/\(current)", forHTTPHeaderField: "User-Agent")
        struct Release: Decodable { let tag_name: String; let draft: Bool?; let prerelease: Bool? }
        guard let result = try? await URLSession.shared.data(for: request),
              (result.1 as? HTTPURLResponse)?.statusCode == 200,
              let release = try? JSONDecoder().decode(Release.self, from: result.0),
              release.draft != true, release.prerelease != true else { return }
        let latest = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        available = Self.isNewer(latest, than: current) ? latest : nil
    }

    func openDownload() {
        NSWorkspace.shared.open(Self.downloadURL)
    }

    /// Numeric, dot-separated comparison: "0.10.0" > "0.9.2".
    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }
}
