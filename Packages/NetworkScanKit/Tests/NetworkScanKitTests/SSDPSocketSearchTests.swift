import Testing
import Foundation
@testable import NetworkScanKit

/// Drives `SSDPSocketSearch.run` with a fake socket (#387 review).
@Suite("SSDPSocketSearch")
struct SSDPSocketSearchTests {

    private static let reply = Array("HTTP/1.1 200 OK\r\nLOCATION: http://192.168.1.20/d.xml\r\n\r\n".utf8)

    /// A socket that records calls. `endless` makes every poll ready and every read
    /// return a datagram, like a LAN flooding the port.
    private static func fakeOps(
        calls: CallLog,
        nonBlocking: Bool = true,
        bind: Bool = true,
        endless: Bool = false
    ) -> SSDPSocketSearch.SocketOps {
        SSDPSocketSearch.SocketOps(
            open: { calls.add("open")
            return 7
            },
            setNonBlocking: { _ in calls.add("nonblocking")
            return nonBlocking
            },
            bindToInterface: { _, _ in calls.add("bind")
            return bind
            },
            send: { _ in calls.add("send")
            return true
            },
            poll: { _, timeoutMs in
                if endless {
                    return 1
                }
                usleep(UInt32(timeoutMs) * 1000)
                return 0
            },
            receive: { _ in endless ? reply : nil },
            close: { _ in calls.add("close") }
        )
    }

    @Test("a failed non-blocking setup aborts before sending, and the socket is closed")
    func nonBlockingFailureAborts() {
        let calls = CallLog()
        let texts = SSDPSocketSearch.run(
            localIP: nil, window: .seconds(1), stop: StopFlag(), ops: Self.fakeOps(calls: calls, nonBlocking: false)
        )
        #expect(texts.isEmpty)
        #expect(calls.values == ["open", "nonblocking", "close"])
    }

    @Test("when an interface was asked for and binding fails, nothing is sent")
    func bindFailureAborts() {
        let calls = CallLog()
        let texts = SSDPSocketSearch.run(
            localIP: "192.168.1.5", window: .seconds(1), stop: StopFlag(), ops: Self.fakeOps(calls: calls, bind: false)
        )
        #expect(texts.isEmpty)
        #expect(calls.values == ["open", "nonblocking", "bind", "close"])
    }

    @Test("with no local address the socket is not bound and the search is sent")
    func noLocalAddressSendsUnbound() {
        let calls = CallLog()
        _ = SSDPSocketSearch.run(
            localIP: nil, window: .milliseconds(50), stop: StopFlag(), ops: Self.fakeOps(calls: calls)
        )
        #expect(calls.values == ["open", "nonblocking", "send", "close"])
    }

    @Test("a continuous source still stops at the deadline")
    func endlessSourceStopsAtDeadline() {
        let calls = CallLog()
        let started = ContinuousClock.now
        let texts = SSDPSocketSearch.run(
            localIP: nil, window: .milliseconds(150), stop: StopFlag(),
            ops: Self.fakeOps(calls: calls, endless: true), maxDatagrams: .max
        )
        #expect(ContinuousClock.now - started < .seconds(2))
        #expect(!texts.isEmpty)
        #expect(calls.values.last == "close")
    }

    @Test("a continuous source stops when the search is cancelled")
    func endlessSourceStopsOnCancel() {
        let stop = StopFlag()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { stop.set() }
        let started = ContinuousClock.now
        _ = SSDPSocketSearch.run(
            localIP: nil, window: .seconds(30), stop: stop,
            ops: Self.fakeOps(calls: CallLog(), endless: true), maxDatagrams: .max
        )
        #expect(ContinuousClock.now - started < .seconds(5))
    }

    @Test("a continuous source is capped at maxDatagrams")
    func endlessSourceIsCapped() {
        let texts = SSDPSocketSearch.run(
            localIP: nil, window: .seconds(30), stop: StopFlag(), ops: Self.fakeOps(calls: CallLog(), endless: true)
        )
        #expect(texts.count == SSDPSocketSearch.maxDatagrams)
    }
}

private final class CallLog: @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [String] = []

    func add(_ call: String) {
        lock.lock()
        calls.append(call)
        lock.unlock()
    }

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }
}
