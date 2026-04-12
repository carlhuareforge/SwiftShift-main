import Cocoa
import Accessibility
import OSLog
struct WindowBounds {
    let topLeft: NSPoint
    let topRight: NSPoint
    let bottomLeft: NSPoint
    let bottomRight: NSPoint
}
class WindowManager {
    private static let logger = Logger(subsystem: "com.pablopunk.Swift-Shift", category: "WindowManager")
    private static let slowResolutionThreshold: TimeInterval = 0.008
    private static var cachedWindow: AXUIElement?
    private static var cachedWindowPID: pid_t?

    struct WindowListEntry {
        let pid: pid_t
        let layer: Int
        let alpha: Double
        let bounds: CGRect
    }
    @discardableResult
    static func move(window: AXUIElement, to point: NSPoint) -> AXError {
        var p = point; let v = AXValueCreate(.cgPoint, &p)!
        return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, v)
    }
    @discardableResult
    static func resize(window: AXUIElement, to s: CGSize, from o: NSPoint, shouldMoveOrigin: Bool = true) -> AXError {
        if shouldMoveOrigin {
            let moveError = move(window: window, to: o)
            if moveError != .success { return moveError }
        }
        var sz = s; let v = AXValueCreate(.cgSize, &sz)!
        return AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, v)
    }
    static func getSize(window: AXUIElement) -> NSSize? {
        var r: CFTypeRef?; guard AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &r) == .success else { return nil }
        var s: CGSize = .zero; AXValueGetValue(r as! AXValue, .cgSize, &s); return NSSize(width: s.width, height: s.height)
    }
    static func currentMouseLocation() -> NSPoint? {
        guard let ev = CGEvent(source: nil) else { return nil }
        return ev.location
    }
    static func getCurrentWindow(at mouseLocation: NSPoint? = nil) -> AXUIElement? {
        guard let mouseLocation = mouseLocation ?? currentMouseLocation() else { return nil }

        let started = ProcessInfo.processInfo.systemUptime
        let currentPID = NSRunningApplication.current.processIdentifier

        if let cachedWindow,
           let cachedPID = cachedWindowPID,
           cachedPID != currentPID,
           windowContains(cachedWindow, mouseLocation: mouseLocation) {
            logResolution(source: "cache", duration: ProcessInfo.processInfo.systemUptime - started, success: true)
            return cachedWindow
        }

        let sys = AXUIElementCreateSystemWide(); var el: AXUIElement?
        if AXUIElementCopyElementAtPosition(sys, Float(mouseLocation.x), Float(mouseLocation.y), &el) == .success, let el = el, let w = getWindow(from: el) {
            let pid = windowPID(w)
            if pid != currentPID {
                cache(window: w)
                logResolution(source: "ax_hit_test", duration: ProcessInfo.processInfo.systemUptime - started, success: true)
                return w
            }
        }

        if let window = getFocusedWindowOfFrontmostApplication(containing: mouseLocation) {
            cache(window: window)
            logResolution(source: "frontmost_app", duration: ProcessInfo.processInfo.systemUptime - started, success: true)
            return window
        }

        if let window = getTopWindowAtCursorUsingCGWindowList(mouseLocation: mouseLocation) {
            cache(window: window)
            logResolution(source: "cg_window_list", duration: ProcessInfo.processInfo.systemUptime - started, success: true)
            return window
        }

        logResolution(source: "unresolved", duration: ProcessInfo.processInfo.systemUptime - started, success: false)
        return nil
    }
    static func windowListCandidates(containing mouseLocation: NSPoint, from entries: [WindowListEntry], excluding excludedPID: pid_t) -> [WindowListEntry] {
        entries.filter { $0.layer == 0 && $0.alpha > 0 && $0.pid != excludedPID && $0.bounds.contains(mouseLocation) }
    }
    private static func getTopWindowAtCursorUsingCGWindowList(mouseLocation: NSPoint) -> AXUIElement? {
        let currentPID = NSRunningApplication.current.processIdentifier
        for entry in windowListCandidates(containing: mouseLocation, from: getWindowListEntries(), excluding: currentPID) {
            let app = AXUIElementCreateApplication(entry.pid)
            if let window = getWindow(in: app, containing: mouseLocation) { return window }
            if let window = getFocusedWindow(from: app) { return window }
            if let window = getFirstWindow(from: app) { return window }
        }
        return nil
    }
    private static func getWindowListEntries() -> [WindowListEntry] {
        let list = CGWindowListCopyWindowInfo([.excludeDesktopElements, .optionOnScreenOnly], kCGNullWindowID) as? [[String: AnyObject]] ?? []
        return list.compactMap { entry in
            guard let boundsDict = entry[kCGWindowBounds as String] as? [String: CGFloat],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t else { return nil }
            let layer = entry[kCGWindowLayer as String] as? Int ?? 0
            let alpha = entry[kCGWindowAlpha as String] as? Double ?? 1
            return WindowListEntry(pid: pid, layer: layer, alpha: alpha, bounds: bounds)
        }
    }
    private static func getWindow(in app: AXUIElement, containing mouseLocation: NSPoint) -> AXUIElement? {
        for window in getWindows(from: app) {
            if let pos = getPosition(window: window), let size = getSize(window: window) {
                let rect = CGRect(origin: pos, size: size)
                if rect.contains(mouseLocation) { return window }
            }
        }
        return nil
    }
    private static func getFocusedWindow(from app: AXUIElement) -> AXUIElement? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }
    private static func getFirstWindow(from app: AXUIElement) -> AXUIElement? {
        getWindows(from: app).first
    }
    private static func getWindows(from app: AXUIElement) -> [AXUIElement] {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return [] }
        return windows
    }
    private static func getFocusedWindowOfFrontmostApplication(containing mouseLocation: NSPoint) -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != NSRunningApplication.current.processIdentifier else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        if let window = getWindow(in: axApp, containing: mouseLocation) { return window }
        return getFocusedWindow(from: axApp)
    }
    private static func getWindow(from element: AXUIElement) -> AXUIElement? {
        var r: AnyObject?; AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &r)
        if r as? String == kAXWindowRole { return element }
        var p: AnyObject?; AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &p)
        if let parent = p { return getWindow(from: parent as! AXUIElement) }
        return nil
    }
    static func focus(window: AXUIElement) { AXUIElementPerformAction(window, kAXRaiseAction as CFString); getNSApplication(from: window)?.activate() }
    static func getNSApplication(from element: AXUIElement) -> NSRunningApplication? {
        var pid: pid_t = 0; AXUIElementGetPid(element, &pid); return NSRunningApplication(processIdentifier: pid)
    }
    static func convertYCoordinateBecauseTheAreTwoFuckingCoordinateSystems(point: NSPoint) -> NSPoint {
        return NSPoint(x: point.x, y: CGDisplayBounds(CGMainDisplayID()).height - point.y)
    }
    static func getPosition(window: AXUIElement) -> NSPoint? {
        var r: CFTypeRef?; guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &r) == .success else { return nil }
        var p: CGPoint = .zero; AXValueGetValue(r as! AXValue, .cgPoint, &p); return NSPoint(x: p.x, y: p.y)
    }
    static func getWindowBounds(windowLocation: NSPoint, windowSize: CGSize) -> WindowBounds {
        let fixed = convertYCoordinateBecauseTheAreTwoFuckingCoordinateSystems(point: windowLocation)
        return WindowBounds(topLeft: fixed, topRight: NSPoint(x: fixed.x + windowSize.width, y: fixed.y), bottomLeft: NSPoint(x: fixed.x, y: fixed.y - windowSize.height), bottomRight: NSPoint(x: fixed.x + windowSize.width, y: fixed.y - windowSize.height))
    }

    private static func cache(window: AXUIElement) {
        cachedWindow = window
        cachedWindowPID = windowPID(window)
    }

    private static func windowContains(_ window: AXUIElement, mouseLocation: NSPoint) -> Bool {
        guard let pos = getPosition(window: window), let size = getSize(window: window) else { return false }
        return CGRect(origin: pos, size: size).contains(mouseLocation)
    }

    private static func windowPID(_ window: AXUIElement) -> pid_t {
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        return pid
    }

    private static func logResolution(source: String, duration: TimeInterval, success: Bool) {
        guard !success || source != "ax_hit_test" || duration >= slowResolutionThreshold else { return }
        let durationMs = duration * 1000
        if success {
            logger.debug("Resolved window via \(source, privacy: .public) in \(durationMs, format: .fixed(precision: 2)) ms")
        } else {
            logger.notice("Failed to resolve window in \(durationMs, format: .fixed(precision: 2)) ms")
        }
    }
}
