import Cocoa
import Accessibility
struct WindowBounds {
    let topLeft: NSPoint
    let topRight: NSPoint
    let bottomLeft: NSPoint
    let bottomRight: NSPoint
}
class WindowManager {
    struct WindowListEntry {
        let pid: pid_t
        let layer: Int
        let alpha: Double
        let bounds: CGRect
    }
    static func move(window: AXUIElement, to point: NSPoint) {
        var p = point; let v = AXValueCreate(.cgPoint, &p)!
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, v)
    }
    static func resize(window: AXUIElement, to s: CGSize, from o: NSPoint, shouldMoveOrigin: Bool = true) {
        if shouldMoveOrigin { move(window: window, to: o) }
        var sz = s; let v = AXValueCreate(.cgSize, &sz)!
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, v)
    }
    static func getSize(window: AXUIElement) -> NSSize? {
        var r: CFTypeRef?; guard AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &r) == .success else { return nil }
        var s: CGSize = .zero; AXValueGetValue(r as! AXValue, .cgSize, &s); return NSSize(width: s.width, height: s.height)
    }
    static func getCurrentWindow() -> AXUIElement? {
        guard let ev = CGEvent(source: nil) else { return nil }
        let sys = AXUIElementCreateSystemWide(); var el: AXUIElement?
        if AXUIElementCopyElementAtPosition(sys, Float(ev.location.x), Float(ev.location.y), &el) == .success, let el = el, let w = getWindow(from: el) {
            var pid: pid_t = 0; AXUIElementGetPid(w, &pid)
            if pid != NSRunningApplication.current.processIdentifier { return w }
        }
        if let window = getTopWindowAtCursorUsingCGWindowList(mouseLocation: ev.location) { return window }
        return getFocusedWindowOfFrontmostApplication(containing: ev.location)
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
}
