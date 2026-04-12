import Cocoa

@main
struct DragGeometryTest {
    static func main() {
        let moved = DragGeometry.moveOrigin(
            initialWindowOrigin: NSPoint(x: 100, y: 200),
            initialPointer: NSPoint(x: 400, y: 300),
            currentPointer: NSPoint(x: 430, y: 360)
        )
        assert(moved == NSPoint(x: 130, y: 260), "Dragging downward should increase window Y in CG-based screen coordinates")

        let resized = DragGeometry.topLeftAnchoredResize(
            initialSize: CGSize(width: 500, height: 400),
            initialPointer: NSPoint(x: 1000, y: 600),
            currentPointer: NSPoint(x: 1120, y: 690)
        )
        assert(resized == CGSize(width: 620, height: 490), "Top-left anchored resize should keep origin fixed and grow width/height with pointer deltas")

        let clamped = DragGeometry.topLeftAnchoredResize(
            initialSize: CGSize(width: 50, height: 50),
            initialPointer: NSPoint(x: 100, y: 100),
            currentPointer: NSPoint(x: -1000, y: -1000)
        )
        assert(clamped == CGSize(width: 1, height: 1), "Resize should clamp to minimum size")

        print("drag geometry test passed")
    }
}
