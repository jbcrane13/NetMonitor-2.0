import Foundation
import os

/// Service for measuring internet download/upload speed and latency
@MainActor
@Observable
public final class SpeedTestService: SpeedTestServiceProtocol {
    // MARK: - Public State

    public var downloadSpeed: Double = 0  // Mbps
    public var uploadSpeed: Double = 0    // Mbps
    public var latency: Double = 0        // ms
    public var progress: Double = 0       // 0-1
    public var phase: SpeedTestPhase = .idle
    public var isRunning: Bool = false
    public var errorMessage: String?
    public var duration: TimeInterval = 5.0  // seconds per phase

    // MARK: - Private

    private var currentTask: Task<SpeedTestData, Error>?
    private var downloadBytesReceived: Int64 = 0
    private var uploadBytesSent: Int64 = 0
    private let session: URLSession

    /// Creates a SpeedTestService.
    ///
    /// - Parameter session: URLSession used for latency measurement. Defaults to `.shared`.
    ///   Inject a custom session (e.g. one configured with `MockURLProtocol`) for testing.
    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Public API

    public func startTest() async throws -> SpeedTestData {
        reset()
        isRunning = true

        let task = Task<SpeedTestData, Error> {
            // Phase 1: Latency
            phase = .latency
            let measuredLatency = await measureLatency()
            try Task.checkCancellation()
            latency = measuredLatency

            // Phase 2: Download
            phase = .download
            let dlSpeed = try await measureDownload()
            try Task.checkCancellation()
            downloadSpeed = dlSpeed

            // Phase 3: Upload
            phase = .upload
            progress = 0
            let ulSpeed = try await measureUpload()
            try Task.checkCancellation()
            uploadSpeed = ulSpeed

            // Complete
            phase = .complete
            progress = 1
            isRunning = false

            return SpeedTestData(
                downloadSpeed: downloadSpeed,
                uploadSpeed: uploadSpeed,
                latency: latency
            )
        }

        currentTask = task

        do {
            let result = try await task.value
            return result
        } catch {
            isRunning = false
            if !(error is CancellationError) {
                errorMessage = error.localizedDescription
                phase = .idle
            }
            throw error
        }
    }

    public func stopTest() {
        currentTask?.cancel()
        currentTask = nil
        isRunning = false
        phase = .idle
    }

    // MARK: - Latency Measurement

    private func measureLatency() async -> Double {
        let iterations = 3
        var times: [Double] = []
        let session = self.session
        let url = URL(string: "https://speed.cloudflare.com/__down?bytes=1000000")!

        for _ in 0..<iterations {
            let start = Date()
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            do {
                let (_, _) = try await session.data(for: request)
                let elapsed = Date().timeIntervalSince(start) * 1000
                times.append(elapsed)
            } catch {
                continue
            }
        }

        guard !times.isEmpty else { return 0 }
        return times.reduce(0, +) / Double(times.count)
    }

    // MARK: - Download Measurement

    /// Use parallel connections to saturate the link (like real speed tests do)
    private func measureDownload() async throws -> Double {
        let chunkSize = 10_000_000 // 10MB chunks for better throughput
        let parallelStreams = 6
        let startTime = Date()
        let totalBytesAtomic = AtomicInt64()

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<parallelStreams {
                group.addTask { [duration] in
                    let session = URLSession(configuration: .ephemeral)
                    defer { session.invalidateAndCancel() }
                    let url = URL(string: "https://speed.cloudflare.com/__down?bytes=\(chunkSize)")!

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
                    }
                }
            }

            // Progress updater
            group.addTask { [duration] in
                while Date().timeIntervalSince(startTime) < duration {
                    try Task.checkCancellation()
                    let elapsed = Date().timeIntervalSince(startTime)
                    let bytes = totalBytesAtomic.load()
                    let speed = elapsed > 0 ? Double(bytes * 8) / elapsed / 1_000_000 : 0
                    await MainActor.run { [speed, elapsed, bytes, duration] in
                        self.downloadSpeed = speed
                        self.progress = min(elapsed / duration, 1.0)
                        self.downloadBytesReceived = bytes
                    }
                    try await Task.sleep(for: .milliseconds(200))
                }
            }

