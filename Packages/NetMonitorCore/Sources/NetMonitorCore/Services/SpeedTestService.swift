import Foundation
import os

/// Service for measuring internet download/upload speed and latency
@MainActor
@Observable
public final class SpeedTestService: SpeedTestServiceProtocol {
    // MARK: - Public State

    public var downloadSpeed: Double = 0  // Mbps (current/final average)
    public var uploadSpeed: Double = 0    // Mbps (current/final average)
    public var peakDownloadSpeed: Double = 0  // Mbps (max observed)
    public var peakUploadSpeed: Double = 0    // Mbps (max observed)
    public var latency: Double = 0        // ms
    public var jitter: Double = 0         // ms
    public var progress: Double = 0       // 0-1
    public var phase: SpeedTestPhase = .idle
    public var isRunning: Bool = false
    public var errorMessage: String?
    public var duration: TimeInterval = 5.0  // seconds per phase
    /// The server to use for the next test. nil = auto (Cloudflare default).
    public var selectedServer: SpeedTestServer?

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

        // Capture the selected server so it stays consistent throughout the test run
        let server = selectedServer

        let task = Task<SpeedTestData, Error> {
            // Phase 1: Latency
            phase = .latency
            let measuredLatency = await measureLatency(server: server)
            try Task.checkCancellation()
            latency = measuredLatency

            // Phase 2: Download
            phase = .download
            let dlSpeed = try await measureDownload(server: server)
            try Task.checkCancellation()
            downloadSpeed = dlSpeed

            // Phase 3: Upload
            phase = .upload
            progress = 0
            let ulSpeed = try await measureUpload(server: server)
            try Task.checkCancellation()
            uploadSpeed = ulSpeed

            // Complete
            phase = .complete
            progress = 1
            isRunning = false

            return SpeedTestData(
                downloadSpeed: downloadSpeed,
                uploadSpeed: uploadSpeed,
                latency: latency,
                jitter: jitter > 0 ? jitter : nil,
                serverName: server?.isAutoSelect == false ? server?.name : nil
            )
        }

        currentTask = task

        do {
            return try await task.value
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

    private func measureLatency(server: SpeedTestServer?) async -> Double {
        let iterations = 3
        var times: [Double] = []
        let session = self.session
        let baseURLString = server?.pingURL ?? "https://speed.cloudflare.com"
        let url = URL(string: baseURLString)!

        for _ in 0..<iterations {
            let start = Date()
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            do {
                let _ = try await session.data(for: request)
                let elapsed = Date().timeIntervalSince(start) * 1000
                times.append(elapsed)
            } catch {
                continue
            }
        }

        guard !times.isEmpty else { return 0 }
        let avg = times.reduce(0, +) / Double(times.count)
        // Calculate jitter as mean absolute deviation between consecutive samples
        if times.count >= 2 {
            var diffs: [Double] = []
            for i in 1..<times.count {
                diffs.append(abs(times[i] - times[i - 1]))
            }
            jitter = diffs.reduce(0, +) / Double(diffs.count)
        }
        return avg
    }

    // MARK: - Download Measurement

    /// Use parallel connections to saturate the link (like real speed tests do)
    private func measureDownload(server: SpeedTestServer?) async throws -> Double {
        let parallelStreams = 8
        let startTime = Date()
        let totalBytesAtomic = AtomicInt64()
        let peakSpeedAtomic = AtomicInt64() // stores peak Kbps * 10 for precision
        let downloadURLString = server?.downloadURL ?? "https://speed.cloudflare.com/__down?bytes=25000000"

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<parallelStreams {
                group.addTask { [duration, downloadURLString] in
                    let session = URLSession(configuration: .ephemeral)
                    defer { session.invalidateAndCancel() }
                    let url = URL(string: downloadURLString)!

                    while Date().timeIntervalSince(startTime) < duration {
                        try Task.checkCancellation()
                        var request = URLRequest(url: url)
                        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
                        // Static-file servers (Linode/OVH) serve 100 MB files — need
                        // long timeout so we can stream partial bytes for the test window.
                        request.timeoutInterval = 120
                        let (bytes, response) = try await session.bytes(for: request)
                        guard let http = response as? HTTPURLResponse,
                              (200...299).contains(http.statusCode) else {
                            continue
                        }
                        // Stream 64 KB chunks, counting bytes as they arrive so static-file
                        // servers contribute partial data even if download doesn't finish.
                        let chunkCapacity = 65_536
                        var buffer = [UInt8]()
                        buffer.reserveCapacity(chunkCapacity)
                        for try await byte in bytes {
                            buffer.append(byte)
                            if buffer.count >= chunkCapacity {
                                totalBytesAtomic.add(Int64(buffer.count))
                                buffer.removeAll(keepingCapacity: true)
                                if Date().timeIntervalSince(startTime) >= duration { break }
                            }
                        }
                        if !buffer.isEmpty {
                            totalBytesAtomic.add(Int64(buffer.count))
                        }
                    }
                }
            }

            // Progress updater — samples every 200ms, tracks rolling 1s window for peak
            group.addTask { [duration] in
                var lastBytes: Int64 = 0
                var lastTime = startTime
                // Rolling window for instantaneous speed (last 1 second)
                var samples: [(time: Date, bytes: Int64)] = []

                while Date().timeIntervalSince(startTime) < duration {
                    try Task.checkCancellation()
                    let now = Date()
                    let totalElapsed = now.timeIntervalSince(startTime)
                    let currentBytes = totalBytesAtomic.load()

                    // Overall average speed
                    let avgSpeed = totalElapsed > 0 ? Double(currentBytes * 8) / totalElapsed / 1_000_000 : 0

                    // Rolling 1-second window for instantaneous/peak speed
                    samples.append((time: now, bytes: currentBytes))
                    samples = samples.filter { now.timeIntervalSince($0.time) <= 1.5 }
                    var instantSpeed = avgSpeed
                    if let oldest = samples.first, samples.count > 1 {
                        let windowTime = now.timeIntervalSince(oldest.time)
                        let windowBytes = currentBytes - oldest.bytes
                        if windowTime > 0.3 {
                            instantSpeed = Double(windowBytes * 8) / windowTime / 1_000_000
                        }
                    }

                    // Track peak (store as Kbps * 10 in atomic)
                    let instantKbps10 = Int64(instantSpeed * 10_000)
                    let currentPeak = peakSpeedAtomic.load()
                    if instantKbps10 > currentPeak {
                        peakSpeedAtomic.store(instantKbps10)
                    }

                    await MainActor.run { [avgSpeed, instantSpeed, totalElapsed, currentBytes, duration] in
                        // Show instantaneous speed during test for responsive gauge
                        self.downloadSpeed = instantSpeed
                        self.progress = min(totalElapsed / duration, 1.0)
                        self.downloadBytesReceived = currentBytes
                        self.peakDownloadSpeed = max(self.peakDownloadSpeed, instantSpeed)
                    }

                    lastBytes = currentBytes
                    lastTime = now
                    try await Task.sleep(for: .milliseconds(200))
                }
            }

            try await group.waitForAll()
        }

        let totalElapsed = Date().timeIntervalSince(startTime)
        let totalBytes = totalBytesAtomic.load()
        guard totalElapsed > 0, totalBytes > 0 else { return 0 }
        // Final result uses overall average (consistent with industry standard)
        let finalSpeed = Double(totalBytes * 8) / totalElapsed / 1_000_000
        downloadSpeed = finalSpeed
        progress = 1.0
        return finalSpeed
    }

