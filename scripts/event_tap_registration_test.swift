import AppKit

private struct RegistrationFailure: Error, CustomStringConvertible {
    let description: String
}

@main
struct EventTapRegistrationTest {
    static func main() {
        do {
            try verifyRegistrationLifecycle()
            print("event tap registration test passed")
        } catch {
            fputs("event tap registration test failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func verifyRegistrationLifecycle() throws {
        let supervisor = CGEventSupervisor.shared
        defer { supervisor.cancelAll() }

        let flagsMask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let clicksMask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseUp.rawValue)

        supervisor.subscribe(as: "flags", to: .nsEvents(.flagsChanged), using: { _ in })
        try expectTap(mask: flagsMask, options: .listenOnly)

        // Changing cancellation needs must update the tap even if its mask stays the same.
        supervisor.subscribe(as: "active_flags", to: .cgEvents(.flagsChanged), using: { _ in })
        try expectTap(mask: flagsMask, options: .defaultTap)
        supervisor.cancel(subscriber: "active_flags")
        try expectTap(mask: flagsMask, options: .listenOnly)

        for _ in 0..<12 {
            supervisor.subscribe(as: "clicks", to: .cgEvents(.leftMouseDown, .leftMouseUp), using: { _ in })
            try expectTap(mask: flagsMask | clicksMask, options: .defaultTap)
            supervisor.cancel(subscriber: "clicks")
            try expectTap(mask: flagsMask, options: .listenOnly)
        }

        supervisor.cancelAll()
        guard try processTaps().isEmpty else {
            throw RegistrationFailure(description: "Input hooks remain after cleanup")
        }
    }

    private static func expectTap(mask: CGEventMask, options: CGEventTapOptions) throws {
        let taps = try processTaps()
        guard taps.count == 1, let tap = taps.first else {
            throw RegistrationFailure(description: "Expected one input hook, found \(taps.count)")
        }
        guard tap.eventsOfInterest == mask else {
            throw RegistrationFailure(description: "Input hook still observes events that are no longer needed")
        }
        guard tap.options == options else {
            throw RegistrationFailure(description: "Read-only observers must not block input; expected option \(options.rawValue), got \(tap.options.rawValue)")
        }
    }

    private static func processTaps() throws -> [CGEventTapInformation] {
        var count: UInt32 = 0
        guard CGGetEventTapList(0, nil, &count) == .success else {
            throw RegistrationFailure(description: "Could not count input hooks")
        }
        guard count > 0 else { return [] }
        var taps = Array(repeating: CGEventTapInformation(), count: Int(count))
        guard CGGetEventTapList(count, &taps, &count) == .success else {
            throw RegistrationFailure(description: "Could not read input hooks")
        }
        return taps.prefix(Int(count)).filter { $0.tappingProcess == getpid() }
    }
}
