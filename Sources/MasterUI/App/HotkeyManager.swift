import AppKit
import Carbon

// MARK: - HotkeyManager

/// Manages global keyboard shortcuts using Carbon Hot Key API.
/// Default shortcut: Cmd+Shift+Space to toggle the floating panel.
class HotkeyManager {
    private weak var panelController: FloatingPanelController?
    private var hotKeyRef: EventHotKeyRef?
    private static var shared: HotkeyManager?

    init(panelController: FloatingPanelController) {
        self.panelController = panelController
        HotkeyManager.shared = self
    }

    deinit {
        unregister()
    }

    func register() {
        // Register Cmd+Shift+Space
        let hotKeyID = EventHotKeyID(signature: OSType(0x4D55_4149), // "MUAI"
                                      id: 1)

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                       eventKind: UInt32(kEventHotKeyPressed))

        // Install handler
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, _) -> OSStatus in
                HotkeyManager.shared?.panelController?.togglePanel()
                return noErr
            },
            1,
            &eventType,
            nil,
            nil
        )

        // Register the hot key: Cmd+Shift+Space
        // Space = keycode 49
        let modifiers: UInt32 = UInt32(cmdKey | shiftKey)
        RegisterEventHotKey(
            UInt32(kVK_Space),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }
}
