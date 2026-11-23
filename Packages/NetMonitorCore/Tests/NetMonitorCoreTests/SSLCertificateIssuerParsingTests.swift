import Testing
import Foundation
@testable import NetMonitorCore

/// Issuer extraction from real certificate DER bytes (#468).
struct SSLCertificateIssuerParsingTests {

    private func fixture(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: nil) else {
            throw NSError(
                domain: "SSLCertificateIssuerParsingTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Fixture '\(name)' not found in Bundle.module"]
            )
        }
        return try Data(contentsOf: url)
    }

    @Test("issuer is the issuing CA's common name (www.apple.com leaf)")
    func issuerCommonName() async throws {
        let der = try fixture("cert-www-apple-com-leaf.der")
        let info = try await SSLCertificateService().certificateInfo(fromDER: der, domain: "apple.com")
        #expect(info.issuer == "Apple Public EV Server RSA CA 1 - G1")
        #expect(info.subject == "www.apple.com")
    }

    @Test("issuer falls back to organization when the issuer has no CN (Starfield Class 2 root)")
    func issuerOrganizationFallback() async throws {
        let der = try fixture("cert-starfield-class2-root.der")
        let info = try await SSLCertificateService().certificateInfo(fromDER: der, domain: "starfield")
        #expect(info.issuer == "Starfield Technologies, Inc.")
    }

    @Test("validity dates still parse alongside the issuer")
    func validityDatesStillParse() async throws {
        let der = try fixture("cert-starfield-class2-root.der")
        let info = try await SSLCertificateService().certificateInfo(fromDER: der, domain: "starfield")
        // notBefore 2004-06-29 17:39:16 UTC, notAfter 2034-06-29 17:39:16 UTC
        #expect(info.validFrom == Date(timeIntervalSince1970: 1_088_530_756))
        #expect(info.validTo == Date(timeIntervalSince1970: 2_035_215_556))
    }
}
