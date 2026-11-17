import Testing
import Foundation
@testable import NetworkScanKit

@Suite("UPnPDescriptionFetcher")
struct UPnPDescriptionFetcherTests {

    private let lan: (String) -> Bool = { $0.hasPrefix("192.168.1.") }

    // MARK: - descriptionURL

    @Test("accepts plain http to an IPv4 address in the scan subnet")
    func acceptsLANHTTP() {
        let url = UPnPDescriptionFetcher.descriptionURL(fromLocation: " http://192.168.1.1:44695/rootDesc.xml ", subnetFilter: lan)
        #expect(url?.absoluteString == "http://192.168.1.1:44695/rootDesc.xml")
    }

    @Test("rejects other schemes, hostnames and addresses outside the subnet", arguments: [
        "https://192.168.1.1/desc.xml",
        "ftp://192.168.1.1/desc.xml",
        "http://router.local/desc.xml",
        "http://example.com/desc.xml",
        "http://10.0.0.1/desc.xml",
        "not a url"
    ])
    func rejects(_ location: String) {
        #expect(UPnPDescriptionFetcher.descriptionURL(fromLocation: location, subnetFilter: lan) == nil)
    }

    // MARK: - request

    @Test("request is an HTTP/1.0 GET for the path and query, with the Host header")
    func request() {
        let url = URL(string: "http://192.168.1.1:44695/rootDesc.xml?x=1")!
        let text = UPnPDescriptionFetcher.request(for: url)
        #expect(text.hasPrefix("GET /rootDesc.xml?x=1 HTTP/1.0\r\n"))
        #expect(text.contains("\r\nHost: 192.168.1.1:44695\r\n"))
        #expect(text.hasSuffix("\r\n\r\n"))
        #expect(UPnPDescriptionFetcher.request(for: URL(string: "http://192.168.1.2")!).hasPrefix("GET / HTTP/1.0\r\n"))
    }

    // MARK: - body(ofHTTPResponse:)

    private func response(_ head: String, body: String) -> Data {
        Data((head + "\r\n\r\n" + body).utf8)
    }

    @Test("a 200 response returns its body")
    func okBody() {
        let data = response("HTTP/1.1 200 OK\r\nContent-Type: text/xml", body: "<root/>")
        #expect(UPnPDescriptionFetcher.body(ofHTTPResponse: data) == Data("<root/>".utf8))
    }

    @Test("non-200, chunked, empty, headerless and oversized responses return nil")
    func rejectedBodies() {
        #expect(UPnPDescriptionFetcher.body(ofHTTPResponse: response("HTTP/1.1 404 Not Found", body: "<root/>")) == nil)
        #expect(UPnPDescriptionFetcher.body(ofHTTPResponse: response("HTTP/1.1 302 Found\r\nLocation: http://x/", body: "")) == nil)
        #expect(UPnPDescriptionFetcher.body(ofHTTPResponse: response("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked", body: "7\r\n<root/>")) == nil)
        #expect(UPnPDescriptionFetcher.body(ofHTTPResponse: response("HTTP/1.1 200 OK", body: "")) == nil)
        #expect(UPnPDescriptionFetcher.body(ofHTTPResponse: Data("<root/>".utf8)) == nil)
        let big = String(repeating: "a", count: UPnPDeviceDescription.maxBytes + 1)
        #expect(UPnPDescriptionFetcher.body(ofHTTPResponse: response("HTTP/1.1 200 OK", body: big)) == nil)
    }
}