            try await group.waitForAll()
        }

        let totalElapsed = Date().timeIntervalSince(startTime)
        let totalBytes = totalBytesAtomic.load()
        guard totalElapsed > 0, totalBytes > 0 else { return 0 }
        let finalSpeed = Double(totalBytes * 8) / totalElapsed / 1_000_000
        downloadSpeed = finalSpeed
        progress = 1.0
        return finalSpeed
    }

    // MARK: - Upload Measurement

    private func measureUpload() async throws -> Double {
        let chunkSize = 1_000_000 // 1MB upload chunks
        let parallelStreams = 4
        let startTime = Date()
        let totalBytesAtomic = AtomicInt64()

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<parallelStreams {
                group.addTask { [duration] in
                    let session = URLSession(configuration: .ephemeral)
                    defer { session.invalidateAndCancel() }
                    let url = URL(string: "https://speed.cloudflare.com/__up")!
                    let uploadData = Data(count: chunkSize)

                    while Date().timeIntervalSince(startTime) < duration {
                        try Task.checkCancellation()
                        var request = URLRequest(url: url)
                        request.httpMethod = "POST"
                        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
                        request.setValue(String(uploadData.count), forHTTPHeaderField: "Content-Length")
                        request.timeoutInterval = 10
                        let (_, response) = try await session.upload(for: request, from: uploadData)
                        guard let http = response as? HTTPURLResponse,
                              (200...299).contains(http.statusCode) else {
                            continue
                        }
                        totalBytesAtomic.add(Int64(chunkSize))
                    }
                }
            }

            // Progress updater
            group.addTask { [duration] in
                while Date().timeIntervalSince(startTime) < duration {
                    try Task.checkCancellation()
                    let elapsed = Date().timeIntervalSince(startTime)
                    let bytes = totalBytesAtomic.load()
                    let speed = elapsed > 0 ? Double(bytes * 8) / elapsed / 1_000_000 : 0
                    await MainActor.run { [speed, elapsed, bytes, duration] in
                        self.uploadSpeed = speed
                        self.progress = min(elapsed / duration, 1.0)
                        self.uploadBytesSent = bytes
                    }
                    try await Task.sleep(for: .milliseconds(200))
                }
            }

            try await group.waitForAll()
        }

        let totalElapsed = Date().timeIntervalSince(startTime)
        let totalBytes = totalBytesAtomic.load()
        guard totalElapsed > 0, totalBytes > 0 else { return 0 }
        let finalSpeed = Double(totalBytes * 8) / totalElapsed / 1_000_000
        uploadSpeed = finalSpeed
        progress = 1.0
        return finalSpeed
    }

    // MARK: - Helpers

    private func reset() {
        downloadSpeed = 0
        uploadSpeed = 0
        latency = 0
        progress = 0
        phase = .idle
        errorMessage = nil
        downloadBytesReceived = 0
        uploadBytesSent = 0
    }
}

// MARK: - Thread-Safe Counter

/// Lock-based atomic counter for parallel stream byte tracking
public final class AtomicInt64: Sendable {
    private let storage = OSAllocatedUnfairLock(initialState: Int64(0))

    public init() {}

    public func add(_ delta: Int64) {
        storage.withLock { $0 += delta }
    }

    public func load() -> Int64 {
        storage.withLock { $0 }
    }
}

// MARK: - Errors

/// Legacy alias — new code should use NetworkError directly
public enum SpeedTestError: LocalizedError {
    case serverError
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .serverError: "Speed test server returned an error"
        case .cancelled: "Speed test was cancelled"
        }
    }

    public var asNetworkError: NetworkError {
        switch self {
        case .serverError: .serverError
        case .cancelled: .cancelled
        }
    }
}
