import Cocoa
import Foundation
import ObjectiveC
import OSLog

enum EventTapRecoveryPolicy {
    static func shouldReenableTap(for eventType: CGEventType) -> Bool {
        eventType == .tapDisabledByTimeout || eventType == .tapDisabledByUserInput
    }
}

final class CGEventSupervisor {
    static let shared = CGEventSupervisor()

    typealias NSEventCallback = (_ event: NSEvent) -> Void
    typealias CGEventCallback = (_ event: CGEvent) -> Void
    typealias NSEventSubscriber = (callback: NSEventCallback, events: [CGEventType])
    typealias CGEventSubscriber = (callback: CGEventCallback, events: [CGEventType])

    struct EventDescriptor<T>: RawRepresentable {
        var rawValue: [CGEventType]
    }

    private static let logger = Logger(subsystem: "com.pablopunk.Swift-Shift", category: "EventSupervisor")
    private var eventTapMachPort: CFMachPort?
    private var eventTapRunLoopSource: CFRunLoopSource?
    private var nsEventSubscribers: [String: NSEventSubscriber] = [:]
    private var cgEventSubscribers: [String: CGEventSubscriber] = [:]

    var subscribedEvents: [CGEventType] {
        var allEvents = nsEventSubscribers.values.flatMap { $0.events }
        allEvents.append(contentsOf: cgEventSubscribers.values.flatMap { $0.events })

        var uniqueEvents: [CGEventType] = []
        for event in allEvents where !uniqueEvents.contains(event) {
            uniqueEvents.append(event)
        }
        return uniqueEvents
    }

    var totalSubscribers: Int {
        nsEventSubscribers.count + cgEventSubscribers.count
    }

    func subscribe(
        as subscriber: String,
        to events: EventDescriptor<NSEvent.EventType>,
        using callback: @escaping NSEventCallback
    ) {
        guard !events.rawValue.isEmpty else { return }
        let previousMask = eventMask
        let previousOptions = eventTapOptions
        nsEventSubscribers[subscriber] = (callback, events.rawValue)
        if previousMask != eventMask || previousOptions != eventTapOptions || eventTapMachPort == nil {
            setup()
        }
    }

    func subscribe(
        as subscriber: String,
        to events: EventDescriptor<CGEventType>,
        using callback: @escaping CGEventCallback
    ) {
        guard !events.rawValue.isEmpty else { return }
        let previousMask = eventMask
        let previousOptions = eventTapOptions
        cgEventSubscribers[subscriber] = (callback, events.rawValue)
        if previousMask != eventMask || previousOptions != eventTapOptions || eventTapMachPort == nil {
            setup()
        }
    }

    func cancel(subscriber: String) {
        let previousMask = eventMask
        let previousOptions = eventTapOptions

        nsEventSubscribers.removeValue(forKey: subscriber)
        cgEventSubscribers.removeValue(forKey: subscriber)

        if previousMask != eventMask || previousOptions != eventTapOptions {
            setup()
        }
    }

    func cancelAll() {
        cgEventSubscribers.removeAll()
        nsEventSubscribers.removeAll()
        teardown()
    }

    fileprivate func handleEventTapDisabled(_ eventType: CGEventType) {
        guard EventTapRecoveryPolicy.shouldReenableTap(for: eventType) else { return }
        if let eventTapMachPort {
            CGEvent.tapEnable(tap: eventTapMachPort, enable: true)
            CGEventSupervisor.logger.notice("Re-enabled shortcut event tap after \(String(describing: eventType), privacy: .public)")
        } else {
            setup()
        }
    }

    fileprivate func dispatch(_ event: CGEvent, eventType: CGEventType) -> Bool {
        for subscriber in cgEventSubscribers.values where subscriber.events.contains(eventType) {
            subscriber.callback(event)
            if event.supervisorShouldCancel { return false }
        }

        if eventType.rawValue > 0,
           eventType.rawValue <= CGEventType.otherMouseDragged.rawValue,
           !nsEventSubscribers.isEmpty,
           let nsEvent = NSEvent(cgEvent: event) {
            for subscriber in nsEventSubscribers.values where subscriber.events.contains(eventType) {
                subscriber.callback(nsEvent)
                if nsEvent.supervisorShouldCancel { return false }
            }
        }

        return true
    }

