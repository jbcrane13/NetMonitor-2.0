import Foundation
import Testing
@testable import NetMonitorCore

/// The download phase read near 0 Mbps (2026-11-21): Cloudflare answers large `__down`
/// requests with 429 (10–50 MB) or 403 (100 MB), and every refusal counted as data and was
/// re-sent at once. Linode's speed test hosts no longer accept connections.
struct SpeedTestDownloadPlanTests {

    @Test("Downloads in 5 MB requests, the size Cloudflare accepts")
    func defaultRequestSize() {
        #expect(SpeedTestService.defaultDownloadURL.absoluteString == "https://speed.cloudflare.com/__down?bytes=5000000")
        #expect(SpeedTestServer.cloudflare.downloadURL == "https://speed.cloudflare.com/__down?bytes=5000000")
    }

    @Test("A refused request is retried smaller, down to 1 MB")
    func stepsDown() throws {
        var url = SpeedTestService.defaultDownloadURL
        var sizes: [String] = []
        while let smaller = SpeedTestService.smallerDownloadURL(after: url) {
            try sizes.append(#require(URLComponents(url: smaller, resolvingAgainstBaseURL: false)?
                    .queryItems?.first { $0.name == "bytes" }?.value))
            url = smaller
        }
        #expect(sizes == ["2500000", "1250000", "1000000"])
    }

    @Test("A file URL without a size has nothing smaller to ask for")
    func fixedFile() throws {
        let url = try #require(URL(string: "https://proof.ovh.net/files/100Mb.dat"))
        #expect(SpeedTestService.smallerDownloadURL(after: url) == nil)
    }

    @Test("Only success responses count as downloaded data", arguments: [
        (200, true), (206, true), (429, false), (403, false), (500, false), (301, false)
    ])
    func acceptedStatus(status: Int, accepted: Bool) {
        #expect(SpeedTestService.isMeasurableResponse(statusCode: status) == accepted)
    }

    @Test("The picker lists only servers that still answer")
    func serverList() {
        #expect(SpeedTestServer.all.map(\.id) == ["auto", "cloudflare", "vultr-dal", "ovh"])
    }
}
