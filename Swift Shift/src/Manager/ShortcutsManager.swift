import ShortcutRecorder
import CGEventSupervisor
import AppKit
import OSLog

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
  private static let logger = Logger(subsystem: "com.pablopunk.Swift-Shift", category: "ShortcutsManager")
  private let watchdogInterval: TimeInterval = 30
  private let staleTransientStateThreshold: TimeInterval = 30
  private let stateLock = NSLock()
  private(set) var activeShortcuts: [ShortcutType: Bool] = [:]
  private var mouseSubscriptions: Set<String> = []
  private var lifecycleObservers: [Any] = []
  private var watchdogTimer: DispatchSourceTimer?
  private var lastInteractionTime = ProcessInfo.processInfo.systemUptime
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
    registerForLifecycleNotifications()
    startWatchdog()
    updateGlobalShortcuts()
  }
  
  deinit {
    stopWatchdog()
    unregisterForLifecycleNotifications()
  }
  
  private func registerForLifecycleNotifications() {
    let notificationCenter = NSWorkspace.shared.notificationCenter
    let names: [NSNotification.Name] = [
      NSWorkspace.activeSpaceDidChangeNotification,
      NSWorkspace.willSleepNotification,
      NSWorkspace.didWakeNotification,
      NSWorkspace.sessionDidResignActiveNotification,
      NSWorkspace.sessionDidBecomeActiveNotification,
    ]

    for name in names {
      let observer = notificationCenter.addObserver(
        forName: name,
        object: nil,
        queue: .main) { [weak self] _ in
          self?.handleLifecycleReset(name)
        }
      lifecycleObservers.append(observer)
    }
  }
  
  private func unregisterForLifecycleNotifications() {
    let notificationCenter = NSWorkspace.shared.notificationCenter
    for observer in lifecycleObservers {
      notificationCenter.removeObserver(observer)
    }
    lifecycleObservers.removeAll()
  }

  private func startWatchdog() {
    stopWatchdog()
    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now() + watchdogInterval, repeating: watchdogInterval, leeway: .seconds(1))
    timer.setEventHandler { [weak self] in
      self?.runWatchdog()
    }
    timer.resume()
    watchdogTimer = timer
  }

  private func stopWatchdog() {
    watchdogTimer?.setEventHandler {}
    watchdogTimer?.cancel()
    watchdogTimer = nil
  }

  private func handleLifecycleReset(_ name: NSNotification.Name) {
    hardResetInputState(reason: name.rawValue)
  }

  private func runWatchdog() {
    guard hasTransientState else { return }
    guard ProcessInfo.processInfo.systemUptime - lastInteractionTime >= staleTransientStateThreshold else { return }
    hardResetInputState(reason: "watchdog_stale_state")
  }
  
  func cleanupAllShortcuts() {
    hardResetInputState(reason: "terminate")
    removeModifierOnlySubscribers()
    removeAllActions()
    stopWatchdog()
    unregisterForLifecycleNotifications()
  }
  
  func save(_ userShortcut: UserShortcut, refreshShortcuts: Bool = true) {
    do {
      if let shortcut = userShortcut.shortcut {
        let data = try NSKeyedArchiver.archivedData(withRootObject: shortcut, requiringSecureCoding: false)
        UserDefaults.standard.set(data, forKey: userShortcut.type.rawValue)
        UserDefaults.standard.set(userShortcut.mouseButton.rawValue, forKey: "\(userShortcut.type.rawValue)_mouseButton")
      }
    } catch {
      print("Error: \(error)")
    }
    if refreshShortcuts {
      updateGlobalShortcuts()
    }
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
  
  func delete(for type: ShortcutType, refreshShortcuts: Bool = true) {
    UserDefaults.standard.removeObject(forKey: type.rawValue)
    UserDefaults.standard.removeObject(forKey: "\(type.rawValue)_mouseButton")
    if refreshShortcuts {
      updateGlobalShortcuts()
    }
  }
  
  func removeClickActionsForAll() {
    for type in ShortcutType.allCases {
      if var userShortcut = load(for: type) {
        userShortcut.mouseButton = .none
        save(userShortcut, refreshShortcuts: false)
      }
    }
    updateGlobalShortcuts()
  }
  
  private func clearActionsAndMonitors() {
    hardResetInputState(reason: "shortcut_refresh")
    removeModifierOnlySubscribers()
    removeAllActions()
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
    
    let keydownAction = ShortcutAction(shortcut: shortcut) { [weak self] _ in
      DispatchQueue.main.async {
        guard let self = self else { return }
        guard self.activeShortcuts[userShortcut.type] != true else { return }
        self.activeShortcuts[userShortcut.type] = true
        self.touchInteraction()
        self.startTracking(userShortcut, mouseAction)
      }
      return true
    }
    
    let keyupAction = ShortcutAction(shortcut: shortcut) { [weak self] _ in
      DispatchQueue.main.async {
        guard let self = self else { return }
        self.touchInteraction()
        self.stopTracking(userShortcut, mouseAction)
      }
      return true
    }
    
    AppDelegate.shared.shortcutMonitor?.addAction(keydownAction, forKeyEvent: .down)
    AppDelegate.shared.shortcutMonitor?.addAction(keyupAction, forKeyEvent: .up)
  }
  
  private func updateGlobalShortcuts() {
    clearActionsAndMonitors()
    stateLock.lock()
    modifierOnlyShortcuts.removeAll()
    stateLock.unlock()
    
    for type in ShortcutType.allCases {
      if let userShortcut = load(for: type), let shortcut = userShortcut.shortcut {
        let mouseAction = action(for: type)
        let isModifierOnlyShortcut = shortcut.charactersIgnoringModifiers == nil
        
        if isModifierOnlyShortcut {
          stateLock.lock()
          modifierOnlyShortcuts[type] = userShortcut
          stateLock.unlock()
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
        guard let self = self else { return }
        event.cancel()
        let location = event.location
        DispatchQueue.main.async {
          self.touchInteraction()
          MouseTracker.shared.startTracking(
            for: action,
            button: userShortcut.mouseButton,
            triggerLocation: NSPoint(x: location.x, y: location.y)
          )
        }
      })
    
    CGEventSupervisor.shared.subscribe(
      as: upKey,
      to: .cgEvents(upEvent),
      using: { [weak self] event in
        guard let self = self else { return }
        event.cancel()
        DispatchQueue.main.async {
          self.touchInteraction()
          self.stopTracking(userShortcut, action)
        }
      })
    
    mouseSubscriptions.insert(downKey)
    mouseSubscriptions.insert(upKey)
  }
  
  private func stopTracking(_ userShortcut: UserShortcut, _ action: MouseAction) {
    MouseTracker.shared.stopTracking(for: action)
    cleanupMouseSubscriptions(action: action)
    activeShortcuts[userShortcut.type] = false
    touchInteraction()
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
          DispatchQueue.main.async {
            self?.handleModifierFlagsChanged(event)
          }
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
          DispatchQueue.main.async {
            self?.handleModifierKeyEvent(event)
          }
        })
    }
  }

  private func removeModifierOnlySubscribers() {
    CGEventSupervisor.shared.cancel(subscriber: modifierFlagsSubscriber)
    CGEventSupervisor.shared.cancel(subscriber: modifierMouseSubscriber)
    CGEventSupervisor.shared.cancel(subscriber: modifierKeysSubscriber)
    stateLock.lock()
    modifierOnlyShortcuts.removeAll()
    suppressedMouseButton = nil
    activeModifierTrackingType = nil
    stateLock.unlock()
  }

  private func handleModifierFlagsChanged(_ event: NSEvent) {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    let shortcuts = modifierOnlyShortcutSnapshot()

    for (type, userShortcut) in shortcuts where userShortcut.mouseButton == .none {
      guard let shortcut = userShortcut.shortcut else { continue }

      let matchesShortcut = flags == shortcut.modifierFlags
      let isActive = activeShortcuts[type] ?? false
      let action = action(for: type)

      if matchesShortcut && !isActive {
        activeShortcuts[type] = true
        touchInteraction()
        MouseTracker.shared.startTracking(for: action, button: .none)
      } else if !matchesShortcut && isActive {
        MouseTracker.shared.stopTracking(for: action)
        activeShortcuts[type] = false
        touchInteraction()
      }
    }

    let activeType = activeModifierTrackingTypeSnapshot()
    guard let activeType, let shortcut = shortcuts[activeType]?.shortcut, flags != shortcut.modifierFlags else { return }

    stopActiveModifierTracking()
  }

  private func handleModifierKeyEvent(_ event: NSEvent) {
    guard event.type == .keyDown || event.type == .keyUp else { return }
    guard (36...126).contains(event.keyCode) else { return }

    for (type, userShortcut) in modifierOnlyShortcutSnapshot() where userShortcut.mouseButton == .none {
      guard activeShortcuts[type] == true else { continue }
      MouseTracker.shared.stopTracking(for: action(for: type))
      activeShortcuts[type] = false
      touchInteraction()
    }
  }

  private func handleModifierMouseEvent(_ event: CGEvent) {
    guard let mouseButton = mouseButton(for: event.type) else { return }
    let shortcuts = modifierOnlyShortcutSnapshot()

    switch event.type {
    case .leftMouseDown, .rightMouseDown:
      guard activeModifierTrackingTypeSnapshot() == nil else { return }
      guard let shortcut = matchingModifierShortcut(in: shortcuts, for: mouseButton, flags: eventModifierFlags(event)) else { return }

      event.cancel()
      let location = event.location
      DispatchQueue.main.async { [weak self] in
        self?.beginModifierTracking(shortcut, mouseButton: mouseButton, location: NSPoint(x: location.x, y: location.y))
      }

    case .leftMouseUp, .rightMouseUp:
      guard mouseButton == suppressedMouseButtonSnapshot() else { return }

      event.cancel()
      DispatchQueue.main.async { [weak self] in
        self?.touchInteraction()
        self?.clearSuppressedMouseButton()
        self?.stopActiveModifierTracking()
      }

    default:
      break
    }
  }

  private func stopActiveModifierTracking() {
    guard let type = activeModifierTrackingTypeSnapshot() else { return }

    MouseTracker.shared.stopTracking(for: action(for: type))
    activeShortcuts[type] = false
    stateLock.lock()
    activeModifierTrackingType = nil
    stateLock.unlock()
    touchInteraction()
  }

  private func action(for type: ShortcutType) -> MouseAction {
    type == .move ? .move : .resize
  }

  private func matchingModifierShortcut(in shortcuts: [ShortcutType: UserShortcut], for mouseButton: MouseButton, flags: NSEvent.ModifierFlags) -> UserShortcut? {
    shortcuts.values.first(where: {
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

  private func beginModifierTracking(_ shortcut: UserShortcut, mouseButton: MouseButton, location: NSPoint) {
    guard activeModifierTrackingTypeSnapshot() == nil else { return }
    stateLock.lock()
    suppressedMouseButton = mouseButton
    activeModifierTrackingType = shortcut.type
    stateLock.unlock()
    activeShortcuts[shortcut.type] = true
    touchInteraction()
    MouseTracker.shared.startTracking(
      for: action(for: shortcut.type),
      button: mouseButton,
      modifierFlags: shortcut.shortcut?.modifierFlags,
      triggerLocation: location
    )
  }

  func hardResetInputState(reason: String) {
    guard hasTransientState else { return }
    ShortcutsManager.logger.notice("Reset input state after \(reason, privacy: .public)")
    MouseTracker.shared.hardReset(reason: reason)
    cleanupAllMouseSubscriptions()
    stateLock.lock()
    activeModifierTrackingType = nil
    suppressedMouseButton = nil
    stateLock.unlock()
    for type in ShortcutType.allCases {
      activeShortcuts[type] = false
    }
    touchInteraction()
  }

  private var hasTransientState: Bool {
    activeShortcuts.values.contains(true) || !mouseSubscriptions.isEmpty || activeModifierTrackingTypeSnapshot() != nil || suppressedMouseButtonSnapshot() != nil || MouseTracker.shared.hasResidualInfrastructure
  }

  private func touchInteraction() {
    lastInteractionTime = ProcessInfo.processInfo.systemUptime
  }

  private func modifierOnlyShortcutSnapshot() -> [ShortcutType: UserShortcut] {
    stateLock.lock()
    let snapshot = modifierOnlyShortcuts
    stateLock.unlock()
    return snapshot
  }

  private func activeModifierTrackingTypeSnapshot() -> ShortcutType? {
    stateLock.lock()
    let snapshot = activeModifierTrackingType
    stateLock.unlock()
    return snapshot
  }

  private func suppressedMouseButtonSnapshot() -> MouseButton? {
    stateLock.lock()
    let snapshot = suppressedMouseButton
    stateLock.unlock()
    return snapshot
  }

  private func clearSuppressedMouseButton() {
    stateLock.lock()
    suppressedMouseButton = nil
    stateLock.unlock()
  }
}
