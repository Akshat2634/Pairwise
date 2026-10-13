import SwiftUI

struct SharedCursorLayer: View {
    let pointers: [RemotePointer]
    let names: [String: String]
    let contentSize: CGSize

    var body: some View {
        GeometryReader { geometry in
            let colors = Theme.distinctPersonColors(for: pointers.map(\.id))
            ForEach(pointers) { pointer in
                if let point = ScreenCoordinateMapper.displayedPoint(normalized: CGPoint(x: pointer.x, y: pointer.y),
                                                                     container: CGRect(origin: .zero, size: geometry.size),
                                                                     contentSize: contentSize) {
                    let color = colors[pointer.id] ?? Theme.personColor(for: pointer.id)
                    CursorArrow().fill(color)
                        .overlay(CursorArrow().stroke(.white.opacity(0.95), lineWidth: 1.3))
                        .frame(width: 18, height: 25)
                        .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                        // The arrow tip, not its center, is the pointer location.
                        .position(x: point.x + 9, y: point.y + 12.5)
                    Text(names[pointer.id] ?? "Teammate")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .frame(maxWidth: 140)
                        .background(color, in: RoundedRectangle(cornerRadius: 5))
                        .fixedSize(horizontal: true, vertical: false)
                        .position(x: min(max(point.x + 58, 70), max(70, geometry.size.width - 70)),
                                  y: min(point.y + 32, geometry.size.height - 12))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct CursorArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let points: [CGPoint] = [.init(x: 0, y: 0), .init(x: 0, y: 19), .init(x: 5, y: 15),
                                 .init(x: 9, y: 25), .init(x: 13, y: 23), .init(x: 9, y: 14),
                                 .init(x: 18, y: 14)]
        path.addLines(points.map { CGPoint(x: $0.x * rect.width / 18, y: $0.y * rect.height / 25) })
        path.closeSubpath()
        return path
    }
}
