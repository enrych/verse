import AppKit
import SkyLightWindow
import SwiftUI

/// Owns the lock-screen layer (one per screen) and the full-screen stage window.
@MainActor
final class DisplayController {
    private unowned let model: AppModel
    private var lockWindows: [NSWindowController] = []
    private var stageWindow: StageWindow?
    private var glowWindows: [CGDirectDisplayID: GlowWindow] = [:]

    init(model: AppModel) {
        self.model = model
    }

    func update(locked: Bool) {
        let settings = model.settings

        // The lock layer carries lyrics, the glow, or both.
        if locked && (settings.lockScreenEnabled || settings.glowEnabled) { showLockLayer() } else { hideLockLayer() }

        if let id = settings.stageDisplayID, let screen = NSScreen.screens.first(where: { $0.displayID == id }) {
            showStage(on: screen)
        } else {
            hideStage()
        }

        // Desktop glow (the lock-screen layer draws its own).
        let wantGlow = settings.glowEnabled && !locked && (model.player.isPlaying || settings.glowAlways)
        let glowScreens = NSScreen.screens.filter { settings.glowDisplayID == nil || $0.displayID == settings.glowDisplayID }
        updateGlow(on: wantGlow ? glowScreens : [])
    }

    // MARK: Edge glow

    private func updateGlow(on screens: [NSScreen]) {
        let wanted = Set(screens.map(\.displayID))
        for (id, window) in glowWindows where !wanted.contains(id) {
            window.orderOut(nil)
            glowWindows[id] = nil
        }
        for screen in screens {
            if let existing = glowWindows[screen.displayID] {
                existing.setFrame(screen.frame, display: true)
                continue
            }
            let window = GlowWindow(screen: screen)
            window.contentView = NSHostingView(rootView: GlowOverlay(notch: screen.notchRect))
            window.orderFrontRegardless()
            glowWindows[screen.displayID] = window
        }
    }

    // MARK: Lock screen

    private func showLockLayer() {
        guard lockWindows.isEmpty else { return }
        for screen in NSScreen.screens {
            // SkyLightWindow moves the window into a SkyLight space that sits
            // above the lock screen.
            let controller = SkyLightOperator.shared.delegateView(AnyView(StageView(surface: .lockScreen)), toScreen: screen)
            controller.window?.ignoresMouseEvents = true
            lockWindows.append(controller)
        }
    }

    private func hideLockLayer() {
        for controller in lockWindows {
            controller.window?.orderOut(nil)
            controller.close()
        }
        lockWindows.removeAll()
    }

    // MARK: Stage

    private func showStage(on screen: NSScreen) {
        if let stageWindow, stageWindow.screen == screen { return }
        hideStage()
        let window = StageWindow(screen: screen) { [weak self] in
            self?.model.settings.stageDisplayID = nil
        }
        window.contentView = NSHostingView(rootView: StageView(surface: .stage))
        window.makeKeyAndOrderFront(nil)
        stageWindow = window
    }

    private func hideStage() {
        stageWindow?.orderOut(nil)
        stageWindow = nil
    }
}

/// Borderless window covering a whole display. Esc closes it.
final class StageWindow: NSWindow {
    private let onClose: () -> Void

    init(screen: NSScreen, onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        isReleasedWhenClosed = false
        backgroundColor = .black
        collectionBehavior = [.fullScreenAuxiliary, .stationary]
        // Cover the menu bar when the stage is on the main display.
        level = screen == NSScreen.screens.first ? NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1) : .normal
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onClose() } else { super.keyDown(with: event) }
    }
}
