import Foundation

public struct CustomGestureMatch: Equatable, Sendable {
    public var identifier: String
    public var score: Double
    public var runnerUpScore: Double?

    public init(identifier: String, score: Double, runnerUpScore: Double?) {
        self.identifier = identifier
        self.score = score
        self.runnerUpScore = runnerUpScore
    }
}

public struct CustomGestureRecognizer: Sendable {
    public var definitions: [CustomGestureDefinition]
    public var minimumScore: Double
    public var minimumMargin: Double
    public var minimumPathLength: Double
    public var sampleCount: Int

    public init(
        definitions: [CustomGestureDefinition],
        minimumScore: Double = 0.78,
        minimumMargin: Double = 0.06,
        minimumPathLength: Double = CustomGestureTrainer.minimumPathLength,
        sampleCount: Int = 64
    ) {
        self.definitions = definitions
        self.minimumScore = minimumScore
        self.minimumMargin = minimumMargin
        self.minimumPathLength = max(0, minimumPathLength)
        self.sampleCount = max(8, sampleCount)
    }

    public func recognize(_ points: [CGPoint]) -> CustomGestureMatch? {
        guard GesturePathNormalizer.pathLength(points) >= minimumPathLength,
              let candidate = GesturePathNormalizer.normalize(points, sampleCount: sampleCount) else {
            return nil
        }
        let ranked = definitions.compactMap { definition -> (String, Double)? in
            let bestScore = definition.samples
                .map { $0.map(\.cgPoint) }
                .filter { $0.count == sampleCount }
                .map { GesturePathNormalizer.similarity(candidate, $0) }
                .max()
            guard let bestScore else { return nil }
            return (definition.identifier, bestScore)
        }.sorted { $0.1 > $1.1 }

        guard let best = ranked.first, best.1 >= minimumScore else { return nil }
        let runnerUp = ranked.dropFirst().first?.1
        if let runnerUp, best.1 - runnerUp < minimumMargin { return nil }
        return CustomGestureMatch(
            identifier: best.0,
            score: best.1,
            runnerUpScore: runnerUp
        )
    }
}

public enum CustomGestureTrainingError: Error, Equatable, Sendable {
    case invalidSampleCount
    case invalidSample(Int)
    case inconsistentSamples(Double)
}

public struct CustomGestureTrainingResult: Equatable, Sendable {
    public var definition: CustomGestureDefinition
    public var warnings: [String]
    public var cohesionScore: Double

    public init(
        definition: CustomGestureDefinition,
        warnings: [String],
        cohesionScore: Double
    ) {
        self.definition = definition
        self.warnings = warnings
        self.cohesionScore = cohesionScore
    }
}

public enum CustomGestureTrainer {
    public static let requiredSampleCount = 3
    public static let minimumPathLength = 40.0

    public static func train(
        identifier: String,
        name: String,
        rawSamples: [[CGPoint]],
        existingCustomGestures: [CustomGestureDefinition] = [],
        fixedGestureIdentifiers: Set<String> = [],
        sampleCount: Int = 64
    ) throws -> CustomGestureTrainingResult {
        guard rawSamples.count == requiredSampleCount else {
            throw CustomGestureTrainingError.invalidSampleCount
        }

        var normalizedSamples: [[CGPoint]] = []
        for (index, sample) in rawSamples.enumerated() {
            guard GesturePathNormalizer.pathLength(sample) >= minimumPathLength,
                  let normalized = GesturePathNormalizer.normalize(sample, sampleCount: sampleCount) else {
                throw CustomGestureTrainingError.invalidSample(index)
            }
            normalizedSamples.append(normalized)
        }

        let pairScores = [
            GesturePathNormalizer.similarity(normalizedSamples[0], normalizedSamples[1]),
            GesturePathNormalizer.similarity(normalizedSamples[0], normalizedSamples[2]),
            GesturePathNormalizer.similarity(normalizedSamples[1], normalizedSamples[2])
        ]
        let cohesion = pairScores.min() ?? 0
        guard cohesion >= 0.70 else {
            throw CustomGestureTrainingError.inconsistentSamples(cohesion)
        }

        var warnings: [String] = []
        let fixedMatches = rawSamples.compactMap {
            GestureRecognizer(simplificationTolerance: 18, minimumGestureLength: 40).recognize($0)
        }
        if let first = fixedMatches.first,
           fixedMatches.count == requiredSampleCount,
           fixedMatches.allSatisfy({ $0 == first }),
           fixedGestureIdentifiers.contains(first.uppercased()) {
            warnings.append("轨迹与现有手势 \(first) 接近；现有绑定会优先执行")
        }

        if !existingCustomGestures.isEmpty {
            let probe = CustomGestureRecognizer(
                definitions: existingCustomGestures,
                minimumScore: 0,
                minimumMargin: 0,
                sampleCount: sampleCount
            )
            let highest = rawSamples.compactMap { probe.recognize($0) }.max { $0.score < $1.score }
            if let highest, highest.score >= 0.88 {
                warnings.append("轨迹与已有自定义手势 \(highest.identifier) 接近")
            }
        }

        return CustomGestureTrainingResult(
            definition: CustomGestureDefinition(
                identifier: identifier,
                name: name,
                samples: normalizedSamples.map { $0.map(GestureSamplePoint.init) }
            ),
            warnings: warnings,
            cohesionScore: cohesion
        )
    }
}

enum GesturePathNormalizer {
    static func pathLength(_ points: [CGPoint]) -> Double {
        zip(points, points.dropFirst()).reduce(0.0) {
            $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y)
        }
    }

    static func normalize(_ points: [CGPoint], sampleCount: Int) -> [CGPoint]? {
        guard let sampled = resample(points, sampleCount: sampleCount), sampled.count == sampleCount else {
            return nil
        }
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
        let sum = scaled.reduce(CGPoint.zero) {
            CGPoint(x: $0.x + $1.x, y: $0.y + $1.y)
        }
        let centroid = CGPoint(
            x: sum.x / Double(scaled.count),
            y: sum.y / Double(scaled.count)
        )
        return scaled.map { CGPoint(x: $0.x - centroid.x, y: $0.y - centroid.y) }
    }

    static func similarity(_ lhs: [CGPoint], _ rhs: [CGPoint]) -> Double {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }
        let averageDistance = zip(lhs, rhs).reduce(0.0) {
            $0 + hypot($1.0.x - $1.1.x, $1.0.y - $1.1.y)
        } / Double(lhs.count)
        return max(0, 1 - averageDistance / (0.5 * sqrt(2)))
    }

    private static func resample(_ points: [CGPoint], sampleCount: Int) -> [CGPoint]? {
        guard points.count >= 2 else { return nil }
        let totalLength = pathLength(points)
        guard totalLength > 0 else { return nil }
        let interval = totalLength / Double(sampleCount - 1)
        var result = [points[0]]
        var accumulated = 0.0
        var previous = points[0]

        for current in points.dropFirst() {
            let segmentEnd = current
            var segmentLength = hypot(segmentEnd.x - previous.x, segmentEnd.y - previous.y)
            while segmentLength > 0, accumulated + segmentLength >= interval {
                let ratio = (interval - accumulated) / segmentLength
                let inserted = CGPoint(
                    x: previous.x + ratio * (segmentEnd.x - previous.x),
                    y: previous.y + ratio * (segmentEnd.y - previous.y)
                )
                result.append(inserted)
                previous = inserted
                segmentLength = hypot(segmentEnd.x - previous.x, segmentEnd.y - previous.y)
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
}
