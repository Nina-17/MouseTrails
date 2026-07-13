import Foundation

public enum RectangleGestureDirection: String, Sendable {
    case clockwise = "SQUARE_CLOCKWISE"
    case counterclockwise = "SQUARE_COUNTERCLOCKWISE"
}

/// Recognizes three- or four-sided box gestures from their overall travel
/// structure. Corners may be broad curves; closure and exact right angles are
/// intentionally not required.
public struct RectangleGestureRecognizer: Sendable {
    public init() {}

    public func recognize(_ points: [CGPoint]) -> RectangleGestureDirection? {
        guard let sampled = resample(points, count: 64) else { return nil }
        let bounds = sampled.reduce(CGRect.null) {
            $0.union(CGRect(origin: $1, size: .zero))
        }
        guard bounds.width > 0, bounds.height > 0,
              min(bounds.width, bounds.height) / max(bounds.width, bounds.height) >= 0.1 else {
            return nil
        }

        let normalized = sampled.map {
            CGPoint(
                x: ($0.x - bounds.minX) / bounds.width,
                y: ($0.y - bounds.minY) / bounds.height
            )
        }

        guard coveredSideCount(normalized) >= 3,
              perimeterResidence(normalized) >= 0.65,
              orthogonalTrend(normalized) >= 0.15 else {
            return nil
        }

        return signedArea(normalized) < 0 ? .clockwise : .counterclockwise
    }

    private func coveredSideCount(_ points: [CGPoint]) -> Int {
        let tolerance = 0.28
        var coordinates = Array(repeating: [Double](), count: 4)
        for point in points {
            let distances = [point.y, 1 - point.x, 1 - point.y, point.x]
            guard let side = distances.indices.min(by: { distances[$0] < distances[$1] }),
                  distances[side] <= tolerance else { continue }
            coordinates[side].append(side.isMultiple(of: 2) ? point.x : point.y)
        }
        return coordinates.filter { values in
            guard values.count >= 4, let minimum = values.min(), let maximum = values.max() else {
                return false
            }
            return maximum - minimum >= 0.42
        }.count
    }

    private func perimeterResidence(_ points: [CGPoint]) -> Double {
        let nearCount = points.filter { point in
            [point.x, 1 - point.x, point.y, 1 - point.y].min()! <= 0.28
        }.count
        return Double(nearCount) / Double(points.count)
    }

    /// Fourfold tangent coherence is high when movement follows two broad,
    /// perpendicular trends, regardless of rotation. Curved corners merely
    /// lower the score instead of failing an angle check.
    private func orthogonalTrend(_ points: [CGPoint]) -> Double {
        var cosine = 0.0
        var sine = 0.0
        var totalWeight = 0.0
        for (start, end) in zip(points, points.dropFirst()) {
            let dx = end.x - start.x
            let dy = end.y - start.y
            let weight = hypot(dx, dy)
            guard weight > 0 else { continue }
            let angle = atan2(dy, dx) * 4
            cosine += cos(angle) * weight
            sine += sin(angle) * weight
            totalWeight += weight
        }
        guard totalWeight > 0 else { return 0 }
        return hypot(cosine, sine) / totalWeight
    }

    private func signedArea(_ points: [CGPoint]) -> Double {
        zip(points, points.dropFirst() + [points[0]]).reduce(0) { area, pair in
            area + pair.0.x * pair.1.y - pair.1.x * pair.0.y
        } / 2
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
