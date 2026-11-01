import AppKit
import Combine

/// Tracks whether the Mac's screen is locked.
@MainActor
final class LockMonitor: ObservableObject {
    @Published private(set) var isLocked = LockMonitor.queryLocked()
    private var tokens: [NSObjectProtocol] = []

    init() {
        let center = DistributedNotificationCenter.default()
        tokens.append(center.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.isLocked = true }
        })
        tokens.append(center.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.isLocked = false }
        })
    }

    nonisolated static func queryLocked() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return session["CGSSessionScreenIsLocked"] as? Bool ?? false
    }
}
