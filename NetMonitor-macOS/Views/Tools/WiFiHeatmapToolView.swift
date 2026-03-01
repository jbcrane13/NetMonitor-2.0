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
        VStack(spacing: 0) {
            headerBar
            Divider().background(MacTheme.Colors.glassBorder)
            HStack(spacing: 0) {
                surveyListPanel
                Divider().background(MacTheme.Colors.glassBorder)
                canvasAndToolbar
                Divider().background(MacTheme.Colors.glassBorder)
                inspectorPanel
            }
        }
        .background(MacTheme.Colors.backgroundBase)
        .sheet(isPresented: $showingCalibration) { macCalibrationSheet }
        .frame(minWidth: 1000, minHeight: 600)
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Wi-Fi Heatmap Analysis")
                    .font(.title2).fontWeight(.bold)
                    .foregroundStyle(MacTheme.Colors.textPrimary)
                Text(vm.statusMessage)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(MacTheme.Colors.textSecondary)
            }

            Spacer()

            if vm.isSurveying {
                HStack(spacing: 6) {
                    Circle().fill(MacTheme.Colors.error).frame(width: 8, height: 8)
                    Text("\(vm.currentRSSI) dBm")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(vm.signalColor)
                }
                .padding(.trailing, 8)
            }

            Button {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.image, .pdf]
                panel.allowsMultipleSelection = false
                if panel.runModal() == .OK, let url = panel.url,
                   let img = NSImage(contentsOf: url) {
                    vm.floorplanImage = img
                }
            } label: {
                Label("Import Blueprint", systemImage: "doc.badge.plus")
                    .fontWeight(.medium)
            }
            .buttonStyle(.borderedProminent)
            .tint(MacTheme.Colors.info)
            .controlSize(.large)

            Button {
                showingCalibration = true
            } label: {
                Label("Calibrate", systemImage: "ruler")
                    .fontWeight(.medium)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .foregroundStyle(vm.calibration != nil ? MacTheme.Colors.info : MacTheme.Colors.textSecondary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(MacTheme.Colors.backgroundElevated)
    }

    // MARK: - Survey List Panel

    private var surveyListPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("RECENT SURVEYS")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(MacTheme.Colors.textTertiary)
                .tracking(1)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)

            List(selection: Binding(
                get: { vm.selectedSurveyID },
                set: { id in
                    if let id, let survey = vm.surveys.first(where: { $0.id == id }) {
                        vm.selectSurvey(survey)
                    }
                }
            )) {
                ForEach(vm.surveys) { survey in
                    surveyRow(survey)
                        .tag(survey.id)
                        .listRowBackground(
                            vm.selectedSurveyID == survey.id
                                ? MacTheme.Colors.sidebarActive.opacity(0.5)
                                : Color.clear
                        )
                }
                .onDelete { indices in
                    indices.forEach { vm.deleteSurvey(vm.surveys[$0]) }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            Divider().background(MacTheme.Colors.glassBorder)

            Button {
                if vm.isSurveying { vm.stopSurvey() } else { vm.startSurvey() }
            } label: {
                Label(
                    vm.isSurveying ? "Stop Survey" : "New Survey",
                    systemImage: vm.isSurveying ? "stop.circle.fill" : "plus.circle.fill"
                )
                .frame(maxWidth: .infinity)
                .fontWeight(.medium)
            }
            .buttonStyle(.borderedProminent)
            .tint(vm.isSurveying ? MacTheme.Colors.error : MacTheme.Colors.info)
            .controlSize(.large)
            .keyboardShortcut("r", modifiers: .command)
            .padding(12)
        }
        .frame(width: 280)
        .background(MacTheme.Colors.backgroundBase)
    }

    private func surveyRow(_ survey: HeatmapSurvey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: survey.mode == .floorplan ? "map.fill" : "hand.tap.fill")
                .foregroundStyle(MacTheme.Colors.info)
                .font(.system(size: 18))
                .frame(width: 24, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(survey.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(MacTheme.Colors.textPrimary)
                    if survey.calibration != nil {
                        Image(systemName: "ruler")
                            .font(.caption2)
                            .foregroundStyle(MacTheme.Colors.info)
                    }
                }
                HStack(spacing: 6) {
                    Text("\(survey.dataPoints.count) nodes")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MacTheme.Colors.success)
                    Text("\u{2022}")
                        .foregroundStyle(MacTheme.Colors.textTertiary)
                    Text(survey.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 12))
                        .foregroundStyle(MacTheme.Colors.textSecondary)
                }
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Canvas + Sub-Toolbar

    private var canvasAndToolbar: some View {
        VStack(spacing: 0) {
            canvasToolbar
            Divider().background(MacTheme.Colors.glassBorder)
            macCanvas
        }
    }

    private var canvasToolbar: some View {
        HStack {
            if let sel = vm.selectedSurveyID,
               let survey = vm.surveys.first(where: { $0.id == sel }) {
                Text(survey.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(MacTheme.Colors.textPrimary)
            } else if vm.isSurveying {
                Text("Recording\u{2026}")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(MacTheme.Colors.error)
            }

            Spacer()

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

            Divider().frame(height: 20)

            HStack(spacing: 12) {
                Button {} label: {
                    Image(systemName: "printer").foregroundStyle(MacTheme.Colors.textSecondary)
                }.buttonStyle(.plain)
                Button {} label: {
                    Image(systemName: "square.and.arrow.up").foregroundStyle(MacTheme.Colors.textSecondary)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(MacTheme.Colors.backgroundElevated.opacity(0.6))
    }

    private func overlayToggle(_ label: String, overlay: HeatmapDisplayOverlay) -> some View {
        let active = vm.displayOverlays.contains(overlay)
        return Toggle(label, isOn: Binding(
            get: { active },
            set: { on in
                if on { vm.displayOverlays.insert(overlay) } else { vm.displayOverlays.remove(overlay) }
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

                if let hover = vm.hoverPoint,
                   let rssi = interpolatedRSSI(at: hover, in: geo.size) {
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
        return vm.dataPoints.min {
            let dx0 = $0.x * size.width - pt.x, dy0 = $0.y * size.height - pt.y
            let dx1 = $1.x * size.width - pt.x, dy1 = $1.y * size.height - pt.y
            return dx0 * dx0 + dy0 * dy0 < dx1 * dx1 + dy1 * dy1
        }?.signalStrength
    }

    private func hoverTooltip(rssi: Int, pt: CGPoint, canvasSize: CGSize) -> some View {
        let level = SignalLevel.from(rssi: rssi)
        var coord = ""
        if let cal = vm.calibration {
            let rx = cal.realDistance(pixels: pt.x)
            let ry = cal.realDistance(pixels: pt.y)
            coord = String(format: " \u{00B7} (%.1f %@, %.1f %@)",
                           rx, cal.unit.displayName, ry, cal.unit.displayName)
        }
        return Text("\(rssi) dBm \u{00B7} \(level.label)\(coord)")
            .font(.system(.caption2, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .stroke(Color.accentColor.opacity(0.4), lineWidth: 1))
            .position(x: min(pt.x + 80, canvasSize.width - 80),
                      y: max(pt.y - 20, 20))
            .allowsHitTesting(false)
    }

    // MARK: - Inspector Panel

    private var inspectorPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("SURVEY INSPECTOR")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(MacTheme.Colors.textTertiary)
                    .tracking(1)

                VStack(spacing: 12) {
                    telemetryRow(
                        label: "Avg Signal",
                        value: vm.stats.averageDBm.map { "\($0) dBm" } ?? "--",
                        color: vm.stats.averageDBm.map {
                            $0 >= -60 ? MacTheme.Colors.success : MacTheme.Colors.warning
                        } ?? MacTheme.Colors.textTertiary
                    )
                    telemetryRow(
                        label: "Best Signal",
                        value: vm.stats.strongestDBm.map { "\($0) dBm" } ?? "--",
                        color: MacTheme.Colors.success
                    )
                    telemetryRow(
                        label: "Worst Signal",
                        value: vm.stats.weakestDBm.map { "\($0) dBm" } ?? "--",
                        color: vm.stats.weakestDBm.map {
                            $0 < -75 ? MacTheme.Colors.error : MacTheme.Colors.warning
                        } ?? MacTheme.Colors.textTertiary
                    )
                    telemetryRow(
                        label: "Coverage",
                        value: vm.stats.strongCoveragePercent.map { "\($0)%" } ?? "--",
                        color: MacTheme.Colors.info
                    )
                }
                .macGlassCard()

                if let cal = vm.calibration {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SCALE")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(MacTheme.Colors.textTertiary)
                            .tracking(1)
                        HStack {
                            Text(String(format: "1px = %.2f %@",
                                        1 / cal.pixelsPerUnit, cal.unit.displayName))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(MacTheme.Colors.info)
                            Spacer()
                            Button("Clear") { vm.clearCalibration() }
                                .buttonStyle(.plain)
                                .foregroundStyle(MacTheme.Colors.textSecondary)
                                .font(.caption)
                        }
                    }
                    .macGlassCard()
                }

                Text("LIVE LOGS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(MacTheme.Colors.textTertiary)
                    .tracking(1)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 8) {
                    logEntry(
                        time: Date().formatted(date: .omitted, time: .standard),
                        message: vm.statusMessage,
                        isWarning: false
                    )
                    if vm.isSurveying {
                        logEntry(
                            time: Date().formatted(date: .omitted, time: .standard),
                            message: "Survey active \u{2014} \(vm.dataPoints.count) points recorded",
                            isWarning: false
                        )
                    }
                    if let weakest = vm.stats.weakestDBm, weakest < -75 {
                        logEntry(
                            time: Date().formatted(date: .omitted, time: .standard),
                            message: "Weak signal detected: \(weakest) dBm",
                            isWarning: true
                        )
                    }
                }
                .macGlassCard()

                Button {} label: {
                    Label("Export PNG", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Spacer()
            }
            .padding(20)
        }
        .frame(width: 280)
        .background(MacTheme.Colors.backgroundElevated)
    }

    private func telemetryRow(label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(MacTheme.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
    }

    private func logEntry(time: String, message: String, isWarning: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(time)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(MacTheme.Colors.textTertiary)
            Text(message)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(isWarning ? MacTheme.Colors.error : Color(white: 0.8))
        }
    }

    // MARK: - Calibration Sheet

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
                    if macCalibPx > 0, macCalibReal > 0 {
                        vm.setCalibration(pixelDist: macCalibPx,
                                          realDist: macCalibReal,
                                          unit: macCalibUnit)
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

                Canvas { ctx, size in
                    let step: CGFloat = 40
                    var xPos: CGFloat = 0
                    while xPos <= size.width {
                        ctx.stroke(
                            Path { path in
                                path.move(to: .init(x: xPos, y: 0))
                                path.addLine(to: .init(x: xPos, y: size.height))
                            },
                            with: .color(.white.opacity(0.06)), lineWidth: 0.5
                        )
                        xPos += step
                    }
                    var yPos: CGFloat = 0
                    while yPos <= size.height {
                        ctx.stroke(
                            Path { path in
                                path.move(to: .init(x: 0, y: yPos))
                                path.addLine(to: .init(x: size.width, y: yPos))
                            },
                            with: .color(.white.opacity(0.06)), lineWidth: 0.5
                        )
                        yPos += step
                    }
                }
                .background(Color.white.opacity(0.03))

                if overlays.contains(.gradient) {
                    Canvas { ctx, size in drawGradient(context: ctx, size: size) }
                }
                if overlays.contains(.deadZones) {
                    Canvas { ctx, size in drawDeadZones(context: ctx, size: size, opacity: deadZonePulse) }
                        .onAppear {
                            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                                deadZonePulse = 0.45
                            }
                        }
                }
                if overlays.contains(.contour) {
                    Canvas { ctx, size in drawContours(context: ctx, size: size) }
                }
                if overlays.contains(.dots) {
                    Canvas { ctx, size in drawDots(context: ctx, size: size) }
                }

                if let cal = calibration {
                    scaleBarView(calibration: cal)
                }

                if isSurveying {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { loc in onTap?(loc, geo.size) }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: MacTheme.Layout.cardCornerRadius))
        }
    }

    // MARK: - Drawing

    private func drawGradient(context: GraphicsContext, size: CGSize) {
        var ctx = context
        ctx.blendMode = .screen
        for pt in points {
            let cx = pt.x * size.width
            let cy = pt.y * size.height
            let rgb = HeatmapRenderer.colorComponents(rssi: pt.signalStrength, scheme: colorScheme)
            let color = Color(red: Double(rgb.r) / 255,
                              green: Double(rgb.g) / 255,
                              blue: Double(rgb.b) / 255)
            let radius = adaptiveRadius(for: size)
            let grad = Gradient(colors: [color.opacity(0.85), color.opacity(0)])
            let shading = GraphicsContext.Shading.radialGradient(
                grad, center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: radius
            )
            let rect = CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2)
            ctx.fill(Path(ellipseIn: rect), with: shading)
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
        let thresholds: [(rssi: Double, color: Color)] = [(-50, .green), (-65, .yellow), (-80, .red)]
        let cellW = size.width / CGFloat(gridSize)
        let cellH = size.height / CGFloat(gridSize)

        for (threshold, color) in thresholds {
            var path = Path()
            for row in 0..<(gridSize - 1) {
                for col in 0..<(gridSize - 1) {
                    guard let val = grid[row][col],
                          let valR = grid[row][col + 1],
                          let valB = grid[row + 1][col] else { continue }
                    let xPos = CGFloat(col) * cellW + cellW / 2
                    let yPos = CGFloat(row) * cellH + cellH / 2
                    if (val < threshold) != (valR < threshold) {
                        path.move(to: CGPoint(x: xPos + cellW, y: yPos))
                        path.addLine(to: CGPoint(x: xPos + cellW, y: yPos + cellH))
                    }
                    if (val < threshold) != (valB < threshold) {
                        path.move(to: CGPoint(x: xPos, y: yPos + cellH))
                        path.addLine(to: CGPoint(x: xPos + cellW, y: yPos + cellH))
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
            let color = Color(red: Double(rgb.r) / 255,
                              green: Double(rgb.g) / 255,
                              blue: Double(rgb.b) / 255)
            let dotR: CGFloat = 9
            let rect = CGRect(x: cx - dotR, y: cy - dotR, width: dotR * 2, height: dotR * 2)
            context.fill(Path(ellipseIn: rect), with: .color(color))
            context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.7)), lineWidth: 1)
            var text = AttributedString("\(pt.signalStrength)")
            text.font = .init(.monospacedSystemFont(ofSize: 9, weight: .regular))
            text.foregroundColor = Color.white
            context.draw(Text(text), at: CGPoint(x: cx, y: cy + dotR + 8))
        }
    }

    private func scaleBarView(calibration: CalibrationScale) -> some View {
        let config = HeatmapRenderer.scaleBar(
            pixelsPerUnit: calibration.pixelsPerUnit, unit: calibration.unit
        )
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
