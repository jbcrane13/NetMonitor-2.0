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

    /// Uses delegate-based URLSession for efficient chunked byte counting.
    /// URLSession delivers data in ~16-64 KB chunks via didReceive callbacks,
    /// avoiding the catastrophic per-byte overhead of AsyncBytes iteration.
    private func measureDownload(server: SpeedTestServer?) async throws -> Double {
        let parallelStreams = 8
        let startTime = Date()
        let totalBytesAtomic = AtomicInt64()
        // 25 MB per stream: large enough to saturate fast connections for the full
        // test duration without exhausting memory on iPhone (100 MB × 8 streams
        // caused stalls and download failures on device).
        let downloadURLString = server?.downloadURL ?? "https://speed.cloudflare.com/__down?bytes=25000000"
        let url = URL(string: downloadURLString)!

        // Create one URLSession per stream. A single session with multiple tasks to the same
        // host will have all tasks multiplexed over one HTTP/2 TCP connection, capping throughput.
        // Separate sessions each establish their own TCP connection, giving true parallel streams.
        var downloadSessions: [URLSession] = []
        defer { downloadSessions.forEach { $0.invalidateAndCancel() } }

        for _ in 0..<parallelStreams {
            let delegate = DownloadMeasurementDelegate(
                bytesReceived: totalBytesAtomic,
                downloadURL: url,
                startTime: startTime,
                duration: duration
            )
            let config = URLSessionConfiguration.ephemeral
            let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
            downloadSessions.append(session)

            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.timeoutInterval = max(duration + 10, 30)
            session.dataTask(with: request).resume()
        }

        // Progress loop — runs on MainActor, samples every 200ms
        var samples: [(time: Date, bytes: Int64)] = []

        while Date().timeIntervalSince(startTime) < duration {
            try Task.checkCancellation()
            let now = Date()
            let totalElapsed = now.timeIntervalSince(startTime)
            let currentBytes = totalBytesAtomic.load()

            let avgSpeed = totalElapsed > 0 ? Double(currentBytes * 8) / totalElapsed / 1_000_000 : 0

            // Rolling 1.5-second window for instantaneous/peak speed
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

            // Show instantaneous speed during test for responsive gauge
            downloadSpeed = instantSpeed
            progress = min(totalElapsed / duration, 1.0)
            downloadBytesReceived = currentBytes
            peakDownloadSpeed = max(peakDownloadSpeed, instantSpeed)

            try await Task.sleep(for: .milliseconds(200))
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

    /// Uses delegate-based URLSession with didSendBodyData callbacks to count
    /// bytes as they leave the device, rather than waiting for server acknowledgement.
    private func measureUpload(server: SpeedTestServer?) async throws -> Double {
        let chunkSize = 16_000_000 // 16 MB per stream — reduces restart gaps on fast connections
        let parallelStreams = 6
        let startTime = Date()
        let totalBytesAtomic = AtomicInt64()
        let uploadURLString = server?.uploadURL ?? "https://speed.cloudflare.com/__up"
        let url = URL(string: uploadURLString)!
        let uploadPayload = Data(count: chunkSize)

        // One URLSession per stream to force independent TCP connections (see measureDownload).
        var uploadSessions: [URLSession] = []
        defer { uploadSessions.forEach { $0.invalidateAndCancel() } }

        for _ in 0..<parallelStreams {
            let delegate = UploadMeasurementDelegate(
                bytesSent: totalBytesAtomic,
                uploadURL: url,
                uploadData: uploadPayload,
                startTime: startTime,
                duration: duration
            )
            let config = URLSessionConfiguration.ephemeral
            let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
            uploadSessions.append(session)

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = max(duration + 10, 15)
            session.uploadTask(with: request, from: uploadPayload).resume()
        }

        // Progress loop — runs on MainActor, samples every 200ms
        var samples: [(time: Date, bytes: Int64)] = []

        while Date().timeIntervalSince(startTime) < duration {
            try Task.checkCancellation()
            let now = Date()
            let totalElapsed = now.timeIntervalSince(startTime)
            let currentBytes = totalBytesAtomic.load()

            let avgSpeed = totalElapsed > 0 ? Double(currentBytes * 8) / totalElapsed / 1_000_000 : 0

            // Rolling 1.5-second window for instantaneous/peak speed
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

            uploadSpeed = instantSpeed
            progress = min(totalElapsed / duration, 1.0)
            uploadBytesSent = currentBytes
            peakUploadSpeed = max(peakUploadSpeed, instantSpeed)

            try await Task.sleep(for: .milliseconds(200))
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

// MARK: - Download Measurement Delegate

/// Counts received bytes efficiently via URLSession's chunked data delivery (~16-64 KB chunks).
/// Automatically restarts downloads when one completes, keeping all streams continuously saturated.
private final class DownloadMeasurementDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    let bytesReceived: AtomicInt64
    private let downloadURL: URL
    private let startTime: Date
    private let duration: TimeInterval

    init(bytesReceived: AtomicInt64, downloadURL: URL, startTime: Date, duration: TimeInterval) {
        self.bytesReceived = bytesReceived
        self.downloadURL = downloadURL
        self.startTime = startTime
        self.duration = duration
        super.init()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        bytesReceived.add(Int64(data.count))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // Don't restart if cancelled (from invalidateAndCancel) or past duration
        if let error = error as? URLError, error.code == .cancelled { return }
        guard Date().timeIntervalSince(startTime) < duration else { return }

        var request = URLRequest(url: downloadURL)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = max(duration + 10, 30)
        session.dataTask(with: request).resume()
    }
}

// MARK: - Upload Measurement Delegate

/// Counts bytes as they leave the device via didSendBodyData callbacks.
/// Automatically restarts uploads when one completes, keeping all streams continuously saturated.
private final class UploadMeasurementDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    let bytesSent: AtomicInt64
    private let uploadURL: URL
    private let uploadData: Data
    private let startTime: Date
    private let duration: TimeInterval

    init(bytesSent: AtomicInt64, uploadURL: URL, uploadData: Data, startTime: Date, duration: TimeInterval) {
        self.bytesSent = bytesSent
        self.uploadURL = uploadURL
        self.uploadData = uploadData
        self.startTime = startTime
        self.duration = duration
        super.init()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didSendBodyData bytesSentIncrement: Int64,
                    totalBytesSent: Int64,
                    totalBytesExpectedToSend: Int64) {
        bytesSent.add(bytesSentIncrement)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error as? URLError, error.code == .cancelled { return }
        guard Date().timeIntervalSince(startTime) < duration else { return }

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = max(duration + 10, 15)
        session.uploadTask(with: request, from: uploadData).resume()
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
