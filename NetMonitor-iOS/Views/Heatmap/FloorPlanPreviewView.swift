import CoreGraphics
import SwiftUI

// MARK: - FloorPlanPreviewView

/// Real-time 2D preview of the emerging floor plan during AR scanning.
/// Shows a top-down view of detected walls with coverage information.
struct FloorPlanPreviewView: View {
    let previewImage: CGImage?
    let coverageInfo: ScanCoverageInfo?
    let vertexCount: Int
    let isLiDAR: Bool

    var body: some View {
        VStack(spacing: 8) {
            // Preview image
            if let previewImage {
                Image(decorative: previewImage, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .accessibilityIdentifier("arScan_floorPlanPreview")
            } else {
                // Placeholder while scanning
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.3))

                    VStack(spacing: 4) {
                        Image(systemName: "square.dashed")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.5))
                        Text("Scanning…")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .frame(height: 120)
                .accessibilityIdentifier("arScan_previewPlaceholder")
            }

            // Coverage stats
            if let coverageInfo {
                HStack(spacing: 12) {
                    coverageStat(
                        label: "Coverage",
                        value: "\(Int(coverageInfo.coveragePercent))%"
                    )
                    coverageStat(
                        label: "Area",
                        value: String(format: "%.1fm²", coverageInfo.scannedAreaM2)
                    )
                    coverageStat(
                        label: isLiDAR ? "Vertices" : "Planes",
                        value: formatCount(vertexCount)
                    )
                }
                .accessibilityIdentifier("arScan_coverageStats")
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func coverageStat(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private func formatCount(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fK", Double(count) / 1000.0)
        }
        return "\(count)"
    }
}

// MARK: - MissedAreaOverlayView

/// Overlay showing areas that have NOT been scanned yet.
/// Displayed as semi-transparent red patches over the preview.
struct MissedAreaOverlayView: View {
    let missedGrid: [UInt8]
    let gridWidth: Int
    let gridHeight: Int

    var body: some View {
        Canvas { context, size in
            guard gridWidth > 0, gridHeight > 0 else { return }

            let cellWidth = size.width / CGFloat(gridWidth)
            let cellHeight = size.height / CGFloat(gridHeight)

            for y in 0 ..< gridHeight {
                for x in 0 ..< gridWidth {
                    let index = y * gridWidth + x
                    guard index < missedGrid.count, missedGrid[index] == 1 else { continue }

                    let rect = CGRect(
                        x: CGFloat(x) * cellWidth,
                        y: CGFloat(y) * cellHeight,
                        width: cellWidth,
                        height: cellHeight
                    )
                    context.fill(Path(rect), with: .color(.red.opacity(0.3)))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityIdentifier("arScan_missedAreaOverlay")
    }
}

// MARK: - GenerationProgressView

/// Progress indicator shown during floor plan generation.
struct GenerationProgressView: View {
    let progress: FloorPlanGenerationProgress?
    let isGenerating: Bool

    var body: some View {
        if isGenerating {
            VStack(spacing: Theme.Layout.itemSpacing) {
                ProgressView(value: progress?.fractionComplete ?? 0, total: 1.0)
                    .progressViewStyle(.linear)
                    .tint(Theme.Colors.accent)

                Text(progress?.message ?? "Generating floor plan…")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .accessibilityIdentifier("arScan_progressMessage")
            }
            .padding(Theme.Layout.cardPadding)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityIdentifier("arScan_generationProgress")
        }
    }
}

// MARK: - Preview

#Preview("Floor Plan Preview") {
    ZStack {
        Color.black

        FloorPlanPreviewView(
            previewImage: nil,
            coverageInfo: ScanCoverageInfo(
                scannedAreaM2: 25.5,
                boundsWidthM: 6.0,
                boundsHeightM: 4.25,
                coveragePercent: 67.0,
                scannedCells: 17,
                totalCells: 25
            ),
            vertexCount: 3450,
            isLiDAR: true
        )
        .padding()
    }
}
