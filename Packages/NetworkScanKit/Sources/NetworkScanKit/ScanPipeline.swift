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
    /// 7. [Hostname identity] — maker and model guesses from the names found (#439)
    ///
    /// Identity values are ranked by source (ADR-022), so step order doesn't decide which
    /// maker or model wins. Hostname identity is last so it reads every name the scan found.
    ///
    /// - Parameters:
    ///   - latencyPhase: Replaces the default ``ICMPLatencyPhase`` in step 3, e.g. to
    ///     construct one with a non-default `probeCount`.
    ///   - nameResolver: Replaces the system PTR lookup in reverse DNS, e.g. with one that
    ///     also asks the gateway.
    ///   - identityLookUpName: Lets the hostname step ask DNS for a device whose own names
    ///     don't identify it. Nil (the default) reads the names the scan found only.
    ///   - includeHostnameIdentity: False leaves the hostname step out, for a caller that merges
    ///     more devices after the pipeline (iOS's Mac companion) and runs it after them.
    ///   - trailingSteps: Additional steps appended after reverse DNS. Callers that need
    ///     platform-specific enrichment append steps here instead of rebuilding the
    ///     pipeline by hand.
    public static func standard(
        bonjourServiceProvider: @escaping @Sendable () async -> [BonjourServiceInfo] = { [] },
        bonjourStopProvider: (@Sendable () async -> Void)? = nil,
        latencyPhase: any ScanPhase = ICMPLatencyPhase(),
        nameResolver: (@Sendable (_ ipAddress: String) async -> String?)? = nil,
        identityLookUpName: (@Sendable (_ ipAddress: String) async -> String?)? = nil,
        includeHostnameIdentity: Bool = true,
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
        ] + trailingSteps + (includeHostnameIdentity ? [
            Step(phases: [HostnameIdentityPhase(lookUpName: identityLookUpName)], concurrent: false),
        ] : []))
    }
}
