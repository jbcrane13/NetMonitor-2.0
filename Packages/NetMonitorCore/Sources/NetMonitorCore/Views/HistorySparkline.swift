import SwiftUI

/// A shared Sparkline view to visualize an array of Double values (e.g., latency, signal strength)
/// Enhanced with vertical gradient "volume" for a more professional instrument feel.
public struct HistorySparkline: View {
    public let data: [Double]
    public let color: Color
    public let lineWidth: CGFloat
    public let showPulse: Bool
    
    public init(data: [Double], color: Color = .green, lineWidth: CGFloat = 2, showPulse: Bool = true) {
        self.data = data
        self.color = color
        self.lineWidth = lineWidth
        self.showPulse = showPulse
    }
    
    public var body: some View {
        GeometryReader { geometry in
            if data.count > 1 {
                let maxVal = data.max() ?? 1
                let minVal = data.min() ?? 0
                let range = maxVal - minVal == 0 ? 1 : maxVal - minVal

                let stepX = geometry.size.width / CGFloat(data.count - 1)

                // Pre-compute points for Catmull-Rom smoothing
                let points: [CGPoint] = data.enumerated().map { i, val in
                    let normalizedVal = CGFloat((val - minVal) / range)
                    let y = geometry.size.height - (normalizedVal * geometry.size.height)
                    let x = CGFloat(i) * stepX
                    return CGPoint(x: x, y: y)
                }

                ZStack {
                    // 1. The Fill (Volume)
                    Path { path in
                        Self.addCatmullRomPath(to: &path, points: points)
                        // Close the path to create a fillable shape
                        path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height))
                        path.addLine(to: CGPoint(x: 0, y: geometry.size.height))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [color.opacity(0.3), color.opacity(0.0)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    // 2. The Line (Stroke)
                    Path { path in
                        Self.addCatmullRomPath(to: &path, points: points)
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                    .shadow(color: color.opacity(0.3), radius: 3, x: 0, y: 0)
                    
                    // 3. The Pulse Node
                    if showPulse, let lastVal = data.last {
                        let normalizedVal = CGFloat((lastVal - minVal) / range)
                        let y = geometry.size.height - (normalizedVal * geometry.size.height)
                        let x = geometry.size.width
                        
                        Circle()
                            .fill(.white)
                            .frame(width: lineWidth * 1.5, height: lineWidth * 1.5)
                            .position(x: x, y: y)
                        
                        Circle()
                            .stroke(color, lineWidth: 1)
                            .frame(width: lineWidth * 4, height: lineWidth * 4)
                            .position(x: x, y: y)
                            .shadow(color: color, radius: 4)
                    }
                }
            } else {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: geometry.size.height / 2))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height / 2))
                }
                .stroke(color.opacity(0.2), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            }
        }
    }

    // MARK: - Catmull-Rom Spline

    /// Converts Catmull-Rom control points to cubic Bézier and adds smooth curves to the path.
    private static func addCatmullRomPath(to path: inout Path, points: [CGPoint]) {
        guard points.count >= 2 else { return }
        path.move(to: points[0])

        if points.count == 2 {
            path.addLine(to: points[1])
            return
        }

        for i in 0..<(points.count - 1) {
            let p0 = i > 0 ? points[i - 1] : points[i]
            let p1 = points[i]
            let p2 = points[i + 1]
            let p3 = i + 2 < points.count ? points[i + 2] : points[i + 1]

            // Catmull-Rom → cubic Bézier control points
            let cp1 = CGPoint(
                x: p1.x + (p2.x - p0.x) / 6,
                y: p1.y + (p2.y - p0.y) / 6
            )
            let cp2 = CGPoint(
                x: p2.x - (p3.x - p1.x) / 6,
                y: p2.y - (p3.y - p1.y) / 6
            )
            path.addCurve(to: p2, control1: cp1, control2: cp2)
        }
    }
}
