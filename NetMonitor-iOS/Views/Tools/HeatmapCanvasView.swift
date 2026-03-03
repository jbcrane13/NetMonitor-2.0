import SwiftUI
import NetMonitorCore

// MARK: - HeatmapCanvasView

/// The central heatmap rendering canvas. Shared between the scroll-view layout
/// and `HeatmapFullScreenView`. Handles all four overlay layers.
struct HeatmapCanvasView: View {

    let points: [HeatmapDataPoint]
    let floorplanImage: UIImage?
    let colorScheme: HeatmapColorScheme
    let overlays: HeatmapDisplayOverlay
    let calibration: CalibrationScale?
    let isSurveying: Bool
    var onTap: ((CGPoint, CGSize) -> Void)?

    // Pulsing animation for dead zones
    @State private var deadZonePulse: Double = 0.15

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // ── 1. Background (floor plan or grid) ──────────────────────
                backgroundLayer(in: geo.size)

                // ── 2. Gradient heatmap ──────────────────────────────────────
                if overlays.contains(.gradient) {
                    Canvas { ctx, size in
                        drawGradient(context: ctx, size: size)
                    }
                }

                // ── 3. Dead zone highlight (animated) ───────────────────────
                if overlays.contains(.deadZones) {
                    Canvas { ctx, size in
                        drawDeadZones(context: ctx, size: size, opacity: deadZonePulse)
                    }
                    .onAppear {
                        withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                            deadZonePulse = 0.45
                        }
                    }
                }

                // ── 4. Contour lines ─────────────────────────────────────────
                if overlays.contains(.contour) {
                    Canvas { ctx, size in
                        drawContours(context: ctx, size: size)
                    }
                }

                // ── 5. Measurement dots ──────────────────────────────────────
                if overlays.contains(.dots) {
                    Canvas { ctx, size in
                        drawDots(context: ctx, size: size)
                    }
                }

                // ── 6. Scale bar ─────────────────────────────────────────────
                if let cal = calibration {
                    scaleBarView(calibration: cal, canvasSize: geo.size)
                }

                // ── 7. Tap capture ───────────────────────────────────────────
                if isSurveying {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { loc in
                            onTap?(loc, geo.size)
                        }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.cardCornerRadius))
        }
    }

    // MARK: - Background

    @ViewBuilder
    private func backgroundLayer(in size: CGSize) -> some View {
        if let img = floorplanImage {
            Image(uiImage: img)
                .resizable()
                .scaledToFit()
                .frame(width: size.width, height: size.height)
                .opacity(0.55)
        } else {
            Canvas { ctx, size in
                let step: CGFloat = 40
                var x: CGFloat = 0
                while x <= size.width {
                    ctx.stroke(Path { p in p.move(to: .init(x: x, y: 0))
                    p.addLine(to: .init(x: x, y: size.height))
                    },
                               with: .color(.white.opacity(0.06)), lineWidth: 0.5)
                    x += step
                }
                var y: CGFloat = 0
                while y <= size.height {
                    ctx.stroke(Path { p in p.move(to: .init(x: 0, y: y))
                    p.addLine(to: .init(x: size.width, y: y))
                    },
                               with: .color(.white.opacity(0.06)), lineWidth: 0.5)
                    y += step
                }
            }
            .background(Color.white.opacity(0.03))
        }
    }

    // MARK: - Gradient Layer

    private func drawGradient(context: GraphicsContext, size: CGSize) {
        var ctx = context
        ctx.blendMode = .screen
        for pt in points {
            let cx = pt.x * size.width
            let cy = pt.y * size.height
            let rgb = HeatmapRenderer.colorComponents(rssi: pt.signalStrength, scheme: colorScheme)
            let color = Color(red: Double(rgb.r) / 255, green: Double(rgb.g) / 255, blue: Double(rgb.b) / 255)
            let radius: CGFloat = adaptiveRadius(for: size)
            let grad = Gradient(colors: [color.opacity(0.85), color.opacity(0)])
            let radialGrad = GraphicsContext.Shading.radialGradient(
                grad,
                center: CGPoint(x: cx, y: cy),
                startRadius: 0,
                endRadius: radius
            )
            let rect = CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2)
            ctx.fill(Path(ellipseIn: rect), with: radialGrad)
        }
    }

    private func adaptiveRadius(for size: CGSize) -> CGFloat {
        guard points.count > 1 else { return 80 }
        let area = size.width * size.height
        let perPoint = area / CGFloat(points.count)
        return max(40, min(100, sqrt(perPoint) * 0.9))
    }

    // MARK: - Dead Zones

    private func drawDeadZones(context: GraphicsContext, size: CGSize, opacity: Double) {
        guard !points.isEmpty else { return }
        let gridSize = 40
        let grid = HeatmapRenderer.idwGrid(
            points: points, gridSize: gridSize,
            canvasWidth: Double(size.width), canvasHeight: Double(size.height)
        )
        let cellW = size.width / CGFloat(gridSize)
        let cellH = size.height / CGFloat(gridSize)
        for row in 0..<gridSize {
            for col in 0..<gridSize {
                guard let rssi = grid[row][col], rssi < -75 else { continue }
                let rect = CGRect(x: CGFloat(col) * cellW, y: CGFloat(row) * cellH,
                                  width: cellW, height: cellH)
                context.fill(Path(rect), with: .color(.red.opacity(opacity)))
            }
        }
    }

    // MARK: - Contour Lines

    private func drawContours(context: GraphicsContext, size: CGSize) {
        guard points.count >= 3 else { return }
        let gridSize = 40
        let grid = HeatmapRenderer.idwGrid(
            points: points, gridSize: gridSize,
            canvasWidth: Double(size.width), canvasHeight: Double(size.height)
        )
        let thresholds: [(rssi: Double, color: Color)] = [
            (-50, .green), (-65, .yellow), (-80, .red)
        ]
        let cellW = size.width / CGFloat(gridSize)
        let cellH = size.height / CGFloat(gridSize)

        for (threshold, color) in thresholds {
            var path = Path()
            for row in 0..<(gridSize - 1) {
                for col in 0..<(gridSize - 1) {
                    guard let v = grid[row][col], let vr = grid[row][col + 1],
                          let vb = grid[row + 1][col] else { continue }
                    let x = CGFloat(col) * cellW + cellW / 2
                    let y = CGFloat(row) * cellH + cellH / 2
                    if (v < threshold) != (vr < threshold) {
                        path.move(to: CGPoint(x: x + cellW, y: y))
                        path.addLine(to: CGPoint(x: x + cellW, y: y + cellH))
                    }
                    if (v < threshold) != (vb < threshold) {
                        path.move(to: CGPoint(x: x, y: y + cellH))
                        path.addLine(to: CGPoint(x: x + cellW, y: y + cellH))
                    }
                }
            }
            context.stroke(path, with: .color(color.opacity(0.7)), lineWidth: 1.5)
        }
    }

    // MARK: - Measurement Dots

    private func drawDots(context: GraphicsContext, size: CGSize) {
        for pt in points {
            let cx = pt.x * size.width
            let cy = pt.y * size.height
            let rgb = HeatmapRenderer.colorComponents(rssi: pt.signalStrength, scheme: colorScheme)
            let color = Color(red: Double(rgb.r) / 255, green: Double(rgb.g) / 255, blue: Double(rgb.b) / 255)
            let r: CGFloat = 9
            let rect = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
            context.fill(Path(ellipseIn: rect), with: .color(color))
            context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.7)), lineWidth: 1)
            // dBm label
            var text = AttributedString("\(pt.signalStrength)")
            text.font = .init(.monospacedSystemFont(ofSize: 9, weight: .regular))
            text.foregroundColor = Color.white
            context.draw(Text(text), at: CGPoint(x: cx, y: cy + r + 8))
        }
    }

    // MARK: - Scale Bar

    private func scaleBarView(calibration: CalibrationScale, canvasSize _: CGSize) -> some View {
        let config = HeatmapRenderer.scaleBar(pixelsPerUnit: calibration.pixelsPerUnit, unit: calibration.unit)
        return VStack(alignment: .leading, spacing: 2) {
            ZStack(alignment: .leading) {
                Rectangle()
                    .frame(width: config.pixels, height: 2)
                    .foregroundStyle(Color.white.opacity(0.9))
                HStack {
                    Rectangle().frame(width: 1, height: 8).foregroundStyle(Color.white)
                    Spacer()
                    Rectangle().frame(width: 1, height: 8).foregroundStyle(Color.white)
                }
                .frame(width: config.pixels)
            }
            Text("\(config.labelValue) \(config.unit.displayName)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.9))
        }
        .padding(6)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(10)
        .allowsHitTesting(false)
    }
}
