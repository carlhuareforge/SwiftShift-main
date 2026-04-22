import Foundation

enum PreferenceKey: String {
    case focusOnApp = "focusOnApp"
    case showMenuBarIcon = "showMenuBarIcon"
    case useQuadrants = "useQuadrants"
    case requireMouseClick = "requireMouseClick"
    case enableDockClickToggle = "enableDockClickToggle"
    case dockClickAction = "dockClickAction"
}

enum DockClickActionPreference: String, CaseIterable {
    case hide = "hide"
    case minimize = "minimize"

    var title: String {
        switch self {
        case .hide:
            return "Hide application"
        case .minimize:
            return "Minimize windows"
        }
    }
}

class PreferencesManager {
    static func loadBool(for key: PreferenceKey) -> Bool {
        return UserDefaults.standard.bool(forKey: key.rawValue)
    }

    static func loadDockClickAction() -> DockClickActionPreference {
        guard let rawValue = UserDefaults.standard.string(forKey: PreferenceKey.dockClickAction.rawValue),
              let action = DockClickActionPreference(rawValue: rawValue) else {
            return .hide
        }

        return action
    }
}
