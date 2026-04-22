import AppKit
import ApplicationServices

final class DockClickManager {
    static let shared = DockClickManager()

    private struct ResolvedDockClick {
        let processIdentifier: pid_t
        let outcome: DockClickOutcome
    }

    private struct PendingDockClick {
        let resolvedClick: ResolvedDockClick
        let mouseDownLocation: CGPoint
        let startedAt: TimeInterval
    }

    private let dockBundleIdentifier = "com.apple.dock"
    private let clickDelay: TimeInterval = 0.12

    private var eventTap: CFMachPort?
    private var eventTapRunLoopSource: CFRunLoopSource?
    private var defaultsObserver: NSObjectProtocol?
    private var pendingDockClick: PendingDockClick?

    private init() {
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshMonitoring()
        }

        refreshMonitoring()
    }

    deinit {
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
        removeEventTap()
    }

    func refreshMonitoring() {
        if PreferencesManager.loadBool(for: .enableDockClickToggle) {
            installEventTapIfNeeded()
        } else {
            removeEventTap()
        }
    }

    func cleanup() {
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
            self.defaultsObserver = nil
        }
        removeEventTap()
    }

    private func installEventTapIfNeeded() {
        guard eventTap == nil else { return }

        let eventMask =
            CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseUp.rawValue)
        guard let eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { _, type, event, userInfo in
                guard let userInfo else {
                    return Unmanaged.passUnretained(event)
                }

                let manager = Unmanaged<DockClickManager>.fromOpaque(userInfo).takeUnretainedValue()
                return manager.handleEventTap(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)

        self.eventTap = eventTap
        eventTapRunLoopSource = runLoopSource
    }

    private func removeEventTap() {
        pendingDockClick = nil

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            if let eventTapRunLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), eventTapRunLoopSource, .commonModes)
            }
            CFMachPortInvalidate(eventTap)
        }

        eventTap = nil
        eventTapRunLoopSource = nil
    }

    private func handleEventTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .leftMouseDown:
            pendingDockClick = resolveDockClick(at: event.location).map {
                PendingDockClick(
                    resolvedClick: $0,
                    mouseDownLocation: event.location,
                    startedAt: ProcessInfo.processInfo.systemUptime
                )
            }
        case .leftMouseUp:
            finalizePendingDockClick(mouseUpLocation: event.location)
        default:
            break
        }

        return Unmanaged.passUnretained(event)
    }

    private func resolveDockClick(at location: CGPoint) -> ResolvedDockClick? {
        guard AXIsProcessTrusted() else { return nil }
        guard let app = runningApplicationForDockItem(at: location) else { return nil }
        guard app.bundleIdentifier != Bundle.main.bundleIdentifier else { return nil }

        let state = captureState(for: app)
        let outcome = DockClickBehavior.outcome(for: state)
        guard outcome != .passthrough else { return nil }

        return ResolvedDockClick(processIdentifier: app.processIdentifier, outcome: outcome)
    }

    private func applyResolvedDockClick(_ resolvedClick: ResolvedDockClick) {
        guard let app = NSRunningApplication(processIdentifier: resolvedClick.processIdentifier) else { return }

        switch resolvedClick.outcome {
        case .passthrough:
            return
        case .hide:
            hideApp(app)
        case .restore:
            restoreApp(app)
        }
    }

    private func hideApp(_ app: NSRunningApplication) {
        switch PreferencesManager.loadDockClickAction() {
        case .hide:
            app.hide()
        case .minimize:
            let windows = applicationWindows(for: app).filter { !isWindowMinimized($0) }
            for window in windows {
                setWindow(window, minimized: true)
            }
        }
    }

    private func restoreApp(_ app: NSRunningApplication) {
        let windows = applicationWindows(for: app)
        for window in windows where isWindowMinimized(window) {
            setWindow(window, minimized: false)
        }

        if app.isHidden {
            app.unhide()
        }
        app.activate(options: [.activateIgnoringOtherApps])
    }

    private func captureState(for app: NSRunningApplication) -> DockClickState {
        let windows = applicationWindows(for: app)
        let hasVisibleWindows = windows.contains(where: { !isWindowMinimized($0) })
        return DockClickState(
            isFrontmost: NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
            isHidden: app.isHidden,
            hasWindows: !windows.isEmpty,
            hasVisibleWindows: hasVisibleWindows,
            hasMinimizedWindows: windows.contains(where: isWindowMinimized)
        )
    }

    private func finalizePendingDockClick(mouseUpLocation: CGPoint) {
        guard let pendingDockClick else { return }
        self.pendingDockClick = nil

        let movementDistance = hypot(
            mouseUpLocation.x - pendingDockClick.mouseDownLocation.x,
            mouseUpLocation.y - pendingDockClick.mouseDownLocation.y
        )
        let duration = ProcessInfo.processInfo.systemUptime - pendingDockClick.startedAt

        guard DockClickGesture.shouldTriggerAction(
            movementDistance: movementDistance,
            duration: duration
        ) else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + clickDelay) { [weak self] in
            self?.applyResolvedDockClick(pendingDockClick.resolvedClick)
        }
    }

    private func runningApplicationForDockItem(at location: CGPoint) -> NSRunningApplication? {
        guard let dockItem = applicationDockItem(at: location) else { return nil }
        guard let bundleIdentifier = bundleIdentifier(for: dockItem) else {
            return runningApplicationMatchingTitle(of: dockItem)
        }

        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        guard !runningApps.isEmpty else { return nil }

        if runningApps.count == 1 {
            return runningApps.first
        }

        let index = dockInstanceIndex(for: dockItem, bundleIdentifier: bundleIdentifier)
        return index < runningApps.count ? runningApps[index] : runningApps.first
    }

    private func runningApplicationMatchingTitle(of dockItem: AXUIElement) -> NSRunningApplication? {
        guard let title = stringAttribute(kAXTitleAttribute, of: dockItem) else { return nil }
        return NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == title })
    }

    private func applicationDockItem(at location: CGPoint) -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(location.x), Float(location.y), &element) == .success,
              let element else {
            return nil
        }

        return nearestApplicationDockItem(from: element)
    }

    private func nearestApplicationDockItem(from element: AXUIElement) -> AXUIElement? {
        var currentElement: AXUIElement? = element

        while let element = currentElement {
            var processIdentifier: pid_t = 0
            AXUIElementGetPid(element, &processIdentifier)

            if processIdentifier == currentDockProcessIdentifier(),
               stringAttribute(kAXSubroleAttribute, of: element) == "AXApplicationDockItem" {
                return element
            }

            currentElement = parent(of: element)
        }

        return nil
    }

    private func dockInstanceIndex(for dockItem: AXUIElement, bundleIdentifier: String) -> Int {
        guard let allDockItems = dockApplicationItems() else { return 0 }

        var matchingItems: [AXUIElement] = []
        for item in allDockItems {
            guard stringAttribute(kAXSubroleAttribute, of: item) == "AXApplicationDockItem",
                  self.bundleIdentifier(for: item) == bundleIdentifier else {
                continue
            }
            matchingItems.append(item)
        }

        for (index, item) in matchingItems.enumerated() where CFEqual(item, dockItem) {
            return index
        }

        return 0
    }

    private func dockApplicationItems() -> [AXUIElement]? {
        guard let dockProcessIdentifier = currentDockProcessIdentifier() else { return nil }
        let dockApp = AXUIElementCreateApplication(dockProcessIdentifier)
        guard let dockChildren = elementArrayAttribute(kAXChildrenAttribute, of: dockApp),
              let dockList = dockChildren.first(where: { stringAttribute(kAXRoleAttribute, of: $0) == kAXListRole }) else {
            return nil
        }

        return elementArrayAttribute(kAXChildrenAttribute, of: dockList)
    }

    private func currentDockProcessIdentifier() -> pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: dockBundleIdentifier).first?.processIdentifier
    }

    private func bundleIdentifier(for dockItem: AXUIElement) -> String? {
        guard let url = urlAttribute(kAXURLAttribute, of: dockItem) else { return nil }
        return Bundle(url: url)?.bundleIdentifier
    }

    private func applicationWindows(for app: NSRunningApplication) -> [AXUIElement] {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        return elementArrayAttribute(kAXWindowsAttribute, of: axApp) ?? []
    }

    private func isWindowMinimized(_ window: AXUIElement) -> Bool {
        boolAttribute(kAXMinimizedAttribute, of: window) ?? false
    }

    private func setWindow(_ window: AXUIElement, minimized: Bool) {
        let value: CFBoolean = minimized ? kCFBooleanTrue : kCFBooleanFalse
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, value)
    }

    private func parent(of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &value) == .success,
              let value else {
            return nil
        }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func boolAttribute(_ attribute: String, of element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? Bool
    }

    private func stringAttribute(_ attribute: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func urlAttribute(_ attribute: String, of element: AXUIElement) -> URL? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? URL
    }

    private func elementArrayAttribute(_ attribute: String, of element: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? [AXUIElement]
    }
}
