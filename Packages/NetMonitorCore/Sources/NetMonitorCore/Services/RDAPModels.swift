import Foundation

// MARK: - RDAPJSONValue

/// A minimal decodable wrapper for arbitrary JSON, used to parse the heterogeneous
/// jCard/vCard arrays RDAP embeds (RFC 7095) where the shape of each element varies
/// (string, number, array, or object) depending on the property.
enum RDAPJSONValue: Decodable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([RDAPJSONValue])
    case object([String: RDAPJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([RDAPJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: RDAPJSONValue].self) {
            self = .object(value)
        } else {
            self = .null
        }
    }

    var stringValue: String? {
        switch self {
        case .string(let value): return value
        case .number(let value): return String(value)
        default: return nil
        }
    }

    var arrayValue: [RDAPJSONValue]? {
        if case .array(let value) = self {
            return value
        }
        return nil
    }

    var objectValue: [String: RDAPJSONValue]? {
        if case .object(let value) = self {
            return value
        }
        return nil
    }
}

// MARK: - RDAP domain response (RFC 9083 §5.3)

struct RDAPDomainResponse: Decodable, Sendable {
    let ldhName: String?
    let handle: String?
    let status: [String]?
    let entities: [RDAPEntity]?
    let events: [RDAPEvent]?
    let nameservers: [RDAPNameserver]?
    let secureDNS: RDAPSecureDNS?
    let links: [RDAPLink]?
}

// MARK: - RDAP IP network response (RFC 9083 §5.4)

struct RDAPIPNetworkResponse: Decodable, Sendable {
    let handle: String?
    let startAddress: String?
    let endAddress: String?
    let ipVersion: String?
    let name: String?
    let type: String?
    let country: String?
    let entities: [RDAPEntity]?
    let events: [RDAPEvent]?

    /// ARIN extension — best-effort, not present on every registry's response.
    let arinOriginAS0OriginAutnums: [String]?

    private enum CodingKeys: String, CodingKey {
        case handle, startAddress, endAddress, ipVersion, name, type, country, entities, events
        case arinOriginAS0OriginAutnums = "arin_originas0_originautnums"
    }
}

// MARK: - Shared RDAP building blocks

struct RDAPEntity: Decodable, Sendable {
    let handle: String?
    let roles: [String]?
    let vcardArray: RDAPJSONValue?
    let entities: [RDAPEntity]?
    let publicIds: [RDAPPublicId]?
    let links: [RDAPLink]?
}

struct RDAPPublicId: Decodable, Sendable {
    let type: String?
    let identifier: String?
}

struct RDAPEvent: Decodable, Sendable {
    let eventAction: String?
    let eventDate: String?
}

struct RDAPNameserver: Decodable, Sendable {
    let ldhName: String?
}

struct RDAPSecureDNS: Decodable, Sendable {
    let delegationSigned: Bool?
}

struct RDAPLink: Decodable, Sendable {
    let rel: String?
    let href: String?
    let type: String?
}

// MARK: - Entity tree search

extension RDAPEntity {
    /// Depth-first search of this entity and its nested `entities` for the first
    /// one carrying the given role (e.g. "registrar", "abuse", "registrant").
    func findFirst(role: String) -> RDAPEntity? {
        if roles?.contains(role) == true {
            return self
        }
        for child in entities ?? [] {
            if let found = child.findFirst(role: role) {
                return found
            }
        }
        return nil
    }
}

extension Array where Element == RDAPEntity {
    func findFirst(role: String) -> RDAPEntity? {
        for entity in self {
            if let found = entity.findFirst(role: role) {
                return found
            }
        }
        return nil
    }
}

// MARK: - vCard extraction (RFC 7095 jCard)

/// Extracted fields of interest from an RDAP entity's `vcardArray`, with
/// "REDACTED FOR PRIVACY"-style placeholder values normalized to nil.
struct RDAPVCardFields: Sendable {
    var fullName: String?
    var organization: String?
    var email: String?
    var phone: String?
    var url: String?
    var country: String?
    var region: String?

    /// Values ICANN's privacy redaction commonly uses in place of real data.
    private static func isRedactedPlaceholder(_ value: String) -> Bool {
        let normalized = value.uppercased()
        return normalized.contains("REDACTED") || normalized.isEmpty
    }

    fileprivate static func sanitized(_ value: String?) -> String? {
        guard let value, !isRedactedPlaceholder(value) else { return nil }
        return value
    }
}

/// Parses an RDAP entity's `vcardArray` (`["vcard", [[name, params, type, value], ...]]`)
/// into the small set of fields the WHOIS tool cares about.
func parseRDAPVCard(_ value: RDAPJSONValue?) -> RDAPVCardFields {
    var fields = RDAPVCardFields()
    guard let topArray = value?.arrayValue, topArray.count >= 2,
          let properties = topArray[1].arrayValue else {
        return fields
    }

    for property in properties {
        guard let parts = property.arrayValue, parts.count >= 4,
              let name = parts[0].stringValue?.lowercased() else { continue }
        let params = parts[1].objectValue ?? [:]
        let valuePart = parts[3]

        switch name {
        case "fn":
            fields.fullName = RDAPVCardFields.sanitized(valuePart.stringValue)
        case "org":
            fields.organization = RDAPVCardFields.sanitized(valuePart.stringValue)
        case "email":
            fields.email = RDAPVCardFields.sanitized(valuePart.stringValue)
        case "tel":
            let raw = valuePart.stringValue
            fields.phone = RDAPVCardFields.sanitized(raw?.replacingOccurrences(of: "tel:", with: ""))
        case "url":
            fields.url = RDAPVCardFields.sanitized(valuePart.stringValue)
        case "adr":
            // jCard adr value is a 7-element array: [pobox, ext, street, locality, region, postalCode, country].
            // Some registries put the readable address in the `label` param instead and leave the
            // array elements empty; prefer the structured elements, fall back to a `cc` param for country.
            if let components = valuePart.arrayValue {
                let strings = components.map { $0.stringValue ?? "" }
                if strings.count > 4 {
                    fields.region = RDAPVCardFields.sanitized(strings[4])
                }
                if strings.count > 6 {
                    fields.country = RDAPVCardFields.sanitized(strings[6])
                }
            }
            if fields.country == nil, let cc = params["cc"]?.stringValue {
                fields.country = RDAPVCardFields.sanitized(cc)
            }
        default:
            break
        }
    }

    return fields
}

// MARK: - RDAP event dates

/// Parses an RDAP `eventDate` string, which is ISO 8601 but may include fractional
/// seconds and/or a non-Z timezone offset (both of which `DateFormatter`'s fixed
/// patterns elsewhere in WHOISService reject).
func parseRDAPDate(_ value: String?) -> Date? {
    guard let value else { return nil }
    let withFractional = ISO8601DateFormatter()
    withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = withFractional.date(from: value) {
        return date
    }

    let standard = ISO8601DateFormatter()
    standard.formatOptions = [.withInternetDateTime]
    return standard.date(from: value)
}
