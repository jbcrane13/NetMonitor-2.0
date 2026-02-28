import SwiftUI
import AppKit
import NetMonitorCore

// MARK: - WiFiHeatmapToolView (macOS)

struct WiFiHeatmapToolView: View {
    @State private var vm = WiFiHeatmapToolViewModel()
    @State private var showingCalibration = false
    @State private var baseZoomScale: CGFloat = 1.0
    @State private var basePanOffset: CGSize = .zero
    @State private var macCalibPx: Double = 0
    @State private var macCalibReal: Double = 0
    @State private var macCalibUnit: DistanceUnit = .feet

    var body: some View {
        NavigationSplitView {
            surveyListSidebar
        } content: {
            VStack(spacing: 0) {
                macToolbar
                macCanvas
            }
            .navigationTitle("")
        } detail: {
            statsSidebar
        }
        .sheet(isPresented: $showingCalibration) {
            macCalibrationSheet
        }
        .frame(minWidth: 900, minHeight: 550)
    }

    // MARK: - Left Sidebar: Survey List

    private var surveyListSidebar: some View {
        List {
            Section("Surveys") {
                ForEach(vm.surveys) { survey in
                    surveyRow(survey)
                }
                .onDelete { indices in
                    indices.forEach { vm.deleteSurvey(vm.surveys[$0]) }
                }
            }

            Section("Tools") {
                Button {
                    showingCalibration = true
                } label: {
                    Label("Calibrate Scale", systemImage: "ruler")
                }
                .buttonStyle(.plain)
                .foregroundColor(vm.calibration != nil ? .accentColor : .primary)

                Button {
                    if vm.isSurveying { vm.stopSurvey() } else { vm.startSurvey() }
                } label: {
                    Label(vm.isSurveying ? "Stop Survey" : "New Survey",
                          systemImage: vm.isSurveying ? "stop.circle.fill" : "plus.circle")
                }
                .buttonStyle(.plain)
                .foregroundColor(vm.isSurveying ? .red : .primary)
                .keyboardShortcut("r", modifiers: .command)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 200)
    }

    private func surveyRow(_ survey: HeatmapSurvey) -> some View {
        Button {
            vm.selectSurvey(survey)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(survey.name)
                        .fontWeight(vm.selectedSurveyID == survey.id ? .semibold : .regular)
                    if survey.calibration != nil {
                        Image(systemName: "ruler").font(.caption2).foregroundColor(.accentColor)
                    }
                }
                Text("\(survey.dataPoints.count) pts · \(survey.mode.displayName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
        .tag(survey.id)
    }

    // MARK: - Toolbar

    private var macToolbar: some View {
        HStack(spacing: 6) {
            Picker("Scheme", selection: $vm.colorScheme) {
                ForEach(HeatmapColorScheme.allCases, id: \.self) { scheme in
                    Text(scheme.displayName).tag(scheme)
                }
            }
            .labelsHidden()
            .frame(width: 100)
            .controlSize(.small)

            Divider().frame(height: 20)

            overlayToggle("Gradient", overlay: .gradient)
            overlayToggle("Dots", overlay: .dots)
            overlayToggle("Contour", overlay: .contour)
            overlayToggle("Zones", overlay: .deadZones)

            Divider().frame(height: 20)

            Button { vm.zoomScale = min(vm.zoomScale * 1.25, 5) } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.plain).controlSize(.small)

            Button { vm.zoomScale = max(vm.zoomScale / 1.25, 0.5) } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.plain).controlSize(.small)

            Button {
                vm.zoomScale = 1
                vm.panOffset = .zero
                baseZoomScale = 1.0
                basePanOffset = .zero
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.plain).controlSize(.small)
            .help("Reset zoom & pan")

            Spacer()

            if vm.isSurveying {
                HStack(spacing: 6) {
                    Circle().fill(vm.signalColor).frame(width: 8)
                    Text("\(vm.currentRSSI) dBm")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(vm.signalColor)
                }
            }

            Text(vm.statusMessage)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Material.bar)
        .overlay(Divider(), alignment: .bottom)
    }

    private func overlayToggle(_ label: String, overlay: HeatmapDisplayOverlay) -> some View {
        let active = vm.displayOverlays.contains(overlay)
        return Toggle(label, isOn: Binding(
            get: { active },
            set: { on in
                if on { vm.displayOverlays.insert(overlay) }
                else { vm.displayOverlays.remove(overlay) }
            }
        ))
        .toggleStyle(.button)
        .controlSize(.small)
        .tint(.accentColor)
    }

