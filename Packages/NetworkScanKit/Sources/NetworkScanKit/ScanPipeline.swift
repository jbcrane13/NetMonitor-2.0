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
    /// 2. [TCP Probe + SSDP + UniFi discovery] concurrent — find more devices + TCP latency
    /// 3. [latencyPhase] — enrich remaining devices with ICMP ping latency
    /// 4. [ARP re-check] — confirm devices whose ARP entry the pings re-confirmed (#378)
    /// 5. [Reverse DNS] — resolve hostnames
    /// 6. [trailingSteps] — platform-supplied enrichment (defaults to none)
    ///
    /// Hostname identity (#439) is not a step here: it must come after every other source,
    /// including ones merged after the scan (the Mac companion on iOS, saved rows on macOS),
    /// so each platform applies ``HostnameIdentity`` at that point.
    ///
    /// - Parameters:
    ///   - latencyPhase: Replaces the default ``ICMPLatencyPhase`` in step 3, e.g. to
    ///     construct one with a non-default `probeCount`.
    ///   - nameResolver: Replaces the system PTR lookup in reverse DNS, e.g. with one that
    ///     also asks the gateway.
    ///   - trailingSteps: Additional steps appended after reverse DNS. Callers that need
    ///     platform-specific enrichment append steps here instead of rebuilding the
    ///     pipeline by hand.
    public static func standard(
        bonjourServiceProvider: @escaping @Sendable () async -> [BonjourServiceInfo] = { [] },
        bonjourStopProvider: (@Sendable () async -> Void)? = nil,
        latencyPhase: any ScanPhase = ICMPLatencyPhase(),
        nameResolver: (@Sendable (_ ipAddress: String) async -> String?)? = nil,
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
            Step(phases: [TCPProbeScanPhase(), SSDPScanPhase(), UbiquitiDiscoveryPhase()], concurrent: true),
            Step(phases: [latencyPhase], concurrent: false),
            Step(phases: [ARPRecheckPhase()], concurrent: false),
            Step(phases: [ReverseDNSScanPhase(resolve: nameResolver)], concurrent: false),
        ] + trailingSteps)
    }
}
