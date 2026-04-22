import Foundation

@main
struct DockClickBehaviorTest {
    static func main() {
        assert(
            DockClickBehavior.outcome(
                for: .init(
                    isFrontmost: true,
                    isHidden: false,
                    hasWindows: true,
                    hasVisibleWindows: true,
                    hasMinimizedWindows: false
                )
            ) == .hide,
            "Frontmost visible apps with windows should hide on dock click"
        )

        assert(
            DockClickBehavior.outcome(
                for: .init(
                    isFrontmost: false,
                    isHidden: false,
                    hasWindows: true,
                    hasVisibleWindows: true,
                    hasMinimizedWindows: false
                )
            ) == .passthrough,
            "Background apps should keep native dock activation behavior"
        )

        assert(
            DockClickBehavior.outcome(
                for: .init(
                    isFrontmost: false,
                    isHidden: true,
                    hasWindows: true,
                    hasVisibleWindows: false,
                    hasMinimizedWindows: false
                )
            ) == .restore,
            "Hidden apps should restore on dock click"
        )

        assert(
            DockClickBehavior.outcome(
                for: .init(
                    isFrontmost: true,
                    isHidden: false,
                    hasWindows: true,
                    hasVisibleWindows: true,
                    hasMinimizedWindows: true
                )
            ) == .hide,
            "Frontmost apps with at least one visible window should still hide on dock click"
        )

        assert(
            DockClickBehavior.outcome(
                for: .init(
                    isFrontmost: false,
                    isHidden: false,
                    hasWindows: true,
                    hasVisibleWindows: true,
                    hasMinimizedWindows: true
                )
            ) == .passthrough,
            "Background apps with visible windows should keep native dock activation even if some windows are minimized"
        )

        assert(
            DockClickBehavior.outcome(
                for: .init(
                    isFrontmost: false,
                    isHidden: false,
                    hasWindows: true,
                    hasVisibleWindows: false,
                    hasMinimizedWindows: true
                )
            ) == .restore,
            "Apps whose windows are all minimized should restore on dock click"
        )

        assert(
            DockClickBehavior.outcome(
                for: .init(
                    isFrontmost: true,
                    isHidden: false,
                    hasWindows: false,
                    hasVisibleWindows: false,
                    hasMinimizedWindows: false
                )
            ) == .passthrough,
            "Apps without windows should keep native dock behavior"
        )

        assert(
            DockClickGesture.shouldTriggerAction(
                movementDistance: 2,
                duration: 0.12
            ),
            "Short presses with tiny pointer movement should count as clicks"
        )

        assert(
            !DockClickGesture.shouldTriggerAction(
                movementDistance: 18,
                duration: 0.12
            ),
            "Dragging a dock icon should not trigger the toggle action"
        )

        assert(
            !DockClickGesture.shouldTriggerAction(
                movementDistance: 2,
                duration: 0.6
            ),
            "Long press interactions should not trigger the toggle action"
        )

        print("dock click behavior test passed")
    }
}
