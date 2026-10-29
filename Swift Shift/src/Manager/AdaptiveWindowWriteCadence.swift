import Foundation

struct AdaptiveWindowWriteCadence {
    let nominalInterval: TimeInterval
    let slowWriteThreshold: TimeInterval
    let minimumAdaptiveInterval: TimeInterval
    let maximumAdaptiveInterval: TimeInterval
    let recoveryWriteCount: Int

    private(set) var currentMinimumInterval: TimeInterval = 0
    private var baseMinimumInterval: TimeInterval = 0
    private var fastWriteStreak = 0

    init(
        nominalInterval: TimeInterval = 1.0 / 120.0,
        slowWriteThreshold: TimeInterval = 1.0 / 90.0,
        minimumAdaptiveInterval: TimeInterval = 1.0 / 60.0,
        maximumAdaptiveInterval: TimeInterval = 1.0 / 30.0,
        recoveryWriteCount: Int = 8
    ) {
        self.nominalInterval = nominalInterval
        self.slowWriteThreshold = slowWriteThreshold
        self.minimumAdaptiveInterval = minimumAdaptiveInterval
        self.maximumAdaptiveInterval = maximumAdaptiveInterval
        self.recoveryWriteCount = max(1, recoveryWriteCount)
    }

    func shouldApplyWrite(at timestamp: TimeInterval, lastWriteStartedAt: TimeInterval?) -> Bool {
        guard currentMinimumInterval > 0, let lastWriteStartedAt else { return true }
        return timestamp - lastWriteStartedAt >= currentMinimumInterval
    }

    mutating func recordWrite(duration: TimeInterval) {
        if duration >= slowWriteThreshold {
            fastWriteStreak = 0
            let targetInterval = min(
                maximumAdaptiveInterval,
                max(minimumAdaptiveInterval, duration * 1.25)
            )
            currentMinimumInterval = max(currentMinimumInterval, targetInterval)
            return
        }

        guard currentMinimumInterval > baseMinimumInterval else { return }

        fastWriteStreak += 1
        guard fastWriteStreak >= recoveryWriteCount else { return }

        fastWriteStreak = 0
        let recoveredInterval = currentMinimumInterval * 0.75
        currentMinimumInterval = max(baseMinimumInterval, recoveredInterval <= nominalInterval ? 0 : recoveredInterval)
    }

    mutating func reset(baseMinimumInterval: TimeInterval = 0) {
        self.baseMinimumInterval = max(0, baseMinimumInterval)
        currentMinimumInterval = self.baseMinimumInterval
        fastWriteStreak = 0
    }
}
