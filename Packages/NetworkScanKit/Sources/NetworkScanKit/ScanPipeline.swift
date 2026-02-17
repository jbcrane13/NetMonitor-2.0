import Foundation

/// Defines the ordering and concurrency of scan phases.
public struct ScanPipeline: Sendable {

    /// A single step in the pipeline, containing one or more phases.
    public struct Step: Sendable {
        /// Phases to execute in this step.
        public let phases: [any ScanPhase]

        /// When `true`, phases in this step run concurrently.
        public let concurrent: Bool

        public init(phases: [any ScanPhase], concurrent: Bool) {
            self.phases = phases
            self.concurrent = concurrent
        }
    }

    /// Ordered steps to execute.
    public var steps: [Step]

    public init(steps: [Step]) {
        self.steps = steps
    }

    /// The default scan pipeline:
    /// 1. [ARP + Bonjour] concurrent — discover devices
    /// 2. [TCP Probe + SSDP] concurrent — find more devices + TCP latency
    /// 3. [ICMP Latency] — enrich remaining devices with ICMP ping latency
    /// 4. [Reverse DNS] — resolve hostnames
    public static func standard(
        bonjourServiceProvider: @escaping @Sendable () async -> [BonjourServiceInfo] = { [] },
        bonjourStopProvider: (@Sendable () async -> Void)? = nil
    ) -> ScanPipeline {
        ScanPipeline(steps: [
            Step(phases: [
                ARPScanPhase(),
                BonjourScanPhase(
                    serviceProvider: bonjourServiceProvider,
                    stopProvider: bonjourStopProvider
                ),
            ], concurrent: true),
            Step(phases: [TCPProbeScanPhase(), SSDPScanPhase()], concurrent: true),
            Step(phases: [ICMPLatencyPhase()], concurrent: false),
            Step(phases: [ReverseDNSScanPhase()], concurrent: false),
        ])
    }
}
