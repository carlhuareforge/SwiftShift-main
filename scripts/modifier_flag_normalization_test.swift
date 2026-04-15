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
            shouldArmModifierMouseMonitor(currentFlags: .control, shortcutModifierFlags: [.control]),
            "A matching modifier should arm the mouse monitor"
        )
        assert(
            shouldArmModifierMouseMonitor(currentFlags: [.control, .capsLock], shortcutModifierFlags: [.control]),
            "Caps Lock should not prevent the mouse monitor from arming"
        )
        assert(
            !shouldArmModifierMouseMonitor(currentFlags: .shift, shortcutModifierFlags: [.control]),
            "A different modifier should not arm the mouse monitor"
        )
        assert(
            !shouldArmModifierMouseMonitor(currentFlags: [], shortcutModifierFlags: [.control]),
            "No modifiers held should leave the mouse monitor disarmed"
        )

        print("modifier flag normalization test passed")
    }
}
