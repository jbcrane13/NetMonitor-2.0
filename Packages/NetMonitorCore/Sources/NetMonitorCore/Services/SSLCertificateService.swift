import Foundation
import Security

/// Checks SSL/TLS certificate information for a domain by initiating a TLS connection
/// and inspecting the server's certificate chain.
public actor SSLCertificateService: SSLCertificateServiceProtocol {

    public init() {}

    public func checkCertificate(domain: String) async throws -> SSLCertificateInfo {
        let cleanDomain = sanitizeDomain(domain)

        guard let url = URL(string: "https://\(cleanDomain)") else {
            throw URLError(.badURL)
        }

        let inspector = CertificateDelegate()
        var config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 20
        let session = URLSession(configuration: config, delegate: inspector, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        // Ignore errors — we only care about the TLS handshake
        _ = try? await session.data(for: request)

        guard let cert = inspector.leafCertificate else {
            throw SSLCertificateError.noCertificateFound
        }

        return try parseCertificate(cert, domain: cleanDomain)
    }

    // MARK: - Private Helpers

    private func sanitizeDomain(_ domain: String) -> String {
        domain
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .components(separatedBy: "/").first ?? domain
    }

    private func parseCertificate(_ cert: SecCertificate, domain: String) throws -> SSLCertificateInfo {
        let subject = SecCertificateCopySubjectSummary(cert) as String? ?? domain

        var validFrom = Date.distantPast
        var validTo = Date.distantFuture
        var issuer = "Unknown"

        // SecCertificateCopyValues was removed in macOS 15 SDK; use DER parsing on all platforms.
        if let dates = parseDERValidityDates(from: cert) {
            validFrom = dates.notBefore
            validTo = dates.notAfter
        }

        let now = Date()
        let daysUntilExpiry = Calendar.current.dateComponents([.day], from: now, to: validTo).day ?? 0
        let isValid = validFrom <= now && now <= validTo

        return SSLCertificateInfo(
            domain: domain,
            issuer: issuer,
            subject: subject,
            validFrom: validFrom,
            validTo: validTo,
            isValid: isValid,
            daysUntilExpiry: max(0, daysUntilExpiry)
        )
    }

    // Minimal DER/ASN.1 parser to extract validity dates from an X.509 certificate.
    private func parseDERValidityDates(from cert: SecCertificate) -> (notBefore: Date, notAfter: Date)? {
        let derData = SecCertificateCopyData(cert) as Data
        var idx = derData.startIndex

        // Enter Certificate SEQUENCE
        guard derReadTag(0x30, in: derData, at: &idx) != nil else { return nil }
        // Enter TBSCertificate SEQUENCE
        guard derReadTag(0x30, in: derData, at: &idx) != nil else { return nil }

        // Skip optional version [0] EXPLICIT
        if idx < derData.endIndex && derData[idx] == 0xA0 {
            guard derSkipTLV(in: derData, at: &idx) else { return nil }
        }
        guard derSkipTLV(in: derData, at: &idx) else { return nil } // serialNumber
        guard derSkipTLV(in: derData, at: &idx) else { return nil } // signature AlgorithmIdentifier
        guard derSkipTLV(in: derData, at: &idx) else { return nil } // issuer Name

        // Enter Validity SEQUENCE
        guard derReadTag(0x30, in: derData, at: &idx) != nil else { return nil }
        guard let notBefore = derParseTime(in: derData, at: &idx),
              let notAfter  = derParseTime(in: derData, at: &idx) else { return nil }
        return (notBefore, notAfter)
    }

    private func derReadLength(in data: Data, at idx: inout Data.Index) -> Int? {
        guard idx < data.endIndex else { return nil }
        let first = data[idx]
        idx = data.index(after: idx)
        if first & 0x80 == 0 { return Int(first) }
        let numBytes = Int(first & 0x7F)
        guard numBytes > 0, numBytes <= 4 else { return nil }
        var length = 0
        for _ in 0..<numBytes {
            guard idx < data.endIndex else { return nil }
            length = (length << 8) | Int(data[idx])
            idx = data.index(after: idx)
        }
        return length
    }

    /// Confirms `tag`, advances past tag+length; idx lands on first content byte.
    private func derReadTag(_ tag: UInt8, in data: Data, at idx: inout Data.Index) -> Int? {
        guard idx < data.endIndex, data[idx] == tag else { return nil }
        idx = data.index(after: idx)
        return derReadLength(in: data, at: &idx)
    }

    /// Skips a complete TLV (tag + length + value).
    private func derSkipTLV(in data: Data, at idx: inout Data.Index) -> Bool {
        guard idx < data.endIndex else { return false }
        idx = data.index(after: idx)
        guard let len = derReadLength(in: data, at: &idx),
              let end = data.index(idx, offsetBy: len, limitedBy: data.endIndex) else { return false }
        idx = end
        return true
    }

    private func derParseTime(in data: Data, at idx: inout Data.Index) -> Date? {
        guard idx < data.endIndex else { return nil }
        let tag = data[idx]
        idx = data.index(after: idx)
        guard let len = derReadLength(in: data, at: &idx),
              let end = data.index(idx, offsetBy: len, limitedBy: data.endIndex) else { return nil }
        let bytes = data[idx..<end]
        idx = end
        guard let str = String(bytes: bytes, encoding: .ascii) else { return nil }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(identifier: "UTC")
        if tag == 0x17 {       // UTCTime: YYMMDDHHMMSSZ
            fmt.dateFormat = "yyMMddHHmmssZ"
        } else if tag == 0x18 { // GeneralizedTime: YYYYMMDDHHMMSSZ
            fmt.dateFormat = "yyyyMMddHHmmssZ"
        } else {
            return nil
        }
        return fmt.date(from: str)
    }
}

// MARK: - Errors

public enum SSLCertificateError: Error, LocalizedError {
    case noCertificateFound
    case cannotParseCertificate

    public var errorDescription: String? {
        switch self {
        case .noCertificateFound: return "No SSL certificate found for this domain"
        case .cannotParseCertificate: return "Could not parse the SSL certificate"
        }
    }
}

// MARK: - Private URLSession Delegate

private final class CertificateDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    var leafCertificate: SecCertificate?

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        if let chain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
           let leaf = chain.first {
            leafCertificate = leaf
        }

        completionHandler(.performDefaultHandling, nil)
    }
}
