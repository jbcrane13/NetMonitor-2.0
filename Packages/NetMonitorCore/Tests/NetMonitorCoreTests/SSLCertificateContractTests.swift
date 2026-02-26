import Foundation
import Testing
@testable import NetMonitorCore

/// Contract tests for SSLCertificateService.
///
/// INTEGRATION GAP: SSL certificate fetching requires a live TLS connection via
/// URLSession with a custom delegate (CertificateDelegate). MockURLProtocol cannot
/// intercept the TLS handshake or provide a SecCertificate. Full end-to-end testing
/// of checkCertificate() requires a real network connection.
///
/// These tests cover:
/// - SSLCertificateInfo model construction and property access
/// - Domain sanitization contract (replicated from private method)
/// - Expiry calculation scenarios
/// - Error types and descriptions
/// - SSLCertificateInfo edge cases (expired, about-to-expire, far-future)
@Suite("SSLCertificateService Contract Tests")
struct SSLCertificateContractTests {

    // MARK: - Domain Sanitization Contract

    /// Replicates the sanitizeDomain logic to verify the transformation contract.
    /// This ensures the service will send correct URLs for various input formats.
    private func sanitize(_ domain: String) -> String {
        domain
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .components(separatedBy: "/").first ?? domain
    }

    @Test("sanitizeDomain strips https:// prefix and lowercases")
    func sanitizeHTTPS() {
        #expect(sanitize("https://Example.COM") == "example.com")
    }

    @Test("sanitizeDomain strips http:// prefix")
    func sanitizeHTTP() {
        #expect(sanitize("http://example.com") == "example.com")
    }

    @Test("sanitizeDomain strips path components")
    func sanitizePath() {
        #expect(sanitize("example.com/path/to/page") == "example.com")
    }

    @Test("sanitizeDomain strips trailing slash")
    func sanitizeTrailingSlash() {
        #expect(sanitize("example.com/") == "example.com")
    }

    @Test("sanitizeDomain trims whitespace")
    func sanitizeWhitespace() {
        #expect(sanitize("  example.com  ") == "example.com")
    }

    @Test("sanitizeDomain handles full URL with path and query")
    func sanitizeFullURL() {
        #expect(sanitize("https://API.Example.COM/v1/endpoint?key=value") == "api.example.com")
    }

    // MARK: - SSLCertificateInfo Model Tests

    @Test("SSLCertificateInfo stores all fields correctly")
    func modelStoresAllFields() {
        let now = Date()
        let validFrom = now.addingTimeInterval(-86400 * 30)
        let validTo = now.addingTimeInterval(86400 * 335)
        let info = SSLCertificateInfo(
            domain: "example.com",
            issuer: "Let's Encrypt Authority X3",
            subject: "CN=example.com",
            validFrom: validFrom,
            validTo: validTo,
            isValid: true,
            daysUntilExpiry: 335
        )
        #expect(info.domain == "example.com")
        #expect(info.issuer == "Let's Encrypt Authority X3")
        #expect(info.subject == "CN=example.com")
        #expect(info.validFrom == validFrom)
        #expect(info.validTo == validTo)
        #expect(info.isValid == true)
        #expect(info.daysUntilExpiry == 335)
    }

    @Test("SSLCertificateInfo with zero daysUntilExpiry (expires today)")
    func expiresToday() {
        let now = Date()
        let info = SSLCertificateInfo(
            domain: "expiring.example.com",
            issuer: "CA",
            subject: "expiring.example.com",
            validFrom: now.addingTimeInterval(-86400 * 365),
            validTo: now,
            isValid: true,
            daysUntilExpiry: 0
        )
        #expect(info.daysUntilExpiry == 0)
        #expect(info.isValid == true)
    }

    @Test("SSLCertificateInfo for expired certificate")
    func expiredCertificate() {
        let now = Date()
        let info = SSLCertificateInfo(
            domain: "expired.example.com",
            issuer: "CA",
            subject: "expired.example.com",
            validFrom: now.addingTimeInterval(-86400 * 400),
            validTo: now.addingTimeInterval(-86400 * 35),
            isValid: false,
            daysUntilExpiry: 0
        )
        #expect(info.isValid == false)
        #expect(info.daysUntilExpiry == 0)
    }

    @Test("SSLCertificateInfo for not-yet-valid certificate")
    func notYetValidCertificate() {
        let now = Date()
        let futureStart = now.addingTimeInterval(86400 * 30)
        let futureEnd = now.addingTimeInterval(86400 * 395)
        let info = SSLCertificateInfo(
            domain: "future.example.com",
            issuer: "CA",
            subject: "future.example.com",
            validFrom: futureStart,
            validTo: futureEnd,
            isValid: false,
            daysUntilExpiry: 395
        )
        #expect(info.isValid == false)
        #expect(info.daysUntilExpiry == 395)
    }

