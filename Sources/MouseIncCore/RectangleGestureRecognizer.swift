import Foundation

/// Recognizes a hand-drawn closed rectangle from scale-independent geometry.
/// It deliberately does not inspect exact corners or compare against a stored
/// template: screenshot gestures only need to follow all four sides reliably.
public struct RectangleGestureRecognizer: Sendable {
    public init() {}

    public func recognizes(_ points: [CGPoint]) -> Bool {
        guard let sampled = resample(points, count: 64) else { return false }
        let bounds = sampled.reduce(CGRect.null) {
            $0.union(CGRect(origin: $1, size: .zero))
        }
        let width = bounds.width
        let height = bounds.height
        guard width > 0, height > 0, min(width, height) / max(width, height) >= 0.12 else {
            return false
        }

        let diagonal = hypot(width, height)
        guard distance(sampled[0], sampled[sampled.count - 1]) / diagonal <= 0.28 else {
            return false
        }

        let normalized = sampled.map {
            CGPoint(x: ($0.x - bounds.minX) / width, y: ($0.y - bounds.minY) / height)
        }
        let normalizedLength = pathLength(normalized)
        let rectanglePerimeter = 4.0
        guard (0.86 ... 1.45).contains(normalizedLength / rectanglePerimeter) else {
            return false
        }

        let sideTolerance = 0.14
        var sideCoordinates = Array(repeating: [Double](), count: 4)
        var pointsNearPerimeter = 0
        for point in normalized {
            let distances = [point.y, 1 - point.x, 1 - point.y, point.x]
            guard let nearest = distances.indices.min(by: { distances[$0] < distances[$1] }) else {
                continue
            }
            if distances[nearest] <= sideTolerance {
                pointsNearPerimeter += 1
                sideCoordinates[nearest].append(nearest.isMultiple(of: 2) ? point.x : point.y)
            }
        }

        guard Double(pointsNearPerimeter) / Double(normalized.count) >= 0.72 else {
            return false
        }
        return sideCoordinates.allSatisfy { coordinates in
            guard let minimum = coordinates.min(), let maximum = coordinates.max() else {
                return false
            }
            return maximum - minimum >= 0.68
        }
    }

    private func resample(_ points: [CGPoint], count: Int) -> [CGPoint]? {
        guard points.count >= 2 else { return nil }
        let totalLength = pathLength(points)
        guard totalLength > 0 else { return nil }
        let interval = totalLength / Double(count - 1)
        var result = [points[0]]
        var accumulated = 0.0
        var previous = points[0]

        for endpoint in points.dropFirst() {
            var segmentLength = distance(previous, endpoint)
            while segmentLength > 0, accumulated + segmentLength >= interval {
                let ratio = (interval - accumulated) / segmentLength
                let inserted = CGPoint(
                    x: previous.x + ratio * (endpoint.x - previous.x),
                    y: previous.y + ratio * (endpoint.y - previous.y)
                )
                result.append(inserted)
                if result.count == count { return result }
                previous = inserted
                segmentLength = distance(previous, endpoint)
                accumulated = 0
            }
            accumulated += segmentLength
            previous = endpoint
        }
        while result.count < count { result.append(points.last!) }
        return result
    }

    private func pathLength(_ points: [CGPoint]) -> Double {
        zip(points, points.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
    }

    private func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> Double {
        hypot(rhs.x - lhs.x, rhs.y - lhs.y)
    }
}
