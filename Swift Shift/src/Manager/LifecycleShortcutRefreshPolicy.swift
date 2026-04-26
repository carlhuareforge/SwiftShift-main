import AppKit

enum LifecycleShortcutRefreshPolicy {
    static let observedNotifications: [NSNotification.Name] = [
        NSWorkspace.activeSpaceDidChangeNotification,
        NSWorkspace.willSleepNotification,
        NSWorkspace.screensDidSleepNotification,
        NSWorkspace.didWakeNotification,
        NSWorkspace.screensDidWakeNotification,
        NSWorkspace.sessionDidResignActiveNotification,
        NSWorkspace.sessionDidBecomeActiveNotification,
    ]

    private static let refreshNotifications: Set<NSNotification.Name> = [
        NSWorkspace.didWakeNotification,
        NSWorkspace.screensDidWakeNotification,
        NSWorkspace.sessionDidBecomeActiveNotification,
    ]

    static func shouldRefreshShortcuts(after notification: NSNotification.Name) -> Bool {
        refreshNotifications.contains(notification)
    }
}
