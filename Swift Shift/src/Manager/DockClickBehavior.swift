import Foundation
import CoreGraphics

enum DockClickOutcome: Equatable {
    case passthrough
    case hide
    case restore
}

struct DockClickState: Equatable {
    let isFrontmost: Bool
    let isHidden: Bool
    let hasWindows: Bool
    let hasVisibleWindows: Bool
    let hasMinimizedWindows: Bool
}

enum DockClickBehavior {
    static func outcome(for state: DockClickState) -> DockClickOutcome {
        guard state.hasWindows else { return .passthrough }

        if state.isHidden {
            return .restore
        }

        if !state.hasVisibleWindows && state.hasMinimizedWindows {
            return .restore
        }

        return state.isFrontmost && state.hasVisibleWindows ? .hide : .passthrough
    }
}

enum DockClickGesture {
    static let maxMovementDistance: CGFloat = 6
    static let maxDuration: TimeInterval = 0.35

    static func shouldTriggerAction(movementDistance: CGFloat, duration: TimeInterval) -> Bool {
        movementDistance <= maxMovementDistance && duration <= maxDuration
    }
}
