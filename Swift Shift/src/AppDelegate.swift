import ShortcutRecorder
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
  static var shared: AppDelegate!
  var shortcutMonitor: GlobalShortcutMonitor?
  
  override init() {
    super.init()
    AppDelegate.shared = self
    UserDefaults.standard.register(defaults: [
      PreferenceKey.focusOnApp.rawValue: true,
      PreferenceKey.showMenuBarIcon.rawValue: true,
      PreferenceKey.useQuadrants.rawValue: false,
      PreferenceKey.requireMouseClick.rawValue: false,
    ])
    self.shortcutMonitor = GlobalShortcutMonitor()
  }
  
  func applicationDidFinishLaunching(_ notification: Notification) {
    let _ = ShortcutsManager.shared // immediately register shortcuts so we won't wait for the UI
  }
  
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    UserDefaults.standard.set(true, forKey: "showMenuBarIcon")
    return true
  }
  
  func applicationWillTerminate(_ notification: Notification) {
    shortcutMonitor?.removeAllActions()
    ShortcutsManager.shared.cleanupAllShortcuts()
  }
}
