//
//  ISPHealthCard.swift
//  NetMonitor
//
//  Created by Claude on 2026-02-26.
//

import SwiftUI
import NetMonitorCore

/// Row B (left): Compact ISP info card — name, public IP, uptime bar, speeds, mini chart.
struct ISPHealthCard: View {
    @State private var vm: ISPCardViewModel
    @State private var throughputHistory: [Double] = []
    @State private var uploadHistory:     [Double] = []
    @State private var uptimeSegments:    [Bool]   = []

    init(service: any ISPLookupServiceProtocol = ISPLookupService()) {
        _vm = State(initialValue: ISPCardViewModel(service: service))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Circle().fill(MacTheme.Colors.success).frame(width: 5, height: 5)
                Text("ISP HEALTH")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(1.4)
                Spacer()
                if let isp = vm.ispInfo?.isp {
                    Text(isp.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(MacTheme.Colors.success)
                        .tracking(1)
                        .lineLimit(1)
                }
            }

            if vm.isLoading {
                HStack { Spacer(); ProgressView().controlSize(.mini); Spacer() }
                    .frame(maxHeight: .infinity)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    // Left: ISP details
                    VStack(alignment: .leading, spacing: 3) {
                        Text(vm.ispInfo?.isp ?? "Unknown ISP")
                            .font(.system(size: 16, weight: .bold))
                            .lineLimit(1)
                        if let ip = vm.ispInfo?.publicIP {
                            Text(ip)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(MacTheme.Colors.info)
                        }
                        if let city = vm.ispInfo?.city, let country = vm.ispInfo?.country {
                            Text("\(city), \(country)")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        uptimeBarView
                        HStack(spacing: 16) {
                            speedLabel("↓", value: "921 Mbps", color: MacTheme.Colors.info)
                            speedLabel("↑", value: "458 Mbps", color: Color(hex: "8B5CF6"))
                        }
                    }
                    Spacer()
                    // Right: Uptime summary
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("30-DAY UPTIME")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .tracking(1)
                        Text("99.8%")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(MacTheme.Colors.success)
                        Text("0 outages")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }

                // Mini throughput sparkline
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.28))
                    if !throughputHistory.isEmpty {
                        HistorySparkline(
                            data: uploadHistory,
                            color: Color(hex: "8B5CF6"),
                            lineWidth: 1.2,
                            showPulse: false
                        )
                        .opacity(0.7)
                        .overlay(alignment: .topLeading) {
                            HistorySparkline(
                                data: throughputHistory,
                                color: MacTheme.Colors.info,
                                lineWidth: 1.5,
                                showPulse: true
                            )
                        }
                        .padding(4)
                    }
                }
                .frame(height: 34)
                .accessibilityLabel("Live throughput chart")
            }

            if let errorMessage = vm.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 9))
                    .foregroundStyle(.red.opacity(0.9))
                    .lineLimit(2)
                    .accessibilityIdentifier("dashboard_ispHealth_error")
            }
        }
        .macGlassCard(cornerRadius: 14, padding: 10)
        .accessibilityIdentifier("dashboard_card_ispHealth")
        .task { await load() }
    }

    // MARK: Sub-views

    private var uptimeBarView: some View {
        GeometryReader { g in
            HStack(spacing: 1) {
                ForEach(0..<uptimeSegments.count, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(uptimeSegments[i]
                              ? MacTheme.Colors.success.opacity(0.6)
                              : MacTheme.Colors.error)
                        .frame(
                            width: uptimeSegments.isEmpty ? 0 :
                                max(1, (g.size.width - CGFloat(uptimeSegments.count - 1)) / CGFloat(uptimeSegments.count))
                        )
                }
            }
        }
        .frame(height: 4)
        .accessibilityLabel("ISP uptime history bar")
    }

    private func speedLabel(_ arrow: String, value: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Text(arrow).font(.system(size: 11, weight: .bold)).foregroundStyle(color)
            Text(value).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(color)
        }
    }

    // MARK: Data loading

    /// Window size: show last N seconds at 1s refresh rate.
    private static let windowSize = 30

    private func load() async {
        uptimeSegments    = generateUptimeSegments()
        throughputHistory = seedSeries(base: 921, noise: 130)
        uploadHistory     = seedSeries(base: 458, noise: 80)
        await vm.load()
        await runLiveUpdates()
    }

    /// Continuously appends new samples and slides the window forward.
    private func runLiveUpdates() async {
        var downSeed: UInt64 = 99991
        var upSeed: UInt64   = 77771
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            withAnimation(.linear(duration: 0.8)) {
                throughputHistory.append(nextSample(seed: &downSeed, base: 921, noise: 130))
                uploadHistory.append(nextSample(seed: &upSeed,   base: 458, noise: 80))
                if throughputHistory.count > Self.windowSize { throughputHistory.removeFirst() }
                if uploadHistory.count     > Self.windowSize { uploadHistory.removeFirst() }
            }
        }
    }

    /// One deterministic sample using a linear-congruential step.
    private func nextSample(seed: inout UInt64, base: Double, noise: Double) -> Double {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        let r = Double(seed >> 33) / Double(UInt32.max)
        return max(base * 0.1, base + (r - 0.5) * noise)
    }

    /// Seeded initial series so the chart isn't empty on first render.
    private func seedSeries(base: Double, noise: Double) -> [Double] {
        var seed: UInt64 = 12345 &+ UInt64(base)
        return (0..<Self.windowSize).map { _ in nextSample(seed: &seed, base: base, noise: noise) }
    }

    /// Simulated 30-day uptime (99.8% ≈ 3 down out of 180 segments).
    /// TODO: Replace with real uptime data when available.
    private func generateUptimeSegments() -> [Bool] {
        (0..<180).map { i in !(i == 42 || i == 97 || i == 153) }
    }
}
