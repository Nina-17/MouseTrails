import Foundation

public struct EdgeScrollOptions: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var inset: Double
    public var step: Double
    public var cooldown: TimeInterval

    public init(enabled: Bool = false, inset: Double = 2, step: Double = 0.05, cooldown: TimeInterval = 0.08) {
        self.enabled = enabled
        self.inset = inset
        self.step = step
        self.cooldown = cooldown
    }
}

public enum ScreenEdge: String, Codable, CaseIterable, Sendable {
    case top
    case bottom
    case left
    case right
}

public struct EdgeScrollDetector: Sendable {
    public var inset: CGFloat

    public init(inset: CGFloat = 2) {
        self.inset = max(0, inset)
    }

    public func edge(at point: CGPoint, in screens: [CGRect]) -> ScreenEdge? {
        guard let screen = screens.first(where: { $0.contains(point) }) else { return nil }
        let distances: [(ScreenEdge, CGFloat)] = [
            (.top, screen.maxY - point.y),
            (.bottom, point.y - screen.minY),
            (.left, point.x - screen.minX),
            (.right, screen.maxX - point.x)
        ]
        return distances
            .filter { $0.1 <= inset }
            .min { $0.1 < $1.1 }?
            .0
    }
}

public struct EdgeScrollCooldown: Sendable {
    public var interval: TimeInterval
    private var lastFireTime: [ScreenEdge: TimeInterval] = [:]

    public init(interval: TimeInterval = 0.6) {
        self.interval = max(0, interval)
    }

    public mutating func shouldFire(edge: ScreenEdge, now: TimeInterval) -> Bool {
        guard now.isFinite else { return false }
        if let previous = lastFireTime[edge], now - previous < interval { return false }
        lastFireTime[edge] = now
        return true
    }
}
