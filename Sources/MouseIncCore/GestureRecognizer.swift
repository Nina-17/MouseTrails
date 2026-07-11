import Foundation

public struct GestureRecognizer: Sendable {
    public var simplificationTolerance: Double
    public var minimumGestureLength: Double

    public init(simplificationTolerance: Double = 18, minimumGestureLength: Double = 40) {
        self.simplificationTolerance = simplificationTolerance
        self.minimumGestureLength = minimumGestureLength
    }

    public func recognize(_ points: [CGPoint]) -> String? {
        guard points.count >= 2, pathLength(points) >= minimumGestureLength else {
            return nil
        }

        let simplified = simplify(points, tolerance: simplificationTolerance)
        guard simplified.count >= 2 else { return nil }

        var directions: [Direction] = []
        for pair in zip(simplified, simplified.dropFirst()) {
            guard distance(pair.0, pair.1) >= max(4, simplificationTolerance * 0.5) else {
                continue
            }
            let direction = Direction(from: pair.0, to: pair.1)
            if directions.last != direction {
                directions.append(direction)
            }
        }

        guard !directions.isEmpty else { return nil }
        return directions.map(\.rawValue).joined(separator: "-")
    }

    private func pathLength(_ points: [CGPoint]) -> Double {
        zip(points, points.dropFirst()).reduce(0) { partial, pair in
            partial + distance(pair.0, pair.1)
        }
    }

    private func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> Double {
        hypot(rhs.x - lhs.x, rhs.y - lhs.y)
    }

    private func simplify(_ points: [CGPoint], tolerance: Double) -> [CGPoint] {
        guard points.count > 2 else { return points }

        let first = points[0]
        let last = points[points.count - 1]
        var maximumDistance = 0.0
        var splitIndex = 0

        for index in 1..<(points.count - 1) {
            let currentDistance = perpendicularDistance(points[index], from: first, to: last)
            if currentDistance > maximumDistance {
                maximumDistance = currentDistance
                splitIndex = index
            }
        }

        if maximumDistance <= tolerance {
            return [first, last]
        }

        let left = simplify(Array(points[0...splitIndex]), tolerance: tolerance)
        let right = simplify(Array(points[splitIndex...]), tolerance: tolerance)
        return left.dropLast() + right
    }

    private func perpendicularDistance(_ point: CGPoint, from start: CGPoint, to end: CGPoint) -> Double {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let denominator = hypot(dx, dy)

        guard denominator > 0 else {
            return distance(point, start)
        }

        let numerator = abs(dy * point.x - dx * point.y + end.x * start.y - end.y * start.x)
        return numerator / denominator
    }
}

private enum Direction: String {
    case up = "UP"
    case down = "DOWN"
    case left = "LEFT"
    case right = "RIGHT"
    case upLeft = "UP_LEFT"
    case upRight = "UP_RIGHT"
    case downLeft = "DOWN_LEFT"
    case downRight = "DOWN_RIGHT"

    init(from start: CGPoint, to end: CGPoint) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let absoluteX = abs(dx)
        let absoluteY = abs(dy)
        let minorToMajorRatio = min(absoluteX, absoluteY) / max(absoluteX, absoluteY)

        // tan(22.5°): values within 22.5° of a cardinal axis remain
        // cardinal; the middle 45° sectors become diagonal directions.
        if minorToMajorRatio >= 0.414_213_562_37 {
            switch (dx >= 0, dy >= 0) {
            case (true, true): self = .upRight
            case (false, true): self = .upLeft
            case (true, false): self = .downRight
            case (false, false): self = .downLeft
            }
        } else if absoluteX >= absoluteY {
            self = dx >= 0 ? .right : .left
        } else {
            self = dy >= 0 ? .up : .down
        }
    }
}
