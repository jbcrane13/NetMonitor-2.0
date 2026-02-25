import SwiftUI

/// A shared Sparkline view to visualize an array of Double values (e.g., latency, signal strength)
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
                
                Path { path in
                    for i in 0..<data.count {
                        let val = data[i]
                        let normalizedVal = CGFloat((val - minVal) / range)
                        let y = geometry.size.height - (normalizedVal * geometry.size.height)
                        let x = CGFloat(i) * stepX
                        
                        if i == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                .shadow(color: color.opacity(0.4), radius: 4, x: 0, y: 0)
                
                if showPulse, let lastVal = data.last {
                    let normalizedVal = CGFloat((lastVal - minVal) / range)
                    let y = geometry.size.height - (normalizedVal * geometry.size.height)
                    let x = geometry.size.width
                    
                    Circle()
                        .fill(color)
                        .frame(width: lineWidth * 3, height: lineWidth * 3)
                        .position(x: x, y: y)
                        .shadow(color: color.opacity(0.8), radius: 6, x: 0, y: 0)
                }
            } else {
                // Not enough data, draw a flat line or nothing
                Path { path in
                    path.move(to: CGPoint(x: 0, y: geometry.size.height / 2))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height / 2))
                }
                .stroke(color.opacity(0.3), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            }
        }
    }
}
