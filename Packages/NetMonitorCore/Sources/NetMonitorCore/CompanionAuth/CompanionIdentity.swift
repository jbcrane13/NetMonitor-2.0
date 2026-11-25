import CryptoKit
import Foundation
import Security

/// One end's TLS identity for the companion link (#590): a P-256 key and a self-signed
/// certificate built from it. Peers trust each other by **pin**, the SHA-256 of the public
/// key's X9.63 form, never by the certificate's names or dates.
public struct CompanionIdentity: Sendable {
    private let privateKey: P256.Signing.PrivateKey

    public init() {
        privateKey = P256.Signing.PrivateKey()
    }

    /// Restores an identity saved with `rawRepresentation`.
    public init(rawRepresentation: Data) throws {
        privateKey = try P256.Signing.PrivateKey(rawRepresentation: rawRepresentation)
    }

    /// The private key's raw bytes, for the Keychain only.
    public var rawRepresentation: Data { privateKey.rawRepresentation }

    /// This identity's pin.
    public var pin: Data { Self.pin(ofPublicKey: privateKey.publicKey.x963Representation) }

    /// The pin of an X9.63 public key, as the Security framework exports EC keys.
    public static func pin(ofPublicKey x963: Data) -> Data {
        Data(SHA256.hash(data: x963))
    }

    /// The identity for `sec_protocol_options_set_local_identity`, or nil if the Security
    /// framework refuses the key or certificate.
    public func makeSecIdentity() -> sec_identity_t? {
        guard let der = try? CompanionCertificate.selfSigned(by: privateKey),
              let certificate = SecCertificateCreateWithData(nil, der as CFData) else { return nil }
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate
        ]
        guard let key = SecKeyCreateWithData(privateKey.x963Representation as CFData, attributes as CFDictionary, nil),
              let identity = SecIdentityCreate(nil, certificate, key) else { return nil }
        return sec_identity_create(identity)
    }
}

/// A minimal X.509 v3 certificate: version, serial, ECDSA-SHA256, a fixed common name,
/// a fixed validity, and the P-256 public key. Nothing in it identifies the device.
enum CompanionCertificate {
    static func selfSigned(by key: P256.Signing.PrivateKey) throws -> Data {
        var serial = [UInt8](repeating: 0, count: 8)
        guard SecRandomCopyBytes(kSecRandomDefault, serial.count, &serial) == errSecSuccess else {
            throw CompanionCredentialError.keychain(errSecAllocate)
        }
        let algorithm = sequence(ecdsaWithSHA256)
        let name = sequence(element(0x31, sequence(commonNameOID, element(0x0C, Array("NetMonitor".utf8)))))
        let validity = sequence(element(0x17, Array("250101000000Z".utf8)), element(0x17, Array("491231235959Z".utf8)))
        let publicKeyInfo = sequence(
            sequence(ecPublicKeyOID, prime256v1OID),
            element(0x03, [0x00] + Array(key.publicKey.x963Representation))
        )
        let tbs = sequence(
            element(0xA0, element(0x02, [0x02])),
            element(0x02, [0x01] + serial),
            algorithm, name, validity, name, publicKeyInfo
        )
        let signature = try key.signature(for: Data(tbs)).derRepresentation
        return Data(sequence(tbs, algorithm, element(0x03, [0x00] + Array(signature))))
    }

    private static let ecPublicKeyOID: [UInt8] = [0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01]
    private static let prime256v1OID: [UInt8] = [0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07]
    private static let ecdsaWithSHA256: [UInt8] = [0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x04, 0x03, 0x02]
    private static let commonNameOID: [UInt8] = [0x06, 0x03, 0x55, 0x04, 0x03]

    private static func element(_ tag: UInt8, _ body: [UInt8]) -> [UInt8] {
        let count = body.count
        let length: [UInt8] = count < 0x80 ? [UInt8(count)]
            : count < 0x100 ? [0x81, UInt8(count)]
            : [0x82, UInt8(count >> 8), UInt8(count & 0xFF)]
        return [tag] + length + body
    }

    private static func sequence(_ parts: [UInt8]...) -> [UInt8] {
        element(0x30, parts.flatMap { $0 })
    }
}
