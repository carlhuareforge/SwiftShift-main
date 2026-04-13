import AppKit

let MAIN_WINDOW_WIDTH = 320.0

func normalizeShortcutModifierFlags(_ flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
    flags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock)
}
