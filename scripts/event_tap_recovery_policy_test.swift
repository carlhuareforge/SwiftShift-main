import CoreGraphics

@main
struct EventTapRecoveryPolicyTest {
    static func main() {
        assert(
            EventTapRecoveryPolicy.shouldReenableTap(for: .tapDisabledByTimeout),
            "Timeout-disabled event taps should be re-enabled"
        )
        assert(
            EventTapRecoveryPolicy.shouldReenableTap(for: .tapDisabledByUserInput),
            "User-input-disabled event taps should be re-enabled"
        )
        assert(
            !EventTapRecoveryPolicy.shouldReenableTap(for: .leftMouseDown),
            "Regular mouse events should not trigger event-tap recovery"
        )

        print("event tap recovery policy test passed")
    }
}
