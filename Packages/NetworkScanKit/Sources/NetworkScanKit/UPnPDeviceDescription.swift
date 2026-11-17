import Foundation

/// What a UPnP device says about itself in its description XML (the document an SSDP
/// reply's `LOCATION` header points to) (#387).
public struct UPnPDeviceDescription: Sendable, Equatable {
    public let friendlyName: String?
    public let manufacturer: String?
    public let modelName: String?

    public init(friendlyName: String?, manufacturer: String?, modelName: String?) {
        self.friendlyName = friendlyName
        self.manufacturer = manufacturer
        self.modelName = modelName
    }

    /// Largest description accepted. Real ones are a few KB; a router's is about 3 KB.
    public static let maxBytes = 64 * 1024

    /// Longest field value kept, so a broken device can't fill the UI.
    static let maxFieldLength = 128

    /// Parses the root device's fields from a UPnP description document.
    ///
    /// Only the root `<device>` counts. Routers nest `<deviceList>` devices (WANDevice,
    /// WANConnectionDevice) with their own `friendlyName`, which must not win. Returns nil
    /// for malformed or oversized input, or when the root device has none of the fields.
    /// Reused for the router's Internet Gateway Device description (#400).
    public static func parse(_ data: Data) -> UPnPDeviceDescription? {
        guard !data.isEmpty, data.count <= maxBytes else { return nil }
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        let delegate = RootDeviceFieldCollector()
        parser.delegate = delegate
        guard parser.parse() else { return nil }

        let description = UPnPDeviceDescription(
            friendlyName: delegate.value(for: "friendlyName"),
            manufacturer: delegate.value(for: "manufacturer"),
            modelName: delegate.value(for: "modelName")
        )
        guard description.friendlyName != nil || description.manufacturer != nil || description.modelName != nil else {
            return nil
        }
        return description
    }
}

/// Collects text of `root > device > field` elements only. Used synchronously by
/// `UPnPDeviceDescription.parse`, never shared across threads.
private final class RootDeviceFieldCollector: NSObject, XMLParserDelegate {
    private static let fields: Set<String> = ["friendlyName", "manufacturer", "modelName"]

    private var path: [String] = []
    private var text = ""
    private var values: [String: String] = [:]
    /// Set once the first root-level `<device>` closes, so a second one is ignored.
    private var rootDeviceDone = false

    func value(for field: String) -> String? {
        values[field]
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        path.append(Self.localName(elementName))
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = Self.localName(elementName)
        if !rootDeviceDone, path.count == 3, path[0] == "root", path[1] == "device", Self.fields.contains(name),
           values[name] == nil {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                values[name] = String(trimmed.prefix(UPnPDeviceDescription.maxFieldLength))
            }
        }
        if path.count == 2, path == ["root", "device"] {
            rootDeviceDone = true
        }
        if !path.isEmpty {
            path.removeLast()
        }
        text = ""
    }

    /// Drops a namespace prefix (`ns:device` → `device`).
    private static func localName(_ name: String) -> String {
        name.split(separator: ":").last.map(String.init) ?? name
    }
}
