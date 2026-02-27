import SwiftUI
import NetMonitorCore

// MARK: - CalibrationView

/// Presented as a sheet after importing a floor plan.
/// The user draws a reference line on the image and enters the real-world distance.
struct CalibrationView: View {
    let floorplanImage: UIImage?
    /// Called with the completed scale, or nil when skipped.
    var onComplete: (CalibrationScale?) -> Void

    @State private var lineStart: CGPoint? = nil
    @State private var lineEnd: CGPoint?   = nil
    @State private var isDragging = false
    @State private var showDistanceEntry = false
    @State private var distanceText = ""
    @State private var unit: DistanceUnit = .feet
    @State private var canvasSize: CGSize = .zero

    private var pixelDistance: Double? {
        guard let s = lineStart, let e = lineEnd else { return nil }
        let dx = e.x - s.x
        let dy = e.y - s.y
        return sqrt(dx * dx + dy * dy)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                instructionBanner
                canvasArea
                if showDistanceEntry { distancePanel }
            }
            .themedBackground()
            .navigationTitle("Calibrate Scale")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Skip") { onComplete(nil) }
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .accessibilityIdentifier("calibration_button_skip")
                }
            }
        }
    }

    // MARK: - Instruction Banner

    private var instructionBanner: some View {
        GlassCard {
            HStack(spacing: 12) {
                Image(systemName: "ruler")
                    .font(.title3)
                    .foregroundStyle(Theme.Colors.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(lineStart == nil ? "Draw a Reference Line" : (showDistanceEntry ? "Enter Real Distance" : "Drag to extend line"))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(lineStart == nil
                         ? "Drag between two points whose real distance you know"
                         : pixelLengthDescription)
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer()
                if lineStart != nil {
                    Button("Reset") {
                        lineStart = nil; lineEnd = nil; showDistanceEntry = false
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.accent)
                }
            }
        }
        .padding(.horizontal, Theme.Layout.screenPadding)
        .padding(.top, 8)
    }

    private var pixelLengthDescription: String {
        guard let d = pixelDistance else { return "" }
        return String(format: "Line length: %.0f px — enter real distance below", d)
    }

    // MARK: - Canvas Area

    private var canvasArea: some View {
        GeometryReader { geo in
            ZStack {
                // Floor plan
                if let img = floorplanImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .opacity(0.7)
                }

                // Drawn line
                if let s = lineStart, let e = lineEnd ?? lineStart {
                    Canvas { ctx, _ in
                        // Dashed cyan line
                        var path = Path()
                        path.move(to: s)
                        path.addLine(to: e)
                        ctx.stroke(path, with: .color(Theme.Colors.accent.opacity(0.9)),
                                   style: StrokeStyle(lineWidth: 2, dash: [6, 4]))

                        // Endpoint handles
                        for pt in [s, e] {
                            let r: CGFloat = 7
                            let rect = CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)
                            ctx.fill(Path(ellipseIn: rect), with: .color(Theme.Colors.accent))
                            ctx.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.8)), lineWidth: 1.5)
                        }
                    }
                }
            }
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.cardCornerRadius))
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { val in
                        if lineStart == nil || (!isDragging) {
                            lineStart = val.startLocation
                            isDragging = true
                            showDistanceEntry = false
                        }
                        lineEnd = val.location
                    }
                    .onEnded { _ in
                        isDragging = false
                        if pixelDistance ?? 0 > 20 {
                            showDistanceEntry = true
                        }
                    }
            )
            .onAppear { canvasSize = geo.size }
        }
        .padding(.horizontal, Theme.Layout.screenPadding)
        .padding(.vertical, 8)
    }

    // MARK: - Distance Entry Panel

    private var distancePanel: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Real-world distance of this line:")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textPrimary)

                HStack(spacing: 10) {
                    TextField("e.g. 12", text: $distanceText)
                        .keyboardType(.decimalPad)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(Theme.Colors.accent)
                        .padding(10)
                        .background(Theme.Colors.accent.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.Colors.accent.opacity(0.4)))
                        .accessibilityIdentifier("calibration_input_distance")

                    Picker("Unit", selection: $unit) {
                        ForEach(DistanceUnit.allCases, id: \.self) { u in
                            Text(u.displayName).tag(u)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 90)
                    .accessibilityIdentifier("calibration_picker_unit")

                    Button("Set Scale") {
                        commitCalibration()
                    }
                    .disabled(Double(distanceText) == nil || (Double(distanceText) ?? 0) <= 0)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Theme.Colors.accent)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .accessibilityIdentifier("calibration_button_set")
                }
            }
        }
        .padding(.horizontal, Theme.Layout.screenPadding)
        .padding(.bottom, 16)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(response: 0.35), value: showDistanceEntry)
    }

    private func commitCalibration() {
        guard let dist = Double(distanceText), dist > 0,
              let px = pixelDistance else { return }
        let scale = CalibrationScale(pixelDistance: px, realDistance: dist, unit: unit)
        onComplete(scale)
    }
}