    // MARK: - Center Canvas

    private var macCanvas: some View {
        GeometryReader { geo in
            ZStack {
                Color.black

                // NOTE: HeatmapCanvasView lives in NetMonitor-iOS and uses UIImage.
                // Task 11 will add #if os(iOS)/#if os(macOS) guards and move the
                // canvas to a shared location. For now we use MacHeatmapCanvasView
                // which is a macOS-native equivalent without UIImage dependency.
                MacHeatmapCanvasView(
                    points: vm.dataPoints,
                    floorplanImage: vm.floorplanImage,
                    colorScheme: vm.colorScheme,
                    overlays: vm.displayOverlays,
                    calibration: vm.calibration,
                    isSurveying: vm.isSurveying,
                    onTap: { loc, size in vm.recordDataPoint(at: loc, in: size) }
                )
                .scaleEffect(vm.zoomScale)
                .offset(vm.panOffset)
                .gesture(
                    MagnificationGesture()
                        .onChanged { val in
                            vm.zoomScale = max(0.5, min(5, baseZoomScale * val))
                        }
                        .onEnded { val in
                            baseZoomScale = max(0.5, min(5, baseZoomScale * val))
                        }
                )
                .gesture(
                    DragGesture()
                        .onChanged { val in
                            vm.panOffset = CGSize(
                                width: basePanOffset.width + val.translation.width,
                                height: basePanOffset.height + val.translation.height
                            )
                        }
                        .onEnded { val in
                            basePanOffset = CGSize(
                                width: basePanOffset.width + val.translation.width,
                                height: basePanOffset.height + val.translation.height
                            )
                        }
                )

                if let hover = vm.hoverPoint, let rssi = interpolatedRSSI(at: hover, in: geo.size) {
                    hoverTooltip(rssi: rssi, pt: hover, canvasSize: geo.size)
                }
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let loc): vm.hoverPoint = loc
                case .ended: vm.hoverPoint = nil
                }
            }
        }
        .background(Color.black)
    }

    private func interpolatedRSSI(at pt: CGPoint, in size: CGSize) -> Int? {
        guard !vm.dataPoints.isEmpty else { return nil }
        let closest = vm.dataPoints.min {
            let dx0 = $0.x * size.width - pt.x, dy0 = $0.y * size.height - pt.y
            let dx1 = $1.x * size.width - pt.x, dy1 = $1.y * size.height - pt.y
            return dx0*dx0+dy0*dy0 < dx1*dx1+dy1*dy1
        }
        return closest?.signalStrength
    }

    private func hoverTooltip(rssi: Int, pt: CGPoint, canvasSize: CGSize) -> some View {
        let level = SignalLevel.from(rssi: rssi)
        var coord = ""
        if let cal = vm.calibration {
            let rx = cal.realDistance(pixels: pt.x)
            let ry = cal.realDistance(pixels: pt.y)
            coord = String(format: " · (%.1f %@, %.1f %@)", rx, cal.unit.displayName, ry, cal.unit.displayName)
        }
        return Text("\(rssi) dBm · \(level.label)\(coord)")
            .font(.system(.caption2, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor.opacity(0.4), lineWidth: 1))
            .position(x: min(pt.x + 80, canvasSize.width - 80), y: max(pt.y - 20, 20))
            .allowsHitTesting(false)
    }

    // MARK: - Right Sidebar: Stats

    private var statsSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Signal Stats")
                    .font(.headline)
                    .padding(.top, 4)

                statBlock(value: vm.stats.averageDBm.map { "\($0) dBm" } ?? "--",
                          label: "Average", color: .primary)
                statBlock(value: vm.stats.weakestDBm.map { "\($0) dBm" } ?? "--",
                          label: "Minimum (worst)", color: .red)
                statBlock(value: vm.stats.strongestDBm.map { "\($0) dBm" } ?? "--",
                          label: "Maximum (best)", color: .green)

                Divider()
                Text("Coverage").font(.headline)

                statBlock(value: vm.stats.strongCoveragePercent.map { "\($0)%" } ?? "--",
                          label: "Strong (>= -50 dBm)")

                Divider()
                Text("Scale").font(.headline)

                if let cal = vm.calibration {
                    statBlock(value: String(format: "1px = %.1f %@", 1 / cal.pixelsPerUnit, cal.unit.displayName),
                              label: "Calibrated", color: .accentColor)
                    Button("Clear Calibration") { vm.clearCalibration() }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                        .font(.caption)
                } else {
                    Button("Calibrate Scale...") { showingCalibration = true }
                        .buttonStyle(.link)
                }

                Divider()

                Button {
                    // Export placeholder — NSView reference requires Representable bridge
                } label: {
                    Label("Export PNG", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Spacer()
            }
            .padding(14)
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 210)
    }

    private func statBlock(value: String, label: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(.title3, design: .monospaced))
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(label).font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Calibration Sheet (macOS)

    private var macCalibrationSheet: some View {
        VStack(spacing: 20) {
            Text("Calibrate Scale")
                .font(.title2).fontWeight(.bold)

            Text("Enter the scale manually. If 100 pixels on screen = 10 feet in reality:")
                .font(.body).foregroundColor(.secondary).multilineTextAlignment(.center)

            HStack(spacing: 12) {
                VStack(alignment: .leading) {
                    Text("Pixels").font(.caption).foregroundColor(.secondary)
                    TextField("e.g. 100", value: $macCalibPx, format: .number)
                        .textFieldStyle(.roundedBorder).frame(width: 100)
                }
                Text("=").foregroundColor(.secondary)
                VStack(alignment: .leading) {
                    Text("Real distance").font(.caption).foregroundColor(.secondary)
                    TextField("e.g. 10", value: $macCalibReal, format: .number)
                        .textFieldStyle(.roundedBorder).frame(width: 100)
                }
                VStack(alignment: .leading) {
                    Text("Unit").font(.caption).foregroundColor(.secondary)
                    Picker("", selection: $macCalibUnit) {
                        ForEach(DistanceUnit.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden().frame(width: 70)
                }
            }

            HStack {
                Button("Skip") { showingCalibration = false }
                    .keyboardShortcut(.escape)
                Button("Set Scale") {
                    if macCalibPx > 0 && macCalibReal > 0 {
                        vm.setCalibration(pixelDist: macCalibPx, realDist: macCalibReal, unit: macCalibUnit)
                    }
                    showingCalibration = false
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(macCalibPx <= 0 || macCalibReal <= 0)
            }
        }
        .padding(30)
        .frame(width: 500)
    }
}

// MARK: - MacHeatmapCanvasView
//
// macOS-native heatmap canvas. Functionally equivalent to the iOS HeatmapCanvasView
// but avoids UIImage. Task 11 will consolidate both into a single cross-platform view
// using #if os(iOS)/#if os(macOS) guards.

private struct MacHeatmapCanvasView: View {

    let points: [HeatmapDataPoint]
    let floorplanImage: NSImage?
    let colorScheme: HeatmapColorScheme
    let overlays: HeatmapDisplayOverlay
    let calibration: CalibrationScale?
    let isSurveying: Bool
    var onTap: ((CGPoint, CGSize) -> Void)?

    @State private var deadZonePulse: Double = 0.15

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let img = floorplanImage {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .opacity(0.55)
                }

                // Background grid
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

                if overlays.contains(.gradient) {
                    Canvas { ctx, size in
                        drawGradient(context: ctx, size: size)
                    }
                }

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

                if overlays.contains(.contour) {
                    Canvas { ctx, size in
                        drawContours(context: ctx, size: size)
                    }
                }

                if overlays.contains(.dots) {
                    Canvas { ctx, size in
                        drawDots(context: ctx, size: size)
                    }
                }

                if let cal = calibration {
                    scaleBarView(calibration: cal, canvasSize: geo.size)
                }

                if isSurveying {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { loc in
                            onTap?(loc, geo.size)
                        }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: MacTheme.Layout.cardCornerRadius))
        }
    }

    // MARK: - Drawing helpers

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
            var text = AttributedString("\(pt.signalStrength)")
            text.font = .init(.monospacedSystemFont(ofSize: 9, weight: .regular))
            text.foregroundColor = Color.white
            context.draw(Text(text), at: CGPoint(x: cx, y: cy + r + 8))
        }
    }

    private func scaleBarView(calibration: CalibrationScale, canvasSize: CGSize) -> some View {
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

#Preview {
    WiFiHeatmapToolView()
}
