import Foundation
import Security

/// The typed fallback for pairing (#590): a one-time 125-bit secret written as 25 Crockford
/// base32 digits plus Crockford's mod-37 check symbol.
///
/// Canonical form: the secret is a 125-bit unsigned big-endian integer held in 16 bytes, the
/// top 3 bits of the first byte zero. Digits run most significant first; the check symbol is
/// the integer mod 37 from Crockford's check alphabet (the 32 digits plus `*~$=U`). The check
/// adds no entropy; it catches typos before a handshake.
public struct CompanionPairingCode: Sendable, Equatable {
    public static let digitCount = 25
    static let digits = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
    static let checkSymbols = digits + Array("*~$=U")

    /// 16 bytes, the top 3 bits zero.
    public let secret: Data

    public init?(secret: Data) {
        guard secret.count == 16, secret[secret.startIndex] & 0xE0 == 0 else { return nil }
        self.secret = secret
    }

    /// Reads what the user typed: any case; dashes and spaces ignored; I and L read as 1, O as 0.
    public init?(typed: String) {
        var symbols: [Character] = []
        for character in typed.uppercased() where character != "-" && !character.isWhitespace {
            switch character {
            case "I", "L": symbols.append("1")
            case "O": symbols.append("0")
            default: symbols.append(character)
            }
        }
        guard symbols.count == Self.digitCount + 1, let check = symbols.last else { return nil }
        var bits = [UInt8](repeating: 0, count: 16)
        for (index, symbol) in symbols.dropLast().enumerated() {
            guard let value = Self.digits.firstIndex(of: symbol) else { return nil }
            Self.setDigit(UInt8(value), at: index, in: &bits)
        }
        guard Self.checkSymbols[Self.mod37(bits)] == check else { return nil }
        self.secret = Data(bits)
    }

    /// A fresh code from the system's secure random source.
    public static func random() -> CompanionPairingCode {
        var bytes = [UInt8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        bytes[0] &= 0x1F
        // swiftlint:disable:next force_unwrapping
        return CompanionPairingCode(secret: Data(bytes))!
    }

    /// 25 digits and the check symbol, with no separators.
    public var canonical: String {
        let bytes = [UInt8](secret)
        let body = (0..<Self.digitCount).map { Self.digits[Int(Self.digit(at: $0, in: bytes))] }
        return String(body) + String(Self.checkSymbols[Self.mod37(bytes)])
    }

    /// The canonical form in groups of five, for the screen.
    public var display: String {
        let characters = Array(canonical)
        return stride(from: 0, to: characters.count, by: 5)
            .map { String(characters[$0..<min($0 + 5, characters.count)]) }
            .joined(separator: "-")
    }

    // MARK: - Bit packing

    /// Digit `index` covers bits `3 + 5·index ..< 8 + 5·index` of the 128-bit big-endian value.
    private static func digit(at index: Int, in bytes: [UInt8]) -> UInt8 {
        var value: UInt8 = 0
        for offset in 0..<5 {
            let bit = 3 + 5 * index + offset
            let isSet = bytes[bit / 8] & (0x80 >> UInt8(bit % 8)) != 0
            value = value << 1 | (isSet ? 1 : 0)
        }
        return value
    }

    private static func setDigit(_ value: UInt8, at index: Int, in bytes: inout [UInt8]) {
        for offset in 0..<5 where value & (0x10 >> UInt8(offset)) != 0 {
            let bit = 3 + 5 * index + offset
            bytes[bit / 8] |= 0x80 >> UInt8(bit % 8)
        }
    }

    private static func mod37(_ bytes: [UInt8]) -> Int {
        bytes.reduce(0) { ($0 * 256 + Int($1)) % 37 }
    }
}
