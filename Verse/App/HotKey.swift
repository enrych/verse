import Carbon
import Foundation

/// A system-wide keyboard shortcut (no Accessibility permission needed).
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: @MainActor () -> Void

    /// - Parameters:
    ///   - keyCode: a virtual key code, e.g. `kVK_ANSI_L`.
    ///   - modifiers: Carbon modifier flags, e.g. `cmdKey | optionKey | controlKey`.
    init(keyCode: Int, modifiers: Int, action: @escaping @MainActor () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            Task { @MainActor in hotKey.action() }
            return noErr
        }, 1, &spec, me, &handlerRef)
        let id = EventHotKeyID(signature: OSType(0x5652_5345), id: 1)   // "VRSE"
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
