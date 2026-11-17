import Foundation
import Network

/// Fetches a UPnP description document from a LAN device (#387).
///
/// A plain HTTP/1.0 GET over `NWConnection` rather than `URLSession`: no redirects can
/// take it off the LAN, App Transport Security does not apply, the byte cap holds while
/// receiving, and the deadline covers the whole exchange.
public enum UPnPDescriptionFetcher {
    /// Whole-exchange deadline: connect, send and receive.
    public static let timeout: Duration = .seconds(2)

    /// Room for the status line and headers on top of the body cap.
    static let maxHeaderBytes = 8 * 1024

    /// The URL to fetch for an SSDP `LOCATION`, or nil unless it is plain `http` to an
    /// IPv4 literal that passes `subnetFilter` (the scan subnet).
    public static func descriptionURL(fromLocation location: String, subnetFilter: (String) -> Bool) -> URL? {
        guard let url = URL(string: location.trimmingCharacters(in: .whitespaces)),
              url.scheme?.lowercased() == "http",
              let host = url.host,
              isValidIPv4Address(host),
              subnetFilter(host) else {
            return nil
        }
        return url
    }

    /// Fetches the document body, or nil on any failure, timeout, non-200 status,
    /// chunked body or a body over ``UPnPDeviceDescription/maxBytes``.
    public static func fetch(_ url: URL, requiredInterfaceType: NWInterface.InterfaceType? = nil) async -> Data? {
        guard let host = url.host, let port = NWEndpoint.Port(rawValue: UInt16(url.port ?? 80)) else { return nil }
        let params = NWParameters.tcp
        if let requiredInterfaceType {
            params.requiredInterfaceType = requiredInterfaceType
        }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: params)
        let request = Data(Self.request(for: url).utf8)

        let result = await withTaskGroup(of: Data?.self) { group -> Data? in
            group.addTask { await Self.exchange(connection, request: request) }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            connection.cancel()
            return first
        }
        guard let result else { return nil }
        return body(ofHTTPResponse: result)
    }

    static func request(for url: URL) -> String {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var target = components?.percentEncodedPath ?? "/"
        if target.isEmpty {
            target = "/"
        }
        if let query = components?.percentEncodedQuery {
            target += "?" + query
        }
        let hostHeader = url.port.map { "\(url.host ?? ""):\($0)" } ?? (url.host ?? "")
        return "GET \(target) HTTP/1.0\r\nHost: \(hostHeader)\r\nAccept: text/xml\r\nConnection: close\r\n\r\n"
    }

    /// The body of a complete HTTP response, or nil unless the status is 200, the body is
    /// not chunked and it fits ``UPnPDeviceDescription/maxBytes``.
    static func body(ofHTTPResponse response: Data) -> Data? {
        guard let separator = response.range(of: Data("\r\n\r\n".utf8)),
              let head = String(data: response[response.startIndex..<separator.lowerBound], encoding: .utf8) else {
            return nil
        }
        let lines = head.components(separatedBy: "\r\n")
        let status = lines.first?.split(separator: " ") ?? []
        guard status.count >= 2, status[0].hasPrefix("HTTP/1."), status[1] == "200" else { return nil }
        let chunked = lines.dropFirst().contains { line in
            let lower = line.lowercased()
            return lower.hasPrefix("transfer-encoding:") && lower.contains("chunked")
        }
        guard !chunked else { return nil }
        let body = response[separator.upperBound...]
        guard !body.isEmpty, body.count <= UPnPDeviceDescription.maxBytes else { return nil }
        return Data(body)
    }

    private static func exchange(_ connection: NWConnection, request: Data) async -> Data? {
        let ready = await withNWConnection(connection, timeout: timeout, timeoutValue: false) { state in
            switch state {
            case .ready: return .completeKeepAlive(true)
            case .failed, .waiting, .cancelled: return .complete(false)
            default: return nil
            }
        }
        guard ready, !Task.isCancelled else { return nil }

        let sent = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            connection.send(content: request, completion: .contentProcessed { error in
                continuation.resume(returning: error == nil)
            })
        }
        guard sent else { return nil }

        let limit = UPnPDeviceDescription.maxBytes + maxHeaderBytes
        var buffer = Data()
        while !Task.isCancelled {
            let (chunk, finished) = await withCheckedContinuation { (continuation: CheckedContinuation<(Data?, Bool), Never>) in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { data, _, isComplete, error in
                    continuation.resume(returning: (data, isComplete || error != nil))
                }
            }
            if let chunk {
                buffer.append(chunk)
            }
            guard buffer.count <= limit else { return nil }
            if finished {
                break
            }
        }
        return buffer.isEmpty ? nil : buffer
    }
}
