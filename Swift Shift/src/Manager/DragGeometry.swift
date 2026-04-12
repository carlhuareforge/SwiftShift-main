import Cocoa

enum Quadrant { case topLeft, top, topRight, left, center, right, bottomLeft, bottom, bottomRight }

enum DragGeometry {
    struct ResizeFrame {
        let origin: NSPoint
        let size: CGSize
    }

    private enum HorizontalBehavior { case moveLeft, moveRight, symmetric }
    private enum VerticalBehavior { case moveTop, moveBottom, symmetric }

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

    static func quadrantResize(initialOrigin: NSPoint, initialSize: CGSize, initialPointer: NSPoint, currentPointer: NSPoint, quadrant: Quadrant) -> ResizeFrame {
        let dx = currentPointer.x - initialPointer.x
        let dy = currentPointer.y - initialPointer.y
        let (horizontal, vertical) = behaviors(for: quadrant)

        return resize(
            initialOrigin: initialOrigin,
            initialSize: initialSize,
            dx: dx,
            dy: dy,
            horizontal: horizontal,
            vertical: vertical
        )
    }

    static func quadrant(mouseLocation: NSPoint, windowOrigin: NSPoint, windowSize: CGSize) -> Quadrant {
        let centerFraction: CGFloat = 0.25
        let sideFraction = (1 - centerFraction) / 2
        let leftX = windowOrigin.x + windowSize.width * sideFraction
        let rightX = windowOrigin.x + windowSize.width * (1 - sideFraction)
        let topY = windowOrigin.y + windowSize.height * sideFraction
        let bottomY = windowOrigin.y + windowSize.height * (1 - sideFraction)

        let column: Int
        if mouseLocation.x < leftX {
            column = 0
        } else if mouseLocation.x < rightX {
            column = 1
        } else {
            column = 2
        }

        let row: Int
        if mouseLocation.y < topY {
            row = 0
        } else if mouseLocation.y < bottomY {
            row = 1
        } else {
            row = 2
        }

        switch (row, column) {
        case (0, 0): return .topLeft
        case (0, 1): return .top
        case (0, 2): return .topRight
        case (1, 0): return .left
        case (1, 1): return .center
        case (1, 2): return .right
        case (2, 0): return .bottomLeft
        case (2, 1): return .bottom
        default: return .bottomRight
        }
    }

    static func roundedQuadrantResize(frame: ResizeFrame, initialOrigin: NSPoint, initialSize: CGSize, quadrant: Quadrant) -> ResizeFrame {
        let (horizontal, vertical) = behaviors(for: quadrant)
        let initialLeft = initialOrigin.x
        let initialRight = initialOrigin.x + initialSize.width
        let initialTop = initialOrigin.y
        let initialBottom = initialOrigin.y + initialSize.height

        var left = frame.origin.x
        var right = frame.origin.x + frame.size.width
        var top = frame.origin.y
        var bottom = frame.origin.y + frame.size.height

        switch horizontal {
        case .moveLeft:
            left = left.rounded()
            right = initialRight
        case .moveRight:
            left = initialLeft
            right = right.rounded()
        case .symmetric:
            left = left.rounded()
            right = right.rounded()
        case nil:
            left = initialLeft
            right = initialRight
        }

        switch vertical {
        case .moveTop:
            top = top.rounded()
            bottom = initialBottom
        case .moveBottom:
            top = initialTop
            bottom = bottom.rounded()
        case .symmetric:
            top = top.rounded()
            bottom = bottom.rounded()
        case nil:
            top = initialTop
            bottom = initialBottom
        }

        if right - left < 1 {
            switch horizontal {
            case .moveLeft:
                left = right - 1
            case .moveRight:
                right = left + 1
            case .symmetric:
                let midX = (left + right) / 2
                left = midX - 0.5
                right = midX + 0.5
            case nil:
                break
            }
        }

        if bottom - top < 1 {
            switch vertical {
            case .moveTop:
                top = bottom - 1
            case .moveBottom:
                bottom = top + 1
            case .symmetric:
                let midY = (top + bottom) / 2
                top = midY - 0.5
                bottom = midY + 0.5
            case nil:
                break
            }
        }

        return ResizeFrame(
            origin: NSPoint(x: left, y: top),
            size: CGSize(width: right - left, height: bottom - top)
        )
    }

    private static func resize(initialOrigin: NSPoint, initialSize: CGSize, dx: CGFloat, dy: CGFloat, horizontal: HorizontalBehavior?, vertical: VerticalBehavior?) -> ResizeFrame {
        var left = initialOrigin.x
        var right = initialOrigin.x + initialSize.width
        var top = initialOrigin.y
        var bottom = initialOrigin.y + initialSize.height

        switch horizontal {
        case .moveLeft:
            left += dx
        case .moveRight:
            right += dx
        case .symmetric:
            left -= dx
            right += dx
        case nil:
            break
        }

        switch vertical {
        case .moveTop:
            top += dy
        case .moveBottom:
            bottom += dy
        case .symmetric:
            top -= dy
            bottom += dy
        case nil:
            break
        }

        if right - left < 1 {
            switch horizontal {
            case .moveLeft:
                left = right - 1
            case .moveRight:
                right = left + 1
            case .symmetric:
                let midX = (left + right) / 2
                left = midX - 0.5
                right = midX + 0.5
            case nil:
                break
            }
        }

        if bottom - top < 1 {
            switch vertical {
            case .moveTop:
                top = bottom - 1
            case .moveBottom:
                bottom = top + 1
            case .symmetric:
                let midY = (top + bottom) / 2
                top = midY - 0.5
                bottom = midY + 0.5
            case nil:
                break
            }
        }

        return ResizeFrame(
            origin: NSPoint(x: left, y: top),
            size: CGSize(width: right - left, height: bottom - top)
        )
    }

    private static func behaviors(for quadrant: Quadrant) -> (HorizontalBehavior?, VerticalBehavior?) {
        switch quadrant {
        case .topLeft:
            return (.moveLeft, .moveTop)
        case .top:
            return (nil, .moveTop)
        case .topRight:
            return (.moveRight, .moveTop)
        case .left:
            return (.moveLeft, nil)
        case .center:
            return (.symmetric, .symmetric)
        case .right:
            return (.moveRight, nil)
        case .bottomLeft:
            return (.moveLeft, .moveBottom)
        case .bottom:
            return (nil, .moveBottom)
        case .bottomRight:
            return (.moveRight, .moveBottom)
        }
    }
}
