import AppKit

let MAIN_WINDOW_WIDTH = 320.0

func normalizeShortcutModifierFlags(_ flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
    flags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock)
}

func shouldArmModifierMouseMonitor(currentFlags: NSEvent.ModifierFlags, shortcutModifierFlags: [NSEvent.ModifierFlags]) -> Bool {
    let normalizedCurrentFlags = normalizeShortcutModifierFlags(currentFlags)
    guard !normalizedCurrentFlags.isEmpty else { return false }
    return shortcutModifierFlags.contains {
        normalizeShortcutModifierFlags($0) == normalizedCurrentFlags
    }
}

func currentGlobalModifierFlags() -> NSEvent.ModifierFlags {
    normalizeShortcutModifierFlags(
        NSEvent.ModifierFlags(rawValue: UInt(CGEventSource.flagsState(.combinedSessionState).rawValue))
    )
}
