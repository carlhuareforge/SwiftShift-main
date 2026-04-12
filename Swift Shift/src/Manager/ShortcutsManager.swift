import ShortcutRecorder
import CGEventSupervisor

enum ShortcutType: String, CaseIterable {
  case move = "Move"
  case resize = "Resize"
}

enum MouseButton: String, CaseIterable {
  case none = "None"
  case left = "Left"
  case right = "Right"
  
  static func parse(rawValue: String?) -> MouseButton {
    guard let rawValue = rawValue else { return .none }
    if let value = MouseButton(rawValue: rawValue) {
      return value
    } else {
      return .none
    }
  }
}

struct UserShortcut {
  var type: ShortcutType
  var shortcut: Shortcut?
  var mouseButton: MouseButton
  
  init(type: ShortcutType, shortcut: Shortcut? = nil, mouseButton: MouseButton) {
    self.type = type
    self.shortcut = shortcut
    self.mouseButton = mouseButton
  }
}

class ShortcutsManager {
  static let shared = ShortcutsManager()
  private(set) var activeShortcuts: [ShortcutType: Bool] = [:]
  private var mouseSubscriptions: Set<String> = []
  private var workspaceNotificationObserver: Any?
  private var modifierOnlyShortcuts: [ShortcutType: UserShortcut] = [:]
  private var activeModifierTrackingType: ShortcutType?
  private var suppressedMouseButton: MouseButton?

  private let modifierFlagsSubscriber = "modifier_only_flags"
  private let modifierMouseSubscriber = "modifier_only_mouse"
  private let modifierKeysSubscriber = "modifier_only_keys"
  
  private init() {
    for type in ShortcutType.allCases {
      activeShortcuts[type] = false
    }
    registerForWorkspaceNotifications()
    updateGlobalShortcuts()
  }
  
  deinit {
    unregisterForWorkspaceNotifications()
  }
  
  private func registerForWorkspaceNotifications() {
    let notificationCenter = NSWorkspace.shared.notificationCenter
    workspaceNotificationObserver = notificationCenter.addObserver(
      forName: NSWorkspace.activeSpaceDidChangeNotification,
      object: nil,
      queue: .main) { [weak self] _ in
        self?.handleSpaceChange()
      }
  }
  
