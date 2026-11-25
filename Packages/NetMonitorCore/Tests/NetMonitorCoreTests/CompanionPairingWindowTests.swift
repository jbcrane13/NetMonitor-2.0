import Foundation
import Testing
@testable import NetMonitorCore

@Suite("CompanionPairingWindow")
struct CompanionPairingWindowTests {
    private func window(at now: TimeInterval = 100) -> CompanionPairingWindow {
        CompanionPairingWindow(opening: now)
    }

    @Test("Open until its monotonic deadline, ten minutes after opening")
    func deadline() {
        let window = window()
        #expect(window.isOpen(now: 100))
        #expect(window.isOpen(now: 100 + 599))
        #expect(!window.isOpen(now: 100 + 600))
    }

    @Test("Admits at most 8 pairing connections")
    func admissionCap() {
        var window = window()
        for _ in 0..<CompanionPairingWindow.maximumConnections {
            let result1 = window.admit(now: 101)
            #expect(result1)
        }
        let result2 = window.admit(now: 101)
        #expect(!result2)
    }

    @Test("Consumed once, for its own generation; then nothing more is admitted or consumed")
    func consumeOnce() {
        var window = window()
        let foreign = window.consume(generation: UUID(), now: 101)
        #expect(!foreign)
        let result3 = window.consume(generation: window.generation, now: 101)
        #expect(result3)
        let result4 = window.consume(generation: window.generation, now: 101)
        #expect(!result4)
        #expect(!window.isOpen(now: 101))
        let result5 = window.admit(now: 101)
        #expect(!result5)
    }

    @Test("An expired or closed window can't be consumed")
    func expiredOrClosed() {
        var expired = window()
        let result6 = expired.consume(generation: expired.generation, now: 100 + 600)
        #expect(!result6)
        var closed = window()
        closed.close()
        let result7 = closed.consume(generation: closed.generation, now: 101)
        #expect(!result7)
        let result8 = closed.admit(now: 101)
        #expect(!result8)
    }

    @Test("The QR secret is 256 bits and the typed code is a separate 125-bit secret, both of this window")
    func secrets() {
        let window = window()
        #expect(window.secret(for: .qr).count == 32)
        #expect(window.secret(for: .code) == window.code.secret)
        #expect(window.secret(for: .qr) != window.secret(for: .code))
        #expect(CompanionPairingWindow(opening: 100).generation != window.generation)
    }
}
