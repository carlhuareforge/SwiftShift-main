import Cocoa

@main
struct WindowManagerSelectionTest {
    static func main() {
        let entries: [WindowManager.WindowListEntry] = [
            WindowManager.WindowListEntry(pid: 1409, layer: 20, alpha: 1, bounds: CGRect(x: 0, y: 0, width: 3360, height: 1418)),
            WindowManager.WindowListEntry(pid: 73121, layer: 0, alpha: 1, bounds: CGRect(x: 56, y: 67, width: 1650, height: 1046)),
            WindowManager.WindowListEntry(pid: 1398, layer: 0, alpha: 1, bounds: CGRect(x: 7, y: 38, width: 3360, height: 1314)),
            WindowManager.WindowListEntry(pid: 72789, layer: 0, alpha: 1, bounds: CGRect(x: 300, y: 300, width: 200, height: 100)),
            WindowManager.WindowListEntry(pid: 80000, layer: 0, alpha: 0, bounds: CGRect(x: 56, y: 67, width: 1650, height: 1046)),
        ]

        let mouseLocation = NSPoint(x: 600, y: 400)
        let candidates = WindowManager.windowListCandidates(containing: mouseLocation, from: entries, excluding: 72789)

        assert(candidates.map { $0.pid } == [73121, 1398], "Expected layer-0 visible app windows in front-to-back order")
        print("window manager selection test passed")
    }
}
