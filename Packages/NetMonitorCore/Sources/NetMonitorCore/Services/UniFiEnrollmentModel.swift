import Foundation
import Observation

/// Settings state for enrolling a UniFi controller, shared by iOS and macOS.
///
/// Enrolling checks the controller's identity first (no key is sent), then saves the key bound
/// to that controller. A key saved by an earlier version is never reused: the user enrolls
/// again with the key, or removes it.
@MainActor @Observable
public final class UniFiEnrollmentModel {
    public enum Status: Equatable {
        case notSetUp
        /// A key from an earlier version, bound to no controller. Inventory is paused.
        case unboundKey
        case enrolled(host: String, pinned: Bool)
    }

    public var hostText = ""
    public var fingerprintText = ""
    public var keyText = ""
    public private(set) var status: Status = .notSetUp
    /// Why the last check or enrollment failed, or that it passed. Never contains the key.
    public private(set) var message: String?
    public private(set) var isChecking = false
    /// The last check of the enrolled controller; nil until one runs.
    public private(set) var lastCheck: UniFiControllerVerification?

    private let store: UniFiAPIKeyStore
    private let verify: @Sendable (_ host: String, _ pinnedSHA256: String?) async -> UniFiControllerVerification

    public init(
        store: UniFiAPIKeyStore = UniFiAPIKeyStore(),
        verify: @escaping @Sendable (_ host: String, _ pinnedSHA256: String?) async -> UniFiControllerVerification
            = { await URLSessionUniFiTransport.verify(host: $0, pinnedSHA256: $1) }
    ) {
        self.store = store
        self.verify = verify
        refreshStatus()
    }

    public var canEnroll: Bool {
        !isChecking && !hostText.trimmingCharacters(in: .whitespaces).isEmpty
            && !keyText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    public func refreshStatus() {
        if let enrollment = store.enrollment() {
            status = .enrolled(host: enrollment.host, pinned: enrollment.certificateSHA256 != nil)
        } else if store.hasUnboundKey {
            status = .unboundKey
        } else {
            status = .notSetUp
        }
    }

    /// Verifies the controller without the key, then saves the key bound to it.
    public func enroll() async {
        guard let host = UniFiControllerEnrollment.normalizedHost(hostText) else {
            message = "Enter the controller's host name or IP address, such as 192.168.1.1."
            return
        }
        let fingerprintEntry = fingerprintText.trimmingCharacters(in: .whitespacesAndNewlines)
        var pin: String?
        if !fingerprintEntry.isEmpty {
            guard let normalized = UniFiControllerEnrollment.normalizedFingerprint(fingerprintEntry) else {
                message = "The certificate fingerprint must be a SHA-256 fingerprint: 64 hexadecimal digits."
                return
            }
            pin = normalized
        }
        let key = keyText.trimmingCharacters(in: .whitespacesAndNewlines)
        isChecking = true
        let result = await verify(host, pin)
        isChecking = false
        guard result == .verified else {
            message = Self.explanation(result)
            return
        }
        if store.save(UniFiControllerEnrollment(host: host, certificateSHA256: pin, apiKey: key)) {
            keyText = ""
            lastCheck = .verified
            message = "Controller verified. Scans read its device list."
        } else {
            message = "The key couldn't be saved to the Keychain."
        }
        refreshStatus()
    }

    /// Checks the enrolled controller again (no key is sent) and says whether inventory works.
    public func checkEnrolled() async {
        guard let enrollment = store.enrollment() else { return }
        isChecking = true
        let result = await verify(enrollment.host, enrollment.certificateSHA256)
        isChecking = false
        lastCheck = result
        message = result == .verified
            ? "Controller verified."
            : "Device lookup is paused: " + Self.explanation(result) + " Remove the key and enroll again if the controller changed."
    }

    public func remove() {
        store.removeAll()
        keyText = ""
        message = nil
        lastCheck = nil
        refreshStatus()
    }

    static func explanation(_ result: UniFiControllerVerification) -> String {
        switch result {
        case .verified:
            "Controller verified."
        case .certificateMismatch:
            "The controller's certificate doesn't match the fingerprint you entered."
        case .untrustedCertificate:
            "The controller's certificate isn't trusted. For a self-signed controller, enter its SHA-256 certificate fingerprint."
        case .unreachable:
            "The controller didn't answer over HTTPS."
        }
    }
}
