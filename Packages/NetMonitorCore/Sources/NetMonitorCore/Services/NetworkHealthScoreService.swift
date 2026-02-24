import Foundation
import Network

// MARK: - NetworkHealthScoreService

/// Computes a composite 0–100 network health score from latency, packet loss, DNS, and connectivity.
public final class NetworkHealthScoreService: NetworkHealthScoreServiceProtocol, @unchecked Sendable {

    // MARK: - Cached Inputs (written by ViewModel, read by calculateScore)

    private let lock = NSLock()
    private var _latencyMs: Double?
    private var _packetLoss: Double?       // 0.0 – 1.0
    private var _dnsResponseMs: Double?
    private var _deviceCount: Int?
    private var _typicalDeviceCount: Int?
    private var _isConnected: Bool = true

    public init() {}

    /// Update cached measurements used by calculateScore().
    public func update(
        latencyMs: Double?,
        packetLoss: Double?,
        dnsResponseMs: Double?,
        deviceCount: Int?,
        typicalDeviceCount: Int?,
        isConnected: Bool
    ) {
        lock.lock()
        defer { lock.unlock() }
        _latencyMs = latencyMs
        _packetLoss = packetLoss
        _dnsResponseMs = dnsResponseMs
        _deviceCount = deviceCount
        _typicalDeviceCount = typicalDeviceCount
        _isConnected = isConnected
    }

    // MARK: - Protocol Conformance

    public func calculateScore() async -> NetworkHealthScore {
        let (latency, loss, dns, deviceCount, typical, connected): (Double?, Double?, Double?, Int?, Int?, Bool) = lock.withLock {
            (_latencyMs, _packetLoss, _dnsResponseMs, _deviceCount, _typicalDeviceCount, _isConnected)
        }

        guard connected else {
            return NetworkHealthScore(
                score: 0,
                grade: "F",
                details: ["connectivity": "Offline"]
            )
        }

        let score = Self.computeScore(
            latencyMs: latency,
            packetLoss: loss,
            dnsMs: dns,
            deviceCount: deviceCount,
            typicalDeviceCount: typical
        )
        let grade = Self.grade(for: score)

        var details: [String: String] = [:]
        if let l = latency { details["latency"] = String(format: "%.0f ms", l) }
        if let p = loss    { details["packetLoss"] = String(format: "%.0f%%", p * 100) }
        if let d = dns     { details["dns"] = String(format: "%.0f ms", d) }
        if let dc = deviceCount { details["devices"] = "\(dc)" }

        return NetworkHealthScore(
            score: score,
            grade: grade,
            latencyMs: latency,
            packetLoss: loss,
            details: details
        )
    }

    // MARK: - Scoring Algorithm

    /// Weighted composite score. Each component contributes a max of its weight.
    /// Weights: latency 35, packetLoss 35, dns 20, deviceAnomaly 10
    static func computeScore(
        latencyMs: Double?,
        packetLoss: Double?,
        dnsMs: Double?,
        deviceCount: Int?,
        typicalDeviceCount: Int?
    ) -> Int {
        var total = 0.0
        var maxTotal = 0.0

        // Latency component (weight 35)
        if let ms = latencyMs {
            let latencyScore: Double
            switch ms {
            case ..<30:   latencyScore = 35
            case 30..<60: latencyScore = 30
            case 60..<100: latencyScore = 22
            case 100..<200: latencyScore = 12
            default:      latencyScore = 0
            }
            total += latencyScore
            maxTotal += 35
        }

        // Packet loss component (weight 35)
        if let loss = packetLoss {
            let lossScore: Double
            switch loss {
            case 0:          lossScore = 35
            case ..<0.01:    lossScore = 30
            case ..<0.05:    lossScore = 20
            case ..<0.10:    lossScore = 10
            default:         lossScore = 0
            }
            total += lossScore
            maxTotal += 35
        }

        // DNS component (weight 20)
        if let dns = dnsMs {
            let dnsScore: Double
            switch dns {
            case ..<50:    dnsScore = 20
            case 50..<100: dnsScore = 15
            case 100..<300: dnsScore = 8
            default:       dnsScore = 0
            }
            total += dnsScore
            maxTotal += 20
        }

        // Device count anomaly (weight 10)
        if let count = deviceCount, let typical = typicalDeviceCount, typical > 0 {
            let ratio = Double(count) / Double(typical)
            let anomalyScore: Double
            switch ratio {
            case 0.5..<1.5: anomalyScore = 10
            case 0.3..<2.0: anomalyScore = 6
            default:        anomalyScore = 2
            }
            total += anomalyScore
            maxTotal += 10
        }

        // If no data, return 0
        guard maxTotal > 0 else { return 0 }

        // Normalize to 0-100
        return min(100, Int((total / maxTotal) * 100))
    }

    static func grade(for score: Int) -> String {
        switch score {
        case 90...100: return "A"
        case 80..<90:  return "B"
        case 70..<80:  return "C"
        case 60..<70:  return "D"
        default:       return "F"
        }
    }
}
