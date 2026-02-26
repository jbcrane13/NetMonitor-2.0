//
//  SpeedTestToolView.swift
//  NetMonitor
//
//  Speed test tool that measures download speed using public test files.
//

import SwiftUI
import NetMonitorCore
import libkern

struct SpeedTestToolView: View {
    @Environment(\.appAccentColor) private var accentColor
    @State private var isRunning = false
    @State private var phase: SpeedTestPhase = .idle
    @State private var pingLatency: Double?
    @State private var downloadSpeed: Double?
    @State private var uploadSpeed: Double?
    @State private var peakDownloadSpeed: Double?
    @State private var peakUploadSpeed: Double?
    @State private var downloadSamples: [Double] = []
    @State private var uploadSamples: [Double] = []
    @State private var progress: Double = 0
    @State private var errorMessage: String?
    @State private var speedTestTask: Task<Void, Never>?
    @State private var testDuration: TimeInterval = 10 // Default 10 seconds
    @State private var timeRemaining: TimeInterval = 0
    @State private var selectedServer: SpeedTestServer = .autoSelect

    var body: some View {
        ToolSheetContainer(
            title: "Speed Test",
            iconName: "speedometer",
            closeAccessibilityID: "speedtest_button_close",
            minWidth: 600,
            minHeight: 500,
            inputArea: { contentArea },
            footerContent: { footer }
        )
        .onDisappear {
            speedTestTask?.cancel()
            speedTestTask = nil
        }
    }

    // MARK: - Content Area

