import Foundation
import Security
import Testing
@testable import NetMonitorCore

// Synthetic keys, hosts and certificate bytes only; no request leaves the test process.

private let enrolled = UniFiControllerEnrollment(host: "unifi.test", certificateSHA256: nil, apiKey: "synthetic-key-1")

/// Records every credential-bearing request and answers from canned JSON by path.
private final class RecordingTransport: UniFiControllerTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [(url: URL, enrollment: UniFiControllerEnrollment)] = []
    let responses: [String: String]

    init(responses: [String: String] = [:]) {
        self.responses = responses
    }

    var requests: [(url: URL, enrollment: UniFiControllerEnrollment)] {
        lock.withLock { calls }
    }

    func get(_ url: URL, enrollment: UniFiControllerEnrollment) async -> Data? {
        lock.withLock { calls.append((url, enrollment)) }
        return responses.first { url.path.hasSuffix($0.key) }.map { Data($0.value.utf8) }
    }
}

struct UniFiEnrolledInventoryTests {
    private let responses = [
        "/sites": #"{"data":[{"id":"site-1"}],"totalCount":1}"#,
        "/devices": #"{"data":[{"name":"U7 Pro","model":"U7 Pro","macAddress":"28:70:4e:00:00:04","ipAddress":"192.168.2.4"}],"totalCount":1}"#,
        "/clients": #"{"data":[{"name":"Meross Smart Bulb 1f:57","macAddress":"c4:e7:ae:00:1f:57","ipAddress":"192.168.2.183"}],"totalCount":1}"#
    ]

    @Test("An enrolled controller's devices come back, every request to its HTTPS origin with its key")
    func enrolledInventory() async {
        let transport = RecordingTransport(responses: responses)
        let entries = await UniFiNetworkService(enrollment: { enrolled }, transport: transport).inventory()
        #expect(entries.map(\.ipAddress) == ["192.168.2.4", "192.168.2.183"])
        #expect(entries.first?.model == "U7 Pro")
        #expect(transport.requests.count == 3)
        for request in transport.requests {
            #expect(request.url.scheme == "https")
            #expect(request.url.host == "unifi.test")
            #expect(request.enrollment == enrolled)
        }
    }

    @Test("No enrollment, or only an unbound key from an earlier version: no request at all")
    func noEnrollmentNoRequest() async {
        let transport = RecordingTransport(responses: responses)
        #expect(await UniFiNetworkService(enrollment: { nil }, transport: transport).inventory().isEmpty)
        #expect(transport.requests.isEmpty)
    }

    @Test("Inventory stops when the controller can't be verified")
    func unverifiedStops() async {
        let transport = RecordingTransport() // every request refused, as the real transport does on a mismatch
        #expect(await UniFiNetworkService(enrollment: { enrolled }, transport: transport).inventory().isEmpty)
        #expect(transport.requests.count == 1)
    }
}

struct UniFiControllerTrustTests {
    private let certA = Data("synthetic certificate A".utf8)
    private let certB = Data("synthetic certificate B".utf8)

    @Test("A pinned certificate is accepted only when it matches, for the enrolled host only")
    func pinned() {
        let pin = UniFiControllerTrust.sha256Hex(certA)
        func accepts(_ host: String, _ cert: Data?) -> Bool {
            UniFiControllerTrust.accepts(
                challengeHost: host, enrolledHost: "192.168.2.1", pinnedSHA256: pin,
                leafCertificateDER: cert, passesStandardValidation: true
            )
        }
        #expect(accepts("192.168.2.1", certA))
        #expect(!accepts("192.168.2.1", certB)) // same address, another controller
        #expect(!accepts("192.168.2.1", nil))
        #expect(!accepts("192.168.2.2", certA)) // endpoint changed
    }

