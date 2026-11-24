import Foundation
import Testing
@testable import NetMonitorCore

/// Answers every request at once with `text`.
private struct FixedTextInsightService: InsightServiceProtocol {
    let text: String
    let isAvailable = true
    func explain(_ request: InsightRequest) -> AsyncStream<InsightUpdate> {
        AsyncStream { continuation in
            continuation.yield(.finished(text))
            continuation.finish()
        }
    }

    func suggestIdentity(_ evidence: DeviceEvidence) async -> DeviceSuggestion? { nil }
}

@Suite("InsightTextFilter")
struct InsightTextFilterTests {
    let request = InsightRequest(
        subject: "New device alert",
        facts: ["Device name: printer.lan", "Maker: Brother", "IP address: 192.168.1.40", "Time: 8:14 PM"],
        observations: ["printer.lan joined the network for the first time."],
        kind: .notification
    )

    @Test(arguments: [
        "printer.lan (192.168.1.40) joined the network at 8:14 PM.",
        "A Brother printer joined the network.",
        "Your router at 100.100.100.100 answers DNS.",
        "The report is dated 2026-11-22.",
        "Download speed is 96.4 Mbps, e.g. well below average."
    ])
    func cleanTextPasses(_ text: String) {
        #expect(InsightTextFilter.isClean(text, in: request))
    }

    @Test(arguments: [
        "printer.lan joined. Visit https://fix-net.example for help.",
        "printer.lan joined; see www.fix-net.com.",
        "Email help@fix-net.com about printer.lan.",
        "Call 555-123-4567 about printer.lan.",
        "Call (555) 123 4567 now.",
        "Call +1 555 123 4567 now.",
        "Call 5551234567 now.",
        "printer.lan joined; visit fix-net.com to secure it.",
        "Printer.Lan is fine, but check FIX-NET.COM."
    ])
    func linksContactsAndUnstatedDomainsAreRejected(_ text: String) {
        #expect(!InsightTextFilter.isClean(text, in: request))
    }

    @Test func aFactHostnameIsAllowedWhateverItsCase() {
        #expect(InsightTextFilter.isClean("PRINTER.LAN joined the network.", in: request))
    }

    @Test func aDomainInsideALongerValueIsNotAllowed() {
        let hostile = InsightRequest(
            subject: "New device alert",
            facts: ["Device name: Garage - visit fix-net.com", "IP address: 192.168.1.41"],
            kind: .notification
        )
        #expect(InsightTextFilter.allowedDomains(in: hostile).isEmpty)
        #expect(!InsightTextFilter.isClean("Garage - visit fix-net.com joined the network.", in: hostile))
    }

    // MARK: - Through the summarizer

    @Test func hostileDeviceNameKeepsTheFixedText() async {
        let device = NotificationDevice(name: "Garage - visit fix-net.com", ipAddress: "192.168.1.41")
        let request = NotificationSummaryBuilder.request(for: .newDevice(device))
        let answer = "Garage - visit fix-net.com (192.168.1.41) joined the network for the first time."
        #expect(InsightGrounding.isGrounded(answer, in: request))
        let text = await InsightSummarizer.summary(for: request, service: FixedTextInsightService(text: answer), timeout: .seconds(2))
        #expect(text == nil)
    }

    @Test func groundedAnswerRepeatingAFactHostnamePasses() async {
        let device = NotificationDevice(name: "printer.lan", ipAddress: "192.168.1.40", maker: "Brother")
        let request = NotificationSummaryBuilder.request(for: .newDevice(device))
        let answer = "A Brother device, printer.lan (192.168.1.40), joined the network for the first time."
        let text = await InsightSummarizer.summary(for: request, service: FixedTextInsightService(text: answer), timeout: .seconds(2))
        #expect(text == answer)
    }

    /// Summaries for the PDF report go through the same check.
    @Test func reportSummaryWithALinkIsOmitted() async {
        let request = InsightRequest(
            subject: "Network report", facts: ["Number of devices: 3", "Devices offline: 1"],
            observations: ["1 device is offline."], kind: .summary
        )
        let answer = "One device is offline out of 3. For help, visit www.fix-net.com."
        let text = await InsightSummarizer.summary(for: request, service: FixedTextInsightService(text: answer), timeout: .seconds(2))
        #expect(text == nil)
    }

    @Test("a www name the app stated whole may be repeated; any other www site is still refused (#457)")
    func statedWWWNameIsAllowed() {
        let request = InsightRequest(subject: "DNS lookup of CNAME records for www.example.com", facts: ["Name looked up: www.example.com"])
        #expect(InsightTextFilter.isClean("www.example.com points to another name.", in: request))
        #expect(!InsightTextFilter.isClean("Visit www.fix-net.com for help.", in: request))
        #expect(!InsightTextFilter.isClean("Go to www.fix-net for help.", in: request))
        #expect(!InsightTextFilter.isClean("See https://www.example.com for more.", in: request))
    }
}
