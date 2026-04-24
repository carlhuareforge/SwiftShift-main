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

        print("modifier flag normalization test passed")
    }
}
