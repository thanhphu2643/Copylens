import Carbon.HIToolbox

/// Global ⌘⇧T. Carbon hot keys need no Accessibility permission.
final class HotKey {
    private static var action: (() -> Void)?
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?

    init?(action: @escaping () -> Void) {
        HotKey.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            HotKey.action?()
            return noErr
        }, 1, &spec, nil, &handler)
        let registered = RegisterEventHotKey(
            UInt32(kVK_ANSI_T),
            UInt32(cmdKey | shiftKey),
            EventHotKeyID(signature: OSType(0x4350_4C4E), id: 1), // "CPLN"
            GetEventDispatcherTarget(),
            0,
            &reference
        )
        guard installed == noErr, registered == noErr else { return nil }
    }
}
