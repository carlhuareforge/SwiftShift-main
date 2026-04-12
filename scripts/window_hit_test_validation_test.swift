import Cocoa

@main
struct WindowHitTestValidationTest {
    static func main() {
        let mouse = NSPoint(x: 700, y: 220)
        let correctBounds = CGRect(x: 640, y: 160, width: 500, height: 400)
        let wrongFocusedBounds = CGRect(x: 120, y: 140, width: 420, height: 360)

        assert(
            WindowManager.shouldAcceptResolvedWindow(containing: mouse, bounds: correctBounds),
            "A resolved window that contains the pointer should be accepted"
        )
        assert(
            !WindowManager.shouldAcceptResolvedWindow(containing: mouse, bounds: wrongFocusedBounds),
            "A resolved window outside the pointer should be rejected even if it is focused"
        )
        assert(
            !WindowManager.shouldAcceptResolvedWindow(containing: mouse, bounds: nil),
            "A resolved window without geometry should be rejected"
        )

        print("window hit test validation test passed")
    }
}
