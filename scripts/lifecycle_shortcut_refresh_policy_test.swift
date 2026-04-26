import AppKit

@main
struct LifecycleShortcutRefreshPolicyTest {
    static func main() {
        let refreshNotifications: [NSNotification.Name] = [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
        ]

        let resetOnlyNotifications: [NSNotification.Name] = [
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.willSleepNotification,
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification,
        ]

        let observedNotifications = Set(LifecycleShortcutRefreshPolicy.observedNotifications)

        for notification in refreshNotifications + resetOnlyNotifications {
            assert(
                observedNotifications.contains(notification),
                "\(notification.rawValue) should be observed by ShortcutsManager"
            )
        }

        for notification in refreshNotifications {
            assert(
                LifecycleShortcutRefreshPolicy.shouldRefreshShortcuts(after: notification),
                "\(notification.rawValue) should rebuild shortcut event taps"
            )
        }

        for notification in resetOnlyNotifications {
            assert(
                !LifecycleShortcutRefreshPolicy.shouldRefreshShortcuts(after: notification),
                "\(notification.rawValue) should only reset transient input state"
            )
        }

        print("lifecycle shortcut refresh policy test passed")
    }
}
