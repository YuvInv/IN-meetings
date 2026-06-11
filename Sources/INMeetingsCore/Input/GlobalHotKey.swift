import Carbon

/// A single system-wide hotkey via Carbon `RegisterEventHotKey`.
///
/// Fires even when another app is focused and needs **no Accessibility permission**: it registers one
/// specific chord with the OS and cannot observe any other input, which is why it is exempt from the
/// keystroke-monitoring TCC gate (a global `NSEvent` monitor would not be). Default chord ⌃⌥⌘R
/// ("R" = Record). See DECISIONS.md (2026-06-11 — global hotkey mechanism).
public final class GlobalHotKey {
    /// Default Start/Stop chord: Control-Option-Command-R.
    public static let defaultKeyCode = UInt32(kVK_ANSI_R)
    public static let defaultModifiers = UInt32(controlKey | optionKey | cmdKey)

    private let id: UInt32
    private var ref: EventHotKeyRef?

    private static let signature: OSType = 0x494E_4D54   // 'INMT'
    private static var nextID: UInt32 = 1
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var installedHandler: EventHandlerRef?

    /// Registers the chord. `onPress` is invoked on the main thread each time it's pressed.
    public init(keyCode: UInt32 = GlobalHotKey.defaultKeyCode,
                modifiers: UInt32 = GlobalHotKey.defaultModifiers,
                onPress: @escaping () -> Void) {
        id = GlobalHotKey.nextID
        GlobalHotKey.nextID += 1
        GlobalHotKey.handlers[id] = onPress
        GlobalHotKey.installDispatcherIfNeeded()

        var newRef: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: GlobalHotKey.signature, id: id)
        if RegisterEventHotKey(keyCode, modifiers, hkID, GetApplicationEventTarget(), 0, &newRef) == noErr {
            ref = newRef
        }
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        GlobalHotKey.handlers[id] = nil
    }

    /// Install one process-wide Carbon event handler that routes hot-key presses to the right closure
    /// by hot-key id. The closure captures nothing (it reads only static state), so it converts to the
    /// C function pointer `InstallEventHandler` requires.
    private static func installDispatcherIfNeeded() {
        guard installedHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var hkID = EventHotKeyID()
            let err = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                        EventParamType(typeEventHotKeyID), nil,
                                        MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            if err == noErr { GlobalHotKey.handlers[hkID.id]?() }
            return noErr
        }, 1, &spec, nil, &installedHandler)
    }
}