    @Test("Without a pin, only a certificate that passes standard HTTPS validation is accepted")
    func standardValidation() {
        #expect(UniFiControllerTrust.accepts(
            challengeHost: "unifi.test", enrolledHost: "unifi.test", pinnedSHA256: nil,
            leafCertificateDER: certA, passesStandardValidation: true
        ))
        #expect(!UniFiControllerTrust.accepts(
            challengeHost: "unifi.test", enrolledHost: "unifi.test", pinnedSHA256: nil,
            leafCertificateDER: certA, passesStandardValidation: false
        ))
        #expect(!UniFiControllerTrust.accepts(
            challengeHost: "other.test", enrolledHost: "unifi.test", pinnedSHA256: nil,
            leafCertificateDER: certA, passesStandardValidation: true
        ))
    }

    @Test("The transport sends nothing to another origin, over HTTP, or to another port")
    func refusesOtherOrigins() async throws {
        let transport = URLSessionUniFiTransport()
        for text in ["https://other.test/proxy/network/integration/v1/sites", "http://unifi.test/sites",
                     "https://unifi.test:8443/sites", "https://user@unifi.test/sites"] {
            let url = try #require(URL(string: text))
            #expect(!URLSessionUniFiTransport.isEnrolledOrigin(url, enrollment: enrolled))
            #expect(await transport.get(url, enrollment: enrolled) == nil)
        }
        #expect(try URLSessionUniFiTransport.isEnrolledOrigin(#require(URL(string: "https://unifi.test/sites")), enrollment: enrolled))
    }

    @Test("Redirects are refused")
    func refusesRedirects() async throws {
        let delegate = UniFiControllerSessionDelegate(host: "unifi.test", pinnedSHA256: nil)
        let url = try #require(URL(string: "https://unifi.test/sites"))
        let response = try #require(HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: nil))
        let task = URLSession.shared.dataTask(with: url)
        let next = try await delegate.urlSession(
            .shared, task: task, willPerformHTTPRedirection: response,
            newRequest: URLRequest(url: #require(URL(string: "https://other.test/")))
        )
        #expect(next == nil)
    }

    @Test("Fingerprints and hosts are normalized, and bad ones rejected")
    func normalization() {
        let hex = String(repeating: "ab", count: 32)
        let colons = stride(from: 0, to: 64, by: 2).map { _ in "AB" }.joined(separator: ":")
        #expect(UniFiControllerEnrollment.normalizedFingerprint(colons) == hex)
        #expect(UniFiControllerEnrollment.normalizedFingerprint("abcd") == nil)
        #expect(UniFiControllerEnrollment.normalizedFingerprint(String(repeating: "zz", count: 32)) == nil)
        #expect(UniFiControllerEnrollment.normalizedHost(" https://UniFi.Test/ ") == "unifi.test")
        #expect(UniFiControllerEnrollment.normalizedHost("192.168.2.1") == "192.168.2.1")
        #expect(UniFiControllerEnrollment.normalizedHost("unifi.test/path") == nil)
        #expect(UniFiControllerEnrollment.normalizedHost("unifi.test:8443") == nil)
        #expect(UniFiControllerEnrollment.normalizedHost("user@unifi.test") == nil)
    }
}

/// Keychain round trips in a throwaway service name, never the app's.
@Suite(.serialized)
struct UniFiAPIKeyStoreTests {
    private let service = "com.netmonitor.unifi.tests.\(UUID().uuidString)"

    /// Saves a key the way 2.2.2 did: a bare key with no controller.
    private func saveUnboundKey() {
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "network-api-key",
            kSecValueData as String: Data("synthetic-legacy-key".utf8)
        ]
        SecItemAdd(item as CFDictionary, nil)
    }

    @Test("Enrollment survives a new store (restart) and removal clears it")
    func roundTrip() {
        let store = UniFiAPIKeyStore(service: service)
        defer { store.removeAll() }
        #expect(store.enrollment() == nil)
        #expect(store.save(enrolled))
        #expect(UniFiAPIKeyStore(service: service).enrollment() == enrolled)
        store.removeAll()
        #expect(store.enrollment() == nil)
    }

    @Test("A key saved without a controller is never used, and enrolling replaces it")
    func unboundKey() {
        let store = UniFiAPIKeyStore(service: service)
        defer { store.removeAll() }
        saveUnboundKey()
        #expect(store.hasUnboundKey)
        #expect(store.enrollment() == nil)
        #expect(store.save(enrolled))
        #expect(!store.hasUnboundKey)
        saveUnboundKey()
        store.removeAll()
        #expect(!store.hasUnboundKey)
    }
}

