import Cocoa
import CoreGraphics

enum Preference {
  case accessibility
  case inputMonitoring
}

struct PermissionState {
  var accessibility = false
  var inputMonitoring = false

  var allGranted: Bool {
    accessibility && inputMonitoring
  }
}

class PermissionsManager {
  static func preferencesURL(for type: Preference) -> URL? {
    switch type {
    case .accessibility:
      return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    case .inputMonitoring:
      return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }
  }

  static func currentPermissionState() -> PermissionState {
    PermissionState(
      accessibility: hasAccessibilityPermission(),
      inputMonitoring: hasInputMonitoringPermission()
    )
  }

  static func hasAccessibilityPermission() -> Bool {
    let checkOptionPrompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    let options = [checkOptionPrompt: false]
    return AXIsProcessTrustedWithOptions(options as CFDictionary)
  }

  static func requestAccessibilityPermission() {
    let checkOptionPrompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    let options = [checkOptionPrompt: true]
    _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
  }

  static func hasInputMonitoringPermission() -> Bool {
    CGPreflightListenEventAccess()
  }

  static func requestInputMonitoringPermission() -> Bool {
    CGRequestListenEventAccess()
  }
  
  static func openPreferences(at type: Preference) {
    if let url = preferencesURL(for: type) {
      NSWorkspace.shared.open(url)
    }
  }
}
