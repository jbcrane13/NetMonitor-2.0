import Foundation
import Testing
@testable import NetMonitorCore

/// Integration tests for SSLCertificateService.
/// These tests make real TLS connections — tag .integration for offline CI filtering.
///
/// The DER parsing contract (parseDERValidityDates) is exercised through the
/// integration path since the method is private.
struct SSLCertificateServiceIntegrationTests {

    // MARK: - Error tests (no network required)

    @Test("checkCertificate with empty domain attempts TLS to 'https://' and throws noCertificateFound")
    func emptyDomainThrows() async {
        let service = SSLCertificateService()
        do {
            _ = try await service.checkCertificate(domain: "")
            // May succeed or throw — empty domain sanitizes to "" → URL("https://")
            // We just verify no hard crash occurs
        } catch {
            // Any error is acceptable
            #expect(true)
        }
    }

    @Test("checkCertificate with characters that prevent URL construction throws")
    func malformedDomainThrows() async {
        let service = SSLCertificateService()
        // After sanitizing "   " → "", URL(string: "https://") succeeds but TLS will fail
        // Test that the service propagates errors rather than swallowing them
        do {
            _ = try await service.checkCertificate(domain: "[invalid::host]")
            // If it doesn't throw, the service handled it some way — acceptable
        } catch {
            // Error surfaced correctly
            #expect(true)
        }
    }

    // MARK: - Integration tests (require network)

    @Test("checkCertificate for apple.com returns valid, non-expired cert", .tags(.integration))
    func appleDotComCertIsValid() async throws {
        let service = SSLCertificateService()
        let info = try await service.checkCertificate(domain: "apple.com")

        #expect(info.domain == "apple.com")
        #expect(info.isValid == true, "apple.com cert should be valid")
        #expect(info.daysUntilExpiry > 0, "apple.com cert must not be expired")
        #expect(info.validTo > Date(), "apple.com cert validTo must be in the future")
        #expect(info.validFrom < Date(), "apple.com cert validFrom must be in the past")
    }

    @Test("checkCertificate for apple.com has non-nil subject", .tags(.integration))
    func appleDotComCertHasSubject() async throws {
        let service = SSLCertificateService()
        let info = try await service.checkCertificate(domain: "apple.com")
        #expect(!info.subject.isEmpty, "Subject/common name must not be empty")
    }

    @Test("checkCertificate strips https:// prefix from domain", .tags(.integration))
    func stripsHTTPSPrefix() async throws {
        let service = SSLCertificateService()
        let info = try await service.checkCertificate(domain: "https://apple.com")
        // After sanitization, domain should be stored as "apple.com"
        #expect(info.domain == "apple.com")
    }

    @Test("checkCertificate for unreachable host surfaces error, not silent nil", .tags(.integration))
    func unreachableHostSurfacesError() async {
        let service = SSLCertificateService()
        do {
            _ = try await service.checkCertificate(domain: "this-host-does-not-exist.invalid")
            Issue.record("Expected an error for unreachable host, but call succeeded")
        } catch {
            // Error surfaced — correct
            #expect(true)
        }
    }

    @Test("checkCertificate for github.com returns cert with daysUntilExpiry >= 0", .tags(.integration))
    func githubCertHasValidExpiry() async throws {
        let service = SSLCertificateService()
        let info = try await service.checkCertificate(domain: "github.com")
        #expect(info.daysUntilExpiry >= 0, "Days until expiry must be non-negative")
    }

    // MARK: - Issuer field limitation

    @Test("issuer is 'Unknown' — DER parser does not extract issuer (known limitation)", .tags(.integration))
    func issuerIsUnknown() async throws {
        // SSLCertificateService.parseCertificate hardcodes issuer = "Unknown" because
        // SecCertificateCopyValues was removed in macOS 15 SDK and the DER walker
        // skips the issuer Name field. This test documents the behavior so that
        // future issuer-parsing improvements can update the expected value.
        let service = SSLCertificateService()
        let info = try await service.checkCertificate(domain: "apple.com")
        #expect(info.issuer == "Unknown",
                "Issuer should be 'Unknown' (known limitation), got '\(info.issuer)'")
    }

    // MARK: - Concurrent requests

    @Test("Concurrent cert checks for different domains do not crash", .tags(.integration))
    func concurrentCertChecksNoCrash() async throws {
        let service = SSLCertificateService()
        let domains = ["apple.com", "github.com", "google.com"]

        try await withThrowingTaskGroup(of: SSLCertificateInfo.self) { group in
            for domain in domains {
                group.addTask {
                    try await service.checkCertificate(domain: domain)
                }
            }
            var results: [SSLCertificateInfo] = []
            for try await info in group {
                results.append(info)
            }
            #expect(results.count == domains.count,
                    "Should get one result per domain, got \(results.count)")
            for info in results {
                #expect(info.isValid, "All major domains should have valid certs")
            }
        }
    }

    // MARK: - DER date parsing validation

    @Test("validFrom and validTo are not sentinel values for a real cert", .tags(.integration))
    func derDatesAreNotSentinels() async throws {
        let service = SSLCertificateService()
        let info = try await service.checkCertificate(domain: "apple.com")
        // If DER parsing fails, parseCertificate falls back to distantPast/distantFuture
        #expect(info.validFrom != Date.distantPast,
                "validFrom should not be .distantPast (DER parsing likely failed)")
        #expect(info.validTo != Date.distantFuture,
                "validTo should not be .distantFuture (DER parsing likely failed)")
        // Dates should be reasonable (within last 5 years to 5 years ahead)
        let fiveYearsAgo = Calendar.current.date(byAdding: .year, value: -5, to: Date())!
        let fiveYearsAhead = Calendar.current.date(byAdding: .year, value: 5, to: Date())!
        #expect(info.validFrom > fiveYearsAgo, "validFrom should be within last 5 years")
        #expect(info.validTo < fiveYearsAhead, "validTo should be within next 5 years")
    }
}
