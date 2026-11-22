import CryptoKit
import Foundation
import os
import Security

/// Decides whether a TLS connection is the enrolled UniFi controller.
public enum UniFiControllerTrust {
    /// True only for the enrolled host, and then only when the certificate matches the pinned
    /// SHA-256 (self-signed controller) or, with no pin, passes standard HTTPS validation.
    public static func accepts(
        challengeHost: String,
        enrolledHost: String,
        pinnedSHA256: String?,
        leafCertificateDER: Data?,
        passesStandardValidation: Bool
    ) -> Bool {
        guard challengeHost.lowercased() == enrolledHost else { return false }
        if let pinnedSHA256 {
            guard let leafCertificateDER else { return false }
            return sha256Hex(leafCertificateDER) == pinnedSHA256
        }
        return passesStandardValidation
    }

    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// The result of checking a controller before enrollment. No API key is sent while checking.
public enum UniFiControllerVerification: Equatable, Sendable {
    case verified
    /// The certificate isn't the one the user entered.
    case certificateMismatch
    /// No fingerprint was entered and the certificate fails standard HTTPS validation
    /// (self-signed, expired or for another name).
    case untrustedCertificate
    case unreachable
}

/// Sends credential-bearing requests to the enrolled controller, and nowhere else.
public protocol UniFiControllerTransport: Sendable {
    /// GETs `url` with the enrollment's API key, or returns nil without sending the key when
    /// `url` isn't HTTPS on the enrolled host, the connection isn't verified as the enrolled
    /// controller, the server redirects, or the response isn't 200.
    func get(_ url: URL, enrollment: UniFiControllerEnrollment) async -> Data?
}

/// The one URLSession path for UniFi API keys, shared by iOS and macOS. It fails closed: the
/// key is attached only after TLS is verified for the enrolled controller (the request is
/// cancelled at the trust challenge otherwise), and redirects are refused.
public struct URLSessionUniFiTransport: UniFiControllerTransport {
    public init() {}

    public func get(_ url: URL, enrollment: UniFiControllerEnrollment) async -> Data? {
        guard Self.isEnrolledOrigin(url, enrollment: enrollment) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.setValue(enrollment.apiKey, forHTTPHeaderField: "X-API-KEY")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let delegate = UniFiControllerSessionDelegate(host: enrollment.host, pinnedSHA256: enrollment.certificateSHA256)
        let session = Self.session(delegate: delegate)
        defer { session.finishTasksAndInvalidate() }
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let finalURL = http.url, Self.isEnrolledOrigin(finalURL, enrollment: enrollment) else { return nil }
        return data
    }

    /// Checks `host` is the controller without sending any key: connects, verifies TLS as an
    /// enrolled request would, and sends a plain GET for `/` only once that passes.
    public static func verify(host: String, pinnedSHA256: String?) async -> UniFiControllerVerification {
        guard let url = URL(string: "https://\(host)/") else { return .unreachable }
        let delegate = UniFiControllerSessionDelegate(host: host, pinnedSHA256: pinnedSHA256)
        let session = Self.session(delegate: delegate)
        defer { session.finishTasksAndInvalidate() }
        if await (try? session.data(for: URLRequest(url: url, timeoutInterval: 5))) != nil {
            return .verified
        }
        return delegate.rejection ?? .unreachable
    }

    static func isEnrolledOrigin(_ url: URL, enrollment: UniFiControllerEnrollment) -> Bool {
        url.scheme == "https" && url.host?.lowercased() == enrollment.host && url.port == nil
            && url.user == nil && url.password == nil
    }

    private static func session(delegate: UniFiControllerSessionDelegate) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.connectionProxyDictionary = [:] // straight to the controller, never via a proxy
        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }
}

/// Accepts the enrolled controller's certificate only; cancels every other challenge and
/// refuses redirects.
final class UniFiControllerSessionDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    let host: String
    let pinnedSHA256: String?
    private let rejectionState = OSAllocatedUnfairLock<UniFiControllerVerification?>(initialState: nil)

    init(host: String, pinnedSHA256: String?) {
        self.host = host
        self.pinnedSHA256 = pinnedSHA256
    }

    var rejection: UniFiControllerVerification? {
        rejectionState.withLock { $0 }
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        decide(challenge)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        decide(challenge)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }

    private func decide(_ challenge: URLAuthenticationChallenge) -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            return (.cancelAuthenticationChallenge, nil)
        }
        let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate]
        let leaf = chain?.first.map { SecCertificateCopyData($0) as Data }
        SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, host as CFString))
        let standard = SecTrustEvaluateWithError(trust, nil)
        if UniFiControllerTrust.accepts(
            challengeHost: challenge.protectionSpace.host,
            enrolledHost: host,
            pinnedSHA256: pinnedSHA256,
            leafCertificateDER: leaf,
            passesStandardValidation: standard
        ) {
            return (.useCredential, URLCredential(trust: trust))
        }
        rejectionState.withLock { $0 = pinnedSHA256 == nil ? .untrustedCertificate : .certificateMismatch }
        return (.cancelAuthenticationChallenge, nil)
    }
}
