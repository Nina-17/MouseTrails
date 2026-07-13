import MouseIncCore
import SwiftUI

struct GesturePreview: View {
    let identifier: String

    var body: some View {
        GeometryReader { geometry in
            let points = previewPoints
            let mappedPoints = points.map { mapped($0, in: geometry.size, points: points) }
            ZStack {
                Path { path in
                    guard let first = mappedPoints.first else { return }
                    path.move(to: first)
                    for point in mappedPoints.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(
                    Color.accentColor,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                )

                directionArrow(for: mappedPoints)
                    .stroke(
                        Color.accentColor,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                    )
            }
        }
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel("手势轨迹预览 \(identifier)")
    }

    private func directionArrow(for points: [CGPoint]) -> Path {
        Path { path in
            guard points.count >= 2, let tip = points.last else { return }
            var previousIndex = points.count - 2
            while previousIndex > 0,
                  hypot(tip.x - points[previousIndex].x, tip.y - points[previousIndex].y) < 0.5 {
                previousIndex -= 1
            }
            let previous = points[previousIndex]
            let angle = atan2(tip.y - previous.y, tip.x - previous.x)
            let length = 8.0
            let spread = Double.pi / 5
            let firstWing = CGPoint(
                x: tip.x - length * cos(angle - spread),
                y: tip.y - length * sin(angle - spread)
            )
            let secondWing = CGPoint(
                x: tip.x - length * cos(angle + spread),
                y: tip.y - length * sin(angle + spread)
            )
            path.move(to: firstWing)
            path.addLine(to: tip)
            path.addLine(to: secondWing)
        }
    }

    private var previewPoints: [CGPoint] {
        switch identifier.uppercased() {
        case "SQUARE_COUNTERCLOCKWISE":
            return [
                CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0),
                CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1), CGPoint(x: 0, y: 0)
            ]
        case "SQUARE_CLOCKWISE":
            return [
                CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 1),
                CGPoint(x: 1, y: 1), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 0)
            ]
        default:
            break
        }
        if let template = GestureTemplate.builtIns.first(where: {
            $0.identifier.caseInsensitiveCompare(identifier) == .orderedSame
        }) {
            return template.points
        }

        var result = [CGPoint.zero]
        for token in identifier.uppercased().split(separator: "-").map(String.init) {
            let delta: CGPoint
            switch token {
            case "UP": delta = CGPoint(x: 0, y: 1)
            case "DOWN": delta = CGPoint(x: 0, y: -1)
            case "LEFT": delta = CGPoint(x: -1, y: 0)
            case "RIGHT": delta = CGPoint(x: 1, y: 0)
            case "UP_LEFT": delta = CGPoint(x: -1, y: 1)
            case "UP_RIGHT": delta = CGPoint(x: 1, y: 1)
            case "DOWN_LEFT": delta = CGPoint(x: -1, y: -1)
            case "DOWN_RIGHT": delta = CGPoint(x: 1, y: -1)
            default: continue
            }
            let last = result.last ?? .zero
            result.append(CGPoint(x: last.x + delta.x, y: last.y + delta.y))
        }
        return result.count > 1 ? result : [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0)]
    }

    private func mapped(_ point: CGPoint, in size: CGSize, points: [CGPoint]) -> CGPoint {
        let minimumX = points.map(\.x).min() ?? 0
        let maximumX = points.map(\.x).max() ?? 1
        let minimumY = points.map(\.y).min() ?? 0
        let maximumY = points.map(\.y).max() ?? 1
        let width = max(maximumX - minimumX, 0.001)
        let height = max(maximumY - minimumY, 0.001)
        let inset = 10.0
        return CGPoint(
            x: inset + (point.x - minimumX) / width * max(0, size.width - inset * 2),
            y: size.height - inset - (point.y - minimumY) / height * max(0, size.height - inset * 2)
        )
    }
}
