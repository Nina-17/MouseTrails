import Foundation

public struct GestureTemplate: Equatable, Sendable {
    public var identifier: String
    public var points: [CGPoint]

    public init(identifier: String, points: [CGPoint]) {
        self.identifier = identifier
        self.points = points
    }
}

public struct GestureTemplateMatch: Equatable, Sendable {
    public var identifier: String
    public var score: Double

    public init(identifier: String, score: Double) {
        self.identifier = identifier
        self.score = score
    }
}

/// A direction-preserving variant of the $1 recognizer. Paths are resampled,
/// scaled and translated, but are not rotated because gesture orientation is
/// meaningful in MouseIncMac.
public struct GestureTemplateRecognizer: Sendable {
    public var templates: [GestureTemplate]
    public var minimumScore: Double
    public var sampleCount: Int

    public init(
        templates: [GestureTemplate] = GestureTemplate.builtIns,
        minimumScore: Double = 0.78,
        sampleCount: Int = 64
    ) {
        self.templates = templates
        self.minimumScore = minimumScore
        self.sampleCount = max(8, sampleCount)
    }

    public func recognize(_ points: [CGPoint]) -> GestureTemplateMatch? {
        guard let candidate = normalize(points) else { return nil }
        var bestMatch: GestureTemplateMatch?

        for template in templates {
            guard let normalizedTemplate = normalize(template.points) else { continue }
            let forwardScore = score(candidate, normalizedTemplate)
            let reverseScore = score(candidate, normalizedTemplate.reversed())
            let match = GestureTemplateMatch(
                identifier: template.identifier,
                score: max(forwardScore, reverseScore)
            )
            if bestMatch == nil || match.score > bestMatch!.score {
                bestMatch = match
            }
        }

        guard let bestMatch, bestMatch.score >= minimumScore else { return nil }
        return bestMatch
    }

    private func normalize(_ points: [CGPoint]) -> [CGPoint]? {
        guard let sampled = resample(points), sampled.count == sampleCount else { return nil }
        let minimumX = sampled.map(\.x).min() ?? 0
        let maximumX = sampled.map(\.x).max() ?? 0
        let minimumY = sampled.map(\.y).min() ?? 0
        let maximumY = sampled.map(\.y).max() ?? 0
        let width = maximumX - minimumX
        let height = maximumY - minimumY
        guard max(width, height) > 0 else { return nil }

        let scale = max(width, height)
        let scaled = sampled.map {
            CGPoint(x: ($0.x - minimumX) / scale, y: ($0.y - minimumY) / scale)
        }
        let center = scaled.reduce(CGPoint.zero) {
            CGPoint(x: $0.x + $1.x, y: $0.y + $1.y)
        }
        let centroid = CGPoint(
            x: center.x / Double(scaled.count),
            y: center.y / Double(scaled.count)
        )
        return scaled.map { CGPoint(x: $0.x - centroid.x, y: $0.y - centroid.y) }
    }

    private func resample(_ points: [CGPoint]) -> [CGPoint]? {
        guard points.count >= 2 else { return nil }
        let totalLength = pathLength(points)
        guard totalLength > 0 else { return nil }
        let interval = totalLength / Double(sampleCount - 1)
        var result = [points[0]]
        var accumulated = 0.0
        var previous = points[0]

        for current in points.dropFirst() {
            let segmentEnd = current
            var segmentLength = distance(previous, segmentEnd)
            while segmentLength > 0, accumulated + segmentLength >= interval {
                let ratio = (interval - accumulated) / segmentLength
                let inserted = CGPoint(
                    x: previous.x + ratio * (segmentEnd.x - previous.x),
                    y: previous.y + ratio * (segmentEnd.y - previous.y)
                )
                result.append(inserted)
                previous = inserted
                segmentLength = distance(previous, segmentEnd)
                accumulated = 0
                if result.count == sampleCount { return result }
            }
            accumulated += segmentLength
            previous = segmentEnd
        }

        while result.count < sampleCount {
            result.append(points.last!)
        }
        return result
    }

    private func score<S: Collection>(_ lhs: [CGPoint], _ rhs: S) -> Double where S.Element == CGPoint {
        let pairs = zip(lhs, rhs)
        let averageDistance = pairs.reduce(0.0) { $0 + distance($1.0, $1.1) }
            / Double(sampleCount)
        return max(0, 1 - averageDistance / (0.5 * sqrt(2)))
    }

    private func pathLength(_ points: [CGPoint]) -> Double {
        zip(points, points.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
    }

    private func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> Double {
        hypot(rhs.x - lhs.x, rhs.y - lhs.y)
    }
}

public extension GestureTemplate {
    static let builtIns: [GestureTemplate] = [
        GestureTemplate(identifier: "LETTER_S", points: polyline([
            CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1), CGPoint(x: 0, y: 0.5),
            CGPoint(x: 1, y: 0.5), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 0)
        ])),
        GestureTemplate(identifier: "LETTER_W", points: polyline([
            CGPoint(x: 0, y: 1), CGPoint(x: 0.25, y: 0), CGPoint(x: 0.5, y: 0.62),
            CGPoint(x: 0.75, y: 0), CGPoint(x: 1, y: 1)
        ]))
    ]

    private static func arcPoints(from start: Double, to end: Double) -> [CGPoint] {
        (0...64).map { index in
            let angle = start + Double(index) / 64 * (end - start)
            return CGPoint(x: cos(angle), y: sin(angle))
        }
    }

    private static func polyline(_ vertices: [CGPoint]) -> [CGPoint] {
        zip(vertices, vertices.dropFirst()).flatMap { start, end in
            (0..<20).map { index in
                let fraction = Double(index) / 20
                return CGPoint(
                    x: start.x + fraction * (end.x - start.x),
                    y: start.y + fraction * (end.y - start.y)
                )
            }
        } + [vertices.last!]
    }
}
