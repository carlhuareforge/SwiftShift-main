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
    switch type {
    case .accessibility:
      if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
        NSWorkspace.shared.open(url)
      }
    case .inputMonitoring:
      if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
        NSWorkspace.shared.open(url)
      }
    }
  }
}