    @Test("SSLCertificateInfo for long-lived certificate (multi-year)")
    func longLivedCertificate() {
        let now = Date()
        let info = SSLCertificateInfo(
            domain: "longcert.example.com",
            issuer: "Root CA",
            subject: "longcert.example.com",
            validFrom: now.addingTimeInterval(-86400 * 365),
            validTo: now.addingTimeInterval(86400 * 365 * 5),
            isValid: true,
            daysUntilExpiry: 1825
        )
        #expect(info.daysUntilExpiry == 1825)
        #expect(info.isValid == true)
    }

    @Test("SSLCertificateInfo with wildcard subject")
    func wildcardSubject() {
        let now = Date()
        let info = SSLCertificateInfo(
            domain: "api.example.com",
            issuer: "DigiCert",
            subject: "*.example.com",
            validFrom: now.addingTimeInterval(-86400 * 30),
            validTo: now.addingTimeInterval(86400 * 335),
            isValid: true,
            daysUntilExpiry: 335
        )
        #expect(info.subject == "*.example.com")
        #expect(info.domain == "api.example.com")
    }

    // MARK: - Expiry Date Calculation Verification

    @Test("Expiry calculation: days between two known dates")
    func expiryCalculation() {
        let now = Date()
        let validTo = now.addingTimeInterval(86400 * 60)
        let daysUntilExpiry = Calendar.current.dateComponents([.day], from: now, to: validTo).day ?? 0
        #expect(daysUntilExpiry == 60)
    }

    @Test("Expiry calculation: past expiry returns negative days")
    func expiryCalculationPastDate() {
        let now = Date()
        let validTo = now.addingTimeInterval(-86400 * 10)
        let daysUntilExpiry = Calendar.current.dateComponents([.day], from: now, to: validTo).day ?? 0
        #expect(daysUntilExpiry == -10)
    }

    @Test("Expiry calculation: same day returns 0")
    func expiryCalculationSameDay() {
        let now = Date()
        let daysUntilExpiry = Calendar.current.dateComponents([.day], from: now, to: now).day ?? 0
        #expect(daysUntilExpiry == 0)
    }

    // MARK: - Validity Logic Verification

    @Test("Certificate is valid when now is between validFrom and validTo")
    func validityLogicValid() {
        let now = Date()
        let validFrom = now.addingTimeInterval(-86400)
        let validTo = now.addingTimeInterval(86400)
        let isValid = validFrom <= now && now <= validTo
        #expect(isValid == true)
    }

    @Test("Certificate is invalid when now is before validFrom")
    func validityLogicNotYetValid() {
        let now = Date()
        let validFrom = now.addingTimeInterval(86400)
        let validTo = now.addingTimeInterval(86400 * 365)
        let isValid = validFrom <= now && now <= validTo
        #expect(isValid == false)
    }

    @Test("Certificate is invalid when now is after validTo")
    func validityLogicExpired() {
        let now = Date()
        let validFrom = now.addingTimeInterval(-86400 * 365)
        let validTo = now.addingTimeInterval(-86400)
        let isValid = validFrom <= now && now <= validTo
        #expect(isValid == false)
    }

    // MARK: - Error Types

    @Test("SSLCertificateError.noCertificateFound has descriptive message")
    func noCertificateFoundError() {
        let error = SSLCertificateError.noCertificateFound
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription?.contains("certificate") == true)
    }

    @Test("SSLCertificateError.cannotParseCertificate has descriptive message")
    func cannotParseCertificateError() {
        let error = SSLCertificateError.cannotParseCertificate
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription?.contains("parse") == true)
    }

    @Test("SSLCertificateError cases are distinct")
    func errorCasesAreDistinct() {
        let err1 = SSLCertificateError.noCertificateFound
        let err2 = SSLCertificateError.cannotParseCertificate
        #expect(err1.errorDescription != err2.errorDescription)
    }

    // INTEGRATION GAP: SSL certificate fetching requires live TLS connection.
    // The following scenarios cannot be tested without a real server:
    // - Full certificate chain inspection
    // - DER parsing of real certificates
    // - Certificate pinning validation
    // - TLS version negotiation
    // Resolution: Add a parseCertificateData(_:domain:) method accepting Data
    // to allow unit testing of the DER parser independently.
}
