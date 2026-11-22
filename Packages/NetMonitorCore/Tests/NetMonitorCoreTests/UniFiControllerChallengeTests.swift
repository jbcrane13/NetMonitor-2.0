import Foundation
import Security
import Testing
@testable import NetMonitorCore

/// A synthetic self-signed certificate (CN=unifi.test), made for these tests only.
private let syntheticCertificateDER = Data(base64Encoded: """
MIIBfzCCASWgAwIBAgIUcexfNYS5K7KlQO4x8K6fl3kjzTEwCgYIKoZIzj0EAwIwFTETMBEGA1UE
AwwKdW5pZmkudGVzdDAeFw0yNjExMjIwMDI4MDNaFw0zNjExMTkwMDI4MDNaMBUxEzARBgNVBAMM
CnVuaWZpLnRlc3QwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAARmHy9jrzKNRxae3Yq4A/WzbAV8
VIokJpjbFx8hU2ppLBLHlyAOp2Ed9TnEkY9Q3h2DTyI5oUnZ+l9GvgliEL8ao1MwUTAdBgNVHQ4E
FgQUx8QB5n5cmIfCY57mHKOkjAl9Fw4wHwYDVR0jBBgwFoAUx8QB5n5cmIfCY57mHKOkjAl9Fw4w
DwYDVR0TAQH/BAUwAwEB/zAKBggqhkjOPQQDAgNIADBFAiBYHPLfDqTIgacIHwgnh+01s2uXvYpw
maL/DTg74k5O5gIhAKKe4Fk+Q8sSnL5FKjkvb9TbOn8+L+C1Km+8BvAFYypZ
""".filter { !$0.isWhitespace }) ?? Data()

/// A protection space carrying a chosen server trust, as URLSession hands one to the delegate.
private final class TrustProtectionSpace: URLProtectionSpace, @unchecked Sendable {
    private let trust: SecTrust?

    init(host: String, trust: SecTrust?, method: String = NSURLAuthenticationMethodServerTrust) {
        self.trust = trust
        super.init(host: host, port: 443, protocol: NSURLProtectionSpaceHTTPS, realm: nil, authenticationMethod: method)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var serverTrust: SecTrust? {
        trust
    }
}

private final class NoSender: NSObject, URLAuthenticationChallengeSender {
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
    func cancel(_ challenge: URLAuthenticationChallenge) {}
}

/// Drives the real `UniFiControllerSessionDelegate` with challenges like URLSession's.
struct UniFiControllerChallengeTests {
    private func trust() throws -> SecTrust {
        let certificate = try #require(SecCertificateCreateWithData(nil, syntheticCertificateDER as CFData))
        var trust: SecTrust?
        SecTrustCreateWithCertificates(certificate, SecPolicyCreateSSL(true, "unifi.test" as CFString), &trust)
        return try #require(trust)
    }

    private func challenge(host: String, method: String = NSURLAuthenticationMethodServerTrust) throws -> URLAuthenticationChallenge {
        try URLAuthenticationChallenge(
            protectionSpace: TrustProtectionSpace(host: host, trust: trust(), method: method),
            proposedCredential: nil, previousFailureCount: 0, failureResponse: nil, error: nil, sender: NoSender()
        )
    }

    private var pin: String {
        UniFiControllerTrust.sha256Hex(syntheticCertificateDER)
    }

    @Test("The enrolled controller's pinned certificate is accepted")
    func matchingPin() async throws {
        let delegate = UniFiControllerSessionDelegate(host: "unifi.test", pinnedSHA256: pin)
        let (disposition, credential) = try await delegate.urlSession(.shared, didReceive: challenge(host: "unifi.test"))
        #expect(disposition == .useCredential)
        #expect(credential != nil)
        #expect(delegate.rejection == nil)
    }

    @Test("Another certificate at the enrolled address is refused")
    func wrongPin() async throws {
        let delegate = UniFiControllerSessionDelegate(host: "unifi.test", pinnedSHA256: String(repeating: "0", count: 64))
        let (disposition, _) = try await delegate.urlSession(.shared, didReceive: challenge(host: "unifi.test"))
        #expect(disposition == .cancelAuthenticationChallenge)
        #expect(delegate.rejection == .certificateMismatch)
    }

    @Test("The right certificate for another host is refused")
    func wrongHost() async throws {
        let delegate = UniFiControllerSessionDelegate(host: "unifi.test", pinnedSHA256: pin)
        let (disposition, _) = try await delegate.urlSession(.shared, didReceive: challenge(host: "other.test"))
        #expect(disposition == .cancelAuthenticationChallenge)
    }

    @Test("A self-signed certificate without a pin fails standard validation and is refused")
    func selfSignedWithoutPin() async throws {
        let delegate = UniFiControllerSessionDelegate(host: "unifi.test", pinnedSHA256: nil)
        let (disposition, _) = try await delegate.urlSession(.shared, didReceive: challenge(host: "unifi.test"))
        #expect(disposition == .cancelAuthenticationChallenge)
        #expect(delegate.rejection == .untrustedCertificate)
    }

    @Test("Challenges other than server trust are refused, even from the enrolled host")
    func otherMethods() async throws {
        let delegate = UniFiControllerSessionDelegate(host: "unifi.test", pinnedSHA256: pin)
        for method in [NSURLAuthenticationMethodHTTPBasic, NSURLAuthenticationMethodClientCertificate] {
            let (disposition, _) = try await delegate.urlSession(.shared, didReceive: challenge(host: "unifi.test", method: method))
            #expect(disposition == .cancelAuthenticationChallenge)
        }
    }
}
