import Darwin
import Foundation
import Observation

/// Monitors real network interface byte counters via getifaddrs, computing Mbps deltas.
/// Polls every second at .utility priority and keeps a rolling 60-sample history.
@Observable @MainActor final class BandwidthMonitorService {

    // MARK: - Observable Properties

    private(set) var downloadMbps: Double = 0
    private(set) var uploadMbps: Double = 0
    private(set) var downloadHistory: [Double] = []
    private(set) var uploadHistory: [Double] = []
    private(set) var sessionDownBytes: UInt64 = 0
    private(set) var sessionUpBytes: UInt64 = 0

    // MARK: - Configuration

    let interfaceName: String
    private static let historyCapacity = 60

    // MARK: - Private State

    private var previousRxBytes: UInt64? = nil
    private var previousTxBytes: UInt64? = nil

    // MARK: - Init

    init(interfaceName: String) {
        self.interfaceName = interfaceName
    }

    // MARK: - Polling

    /// Starts the polling loop. Cancellable via Task.isCancelled.
    /// Call with `.task(priority: .utility) { await bandwidth.start() }`.
    func start() async {
        while !Task.isCancelled {
            sample()
            try? await Task.sleep(for: .seconds(1))
        }
    }

    // MARK: - Sampling

    private func sample() {
        guard let (rxBytes, txBytes) = readIfBytes(for: interfaceName) else { return }

        if let prevRx = previousRxBytes, let prevTx = previousTxBytes {
            // Handle UInt64 counter rollover gracefully
            let rxDelta = rxBytes >= prevRx ? rxBytes - prevRx : rxBytes &+ (UInt64.max - prevRx) &+ 1
            let txDelta = txBytes >= prevTx ? txBytes - prevTx : txBytes &+ (UInt64.max - prevTx) &+ 1

            // Convert to Double before multiplying to avoid UInt64 overflow trap.
            let dlMbps = Double(rxDelta) * 8.0 / 1_000_000.0
            let ulMbps = Double(txDelta) * 8.0 / 1_000_000.0

            downloadMbps = dlMbps
            uploadMbps = ulMbps

            sessionDownBytes += rxDelta
            sessionUpBytes += txDelta

            downloadHistory.append(dlMbps)
            uploadHistory.append(ulMbps)

            if downloadHistory.count > Self.historyCapacity {
                downloadHistory.removeFirst()
            }
            if uploadHistory.count > Self.historyCapacity {
                uploadHistory.removeFirst()
            }
        }

        previousRxBytes = rxBytes
        previousTxBytes = txBytes
    }

    // MARK: - Interface Reading

    /// Reads the cumulative ifi_ibytes/ifi_obytes for the named AF_LINK interface entry.
    private func readIfBytes(for name: String) -> (rx: UInt64, tx: UInt64)? {
        var ifap: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&ifap) == 0, let ifap else { return nil }
        defer { freeifaddrs(ifap) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = ifap
        while let ifa = cursor {
            defer { cursor = ifa.pointee.ifa_next }

            guard let ifaName = ifa.pointee.ifa_name,
                  String(cString: ifaName) == name,
                  let addr = ifa.pointee.ifa_addr,
                  addr.pointee.sa_family == AF_LINK,
                  let dataPtr = ifa.pointee.ifa_data else {
                continue
            }

            let ifData = dataPtr.assumingMemoryBound(to: if_data.self)
            let rx = UInt64(ifData.pointee.ifi_ibytes)
            let tx = UInt64(ifData.pointee.ifi_obytes)
            return (rx, tx)
        }

        return nil
    }

    // MARK: - Static Formatters

    static func formatBytes(_ bytes: UInt64) -> String {
        let gb: Double = 1_073_741_824
        let mb: Double = 1_048_576
        let kb: Double = 1_024
        let d = Double(bytes)
        if d >= gb {
            return String(format: "%.2f GB", d / gb)
        } else if d >= mb {
            return String(format: "%.1f MB", d / mb)
        } else if d >= kb {
            return String(format: "%.0f KB", d / kb)
        } else {
            return "\(bytes) B"
        }
    }

    static func formatMbps(_ mbps: Double) -> String {
        if mbps >= 1000 {
            return String(format: "%.2f Gbps", mbps / 1000)
        } else if mbps >= 1 {
            return String(format: "%.1f Mbps", mbps)
        } else {
            return String(format: "%.0f Kbps", mbps * 1000)
        }
    }
}
