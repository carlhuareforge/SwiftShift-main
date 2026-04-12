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

        let bottomRight = DragGeometry.quadrantResize(
            initialOrigin: NSPoint(x: 100, y: 200),
            initialSize: CGSize(width: 500, height: 400),
            initialPointer: NSPoint(x: 600, y: 600),
            currentPointer: NSPoint(x: 650, y: 560),
            quadrant: .bottomRight
        )
        assert(bottomRight.origin == NSPoint(x: 100, y: 200), "Bottom-right resize should keep the top-left anchored")
        assert(bottomRight.size == CGSize(width: 550, height: 360), "Bottom-right resize should change width and height with pointer deltas")

        let bottom = DragGeometry.quadrantResize(
            initialOrigin: NSPoint(x: 100, y: 200),
            initialSize: CGSize(width: 500, height: 400),
            initialPointer: NSPoint(x: 350, y: 600),
            currentPointer: NSPoint(x: 350, y: 550),
            quadrant: .bottom
        )
        assert(bottom.origin == NSPoint(x: 100, y: 200), "Bottom-edge resize should keep the top edge anchored")
        assert(bottom.size == CGSize(width: 500, height: 350), "Bottom-edge resize should only change height")

        let bottomLeft = DragGeometry.quadrantResize(
            initialOrigin: NSPoint(x: 100, y: 200),
            initialSize: CGSize(width: 500, height: 400),
            initialPointer: NSPoint(x: 100, y: 600),
            currentPointer: NSPoint(x: 160, y: 650),
            quadrant: .bottomLeft
        )
        assert(bottomLeft.origin == NSPoint(x: 160, y: 200), "Bottom-left resize should keep the top-right corner anchored vertically")
        assert(bottomLeft.size == CGSize(width: 440, height: 450), "Bottom-left resize should move the left edge and bottom edge only")

        let top = DragGeometry.quadrantResize(
            initialOrigin: NSPoint(x: 100, y: 200),
            initialSize: CGSize(width: 500, height: 400),
            initialPointer: NSPoint(x: 350, y: 200),
            currentPointer: NSPoint(x: 350, y: 260),
            quadrant: .top
        )
        assert(top.origin == NSPoint(x: 100, y: 260), "Top-edge resize should move the top edge while keeping the bottom anchored")
        assert(top.size == CGSize(width: 500, height: 340), "Top-edge resize should shrink height when dragged downward")

        let detectedBottomRight = DragGeometry.quadrant(
            mouseLocation: NSPoint(x: 590, y: 590),
            windowOrigin: NSPoint(x: 100, y: 200),
            windowSize: CGSize(width: 500, height: 400)
        )
        assert(detectedBottomRight == .bottomRight, "Quadrant detection should not flip bottom-right into a top quadrant")

        let roundedBottomLeft = DragGeometry.roundedQuadrantResize(
            frame: DragGeometry.quadrantResize(
                initialOrigin: NSPoint(x: 100, y: 200),
                initialSize: CGSize(width: 500, height: 400),
                initialPointer: NSPoint(x: 100, y: 600),
                currentPointer: NSPoint(x: 100.5, y: 600),
                quadrant: .bottomLeft
            ),
            initialOrigin: NSPoint(x: 100, y: 200),
            initialSize: CGSize(width: 500, height: 400),
            quadrant: .bottomLeft
        )
        assert(roundedBottomLeft.origin.x + roundedBottomLeft.size.width == 600, "Left-handle rounding should keep the right edge anchored")

        print("drag geometry test passed")
    }
}
