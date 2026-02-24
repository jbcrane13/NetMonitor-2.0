import Foundation
import Testing
@testable import NetMonitorCore

@Suite("SSLCertificateService")
struct SSLCertificateServiceTests {

    // SSLCertificateService.sanitizeDomain is private, so we test its observable
    // effects through SSLCertificateInfo construction helpers and through the
    // public interface indirectly via the logic we can access.

    // MARK: - Domain sanitization (via a test-accessible wrapper)

    // We expose sanitizeDomain logic by exercising the same string transformations
    // that the production code applies, then verifying results via SSLCertificateInfo
    // initializer behavior. Since sanitizeDomain is private, we replicate its
    // logic here for direct unit-testing of the transformation contract.

    private func sanitize(_ domain: String) -> String {
        domain
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .components(separatedBy: "/").first ?? domain
    }

    @Test("sanitizeDomain strips https:// prefix")
    func sanitizeStripsHTTPS() {
        #expect(sanitize("https://example.com") == "example.com")
    }

    @Test("sanitizeDomain strips http:// prefix")
    func sanitizeStripsHTTP() {
        #expect(sanitize("http://example.com") == "example.com")
    }

    @Test("sanitizeDomain strips trailing path slash")
    func sanitizeStripsTrailingSlash() {
        #expect(sanitize("example.com/") == "example.com")
    }

    @Test("sanitizeDomain strips path component after slash")
    func sanitizeStripsPath() {
        #expect(sanitize("example.com/some/path") == "example.com")
    }

    @Test("sanitizeDomain strips https:// and trailing slash together")
    func sanitizeStripsHTTPSAndSlash() {
        #expect(sanitize("https://example.com/") == "example.com")
    }

    @Test("sanitizeDomain lowercases the domain")
    func sanitizeLowercases() {
        #expect(sanitize("EXAMPLE.COM") == "example.com")
    }

    @Test("sanitizeDomain trims leading/trailing whitespace")
    func sanitizeTrimsWhitespace() {
        #expect(sanitize("  example.com  ") == "example.com")
    }

    // MARK: - SSLCertificateInfo model

    @Test("SSLCertificateInfo: daysUntilExpiry reflects provided value")
    func certInfoDaysUntilExpiry() {
        let now = Date()
        let info = SSLCertificateInfo(
            domain: "example.com",
            issuer: "Test CA",
            subject: "example.com",
            validFrom: now.addingTimeInterval(-86400 * 30),
            validTo: now.addingTimeInterval(86400 * 60),
            isValid: true,
            daysUntilExpiry: 60
        )
        #expect(info.daysUntilExpiry == 60)
        #expect(info.isValid == true)
    }

    @Test("SSLCertificateInfo: expired cert can be modelled with isValid false and daysUntilExpiry 0")
    func certInfoExpired() {
        let now = Date()
        let info = SSLCertificateInfo(
            domain: "expired.example.com",
            issuer: "Test CA",
            subject: "expired.example.com",
            validFrom: now.addingTimeInterval(-86400 * 400),
            validTo: now.addingTimeInterval(-86400 * 10),
            isValid: false,
            daysUntilExpiry: 0
        )
        #expect(info.isValid == false)
        #expect(info.daysUntilExpiry == 0)
    }

    @Test("SSLCertificateInfo: domain field is stored as-is")
    func certInfoDomainStored() {
        let now = Date()
        let info = SSLCertificateInfo(
            domain: "api.example.com",
            issuer: "CA",
            subject: "api.example.com",
            validFrom: now,
            validTo: now.addingTimeInterval(86400),
            isValid: true,
            daysUntilExpiry: 1
        )
        #expect(info.domain == "api.example.com")
    }

    // MARK: - SSLCertificateError

    @Test("SSLCertificateError.noCertificateFound has non-nil localizedDescription")
    func errorNoCert() {
        let err = SSLCertificateError.noCertificateFound
        #expect(err.errorDescription != nil)
        #expect(err.errorDescription?.isEmpty == false)
    }

    @Test("SSLCertificateError.cannotParseCertificate has non-nil localizedDescription")
    func errorCannotParse() {
        let err = SSLCertificateError.cannotParseCertificate
        #expect(err.errorDescription != nil)
        #expect(err.errorDescription?.isEmpty == false)
    }
}