    private func setup() {
        teardown()
        guard totalSubscribers > 0 else { return }

        guard let eventTapMachPort = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: eventTapOptions,
            eventsOfInterest: eventMask,
            callback: eventSupervisorCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            CGEventSupervisor.logger.error("Could not allocate shortcut event tap")
            return
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTapMachPort, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTapMachPort, enable: true)

        self.eventTapMachPort = eventTapMachPort
        eventTapRunLoopSource = runLoopSource
    }

    private func teardown() {
        if let eventTapMachPort {
            CGEvent.tapEnable(tap: eventTapMachPort, enable: false)
            if let eventTapRunLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), eventTapRunLoopSource, .commonModes)
            }
            CFMachPortInvalidate(eventTapMachPort)
        }

        eventTapMachPort = nil
        eventTapRunLoopSource = nil
    }

    private var eventMask: CGEventMask {
        CGEventMask(subscribedEvents.reduce(0) {
            $0 | (1 << $1.rawValue)
        })
    }

    private var eventTapOptions: CGEventTapOptions {
        // NSEvent subscribers observe flags and keys. Only CGEvent subscribers cancel clicks.
        cgEventSubscribers.isEmpty ? .listenOnly : .defaultTap
    }
}

extension CGEventSupervisor.EventDescriptor where T == CGEventType {
    static func cgEvents(_ events: CGEventType...) -> Self {
        .init(rawValue: events)
    }
}

extension CGEventSupervisor.EventDescriptor where T == NSEvent.EventType {
    static func nsEvents(_ events: UniversalEventType...) -> Self {
        .init(rawValue: events.compactMap { CGEventType(rawValue: $0.rawValue) })
    }

    enum UniversalEventType: UInt32 {
        case leftMouseDown = 1
        case leftMouseUp = 2
        case rightMouseDown = 3
        case rightMouseUp = 4
        case mouseMoved = 5
        case leftMouseDragged = 6
        case rightMouseDragged = 7
        case keyDown = 10
        case keyUp = 11
        case flagsChanged = 12
        case scrollWheel = 22
        case tabletPointer = 23
        case tabletProximity = 24
        case otherMouseDown = 25
        case otherMouseUp = 26
        case otherMouseDragged = 27
    }
}

private func eventSupervisorCallback(
    _ eventTap: CGEventTapProxy,
    _ eventType: CGEventType,
    _ event: CGEvent,
    _ userData: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userData else {
        return Unmanaged.passUnretained(event)
    }

    let supervisor = Unmanaged<CGEventSupervisor>
        .fromOpaque(userData)
        .takeUnretainedValue()

    if EventTapRecoveryPolicy.shouldReenableTap(for: eventType) {
        supervisor.handleEventTapDisabled(eventType)
        return Unmanaged.passUnretained(event)
    }

    return supervisor.dispatch(event, eventType: eventType)
        ? Unmanaged.passUnretained(event)
        : nil
}

private var supervisedCGEventShouldCancelKey: UInt8 = 0
private var supervisedNSEventShouldCancelKey: UInt8 = 0

extension CGEvent {
    fileprivate var supervisorShouldCancel: Bool {
        get {
            objc_getAssociatedObject(self, &supervisedCGEventShouldCancelKey) as? Bool ?? false
        }
        set {
            objc_setAssociatedObject(
                self,
                &supervisedCGEventShouldCancelKey,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }

    func cancel() {
        supervisorShouldCancel = true
    }
}

extension NSEvent {
    fileprivate var supervisorShouldCancel: Bool {
        get {
            objc_getAssociatedObject(self, &supervisedNSEventShouldCancelKey) as? Bool ?? false
        }
        set {
            objc_setAssociatedObject(
                self,
                &supervisedNSEventShouldCancelKey,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }

    func cancel() {
        supervisorShouldCancel = true
    }
}
