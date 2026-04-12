import Cocoa

@main
struct WindowResolutionPreferenceTest {
    static func main() {
        let mouse = NSPoint(x: 320, y: 320)
        let windows = [
            WindowManager.WindowCandidateGeometry(bounds: CGRect(x: 100, y: 100, width: 400, height: 400), isFocused: false),
            WindowManager.WindowCandidateGeometry(bounds: CGRect(x: 250, y: 250, width: 400, height: 400), isFocused: true),
        ]

        let focusedPreferred = WindowManager.preferredContainedWindowIndex(
            containing: mouse,
            matching: CGRect(x: 250, y: 250, width: 400, height: 400),
            windows: windows
        )
        assert(focusedPreferred == 1, "Focused overlapping window should win")

        let geometryPreferred = WindowManager.preferredContainedWindowIndex(
            containing: mouse,
            matching: CGRect(x: 100, y: 100, width: 400, height: 400),
            windows: windows.map { WindowManager.WindowCandidateGeometry(bounds: $0.bounds, isFocused: false) }
        )
        assert(geometryPreferred == 0, "Best geometry match should win when no focused window is available")

        let none = WindowManager.preferredContainedWindowIndex(
            containing: NSPoint(x: 50, y: 50),
            matching: nil,
            windows: windows
        )
        assert(none == nil, "No containing window should produce nil")

        print("window resolution preference test passed")
    }
}
