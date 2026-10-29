import Cocoa

@main
struct ModifierFlagNormalizationTest {
    static func main() {
        let control = NSEvent.ModifierFlags.control
        let controlWithCapsLock = NSEvent.ModifierFlags([.control, .capsLock])
        let commandWithCapsLock = NSEvent.ModifierFlags([.command, .capsLock])

        assert(
            normalizeShortcutModifierFlags(control) == control,
            "Normalization should leave a plain modifier shortcut unchanged"
        )
        assert(
            normalizeShortcutModifierFlags(controlWithCapsLock) == control,
            "Caps Lock should not break a control-based shortcut"
        )
        assert(
            normalizeShortcutModifierFlags(commandWithCapsLock) == .command,
            "Caps Lock should be ignored for other modifier shortcuts too"
        )

        assert(
            !shouldArmModifierMouseMonitor(currentFlags: [], shortcutModifierFlags: [control]),
            "Ordinary mouse use must not arm shortcut interception"
        )
        assert(
            shouldArmModifierMouseMonitor(currentFlags: controlWithCapsLock, shortcutModifierFlags: [control]),
            "Control-click must still arm the shortcut with Caps Lock on"
        )
        assert(
            !shouldArmModifierMouseMonitor(currentFlags: .command, shortcutModifierFlags: [control]),
            "An unrelated modifier must not intercept mouse clicks"
        )
        assert(
            !shouldArmModifierMouseMonitor(currentFlags: [.control, .shift], shortcutModifierFlags: [control]),
            "An extra modifier must leave ordinary app shortcuts alone"
        )

        print("modifier flag normalization test passed")
    }
}
