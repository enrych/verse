import ServiceManagement

/// Wraps SMAppService so the menu can show and change "Open at login".
@MainActor
final class LaunchAtLogin: ObservableObject {
    @Published private(set) var enabled = SMAppService.mainApp.status == .enabled
    @Published private(set) var error: String?

    func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            error = nil
        } catch {
            self.error = "Couldn't change this. Move Verse to Applications and try again."
        }
        enabled = SMAppService.mainApp.status == .enabled
    }

    func refresh() {
        enabled = SMAppService.mainApp.status == .enabled
    }
}