  private func unregisterForWorkspaceNotifications() {
    if let observer = workspaceNotificationObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
      workspaceNotificationObserver = nil
    }
  }
  
  private func handleSpaceChange() {
    for type in ShortcutType.allCases {
      if activeShortcuts[type] == true {
        activeShortcuts[type] = false
      }
    }
  }
  
  func cleanupAllShortcuts() {
    for type in ShortcutType.allCases {
      if activeShortcuts[type] == true {
        let action = type == .move ? MouseAction.move : MouseAction.resize
        MouseTracker.shared.stopTracking(for: action)
        cleanupMouseSubscriptions(action: action)
      }
    }
    removeModifierOnlySubscribers()
    removeAllActions()
    for type in ShortcutType.allCases {
      activeShortcuts[type] = false
    }
    unregisterForWorkspaceNotifications()
  }
  
  func save(_ userShortcut: UserShortcut) {
    do {
      if let shortcut = userShortcut.shortcut {
        let data = try NSKeyedArchiver.archivedData(withRootObject: shortcut, requiringSecureCoding: false)
        UserDefaults.standard.set(data, forKey: userShortcut.type.rawValue)
        UserDefaults.standard.set(userShortcut.mouseButton.rawValue, forKey: "\(userShortcut.type.rawValue)_mouseButton")
      }
    } catch {
      print("Error: \(error)")
    }
    updateGlobalShortcuts()
  }
  
  func load(for type: ShortcutType) -> UserShortcut? {
    guard let data = UserDefaults.standard.data(forKey: type.rawValue) else { return nil }
    do {
      let shortcut = try NSKeyedUnarchiver.unarchivedObject(ofClass: Shortcut.self, from: data)
      let mouseButton = MouseButton.parse(rawValue: UserDefaults.standard.string(forKey: "\(type.rawValue)_mouseButton"))
      return UserShortcut(type: type, shortcut: shortcut, mouseButton: mouseButton)
    } catch {
      print("Error unarchiving data: \(error.localizedDescription)")
      return nil
    }
  }
  
  func delete(for type: ShortcutType) {
    UserDefaults.standard.removeObject(forKey: type.rawValue)
    updateGlobalShortcuts()
  }
  
  func removeClickActionsForAll() {
    for type in ShortcutType.allCases {
      if var userShortcut = load(for: type) {
        userShortcut.mouseButton = .none
        self.save(userShortcut)
      }
    }
  }
  
  private func clearActionsAndMonitors() {
    stopActiveModifierTracking()
    removeModifierOnlySubscribers()
    removeAllActions()
    cleanupAllMouseSubscriptions()
    for type in ShortcutType.allCases {
      activeShortcuts[type] = false
    }
  }
  
  private func removeAllActions() {
    AppDelegate.shared.shortcutMonitor?.removeAllActions()
  }
  
  private func cleanupAllMouseSubscriptions() {
    for subscriptionKey in mouseSubscriptions {
      CGEventSupervisor.shared.cancel(subscriber: subscriptionKey)
    }
    mouseSubscriptions.removeAll()
  }
  
  // Regular shortcuts (key + modifiers)
  private func addActions(mouseAction: MouseAction, for userShortcut: UserShortcut) {
    guard let shortcut = userShortcut.shortcut else { return }
    
    let keydownAction = ShortcutAction(shortcut: shortcut) { _ in
      self.activeShortcuts[userShortcut.type] = true
      self.startTracking(userShortcut, mouseAction)
      return true
    }
    
    let keyupAction = ShortcutAction(shortcut: shortcut) { _ in
      self.stopTracking(userShortcut, mouseAction)
      self.activeShortcuts[userShortcut.type] = false
      return true
    }
    
    AppDelegate.shared.shortcutMonitor?.addAction(keydownAction, forKeyEvent: .down)
    AppDelegate.shared.shortcutMonitor?.addAction(keyupAction, forKeyEvent: .up)
  }
  
  private func updateGlobalShortcuts() {
    clearActionsAndMonitors()
    modifierOnlyShortcuts.removeAll()
    
    for type in ShortcutType.allCases {
      if let userShortcut = load(for: type), let shortcut = userShortcut.shortcut {
        let mouseAction = action(for: type)
        let isModifierOnlyShortcut = shortcut.charactersIgnoringModifiers == nil
        
        if isModifierOnlyShortcut {
          modifierOnlyShortcuts[type] = userShortcut
        } else {
          addActions(mouseAction: mouseAction, for: userShortcut)
        }
      }
    }

    configureModifierOnlyMonitoring()
  }
  
  private func startTracking(_ userShortcut: UserShortcut, _ action: MouseAction) {
    if userShortcut.mouseButton == .none {
      MouseTracker.shared.startTracking(for: action, button: .none)
      return
    }
    
    let downEvent: CGEventType = userShortcut.mouseButton == .left ? .leftMouseDown : .rightMouseDown
    let upEvent: CGEventType = userShortcut.mouseButton == .left ? .leftMouseUp : .rightMouseUp
    let downKey = "\(action.rawValue)_mouseDown"
    let upKey = "\(action.rawValue)_mouseUp"
    
    CGEventSupervisor.shared.subscribe(
      as: downKey,
      to: .cgEvents(downEvent),
      using: { [weak self] event in
        guard let self = self, self.activeShortcuts[userShortcut.type] == true else { return }
        event.cancel()
        MouseTracker.shared.startTracking(for: action, button: userShortcut.mouseButton)
      })
    
    CGEventSupervisor.shared.subscribe(
      as: upKey,
      to: .cgEvents(upEvent),
      using: { [weak self] event in
        guard let self = self, self.activeShortcuts[userShortcut.type] == true else { return }
        event.cancel()
        MouseTracker.shared.stopTracking(for: action)
      })
    
    mouseSubscriptions.insert(downKey)
    mouseSubscriptions.insert(upKey)
  }
  
  private func stopTracking(_ userShortcut: UserShortcut, _ action: MouseAction) {
    MouseTracker.shared.stopTracking(for: action)
    cleanupMouseSubscriptions(action: action)
    activeShortcuts[userShortcut.type] = false
  }
  
  private func cleanupMouseSubscriptions(action: MouseAction) {
    let downKey = "\(action.rawValue)_mouseDown"
    let upKey = "\(action.rawValue)_mouseUp"
    
    CGEventSupervisor.shared.cancel(subscriber: downKey)
    CGEventSupervisor.shared.cancel(subscriber: upKey)
    
    mouseSubscriptions.remove(downKey)
    mouseSubscriptions.remove(upKey)
  }

  private func configureModifierOnlyMonitoring() {
    guard !modifierOnlyShortcuts.isEmpty else { return }

    if modifierOnlyShortcuts.values.contains(where: { $0.mouseButton == .none }) {
      CGEventSupervisor.shared.subscribe(
        as: modifierFlagsSubscriber,
        to: .nsEvents(.flagsChanged),
        using: { [weak self] event in
          self?.handleModifierFlagsChanged(event)
        })
    }

    if modifierOnlyShortcuts.values.contains(where: { $0.mouseButton != .none }) {
      CGEventSupervisor.shared.subscribe(
        as: modifierMouseSubscriber,
        to: .cgEvents(.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp),
        using: { [weak self] event in
          self?.handleModifierMouseEvent(event)
        })
    }

    if modifierOnlyShortcuts.values.contains(where: { $0.mouseButton == .none }) {
      CGEventSupervisor.shared.subscribe(
        as: modifierKeysSubscriber,
        to: .nsEvents(.keyDown, .keyUp),
        using: { [weak self] event in
          self?.handleModifierKeyEvent(event)
        })
    }
  }

  private func removeModifierOnlySubscribers() {
    CGEventSupervisor.shared.cancel(subscriber: modifierFlagsSubscriber)
    CGEventSupervisor.shared.cancel(subscriber: modifierMouseSubscriber)
    CGEventSupervisor.shared.cancel(subscriber: modifierKeysSubscriber)
    modifierOnlyShortcuts.removeAll()
    suppressedMouseButton = nil
    activeModifierTrackingType = nil
  }

  private func handleModifierFlagsChanged(_ event: NSEvent) {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

    for (type, userShortcut) in modifierOnlyShortcuts where userShortcut.mouseButton == .none {
      guard let shortcut = userShortcut.shortcut else { continue }

      let matchesShortcut = flags == shortcut.modifierFlags
      let isActive = activeShortcuts[type] ?? false
      let action = action(for: type)

      if matchesShortcut && !isActive {
        activeShortcuts[type] = true
        MouseTracker.shared.startTracking(for: action, button: .none)
      } else if !matchesShortcut && isActive {
        MouseTracker.shared.stopTracking(for: action)
        activeShortcuts[type] = false
      }
    }

    guard
      let activeType = activeModifierTrackingType,
      let shortcut = modifierOnlyShortcuts[activeType]?.shortcut,
      flags != shortcut.modifierFlags
    else { return }

    stopActiveModifierTracking()
  }

  private func handleModifierKeyEvent(_ event: NSEvent) {
    guard event.type == .keyDown || event.type == .keyUp else { return }
    guard (36...126).contains(event.keyCode) else { return }

    for (type, userShortcut) in modifierOnlyShortcuts where userShortcut.mouseButton == .none {
      guard activeShortcuts[type] == true else { continue }
      MouseTracker.shared.stopTracking(for: action(for: type))
      activeShortcuts[type] = false
    }
  }

  private func handleModifierMouseEvent(_ event: CGEvent) {
    guard let mouseButton = mouseButton(for: event.type) else { return }

    switch event.type {
    case .leftMouseDown, .rightMouseDown:
      guard activeModifierTrackingType == nil else { return }
      guard let shortcut = matchingModifierShortcut(for: mouseButton, flags: eventModifierFlags(event)) else { return }

      event.cancel()
      suppressedMouseButton = mouseButton
      activeModifierTrackingType = shortcut.type
      activeShortcuts[shortcut.type] = true
      MouseTracker.shared.startTracking(for: action(for: shortcut.type), button: mouseButton, modifierFlags: shortcut.shortcut?.modifierFlags)

    case .leftMouseUp, .rightMouseUp:
      guard mouseButton == suppressedMouseButton else { return }

      event.cancel()
      suppressedMouseButton = nil
      stopActiveModifierTracking()

    default:
      break
    }
  }

  private func stopActiveModifierTracking() {
    guard let type = activeModifierTrackingType else { return }

    MouseTracker.shared.stopTracking(for: action(for: type))
    activeShortcuts[type] = false
    activeModifierTrackingType = nil
  }

  private func action(for type: ShortcutType) -> MouseAction {
    type == .move ? .move : .resize
  }

  private func matchingModifierShortcut(for mouseButton: MouseButton, flags: NSEvent.ModifierFlags) -> UserShortcut? {
    modifierOnlyShortcuts.values.first(where: {
      guard let shortcut = $0.shortcut else { return false }
      return $0.mouseButton == mouseButton && shortcut.modifierFlags == flags
    })
  }

  private func mouseButton(for eventType: CGEventType) -> MouseButton? {
    switch eventType {
    case .leftMouseDown, .leftMouseUp:
      return .left
    case .rightMouseDown, .rightMouseUp:
      return .right
    default:
      return nil
    }
  }

  private func eventModifierFlags(_ event: CGEvent) -> NSEvent.ModifierFlags {
    NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue)).intersection(.deviceIndependentFlagsMask)
  }
}
