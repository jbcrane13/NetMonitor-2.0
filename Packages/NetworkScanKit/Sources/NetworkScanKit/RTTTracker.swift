import Foundation

/// Tracks round-trip times from TCP probes and computes adaptive timeouts
/// using exponential moving averages (RFC 6298 style).
///
/// On a consistent LAN (20-80ms RTT), this converges to ~100-200ms timeouts
/// instead of the conservative 500-800ms base values, dramatically reducing
/// scan time for unreachable hosts.
public actor RTTTracker: Sendable {
    private var samples: [Double] = []
    private var srtt: Double = 0
    private var rttVar: Double = 0

    /// Minimum samples before using adaptive timeout.
    private let minSamples: Int
    /// Floor for adaptive timeout (ms).
    private let minTimeout: Double
    /// Ceiling for adaptive timeout (ms).
    private let maxTimeout: Double

    public init(minSamples: Int = 3, minTimeout: Double = 100, maxTimeout: Double = 1000) {
        self.minSamples = minSamples
        self.minTimeout = minTimeout
        self.maxTimeout = maxTimeout
    }

    /// Record a successful RTT measurement in milliseconds.
    public func recordRTT(_ rttMs: Double) {
        guard rttMs > 0 else { return }
        samples.append(rttMs)

        if samples.count == 1 {
            srtt = rttMs
            rttVar = rttMs / 2
        } else {
            // RFC 6298 exponential moving average
            let alpha = 0.125
            let beta = 0.25
            rttVar = (1 - beta) * rttVar + beta * abs(srtt - rttMs)
            srtt = (1 - alpha) * srtt + alpha * rttMs
        }
    }

    /// Returns adaptive timeout in milliseconds, or `base` if not enough samples yet.
    ///
    /// Formula: `clamp(SRTT + 4 * RTTVar, minTimeout, maxTimeout)`
    public func adaptiveTimeout(base: Double) -> Double {
        guard samples.count >= minSamples else { return base }
        let computed = srtt + 4 * rttVar
        return min(max(computed, minTimeout), maxTimeout)
    }

    /// Number of RTT samples collected so far.
    public var sampleCount: Int { samples.count }
}
