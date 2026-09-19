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
    /// 3. [latencyPhase] — enrich remaining devices with ICMP ping latency
    /// 4. [Reverse DNS] — resolve hostnames
    /// 5. [trailingSteps] — platform-supplied enrichment (defaults to none; iOS is byte-identical)
    ///
    /// - Parameters:
    ///   - latencyPhase: Replaces the default ``ICMPLatencyPhase`` in step 3, e.g. to
    ///     construct one with a non-default `probeCount`.
    ///   - trailingSteps: Additional steps appended after reverse DNS. Callers that need
    ///     platform-specific enrichment append steps here instead of rebuilding the
    ///     pipeline by hand.
    public static func standard(
        bonjourServiceProvider: @escaping @Sendable () async -> [BonjourServiceInfo] = { [] },
        bonjourStopProvider: (@Sendable () async -> Void)? = nil,
        latencyPhase: any ScanPhase = ICMPLatencyPhase(),
        trailingSteps: [Step] = []
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
            Step(phases: [latencyPhase], concurrent: false),
            Step(phases: [ReverseDNSScanPhase()], concurrent: false),
        ] + trailingSteps)
    }
}