@MainActor
struct UniFiEnrollmentModelTests {
    private func makeModel(_ result: UniFiControllerVerification, checked: @escaping @Sendable (String, String?) -> Void = { _, _ in })
        -> (UniFiEnrollmentModel, UniFiAPIKeyStore) {
        let store = UniFiAPIKeyStore(service: "com.netmonitor.unifi.tests.\(UUID().uuidString)")
        let model = UniFiEnrollmentModel(store: store) { host, pin in
            checked(host, pin)
            return result
        }
        return (model, store)
    }

    @Test("Enrolling a verified controller saves the key bound to it")
    func enrolls() async {
        let (model, store) = makeModel(.verified)
        defer { store.removeAll() }
        model.hostText = "https://UniFi.test/"
        model.keyText = "synthetic-key-2"
        await model.enroll()
        #expect(store.enrollment() == UniFiControllerEnrollment(host: "unifi.test", certificateSHA256: nil, apiKey: "synthetic-key-2"))
        #expect(model.status == .enrolled(host: "unifi.test", pinned: false))
        #expect(model.keyText.isEmpty)
    }

    @Test("A certificate mismatch or untrusted certificate saves nothing", arguments: [
        UniFiControllerVerification.certificateMismatch, .untrustedCertificate, .unreachable
    ])
    func failedVerificationSavesNothing(result: UniFiControllerVerification) async {
        let (model, store) = makeModel(result)
        defer { store.removeAll() }
        model.hostText = "192.168.2.1"
        model.fingerprintText = String(repeating: "ab", count: 32)
        model.keyText = "synthetic-key-3"
        await model.enroll()
        #expect(store.enrollment() == nil)
        #expect(model.status == .notSetUp)
        #expect(model.message?.contains("synthetic-key-3") == false)
    }

    @Test("A bad fingerprint is rejected before any check")
    func badFingerprint() async {
        let (model, store) = makeModel(.verified, checked: { _, _ in Issue.record("checked a controller") })
        defer { store.removeAll() }
        model.hostText = "192.168.2.1"
        model.fingerprintText = "not-a-fingerprint"
        model.keyText = "synthetic-key-4"
        await model.enroll()
        #expect(store.enrollment() == nil)
    }

    @Test("An unbound key shows as paused; removing it leaves nothing")
    func unboundThenRemove() {
        let service = "com.netmonitor.unifi.tests.\(UUID().uuidString)"
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "network-api-key",
            kSecValueData as String: Data("synthetic-legacy-key".utf8)
        ]
        SecItemAdd(item as CFDictionary, nil)
        let store = UniFiAPIKeyStore(service: service)
        defer { store.removeAll() }
        let model = UniFiEnrollmentModel(store: store) { _, _ in
            Issue.record("checked a controller")
            return .verified
        }
        #expect(model.status == .unboundKey)
        model.remove()
        #expect(model.status == .notSetUp)
        #expect(!store.hasUnboundKey)
    }

    @Test("A failed check of the enrolled controller says why, and removing the enrollment clears it")
    func checkThenRemove() async {
        let (model, store) = makeModel(.certificateMismatch)
        defer { store.removeAll() }
        #expect(store.save(enrolled))
        model.refreshStatus()
        await model.checkEnrolled()
        #expect(model.lastCheck == .certificateMismatch)
        #expect(model.message?.contains("paused") == true)
        #expect(model.message?.contains("synthetic-key-1") == false)
        model.remove()
        #expect(store.enrollment() == nil)
        #expect(model.status == .notSetUp)
        #expect(model.lastCheck == nil)
    }

    @Test("The pinned fingerprint is what the check uses")
    func passesPin() async {
        let pin = String(repeating: "cd", count: 32)
        let (model, store) = makeModel(.verified, checked: { host, checkedPin in
            #expect(host == "192.168.2.1")
            #expect(checkedPin == pin)
        })
        defer { store.removeAll() }
        model.hostText = "192.168.2.1"
        model.fingerprintText = pin.uppercased()
        model.keyText = "synthetic-key-5"
        await model.enroll()
        #expect(model.status == .enrolled(host: "192.168.2.1", pinned: true))
    }
}
