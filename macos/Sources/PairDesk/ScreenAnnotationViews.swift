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
