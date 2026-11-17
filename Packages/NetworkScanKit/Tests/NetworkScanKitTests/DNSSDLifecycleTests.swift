import dnssd
import Foundation
import Testing
@testable import NetworkScanKit

/// #386 review: DNS-SD request and Bonjour phase lifecycles under timeouts and cancellation.
/// Serialized because they read the process-wide live-ref count.
@Suite("DNS-SD lifecycle", .serialized)
struct DNSSDLifecycleTests {

    private let context = ScanContext(hosts: [], subnetFilter: { _ in true }, localIP: nil, requiredInterfaceType: .wifi)

    // MARK: - DNSSDRequest

    @Test("The timeout fires even while the start call is still blocked")
    func timeoutDoesNotWaitForStart() async {
        let clock = ContinuousClock()
        let started = clock.now
        let value = await DNSSDRequest<Int>.run(timeout: .milliseconds(100), timeoutValue: -1) { _, _ in
            Thread.sleep(forTimeInterval: 1.5)
            return DNSServiceErrorType(kDNSServiceErr_Unknown)
        }
        #expect(value == -1)
        #expect(clock.now - started < .milliseconds(800))
    }

    @Test("Cancellation completes the caller even while the start call is still blocked")
    func cancellationDoesNotWaitForStart() async {
        let clock = ContinuousClock()
        let task = Task {
            await DNSSDRequest<Int>.run(timeout: .seconds(30), timeoutValue: -1) { _, _ in
                Thread.sleep(forTimeInterval: 1.5)
                return DNSServiceErrorType(kDNSServiceErr_Unknown)
            }
        }
        try? await Task.sleep(for: .milliseconds(100))
        let cancelledAt = clock.now
        task.cancel()
        #expect(await task.value == -1)
        #expect(clock.now - cancelledAt < .milliseconds(800))
    }

    @Test("A ref created after the request finished is released, never installed")
    func lateRefIsReleased() async {
        let baseline = DNSSDRequest<Int>.liveRefCount
        let createdLate = Flag()
        let value = await DNSSDRequest<Int>.run(timeout: .milliseconds(100), timeoutValue: -1) { ref, context in
            Thread.sleep(forTimeInterval: 0.5)
            createdLate.set()
            return DNSServiceResolve(ref, 0, 0, "w2-lifecycle-test", "_http._tcp", "local.", { _, _, _, _, _, _, _, _, _, _ in }, context)
        }
        #expect(value == -1)
        await waitUntil(timeout: .seconds(3)) { createdLate.isSet }
        // Give the reply queue time to see the late ref.
        try? await Task.sleep(for: .milliseconds(200))
        #expect(DNSSDRequest<Int>.liveRefCount == baseline)
    }

    // MARK: - BonjourScanPhase

    @Test("Cancelling a scan with an address lookup in flight releases its DNS-SD ref")
    func cancelledScanReleasesLookupRef() async {
        let baseline = DNSSDRequest<[String]>.liveRefCount
        let host = "w2-missing-\(UUID().uuidString.prefix(8)).local."
        let phase = BonjourScanPhase(
            serviceProvider: { [BonjourServiceInfo(name: "Ghost", type: "_http._tcp.", domain: "local.")] },
            stopProvider: nil,
            resolver: { _ in BonjourResolution(hostTarget: host, port: 80) },
            addressResolver: { await DNSSDResolver.ipv4Addresses(host: $0, timeout: .seconds(30)) },
            deviceInfoQuery: { _ in nil }
        )
        let accumulator = ScanAccumulator()
        let context = self.context
        let scan = Task { await phase.execute(context: context, accumulator: accumulator) { _ in } }

        await waitUntil(timeout: .seconds(8)) { DNSSDRequest<[String]>.liveRefCount > baseline }
        #expect(DNSSDRequest<[String]>.liveRefCount > baseline, "the lookup should be in flight")

        let clock = ContinuousClock()
        let cancelledAt = clock.now
        scan.cancel()
        await scan.value
        #expect(clock.now - cancelledAt < .seconds(2))

        await waitUntil(timeout: .seconds(2)) { DNSSDRequest<[String]>.liveRefCount == baseline }
        #expect(DNSSDRequest<[String]>.liveRefCount == baseline)
        #expect(await accumulator.isEmpty)
    }

    @Test("Cancelling with resolved devices buffered publishes nothing and still stops browsing")
    func cancelledScanPublishesNothing() async {
        let stopped = Flag()
        let querying = Flag()
        let phase = BonjourScanPhase(
            serviceProvider: { [BonjourServiceInfo(name: "Studio", type: "_ssh._tcp.", domain: "local.")] },
            stopProvider: { stopped.set() },
            resolver: { _ in BonjourResolution(hostTarget: "192.0.2.40", port: 22) },
            addressResolver: { _ in [] },
            deviceInfoQuery: { _ in
                querying.set()
                try? await Task.sleep(for: .seconds(30))
                return "Mac16,10"
            }
        )
        let accumulator = ScanAccumulator()
        let context = self.context
        let scan = Task { await phase.execute(context: context, accumulator: accumulator) { _ in } }

        await waitUntil(timeout: .seconds(8)) { querying.isSet }
        #expect(querying.isSet, "the resolved device should be buffered, waiting for its model")
        scan.cancel()
        await scan.value

        #expect(await accumulator.isEmpty)
        #expect(stopped.isSet)
    }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.withLock { value }
    }

    func set() {
        lock.withLock { value = true }
    }
}

private func waitUntil(timeout: Duration, _ condition: @Sendable () async -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while await !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(20))
    }
}
