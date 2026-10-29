import Foundation

@main
struct AdaptiveWindowWriteCadenceTest {
    static func main() {
        let nominalInterval = 1.0 / 120.0
        let slowThreshold = 1.0 / 90.0
        let minimumAdaptiveInterval = 1.0 / 60.0
        let maximumAdaptiveInterval = 1.0 / 30.0

        var cadence = AdaptiveWindowWriteCadence(
            nominalInterval: nominalInterval,
            slowWriteThreshold: slowThreshold,
            minimumAdaptiveInterval: minimumAdaptiveInterval,
            maximumAdaptiveInterval: maximumAdaptiveInterval,
            recoveryWriteCount: 4
        )

        assert(cadence.currentMinimumInterval == 0, "Fresh cadence should not throttle fast windows")
        assert(
            cadence.shouldApplyWrite(at: 10, lastWriteStartedAt: nil),
            "First pending write should always apply"
        )

        cadence.recordWrite(duration: slowThreshold - 0.001)
        assert(cadence.currentMinimumInterval == 0, "Fast writes should keep the 120 Hz path")

        cadence.recordWrite(duration: slowThreshold + 0.001)
        assert(
            cadence.currentMinimumInterval >= minimumAdaptiveInterval,
            "A slow write should enable adaptive coalescing"
        )
        assert(
            !cadence.shouldApplyWrite(at: 10 + nominalInterval, lastWriteStartedAt: 10),
            "Pending updates should be coalesced until the adaptive interval has elapsed"
        )
        assert(
            cadence.shouldApplyWrite(at: 10 + cadence.currentMinimumInterval, lastWriteStartedAt: 10),
            "The newest pending update should apply once the adaptive interval elapses"
        )

        cadence.recordWrite(duration: 0.100)
        assert(
            cadence.currentMinimumInterval == maximumAdaptiveInterval,
            "Very slow writes should be capped to avoid over-throttling"
        )

        for _ in 0..<4 {
            cadence.recordWrite(duration: 0.001)
        }
        assert(
            cadence.currentMinimumInterval < maximumAdaptiveInterval,
            "A streak of fast writes should begin recovering toward full cadence"
        )

        cadence.reset(baseMinimumInterval: 1.0 / 45.0)
        assert(
            cadence.currentMinimumInterval == 1.0 / 45.0,
            "Known compositor-heavy targets should be able to start with a lower baseline cadence"
        )
        assert(
            !cadence.shouldApplyWrite(at: 20 + nominalInterval, lastWriteStartedAt: 20),
            "The baseline cadence should coalesce early writes even before a slow AX call is observed"
        )
        for _ in 0..<8 {
            cadence.recordWrite(duration: 0.001)
        }
        assert(
            cadence.currentMinimumInterval == 1.0 / 45.0,
            "Fast recovery should not go below a target-specific baseline cadence"
        )

        cadence.reset()
        assert(cadence.currentMinimumInterval == 0, "Reset should clear adaptive state between gestures")

        print("adaptive window write cadence test passed")
    }
}
