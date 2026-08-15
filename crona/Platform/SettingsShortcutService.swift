import AppKit
import Carbon.HIToolbox

struct SettingsShortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let display: String

    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbonModifiers: UInt32 = 0
        var prefix = ""
        if flags.contains(.control) { carbonModifiers |= UInt32(controlKey); prefix += "⌃" }
        if flags.contains(.option) { carbonModifiers |= UInt32(optionKey); prefix += "⌥" }
        if flags.contains(.shift) { carbonModifiers |= UInt32(shiftKey); prefix += "⇧" }
        if flags.contains(.command) { carbonModifiers |= UInt32(cmdKey); prefix += "⌘" }
        guard carbonModifiers != 0,
              let character = event.charactersIgnoringModifiers?.uppercased(),
              !character.isEmpty
        else { return nil }
        keyCode = UInt32(event.keyCode)
        modifiers = carbonModifiers
        display = prefix + character
    }
}

@MainActor
final class SettingsShortcutService {
    private weak var appState: CompanionAppState?
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    func configure(appState: CompanionAppState) {
        self.appState = appState
        installEventHandlerIfNeeded()
        update(shortcut: appState.preferences.preferences.settingsShortcut)
    }

    func update(shortcut: SettingsShortcut?) {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        guard let shortcut else { return }

        let identifier = EventHotKeyID(signature: OSType(0x43524F4E), id: 1)
        var registered: EventHotKeyRef?
        let result = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            identifier,
            GetEventDispatcherTarget(),
            0,
            &registered
        )
        if result == noErr {
            hotKey = registered
        }
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let service = Unmanaged<SettingsShortcutService>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in service.appState?.openSettings() }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    isolated deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}
