import Cocoa
import Accessibility
import CGEventSupervisor
import OSLog

enum MouseAction: String { case move, resize, none }
enum Quadrant { case topLeft, top, topRight, left, center, right, bottomLeft, bottom, bottomRight }

class MouseTracker {
    static let shared = MouseTracker()

    private static let logger = Logger(subsystem: "com.pablopunk.Swift-Shift", category: "MouseTracker")

    private let trackingTimeout: TimeInterval = 4
    private let nominalUpdateInterval: TimeInterval = 1.0 / 120.0
    private let slowWriteThreshold: TimeInterval = 1.0 / 90.0
    private let maxConsecutiveWriteFailures = 4
    private let trackingInputSubscriber = "tracking_input"
    private let trackingFlagsSubscriber = "tracking_flags"
    private let pendingStateLock = NSLock()

    private var initialMouseLocation: NSPoint?
    private var initialWindowLocation: NSPoint?
    private var trackedWindow: AXUIElement?
    private var trackedWindowIsFocused = false
    private var shouldFocusWindow = false
    private var currentAction: MouseAction = .none
    private var shouldUseQuadrants = false
    private var quadrant: Quadrant?
    private var windowSize: CGSize?
    private var isTracking = false
    private var requiredModifierFlags: NSEvent.ModifierFlags?
    private var pendingMouseLocation: NSPoint?
    private var lastInputTime: TimeInterval = 0
    private var updateTimer: DispatchSourceTimer?
    private var inputSubscriptionActive = false
    private var flagsSubscriptionActive = false
    private var lastAppliedOrigin: NSPoint?
    private var lastAppliedSize: CGSize?

    private var trackingStartedAt: TimeInterval = 0
    private var writeCount = 0
    private var coalescedInputCount = 0
    private var totalWriteDuration: TimeInterval = 0
    private var worstWriteDuration: TimeInterval = 0
    private var slowWriteCount = 0
    private var consecutiveWriteFailures = 0
    private var writeFailureCount = 0

    private init() {}

    var hasResidualInfrastructure: Bool {
        currentAction != .none || trackedWindow != nil || updateTimer != nil || inputSubscriptionActive || flagsSubscriptionActive || pendingMouseLocation != nil
    }

    func startTracking(for action: MouseAction, button: MouseButton, modifierFlags: NSEvent.ModifierFlags? = nil, triggerLocation: NSPoint? = nil) {
        if currentAction != .none { stopTracking(for: currentAction, reason: "restart") }
        prepareTracking(for: action, triggerLocation: triggerLocation, modifierFlags: modifierFlags)
        guard trackedWindow != nil else { return }

        registerTrackingSubscribers(button: button)
        startUpdateTimer()
        isTracking = true
        trackingStartedAt = now()

        pendingStateLock.lock()
        pendingMouseLocation = initialMouseLocation
        lastInputTime = trackingStartedAt
        pendingStateLock.unlock()
    }

    func stopTracking(for action: MouseAction) {
        stopTracking(for: action, reason: "stop")
    }

    func hardReset(reason: String) {
        guard hasResidualInfrastructure else { return }

        if currentAction != .none {
            stopTracking(for: currentAction, reason: reason)
            return
        }

        invalidateUpdateTimer()
        removeTrackingSubscribers()
        resetTrackingVariables()
        isTracking = false
        MouseTracker.logger.notice("Reset idle tracker after \(reason, privacy: .public)")
    }

    private func prepareTracking(for action: MouseAction, triggerLocation: NSPoint?, modifierFlags: NSEvent.ModifierFlags?) {
        guard let startLocation = triggerLocation ?? WindowManager.currentMouseLocation() else {
            trackedWindow = nil
            return
        }

        guard let currentWindow = WindowManager.getCurrentWindow(at: startLocation) else {
            trackedWindow = nil
            return
        }

        shouldFocusWindow = PreferencesManager.loadBool(for: .focusOnApp)
        shouldUseQuadrants = PreferencesManager.loadBool(for: .useQuadrants)
        trackedWindowIsFocused = false
        currentAction = action
        initialMouseLocation = startLocation
        trackedWindow = currentWindow
        initialWindowLocation = WindowManager.getPosition(window: currentWindow)
        windowSize = WindowManager.getSize(window: currentWindow)
        requiredModifierFlags = modifierFlags
        lastAppliedOrigin = initialWindowLocation
        lastAppliedSize = windowSize
        resetGestureMetrics()

        if action == .resize,
           shouldUseQuadrants,
           let m = initialMouseLocation,
           let w = initialWindowLocation,
           let s = windowSize {
            quadrant = determineQuadrant(mouseLocation: m, windowSize: s, windowLocation: w)
        }
    }

