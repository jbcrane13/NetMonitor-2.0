import CryptoKit
import Foundation
import Security

/// What the Mac's pairing QR code carries (#590): the Mac's identity and pin, a one-time
/// 256-bit secret, and where to reach it.
public struct CompanionPairingInvitation: Sendable, Equatable {
    public let macID: UUID
    public let macName: String
    public let macPin: Data
    public let secret: Data
    public let host: String?
    public let port: UInt16

    public init(macID: UUID, macName: String, macPin: Data, secret: Data, host: String?, port: UInt16) {
        self.macID = macID
        self.macName = macName
        self.macPin = macPin
        self.secret = secret
        self.host = host
        self.port = port
    }

    /// `netmonitor://pair?v=2&m=<uuid>&n=<name>&pin=<b64url>&k=<b64url>&h=<host>&p=<port>`
    public var qrText: String {
        var components = URLComponents()
        components.scheme = "netmonitor"
        components.host = "pair"
        components.queryItems = [
            URLQueryItem(name: "v", value: "2"),
            URLQueryItem(name: "m", value: macID.uuidString),
            URLQueryItem(name: "n", value: macName),
            URLQueryItem(name: "pin", value: macPin.base64URLEncoded),
            URLQueryItem(name: "k", value: secret.base64URLEncoded),
            URLQueryItem(name: "h", value: host),
            URLQueryItem(name: "p", value: String(port))
        ].filter { $0.value != nil }
        return components.string ?? ""
    }

    public init?(qrText: String) {
        guard let components = URLComponents(string: qrText),
              components.scheme == "netmonitor", components.host == "pair" else { return nil }
        let items = Dictionary((components.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
        guard items["v"] == "2",
              let macID = items["m"].flatMap(UUID.init(uuidString:)),
              let macPin = items["pin"].flatMap(Data.init(base64URLEncoded:)), macPin.count == 32,
              let secret = items["k"].flatMap(Data.init(base64URLEncoded:)), secret.count == 32 else { return nil }
        self.init(
            macID: macID,
            macName: items["n"] ?? "Mac",
            macPin: macPin,
            secret: secret,
            host: items["h"].flatMap { $0.isEmpty ? nil : $0 },
            port: items["p"].flatMap(UInt16.init) ?? 8849
        )
    }
}

/// Proofs that a peer knows the one-time pairing secret, bound to one TLS session and to both
/// pins, plus the comparison code both screens show (#590).
public enum CompanionPairingProof {
    public enum Role: String, Sendable { case phone, mac }

    /// Which one-time secret the phone used: the QR's 256 bits or the typed 125-bit code.
    public enum Kind: String, Codable, Sendable { case qr, code }

    /// What a proof is bound to: one TLS session and both pins, the Mac's named first.
    public struct Binding: Sendable, Equatable {
        public let exporter: Data
        public let macPin: Data
        public let phonePin: Data

        public init(exporter: Data, macPin: Data, phonePin: Data) {
            self.exporter = exporter
            self.macPin = macPin
            self.phonePin = phonePin
        }

        var transcriptTail: Data { exporter + macPin + phonePin }
    }

    public static func make(role: Role, kind: Kind, secret: Data, binding: Binding) -> Data {
        let mac = HMAC<SHA256>.authenticationCode(
            for: transcript(role: role, binding: binding),
            using: key(kind: kind, secret: secret)
        )
        return Data(mac)
    }

    /// Constant-time check of `proof`.
    public static func verify(_ proof: Data, role: Role, kind: Kind, secret: Data, binding: Binding) -> Bool {
        HMAC<SHA256>.isValidAuthenticationCode(
            proof,
            authenticating: transcript(role: role, binding: binding),
            using: key(kind: kind, secret: secret)
        )
    }

    /// Six digits as "123 456", from this session's exporter, both pins and both nonces. Equal
    /// on both screens only when both ends share one session with each other.
    ///
    /// The nonces stop a party in the middle from steering the code: the Mac commits to its nonce
    /// (`commitment(to:)`) before the phone sends its own, and reveals it only after, so neither
    /// side can choose its input once it knows the other's. (A TLS 1.3 exporter alone is fixed
    /// before the client's certificate is sent, so a client could otherwise grind its key.)
    public static func comparisonCode(exporter: Data, macPin: Data, phonePin: Data, macNonce: Data, phoneNonce: Data) -> String {
        let derived = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: exporter),
            info: Data("netmonitor compare v2".utf8) + macPin + phonePin + macNonce + phoneNonce,
            outputByteCount: 4
        )
        let value = derived.withUnsafeBytes { bytes in bytes.reduce(UInt32(0)) { $0 << 8 | UInt32($1) } } % 1_000_000
        let digits = String(format: "%06u", value)
        return "\(digits.prefix(3)) \(digits.suffix(3))"
    }

    /// The Mac's commitment to `nonce`, sent before the phone's nonce.
    public static func commitment(to nonce: Data) -> Data {
        Data(SHA256.hash(data: Data("netmonitor commit v2".utf8) + nonce))
    }

    /// 32 fresh random bytes for a commitment or a comparison nonce.
    public static func makeNonce() -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        return Data(bytes)
    }

    private static func key(kind: Kind, secret: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: secret),
            salt: Data("netmonitor pairing v2".utf8),
            info: Data("proof \(kind.rawValue)".utf8),
            outputByteCount: 32
        )
    }

    private static func transcript(role: Role, binding: Binding) -> Data {
        Data("netmonitor pair v2 \(role.rawValue)".utf8) + binding.transcriptTail
    }
}

extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded text: String) {
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }
}