    // MARK: - Upload Measurement

    private func measureUpload(server: SpeedTestServer?) async throws -> Double {
        let chunkSize = 4_000_000 // 4MB upload chunks for better throughput
        let parallelStreams = 6
        let startTime = Date()
        let totalBytesAtomic = AtomicInt64()
        let uploadURLString = server?.uploadURL ?? "https://speed.cloudflare.com/__up"

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<parallelStreams {
                group.addTask { [duration, uploadURLString] in
                    let session = URLSession(configuration: .ephemeral)
                    defer { session.invalidateAndCancel() }
                    let url = URL(string: uploadURLString)!
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

            // Progress updater with peak tracking
            group.addTask { [duration] in
                var samples: [(time: Date, bytes: Int64)] = []

                while Date().timeIntervalSince(startTime) < duration {
                    try Task.checkCancellation()
                    let now = Date()
                    let totalElapsed = now.timeIntervalSince(startTime)
                    let currentBytes = totalBytesAtomic.load()

                    let avgSpeed = totalElapsed > 0 ? Double(currentBytes * 8) / totalElapsed / 1_000_000 : 0

                    samples.append((time: now, bytes: currentBytes))
                    samples = samples.filter { now.timeIntervalSince($0.time) <= 1.5 }
                    var instantSpeed = avgSpeed
                    if let oldest = samples.first, samples.count > 1 {
                        let windowTime = now.timeIntervalSince(oldest.time)
                        let windowBytes = currentBytes - oldest.bytes
                        if windowTime > 0.3 {
                            instantSpeed = Double(windowBytes * 8) / windowTime / 1_000_000
                        }
                    }

                    await MainActor.run { [instantSpeed, totalElapsed, currentBytes, duration] in
                        self.uploadSpeed = instantSpeed
                        self.progress = min(totalElapsed / duration, 1.0)
                        self.uploadBytesSent = currentBytes
                        self.peakUploadSpeed = max(self.peakUploadSpeed, instantSpeed)
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
        peakDownloadSpeed = 0
        peakUploadSpeed = 0
        latency = 0
        jitter = 0
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

    public func store(_ value: Int64) {
        storage.withLock { $0 = value }
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
