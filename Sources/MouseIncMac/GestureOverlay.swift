import AppKit
import MouseIncCore

@MainActor
final class GestureOverlay {
    private let panel: NSPanel
    private let traceView: GestureTraceView
    private var activeScreen: NSScreen?

    init() {
        traceView = GestureTraceView(frame: .zero)
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = traceView
    }

    var captureWindowID: CGWindowID {
        CGWindowID(panel.windowNumber)
    }

    func show(points: [CGPoint], color: GestureTrailColor) {
        guard points.count > 1, let firstPoint = points.first else {
            hide()
            return
        }
        let screen = screen(containing: firstPoint) ?? NSScreen.main
        guard let screen else { return }

        if activeScreen != screen {
            activeScreen = screen
            panel.setFrame(screen.frame, display: true)
        }

        traceView.points = points.map {
            CGPoint(x: $0.x - screen.frame.minX, y: $0.y - screen.frame.minY)
        }
        traceView.color = color
        traceView.needsDisplay = true
        panel.orderFrontRegardless()
    }

    func hide() {
        traceView.points = []
        traceView.needsDisplay = true
        // Clear the backing surface before hiding the panel. This prevents a
        // one-frame stale trail from being composited into a region capture.
        traceView.displayIfNeeded()
        panel.orderOut(nil)
    }

    private func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
    }
}

@MainActor
private final class GestureTraceView: NSView {
    var points: [CGPoint] = []
    var color: GestureTrailColor = .orange

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard points.count > 1 else { return }

        let path = NSBezierPath()
        path.move(to: points[0])
        for point in points.dropFirst() {
            path.line(to: point)
        }
        path.lineWidth = 4
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        NSColor.black.withAlphaComponent(0.35).setStroke()
        let shadowPath = path.copy() as! NSBezierPath
        shadowPath.lineWidth = 7
        shadowPath.stroke()

        trailNSColor.setStroke()
        path.stroke()
    }

    private var trailNSColor: NSColor {
        NSColor(
            calibratedRed: color.red,
            green: color.green,
            blue: color.blue,
            alpha: color.alpha
        )
    }
}
