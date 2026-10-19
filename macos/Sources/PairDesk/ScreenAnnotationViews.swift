import SwiftUI

struct ScreenAnnotationLayer: View {
    let strokes: [ScreenAnnotationStroke]
    let names: [String: String]
    let contentSize: CGSize

    var body: some View {
        GeometryReader { geometry in
            ForEach(strokes) { stroke in
                Path { path in
                    let points = stroke.points.compactMap { point in
                        ScreenCoordinateMapper.displayedPoint(normalized: CGPoint(x: point.x, y: point.y),
                            container: CGRect(origin: .zero, size: geometry.size), contentSize: contentSize)
                    }
                    guard let first = points.first else { return }
                    if points.count == 1 {
                        path.addEllipse(in: CGRect(x: first.x - 6, y: first.y - 6, width: 12, height: 12))
                        return
                    }
                    path.move(to: first)
                    for point in points.dropFirst() { path.addLine(to: point) }
                }
                .stroke(Theme.personColor(for: stroke.participantIdentity),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                if let first = stroke.points.first,
                   let point = ScreenCoordinateMapper.displayedPoint(normalized: CGPoint(x: first.x, y: first.y),
                       container: CGRect(origin: .zero, size: geometry.size), contentSize: contentSize) {
                    Text(names[stroke.participantIdentity] ?? "Teammate")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(Theme.personColor(for: stroke.participantIdentity), in: Capsule())
                        .position(x: min(max(point.x + 34, 34), geometry.size.width - 34),
                                  y: min(max(point.y - 12, 12), geometry.size.height - 12))
                }
            }
        }
    }
}

struct ScreenAnnotationLaserLayer: View {
    let lasers: [ScreenAnnotationLaser]
    let names: [String: String]
    let contentSize: CGSize

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 0.1)) { _ in
                ForEach(lasers.filter { $0.expiresAt > ProcessInfo.processInfo.systemUptime }, id: \.participantIdentity) { laser in
                    if let point = ScreenCoordinateMapper.displayedPoint(
                        normalized: CGPoint(x: laser.point.x, y: laser.point.y),
                        container: CGRect(origin: .zero, size: geometry.size), contentSize: contentSize) {
                        let remaining = max(0, min(1, laser.expiresAt - ProcessInfo.processInfo.systemUptime))
                        let color = Theme.personColor(for: laser.participantIdentity)
                        ZStack {
                            Circle().fill(color.opacity(0.3 * remaining)).frame(width: 34, height: 34)
                            Circle().stroke(color.opacity(remaining), lineWidth: 3).frame(width: 25, height: 25)
                            Circle().fill(color).frame(width: 10, height: 10)
                            Text(names[laser.participantIdentity] ?? "Teammate")
                                .font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
                                .padding(.horizontal, 7).padding(.vertical, 4)
                                .background(color, in: Capsule())
                                .offset(x: 0, y: -28)
                        }
                        .position(point)
                        .allowsHitTesting(false)
                    }
                }
            }
        }
    }
}