    private var contentArea: some View {
        VStack(spacing: 32) {
            // Configuration row: duration + server
            HStack(spacing: 32) {
                // Duration picker
                VStack(spacing: 8) {
                    Text("Test Duration")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("Duration", selection: $testDuration) {
                        Text("5 seconds").tag(TimeInterval(5))
                        Text("10 seconds").tag(TimeInterval(10))
                        Text("30 seconds").tag(TimeInterval(30))
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 300)
                    .disabled(isRunning)
                    .accessibilityIdentifier("speedtest_picker_duration")
                }

                // Server picker
                VStack(spacing: 8) {
                    Text("Server")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("Server", selection: $selectedServer) {
                        ForEach(SpeedTestServer.all) { server in
                            Text(server.name).tag(server)
                        }
                    }
                    .frame(maxWidth: 180)
                    .disabled(isRunning)
                    .accessibilityIdentifier("speedtest_picker_server")
                }
            }

            Spacer()

            // Speedometer display
            speedometerView

            // Time remaining during test
            if isRunning && (phase == .download || phase == .upload) && timeRemaining > 0 {
                Text("Time remaining: \(Int(timeRemaining))s")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Results
            resultsView

            Spacer()

            // Start button
            if !isRunning {
                Button {
                    runSpeedTest()
                } label: {
                    Label("Start Test", systemImage: "play.fill")
                        .font(.headline)
                        .frame(width: 200)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("speedtest_button_start")
            } else {
                Button {
                    stopSpeedTest()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.headline)
                        .frame(width: 200)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityIdentifier("speedtest_button_stop")
            }

            Spacer()
        }
        .padding()
        .background(Color.black.opacity(0.2))
    }

    private var speedometerView: some View {
        ZStack {
            // Background arc
            Circle()
                .trim(from: 0.15, to: 0.85)
                .stroke(Color.gray.opacity(0.3), lineWidth: 20)
                .rotationEffect(.degrees(90))
                .frame(width: 200, height: 200)

            // Progress arc
            Circle()
                .trim(from: 0.15, to: 0.15 + (0.7 * min(progress, 1.0)))
                .stroke(
                    LinearGradient(
                        colors: [accentColor, .green],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 20, lineCap: .round)
                )
                .rotationEffect(.degrees(90))
                .frame(width: 200, height: 200)
                .animation(.easeInOut(duration: 0.3), value: progress)

            // Center display
            VStack(spacing: 4) {
                if isRunning {
                    Text(phase.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if phase == .complete {
                    Text("Complete")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                if phase == .download, let speed = downloadSpeed {
                    Text(formatSpeed(speed))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                } else if phase == .upload, let speed = uploadSpeed {
                    Text(formatSpeed(speed))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                } else if phase == .complete, let speed = downloadSpeed {
                    Text(formatSpeed(speed))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                } else if isRunning {
                    ProgressView()
                        .scaleEffect(1.5)
                } else {
                    Text("--")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("Mbps")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var resultsView: some View {
        HStack(spacing: 48) {
            // Ping
            VStack(spacing: 4) {
                Image(systemName: "waveform.path")
                    .font(.title2)
                    .foregroundStyle(accentColor)

                if let ping = pingLatency {
                    Text(String(format: "%.0f", ping))
                        .font(.title2.bold())
                    Text("ms ping")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("--")
                        .font(.title2.bold())
                        .foregroundStyle(.secondary)
                    Text("ms ping")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            // Download
            VStack(spacing: 4) {
                Image(systemName: "arrow.down.circle")
                    .font(.title2)
                    .foregroundStyle(.green)

                if let speed = downloadSpeed {
                    Text(formatSpeed(speed))
                        .font(.title2.bold())
                    Text("avg down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let peak = peakDownloadSpeed {
                        Text("Peak: \(formatSpeed(peak))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("--")
                        .font(.title2.bold())
                        .foregroundStyle(.secondary)
                    Text("down")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            // Upload
            VStack(spacing: 4) {
                Image(systemName: "arrow.up.circle")
                    .font(.title2)
                    .foregroundStyle(.blue)

                if let speed = uploadSpeed {
                    Text(formatSpeed(speed))
                        .font(.title2.bold())
                    Text("avg up")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let peak = peakUploadSpeed {
                        Text("Peak: \(formatSpeed(peak))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("--")
                        .font(.title2.bold())
                        .foregroundStyle(.secondary)
                    Text("up")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            // Server
            VStack(spacing: 4) {
                Image(systemName: "server.rack")
                    .font(.title2)
                    .foregroundStyle(.orange)

                Text(selectedServer.name)
                    .font(.title3.bold())
                Text(selectedServer.location)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if let error = errorMessage {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(error)
                    .foregroundStyle(.secondary)
            } else if isRunning {
                Text(phase.description)
                    .foregroundStyle(.secondary)
            } else if downloadSpeed != nil || uploadSpeed != nil {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Test completed")
                    .foregroundStyle(.secondary)
            } else {
                Text("Test your internet connection speed")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if (downloadSpeed != nil || uploadSpeed != nil) && !isRunning {
                Button("Reset") {
                    resetTest()
                }
                .accessibilityIdentifier("speedtest_button_reset")
            }
        }
        .padding()
    }

    // MARK: - Actions

    private func runSpeedTest() {
        isRunning = true
        errorMessage = nil
        pingLatency = nil
        downloadSpeed = nil
        uploadSpeed = nil
        peakDownloadSpeed = nil
        peakUploadSpeed = nil
        downloadSamples = []
        uploadSamples = []
        progress = 0
        timeRemaining = 0

        // Capture the server selection so it stays consistent during the test.
        let server = selectedServer

        speedTestTask = Task {
            // Phase 1: Latency test
            await MainActor.run { phase = .latency }
            pingLatency = await measurePing(server: server)

            guard isRunning else { return }

            // Phase 2: Download test
            await MainActor.run { phase = .download }
            downloadSpeed = await measureDownload(server: server)

            guard isRunning else { return }

            // Phase 3: Upload test
            await MainActor.run { phase = .upload }
            uploadSpeed = await measureUpload(server: server)

            await MainActor.run {
                phase = .complete
                isRunning = false
            }
        }
    }

    private func stopSpeedTest() {
        speedTestTask?.cancel()
        speedTestTask = nil
        isRunning = false
        phase = .idle
        progress = 0
        timeRemaining = 0
    }

    private func resetTest() {
        pingLatency = nil
        downloadSpeed = nil
        uploadSpeed = nil
        peakDownloadSpeed = nil
        peakUploadSpeed = nil
        downloadSamples = []
        uploadSamples = []
        progress = 0
        phase = .idle
        errorMessage = nil
        timeRemaining = 0
    }

    // MARK: - Measurements

    private func measurePing(server: SpeedTestServer) async -> Double? {
        // Simple ping using HEAD request
        let startTime = Date()
        // Use the server's ping URL when available; fall back to Cloudflare.
        let pingURLString = server.pingURL ?? "https://speed.cloudflare.com"
        guard let pingURL = URL(string: pingURLString) else { return nil }

        do {
            var request = URLRequest(url: pingURL)
            request.httpMethod = "HEAD"
            request.timeoutInterval = 5

            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                return Date().timeIntervalSince(startTime) * 1000 // Convert to ms
            }
        } catch {
            await MainActor.run {
                errorMessage = "Ping failed: \(error.localizedDescription)"
            }
        }

        return nil
    }

    private func measureDownload(server: SpeedTestServer) async -> Double? {
        let chunkSize = 10_000_000 // 10MB chunks for better throughput
        let parallelStreams = 6
        let startTime = Date()
        let totalBytesAtomic = AtomicInt64()
        let peakAtomic = AtomicDouble()
        let duration = testDuration

        // Resolve download URL: prefer server's URL, fall back to Cloudflare.
        let downloadURLString = server.downloadURL ?? "https://speed.cloudflare.com/__down?bytes=\(chunkSize)"

        // Progress updater runs alongside the download streams
        let progressTask = Task {
            while Date().timeIntervalSince(startTime) < duration && !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(startTime)
                let bytes = totalBytesAtomic.load()
                let speed = elapsed > 0 ? Double(bytes * 8) / elapsed / 1_000_000 : 0
                let peak = peakAtomic.load()

                await MainActor.run {
                    self.downloadSpeed = speed
                    self.peakDownloadSpeed = peak
                    self.progress = min(elapsed / duration, 1.0)
                    self.timeRemaining = max(0, duration - elapsed)
                }

                try? await Task.sleep(for: .milliseconds(200))
            }
        }

        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for _ in 0..<parallelStreams {
                    group.addTask {
                        let session = URLSession(configuration: .ephemeral)
                        defer { session.invalidateAndCancel() }
                        let url = URL(string: downloadURLString) ?? URL(string: "https://speed.cloudflare.com/__down?bytes=\(chunkSize)")!

                        while Date().timeIntervalSince(startTime) < duration {
                            try Task.checkCancellation()
                            var request = URLRequest(url: url)
                            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
                            request.timeoutInterval = 10
                            let (data, response) = try await session.data(for: request)
                            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                                continue
                            }
                            totalBytesAtomic.add(Int64(data.count))

                            let elapsed = Date().timeIntervalSince(startTime)
                            let currentSpeed = elapsed > 0 ? Double(totalBytesAtomic.load() * 8) / elapsed / 1_000_000 : 0
                            peakAtomic.updateMax(currentSpeed)
                        }
                    }
                }

                try await group.waitForAll()
            }
        } catch is CancellationError {
            // Test was cancelled
        } catch {
            if isRunning {
                await MainActor.run {
                    errorMessage = "Download failed: \(error.localizedDescription)"
                }
            }
        }

        progressTask.cancel()

        let totalTime = Date().timeIntervalSince(startTime)
        let totalBytes = totalBytesAtomic.load()
        let finalSpeed = (totalBytes > 0 && totalTime > 0) ? Double(totalBytes * 8) / totalTime / 1_000_000 : nil
        let peak = peakAtomic.load()

        // Only update UI if the test wasn't stopped/cancelled
        await MainActor.run {
            guard isRunning else { return }
            downloadSpeed = finalSpeed
            peakDownloadSpeed = peak
            progress = 1.0
            timeRemaining = 0
        }

        return finalSpeed
    }

    private func measureUpload(server: SpeedTestServer) async -> Double? {
        let chunkSize = 1_000_000 // 1MB upload chunks
        let parallelStreams = 4
        let startTime = Date()
        let totalBytesAtomic = AtomicInt64()
        let peakAtomic = AtomicDouble()
        let duration = testDuration

        // Use the server's uploadURL when available; fall back to Cloudflare.
        let uploadURLString = server.uploadURL ?? "https://speed.cloudflare.com/__up"

        // Pre-generate upload payload once (reused across streams)
        let uploadData = Data(count: chunkSize)

        // Progress updater runs alongside the upload streams
        let progressTask = Task {
            while Date().timeIntervalSince(startTime) < duration && !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(startTime)
                let bytes = totalBytesAtomic.load()
                let speed = elapsed > 0 ? Double(bytes * 8) / elapsed / 1_000_000 : 0
                let peak = peakAtomic.load()

                await MainActor.run {
                    self.uploadSpeed = speed
                    self.peakUploadSpeed = peak
                    self.progress = min(elapsed / duration, 1.0)
                    self.timeRemaining = max(0, duration - elapsed)
                }

                try? await Task.sleep(for: .milliseconds(200))
            }
        }

        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for _ in 0..<parallelStreams {
                    group.addTask {
                        let session = URLSession(configuration: .ephemeral)
                        defer { session.invalidateAndCancel() }
                        let url = URL(string: uploadURLString) ?? URL(string: "https://speed.cloudflare.com/__up")!

                        while Date().timeIntervalSince(startTime) < duration {
                            try Task.checkCancellation()
                            var request = URLRequest(url: url)
                            request.httpMethod = "POST"
                            request.httpBody = uploadData
                            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
                            request.timeoutInterval = 10
                            let (_, response) = try await session.upload(for: request, from: uploadData)
                            guard let http = response as? HTTPURLResponse,
                                  (200...299).contains(http.statusCode) else {
                                continue
                            }
                            totalBytesAtomic.add(Int64(chunkSize))

                            let elapsed = Date().timeIntervalSince(startTime)
                            let currentSpeed = elapsed > 0 ? Double(totalBytesAtomic.load() * 8) / elapsed / 1_000_000 : 0
                            peakAtomic.updateMax(currentSpeed)
                        }
                    }
                }

                try await group.waitForAll()
            }
        } catch is CancellationError {
            // Test was cancelled
        } catch {
            if isRunning {
                await MainActor.run {
                    errorMessage = "Upload failed: \(error.localizedDescription)"
                }
            }
        }

        progressTask.cancel()

        let totalTime = Date().timeIntervalSince(startTime)
        let totalBytes = totalBytesAtomic.load()
        let finalSpeed = (totalBytes > 0 && totalTime > 0) ? Double(totalBytes * 8) / totalTime / 1_000_000 : nil
        let peak = peakAtomic.load()

        // Only update UI if the test wasn't stopped/cancelled
        await MainActor.run {
            guard isRunning else { return }
            uploadSpeed = finalSpeed
            peakUploadSpeed = peak
            progress = 1.0
            timeRemaining = 0
        }

        return finalSpeed
    }

}

// MARK: - SpeedTestPhase Display

fileprivate extension SpeedTestPhase {
    var description: String {
        switch self {
        case .idle: return "Ready"
        case .latency: return "Testing latency..."
        case .download: return "Testing download..."
        case .upload: return "Testing upload..."
        case .complete: return "Complete"
        }
    }
}

// MARK: - Thread-Safe Counters

/// Lock-free atomic counter for parallel stream byte tracking
private final class AtomicInt64: @unchecked Sendable {
    private let value = UnsafeMutablePointer<Int64>.allocate(capacity: 1)

    init() { value.initialize(to: 0) }
    deinit { value.deallocate() }

    func add(_ delta: Int64) {
        OSAtomicAdd64(delta, value)
    }

    func load() -> Int64 {
        OSAtomicAdd64(0, value)
    }
}

/// Thread-safe atomic double for tracking peak speeds
private final class AtomicDouble: @unchecked Sendable {
    private var lock = os_unfair_lock()
    private var _value: Double = 0

    func updateMax(_ newValue: Double) {
        os_unfair_lock_lock(&lock)
        if newValue > _value { _value = newValue }
        os_unfair_lock_unlock(&lock)
    }

    func load() -> Double {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return _value
    }
}

#Preview {
    SpeedTestToolView()
}
