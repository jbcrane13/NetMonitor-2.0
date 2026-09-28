//
//  CardStateViews.swift
//  NetMonitor-macOS
//
//  Consistent empty, loading, and error state views for dashboard cards.
//  Provides shimmer skeleton placeholders and themed empty states that
//  match the macGlassCard visual language.
//

import SwiftUI

// MARK: - Shimmer Effect

/// Animated shimmer modifier for skeleton loading placeholders.
/// Sweeps a highlight from left to right to indicate loading progress.
struct ShimmerModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @State private var phase: CGFloat = -1.0

    private var sweepColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.10)
            : Color.white.opacity(0.55)
    }

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { _ in
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: max(0, phase - 0.15)),
                            .init(color: sweepColor, location: phase),
                            .init(color: .clear, location: min(1, phase + 0.15)),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
                .allowsHitTesting(false)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 2.0
                }
            }
    }
}

extension View {
    /// Adds an animated shimmer sweep to indicate loading state.
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

// MARK: - Skeleton Shapes

/// A rounded placeholder bar that shimmers — used to build skeleton layouts.
struct SkeletonBar: View {
    @Environment(\.colorScheme) private var colorScheme
    var width: CGFloat? = nil
    var height: CGFloat = 10
    var cornerRadius: CGFloat = 4
    var opacity: Double = 0.12

    private var fillColor: Color {
        // In light mode, a darker base reads against the bright glass card;
        // in dark mode, white over dark glass is correct.
        colorScheme == .dark
            ? Color.white.opacity(opacity)
            : Color(red: 0.20, green: 0.27, blue: 0.39).opacity(min(1.0, opacity * 2.4))
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(fillColor)
            .frame(width: width, height: height)
            .shimmer()
    }
}

/// A circular skeleton placeholder.
struct SkeletonCircle: View {
    @Environment(\.colorScheme) private var colorScheme
    var size: CGFloat = 24
    var opacity: Double = 0.12

    private var fillColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(opacity)
            : Color(red: 0.20, green: 0.27, blue: 0.39).opacity(min(1.0, opacity * 2.4))
    }

    var body: some View {
        Circle()
            .fill(fillColor)
            .frame(width: size, height: size)
            .shimmer()
    }
}

// MARK: - Card Loading Skeleton

/// A generic skeleton layout for dashboard cards during initial data load.
/// Matches the visual cadence of a typical card: header line, 2-3 body lines, chart area.
struct CardLoadingSkeleton: View {
    var showChart: Bool = true
    var lineCount: Int = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header skeleton
            HStack {
                SkeletonCircle(size: 5, opacity: 0.08)
                SkeletonBar(width: 100, height: 8, opacity: 0.08)
                Spacer()
                SkeletonBar(width: 40, height: 8, opacity: 0.06)
            }

            // Body lines
            VStack(alignment: .leading, spacing: 6) {
                ForEach(0..<lineCount, id: \.self) { i in
                    SkeletonBar(
                        width: i == lineCount - 1 ? 120 : nil,
                        height: i == 0 ? 18 : 10,
                        opacity: i == 0 ? 0.15 : 0.10
                    )
                }
            }

            // Chart placeholder
            if showChart {
                RoundedRectangle(cornerRadius: 6)
                    .fill(MacTheme.Colors.chartSurface)
                    .frame(height: 34)
                    .shimmer()
            }
        }
    }
}

// MARK: - Card Empty State

/// A themed empty state for cards that have no data to display.
/// Shows an icon, title, and optional description within the card's visual language.
struct CardEmptyState: View {
    let icon: String
    let title: String
    var description: String? = nil

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(MacTheme.Colors.labelTertiary)

            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(MacTheme.Colors.labelSecondary)

            if let description {
                Text(description)
                    .font(.system(size: 10))
                    .foregroundStyle(MacTheme.Colors.labelTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Card Error State

/// A themed error state for cards that failed to load data.
struct CardErrorState: View {
    let message: String
    var retryAction: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 18))
                .foregroundStyle(MacTheme.Colors.warning.opacity(0.85))

            Text(message)
                .font(.system(size: 10))
                .foregroundStyle(MacTheme.Colors.labelSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)

            if let retryAction {
                Button("Retry", action: retryAction)
                    .font(.system(size: 10, weight: .medium))
                    .buttonStyle(.plain)
                    .foregroundStyle(MacTheme.Colors.info)
                    .accessibilityIdentifier("cardError_button_retry")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Card State Wrapper

/// Convenience wrapper that switches between loading, empty, error, and content states.
///
/// Usage:
/// ```swift
/// CardStateView(
///     isLoading: vm.isLoading,
///     isEmpty: vm.data.isEmpty,
///     error: vm.error,
///     emptyIcon: "wifi.slash",
///     emptyTitle: "No WiFi",
///     showChart: true
/// ) {
///     // Your card content
/// }
/// ```
struct CardStateView<Content: View>: View {
    let isLoading: Bool
    let isEmpty: Bool
    var error: String? = nil
    var emptyIcon: String = "tray"
    var emptyTitle: String = "No data"
    var emptyDescription: String? = nil
    var showChart: Bool = true
    var skeletonLines: Int = 3
    var retryAction: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        if isLoading {
            CardLoadingSkeleton(showChart: showChart, lineCount: skeletonLines)
        } else if let error {
            CardErrorState(message: error, retryAction: retryAction)
        } else if isEmpty {
            CardEmptyState(icon: emptyIcon, title: emptyTitle, description: emptyDescription)
        } else {
            content()
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Card States") {
    HStack(spacing: 16) {
        VStack(alignment: .leading, spacing: 4) {
            Text("Loading").font(.caption).foregroundStyle(.secondary)
            CardLoadingSkeleton()
                .macGlassCard(cornerRadius: 14, padding: 10)
        }

        VStack(alignment: .leading, spacing: 4) {
            Text("Empty").font(.caption).foregroundStyle(.secondary)
            CardEmptyState(
                icon: "wifi.slash",
                title: "No WiFi",
                description: "Connect to a wireless network"
            )
            .macGlassCard(cornerRadius: 14, padding: 10)
        }

        VStack(alignment: .leading, spacing: 4) {
            Text("Error").font(.caption).foregroundStyle(.secondary)
            CardErrorState(
                message: "Failed to load ISP info",
                retryAction: {}
            )
            .macGlassCard(cornerRadius: 14, padding: 10)
        }
    }
    .frame(height: 160)
    .padding()
    .background(MacTheme.Colors.backgroundBase)
}
#endif
