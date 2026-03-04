import AppKit
import NetMonitorCore
import SwiftUI

// MARK: - DrawingTool

/// The active drawing tool for the floor plan canvas.
enum DrawingTool: String, CaseIterable, Identifiable, Sendable {
    case wall = "Wall"
    case door = "Door"
    case room = "Room"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .wall: "line.diagonal"
        case .door: "door.left.hand.open"
        case .room: "rectangle"
        }
    }
}

// MARK: - DrawnSegment

/// A segment drawn on the floor plan canvas.
struct DrawnSegment: Identifiable, Sendable {
    let id = UUID()
    let tool: DrawingTool
    let startPoint: CGPoint
    let endPoint: CGPoint
}

// MARK: - DrawFloorPlanView

/// A basic canvas for drawing walls, doors, and rooms to use as a floor plan for survey.
/// The user draws line segments for walls, gaps for doors, and rectangles for rooms.
/// When finished, the drawing is rasterized into a floor plan image.
struct DrawFloorPlanView: View {
    let canvasWidth: Int
    let canvasHeight: Int
    let onComplete: (Data) -> Void
    let onCancel: () -> Void

    @State private var segments: [DrawnSegment] = []
    @State private var currentTool: DrawingTool = .wall
    @State private var dragStart: CGPoint?
    @State private var dragEnd: CGPoint?
    @State private var showingClearConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            drawingToolbar
            Divider()
            drawingCanvas
        }
        .frame(minWidth: 600, minHeight: 500)
        .alert("Clear Drawing?", isPresented: $showingClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                segments.removeAll()
            }
        } message: {
            Text("This will remove all drawn elements. This cannot be undone.")
        }
        .accessibilityIdentifier("heatmap_draw_floor_plan")
    }

    // MARK: - Toolbar

    private var drawingToolbar: some View {
        HStack(spacing: 12) {
            // Tool picker
            ForEach(DrawingTool.allCases) { tool in
                drawingToolButton(for: tool)
                    .accessibilityIdentifier("heatmap_draw_tool_\(tool.rawValue.lowercased())")
            }

            Divider()
                .frame(height: 20)

            // Segment count
            Text("\(segments.count) elements")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            // Clear all
            Button(role: .destructive) {
                showingClearConfirmation = true
            } label: {
                Label("Clear All", systemImage: "trash")
            }
            .disabled(segments.isEmpty)
            .accessibilityIdentifier("heatmap_draw_clear")

            // Undo last
            Button {
                if !segments.isEmpty {
                    segments.removeLast()
                }
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .disabled(segments.isEmpty)
            .keyboardShortcut("z", modifiers: .command)
            .accessibilityIdentifier("heatmap_draw_undo")

            Divider()
                .frame(height: 20)

            // Cancel
            Button("Cancel") {
                onCancel()
            }
            .accessibilityIdentifier("heatmap_draw_cancel")

            // Done
            Button("Use as Floor Plan") {
                let imageData = rasterizeDrawing()
                onComplete(imageData)
            }
            .buttonStyle(.borderedProminent)
            .disabled(segments.isEmpty)
            .accessibilityIdentifier("heatmap_draw_done")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .accessibilityIdentifier("heatmap_draw_toolbar")
    }

    // MARK: - Canvas

    private var drawingCanvas: some View {
        GeometryReader { geometry in
            let canvasSize = aspectFitSize(
                imageWidth: CGFloat(canvasWidth),
                imageHeight: CGFloat(canvasHeight),
                containerSize: geometry.size
            )
            let origin = CGPoint(
                x: (geometry.size.width - canvasSize.width) / 2,
                y: (geometry.size.height - canvasSize.height) / 2
            )

            ZStack {
                // White canvas background
                Rectangle()
                    .fill(.white)
                    .frame(width: canvasSize.width, height: canvasSize.height)
                    .position(
                        x: geometry.size.width / 2,
                        y: geometry.size.height / 2
                    )
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)

                // Grid lines for guidance
                Canvas { context, _ in
                    drawGrid(
                        context: &context,
                        origin: origin,
                        size: canvasSize
                    )
                    drawSegments(
                        context: &context,
                        origin: origin,
                        size: canvasSize
                    )
                    drawCurrentDrag(
                        context: &context,
                        origin: origin,
                        size: canvasSize
                    )
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .gesture(
                DragGesture(minimumDistance: 5)
                    .onChanged { value in
                        let normalized = normalizePoint(
                            value.startLocation,
                            origin: origin,
                            size: canvasSize
                        )
                        let normalizedEnd = normalizePoint(
                            value.location,
                            origin: origin,
                            size: canvasSize
                        )
                        if dragStart == nil {
                            dragStart = normalized
                        }
                        dragEnd = normalizedEnd
                    }
                    .onEnded { value in
                        let normalizedEnd = normalizePoint(
                            value.location,
                            origin: origin,
                            size: canvasSize
                        )
                        if let start = dragStart {
                            let clampedStart = clampPoint(start)
                            let clampedEnd = clampPoint(normalizedEnd)
                            let segment = DrawnSegment(
                                tool: currentTool,
                                startPoint: clampedStart,
                                endPoint: clampedEnd
                            )
                            segments.append(segment)
                        }
                        dragStart = nil
                        dragEnd = nil
                    }
            )
            .accessibilityIdentifier("heatmap_draw_canvas")
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Tool Button

    @ViewBuilder
    private func drawingToolButton(for tool: DrawingTool) -> some View {
        if tool == currentTool {
            Button {
                currentTool = tool
            } label: {
                Label(tool.rawValue, systemImage: tool.icon)
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button {
                currentTool = tool
            } label: {
                Label(tool.rawValue, systemImage: tool.icon)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Drawing Helpers

    private func drawGrid(
        context: inout GraphicsContext,
        origin: CGPoint,
        size: CGSize
    ) {
        let gridSpacing: CGFloat = size.width / 20

        for i in 0...20 {
            let x = origin.x + CGFloat(i) * gridSpacing
            let path = Path { p in
                p.move(to: CGPoint(x: x, y: origin.y))
                p.addLine(to: CGPoint(x: x, y: origin.y + size.height))
            }
            context.stroke(path, with: .color(.gray.opacity(0.15)), lineWidth: 0.5)
        }

        let vGridSpacing = size.height / CGFloat(Int(20 * size.height / size.width))
        let vCount = Int(size.height / vGridSpacing)
        for i in 0...vCount {
            let y = origin.y + CGFloat(i) * vGridSpacing
            let path = Path { p in
                p.move(to: CGPoint(x: origin.x, y: y))
                p.addLine(to: CGPoint(x: origin.x + size.width, y: y))
            }
            context.stroke(path, with: .color(.gray.opacity(0.15)), lineWidth: 0.5)
        }
    }

    private func drawSegments(
        context: inout GraphicsContext,
        origin: CGPoint,
        size: CGSize
    ) {
        for segment in segments {
            let start = denormalizePoint(segment.startPoint, origin: origin, size: size)
            let end = denormalizePoint(segment.endPoint, origin: origin, size: size)

            switch segment.tool {
            case .wall:
                let path = Path { p in
                    p.move(to: start)
                    p.addLine(to: end)
                }
                context.stroke(path, with: .color(.black), lineWidth: 3)

            case .door:
                let path = Path { p in
                    p.move(to: start)
                    p.addLine(to: end)
                }
                context.stroke(
                    path,
                    with: .color(.brown),
                    style: StrokeStyle(lineWidth: 3, dash: [6, 4])
                )

            case .room:
                let rect = CGRect(
                    x: min(start.x, end.x),
                    y: min(start.y, end.y),
                    width: abs(end.x - start.x),
                    height: abs(end.y - start.y)
                )
                context.fill(
                    Rectangle().path(in: rect),
                    with: .color(.blue.opacity(0.05))
                )
                context.stroke(
                    Rectangle().path(in: rect),
                    with: .color(.blue.opacity(0.5)),
                    lineWidth: 1.5
                )
            }
        }
    }

    private func drawCurrentDrag(
        context: inout GraphicsContext,
        origin: CGPoint,
        size: CGSize
    ) {
        guard let start = dragStart, let end = dragEnd
        else { return }

        let screenStart = denormalizePoint(clampPoint(start), origin: origin, size: size)
        let screenEnd = denormalizePoint(clampPoint(end), origin: origin, size: size)

        switch currentTool {
        case .wall:
            let path = Path { p in
                p.move(to: screenStart)
                p.addLine(to: screenEnd)
            }
            context.stroke(path, with: .color(.black.opacity(0.5)), lineWidth: 3)

        case .door:
            let path = Path { p in
                p.move(to: screenStart)
                p.addLine(to: screenEnd)
            }
            context.stroke(
                path,
                with: .color(.brown.opacity(0.5)),
                style: StrokeStyle(lineWidth: 3, dash: [6, 4])
            )

        case .room:
            let rect = CGRect(
                x: min(screenStart.x, screenEnd.x),
                y: min(screenStart.y, screenEnd.y),
                width: abs(screenEnd.x - screenStart.x),
                height: abs(screenEnd.y - screenStart.y)
            )
            context.fill(
                Rectangle().path(in: rect),
                with: .color(.blue.opacity(0.03))
            )
            context.stroke(
                Rectangle().path(in: rect),
                with: .color(.blue.opacity(0.3)),
                lineWidth: 1.5
            )
        }
    }

    // MARK: - Coordinate Helpers

    private func normalizePoint(_ point: CGPoint, origin: CGPoint, size: CGSize) -> CGPoint {
        CGPoint(
            x: (point.x - origin.x) / size.width,
            y: (point.y - origin.y) / size.height
        )
    }

    private func denormalizePoint(_ point: CGPoint, origin: CGPoint, size: CGSize) -> CGPoint {
        CGPoint(
            x: origin.x + point.x * size.width,
            y: origin.y + point.y * size.height
        )
    }

    private func clampPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: max(0, min(1, point.x)),
            y: max(0, min(1, point.y))
        )
    }

    private func aspectFitSize(imageWidth: CGFloat, imageHeight: CGFloat, containerSize: CGSize) -> CGSize {
        let imageAspect = imageWidth / imageHeight
        let containerAspect = containerSize.width / containerSize.height

        if imageAspect > containerAspect {
            let width = containerSize.width * 0.9
            return CGSize(width: width, height: width / imageAspect)
        } else {
            let height = containerSize.height * 0.9
            return CGSize(width: height * imageAspect, height: height)
        }
    }

    // MARK: - Rasterization

    /// Rasterizes the drawn elements into a PNG image.
    private func rasterizeDrawing() -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: canvasWidth,
            height: canvasHeight,
            bitsPerComponent: 8,
            bytesPerRow: canvasWidth * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return Data()
        }

        // White background
        context.setFillColor(CGColor.white)
        context.fill(CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))

        let w = CGFloat(canvasWidth)
        let h = CGFloat(canvasHeight)

        for segment in segments {
            let startX = segment.startPoint.x * w
            // Flip Y: CGContext has origin at bottom-left
            let startY = (1 - segment.startPoint.y) * h
            let endX = segment.endPoint.x * w
            let endY = (1 - segment.endPoint.y) * h

            switch segment.tool {
            case .wall:
                context.setStrokeColor(CGColor.black)
                context.setLineWidth(4)
                context.setLineDash(phase: 0, lengths: [])
                context.move(to: CGPoint(x: startX, y: startY))
                context.addLine(to: CGPoint(x: endX, y: endY))
                context.strokePath()

            case .door:
                context.setStrokeColor(CGColor(red: 0.6, green: 0.3, blue: 0.1, alpha: 1.0))
                context.setLineWidth(4)
                context.setLineDash(phase: 0, lengths: [8, 6])
                context.move(to: CGPoint(x: startX, y: startY))
                context.addLine(to: CGPoint(x: endX, y: endY))
                context.strokePath()
                context.setLineDash(phase: 0, lengths: [])

            case .room:
                let rect = CGRect(
                    x: min(startX, endX),
                    y: min(startY, endY),
                    width: abs(endX - startX),
                    height: abs(endY - startY)
                )
                context.setFillColor(CGColor(red: 0.9, green: 0.95, blue: 1.0, alpha: 1.0))
                context.fill(rect)
                context.setStrokeColor(CGColor(red: 0.3, green: 0.3, blue: 0.8, alpha: 1.0))
                context.setLineWidth(2)
                context.stroke(rect)
            }
        }

        guard let cgImage = context.makeImage()
        else { return Data() }

        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .png, properties: [:]) ?? Data()
    }
}

#if DEBUG
#Preview {
    DrawFloorPlanView(
        canvasWidth: 1000,
        canvasHeight: 800,
        onComplete: { _ in },
        onCancel: {}
    )
    .frame(width: 800, height: 600)
}
#endif
