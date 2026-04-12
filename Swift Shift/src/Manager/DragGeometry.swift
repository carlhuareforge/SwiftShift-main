import Cocoa

enum DragGeometry {
    static func moveOrigin(initialWindowOrigin: NSPoint, initialPointer: NSPoint, currentPointer: NSPoint) -> NSPoint {
        let dx = currentPointer.x - initialPointer.x
        let dy = currentPointer.y - initialPointer.y
        return NSPoint(x: initialWindowOrigin.x + dx, y: initialWindowOrigin.y + dy)
    }

    static func topLeftAnchoredResize(initialSize: CGSize, initialPointer: NSPoint, currentPointer: NSPoint) -> CGSize {
        let dx = currentPointer.x - initialPointer.x
        let dy = currentPointer.y - initialPointer.y
        return CGSize(
            width: max(initialSize.width + dx, 1),
            height: max(initialSize.height + dy, 1)
        )
    }
}