    private func determineQuadrant(mouseLocation: NSPoint, windowSize: CGSize, windowLocation: NSPoint) -> Quadrant {
        let b = WindowManager.getWindowBounds(windowLocation: windowLocation, windowSize: windowSize)
        let cSize = 0.25, sSize = (1 - cSize) / 2
        let tx = (b.topRight.x - b.topLeft.x) * sSize, ty = (b.topLeft.y - b.bottomLeft.y) * sSize
        let lx = b.topLeft.x + tx, rx = b.topRight.x - tx, tyP = b.topLeft.y - ty, by = b.bottomLeft.y + ty
        switch (mouseLocation.x, mouseLocation.y) {
            case (..<lx, tyP...): return .topLeft
            case (lx..<rx, tyP...): return .top
            case (rx..., tyP...): return .topRight
            case (..<lx, by..<tyP): return .left
            case (lx..<rx, by..<tyP): return .center
            case (rx..., by..<tyP): return .right
            case (..<lx, ..<by): return .bottomLeft
            case (lx..<rx, ..<by): return .bottom
            default: return .bottomRight
        }
    }

    private func registerTrackingSubscribers(button: MouseButton) {
        removeTrackingSubscribers()

        let inputEventType: CGEventType
        switch button {
        case .left:
            inputEventType = .leftMouseDragged
        case .right:
            inputEventType = .rightMouseDragged
        case .none:
            inputEventType = .mouseMoved
        }

        let expectedModifierFlags = requiredModifierFlags
        CGEventSupervisor.shared.subscribe(
            as: trackingInputSubscriber,
            to: .cgEvents(inputEventType),
            using: { [weak self] event in
                guard let self = self else { return }

                if let expectedModifierFlags {
                    let currentFlags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue)).intersection(.deviceIndependentFlagsMask)
                    if currentFlags != expectedModifierFlags {
                        DispatchQueue.main.async {
                            ShortcutsManager.shared.hardResetInputState(reason: "modifier_mismatch")
                        }
                        return
                    }
                }

                self.recordInput(location: event.location)
            })
        inputSubscriptionActive = true

        if let expectedModifierFlags {
            CGEventSupervisor.shared.subscribe(
                as: trackingFlagsSubscriber,
                to: .nsEvents(.flagsChanged),
                using: { event in
                    let currentFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    guard currentFlags != expectedModifierFlags else { return }
                    DispatchQueue.main.async {
                        ShortcutsManager.shared.hardResetInputState(reason: "modifier_released")
                    }
                })
            flagsSubscriptionActive = true
        }
    }

    private func startUpdateTimer() {
        invalidateUpdateTimer()

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: nominalUpdateInterval, leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in
            self?.handleUpdateTick()
        }
        timer.resume()
        updateTimer = timer
    }

    private func handleUpdateTick() {
        guard currentAction != .none else { return }

        pendingStateLock.lock()
        let idleDuration = now() - lastInputTime
        pendingStateLock.unlock()

        if idleDuration >= trackingTimeout {
            ShortcutsManager.shared.hardResetInputState(reason: "tracking_timeout")
            return
        }

        flushPendingMouseUpdate()
    }

    private func recordInput(location: CGPoint) {
        pendingStateLock.lock()
        if pendingMouseLocation != nil {
            coalescedInputCount += 1
        }
        pendingMouseLocation = NSPoint(x: location.x, y: location.y)
        lastInputTime = now()
        pendingStateLock.unlock()
    }

    private func flushPendingMouseUpdate() {
        pendingStateLock.lock()
        let location = pendingMouseLocation
        pendingMouseLocation = nil
        pendingStateLock.unlock()

        guard let location else { return }

        let started = now()
        let result: (applied: Bool, error: AXError?)
        switch currentAction {
        case .move:
            result = moveWindowBasedOnMouseLocation(location)
        case .resize:
            result = resizeWindowBasedOnMouseLocation(location)
        case .none:
            return
        }

        guard result.applied else { return }
        recordWrite(duration: now() - started, error: result.error)
    }

    private func moveWindowBasedOnMouseLocation(_ location: NSPoint) -> (applied: Bool, error: AXError?) {
        guard let initialMouseLocation, let initialWindowLocation, let trackedWindow else { return (false, nil) }
        let newOrigin = roundedPoint(
            DragGeometry.moveOrigin(
                initialWindowOrigin: initialWindowLocation,
                initialPointer: initialMouseLocation,
                currentPointer: location
            )
        )

        guard !pointsApproximatelyEqual(newOrigin, lastAppliedOrigin) else { return (false, nil) }

        ensureTrackedWindowFocusIfNeeded()
        lastAppliedOrigin = newOrigin
        let error = WindowManager.move(window: trackedWindow, to: newOrigin)
        return error == .success ? (true, nil) : (true, error)
    }

    private func resizeWindowBasedOnMouseLocation(_ location: NSPoint) -> (applied: Bool, error: AXError?) {
        guard let windowSize, let initialMouseLocation, let initialWindowLocation, let trackedWindow else { return (false, nil) }

        var newWidth = windowSize.width
        var newHeight = windowSize.height
        var newOrigin = initialWindowLocation

        if shouldUseQuadrants, let quadrant {
            let dx = location.x - initialMouseLocation.x
            let dy = location.y - initialMouseLocation.y
            switch quadrant {
                case .topLeft: newWidth -= dx; newHeight += dy; newOrigin.x += dx; newOrigin.y -= dy
                case .top: newHeight += dy; newOrigin.y -= dy
                case .topRight: newWidth += dx; newHeight += dy; newOrigin.y -= dy
                case .left: newWidth -= dx; newOrigin.x += dx
                case .center: newWidth += 2 * dx; newOrigin.x -= dx; newHeight += 2 * dy; newOrigin.y -= dy
                case .right: newWidth += dx
                case .bottomLeft: newWidth -= dx; newHeight -= dy; newOrigin.x += dx
                case .bottom: newHeight -= dy
                case .bottomRight: newWidth += dx; newHeight -= dy
            }
        } else {
            let resized = DragGeometry.topLeftAnchoredResize(
                initialSize: windowSize,
                initialPointer: initialMouseLocation,
                currentPointer: location
            )
            newWidth = resized.width
            newHeight = resized.height
            newOrigin = initialWindowLocation
        }

        newWidth = max(newWidth, 1)
        newHeight = max(newHeight, 1)
        newOrigin = roundedPoint(newOrigin)
        let newSize = roundedSize(CGSize(width: newWidth, height: newHeight))
        let shouldMoveOrigin = !pointsApproximatelyEqual(newOrigin, lastAppliedOrigin)

        guard shouldMoveOrigin || !sizesApproximatelyEqual(newSize, lastAppliedSize) else { return (false, nil) }

        ensureTrackedWindowFocusIfNeeded()
        lastAppliedOrigin = newOrigin
        lastAppliedSize = newSize
        let error = WindowManager.resize(window: trackedWindow, to: newSize, from: newOrigin, shouldMoveOrigin: shouldMoveOrigin)
        return error == .success ? (true, nil) : (true, error)
    }

    private func ensureTrackedWindowFocusIfNeeded() {
        guard shouldFocusWindow, !trackedWindowIsFocused, let trackedWindow else { return }
        WindowManager.focus(window: trackedWindow)
        trackedWindowIsFocused = true
    }

    private func recordWrite(duration: TimeInterval, error: AXError?) {
        writeCount += 1
        totalWriteDuration += duration
        worstWriteDuration = max(worstWriteDuration, duration)

        if duration >= slowWriteThreshold {
            slowWriteCount += 1
        }

        if let error {
            writeFailureCount += 1
            consecutiveWriteFailures += 1
            MouseTracker.logger.notice("AX write failed with code \(error.rawValue) during \(self.currentAction.rawValue, privacy: .public)")
            if consecutiveWriteFailures >= maxConsecutiveWriteFailures {
                ShortcutsManager.shared.hardResetInputState(reason: "ax_write_failures")
            }
        } else {
            consecutiveWriteFailures = 0
        }
    }

    private func stopTracking(for action: MouseAction, reason: String) {
        guard currentAction == action else { return }
        flushPendingMouseUpdate()
        logGestureSummary(reason: reason)
        invalidateUpdateTimer()
        removeTrackingSubscribers()
        resetTrackingVariables()
        isTracking = false
    }

    private func logGestureSummary(reason: String) {
        guard trackingStartedAt > 0 else { return }

        let duration = now() - trackingStartedAt
        let averageWriteDuration = writeCount > 0 ? totalWriteDuration / Double(writeCount) : 0
        let averageWriteMs = averageWriteDuration * 1000
        let maxWriteMs = worstWriteDuration * 1000

        if slowWriteCount > 0 || writeFailureCount > 0 || coalescedInputCount > 0 || duration > 0.5 {
            MouseTracker.logger.debug(
                "\(self.currentAction.rawValue, privacy: .public) gesture ended after \(duration * 1000, format: .fixed(precision: 2)) ms, reason=\(reason, privacy: .public), writes=\(self.writeCount), coalescedInputs=\(self.coalescedInputCount), avgWriteMs=\(averageWriteMs, format: .fixed(precision: 2)), maxWriteMs=\(maxWriteMs, format: .fixed(precision: 2)), slowWrites=\(self.slowWriteCount), failures=\(self.writeFailureCount)"
            )
        }
    }

    private func invalidateUpdateTimer() {
        updateTimer?.setEventHandler {}
        updateTimer?.cancel()
        updateTimer = nil
    }

    private func removeTrackingSubscribers() {
        CGEventSupervisor.shared.cancel(subscriber: trackingInputSubscriber)
        CGEventSupervisor.shared.cancel(subscriber: trackingFlagsSubscriber)
        inputSubscriptionActive = false
        flagsSubscriptionActive = false
    }

    private func resetGestureMetrics() {
        trackingStartedAt = 0
        writeCount = 0
        coalescedInputCount = 0
        totalWriteDuration = 0
        worstWriteDuration = 0
        slowWriteCount = 0
        consecutiveWriteFailures = 0
        writeFailureCount = 0
    }

    private func resetTrackingVariables() {
        pendingStateLock.lock()
        pendingMouseLocation = nil
        lastInputTime = 0
        pendingStateLock.unlock()

        lastAppliedOrigin = nil
        lastAppliedSize = nil
        trackedWindow = nil
        initialMouseLocation = nil
        initialWindowLocation = nil
        currentAction = .none
        quadrant = nil
        windowSize = nil
        requiredModifierFlags = nil
        trackedWindowIsFocused = false
        shouldFocusWindow = false
        shouldUseQuadrants = false
        resetGestureMetrics()
    }

    private func pointsApproximatelyEqual(_ a: NSPoint?, _ b: NSPoint?) -> Bool {
        guard let a, let b else { return false }
        return abs(a.x - b.x) < 0.5 && abs(a.y - b.y) < 0.5
    }

    private func sizesApproximatelyEqual(_ a: CGSize?, _ b: CGSize?) -> Bool {
        guard let a, let b else { return false }
        return abs(a.width - b.width) < 0.5 && abs(a.height - b.height) < 0.5
    }

    private func roundedPoint(_ point: NSPoint) -> NSPoint {
        NSPoint(x: point.x.rounded(), y: point.y.rounded())
    }

    private func roundedSize(_ size: CGSize) -> CGSize {
        CGSize(width: size.width.rounded(), height: size.height.rounded())
    }

    private func now() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }
}
