import MouseIncCore
import SwiftUI

struct GesturePreview: View {
    let identifier: String

    var body: some View {
        GeometryReader { geometry in
            let points = previewPoints
            Path { path in
                guard let first = points.first else { return }
                path.move(to: mapped(first, in: geometry.size, points: points))
                for point in points.dropFirst() {
                    path.addLine(to: mapped(point, in: geometry.size, points: points))
                }
            }
            .stroke(
                Color.accentColor,
                style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
            )
        }
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel("手势轨迹预览 \(identifier)")
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
