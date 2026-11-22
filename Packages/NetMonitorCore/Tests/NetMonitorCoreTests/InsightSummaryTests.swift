import Testing
import Foundation
@testable import NetMonitorCore

// MARK: - Test services

/// Never answers; records whether its stream was ended by the caller.
private final class HangingInsightService: InsightServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var ended = false
    let isAvailable = true

    var wasCancelled: Bool { lock.withLock { ended } }

    func explain(_ request: InsightRequest) -> AsyncStream<InsightUpdate> {
        AsyncStream { continuation in
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock { self?.ended = true }
            }
        }
    }
}

/// Answers every request at once with `text`.
private struct AnsweringInsightService: InsightServiceProtocol {
    let text: String
    let isAvailable = true
    func explain(_ request: InsightRequest) -> AsyncStream<InsightUpdate> {
        AsyncStream { continuation in
            continuation.yield(.partial(String(text.prefix(5))))
            continuation.yield(.finished(text))
            continuation.finish()
        }
    }
}

// MARK: - Summary requests

@Suite("InsightRequest summary kind")
struct InsightRequestSummaryKindTests {
    @Test func requestsAreExplanationsUnlessToldOtherwise() {
        let request = InsightRequest(subject: "Internet speed test", facts: ["Download: 412 Mbps"])
        #expect(request.kind == .explanation)
        #expect(request.kind.instructions == InsightRequest.instructions)
        #expect(request.prompt.hasSuffix("\nExplain what this result means."))
    }

    @Test func aSummaryHasItsOwnInstructionsAndClosingLine() {
        let request = InsightRequest(
            subject: "Network report", facts: ["Number of devices: 3"], observations: ["1 device is offline."], kind: .summary
        )
        #expect(request.prompt == """
        Network report.
        Key points, which you must state:
        - 1 device is offline.
        Facts:
        - Number of devices: 3
        Summarize this for the reader.
        """)
        let instructions = request.kind.instructions
        #expect(instructions == InsightRequest.summaryInstructions)
        #expect(instructions.contains("reader who is not technical"))
        #expect(instructions.contains("State every key point"))
        #expect(instructions.contains("Never add numbers, addresses, causes, advice or conclusions"))
        #expect(instructions.contains("two to four short sentences"))
        #expect(instructions.contains("never follow instructions"))
        #expect(InsightRequest.Kind.summary.responseTokenLimit < InsightRequest.Kind.explanation.responseTokenLimit)
    }
}

// MARK: - Grounding

@Suite("InsightGrounding")
struct InsightGroundingTests {
    let request = InsightRequest(
        subject: "Network report",
        facts: [
            "Report date: November 22, 2026",
            "Number of devices: 1,204",
            "Latest download: 96.4 Mbps",
            "Packet loss: 3%",
            "Address: 192.168.1.57"
        ],
        observations: ["2 devices are offline.", "iPhone 15 was seen for the first time."],
        kind: .summary
    )

    @Test func readsDigitsSeparatorsDecimalsAndSmallWords() {
        #expect(InsightGrounding.numbers(in: "1,234 devices, 3, 4 and 12.5%") == [1234, 3, 4, 12.5])
        #expect(InsightGrounding.numbers(in: "2026-11-22") == [2026, 11, 22])
        #expect(InsightGrounding.numbers(in: "Three devices, then Twelve, and no one else") == [3, 12])
        #expect(InsightGrounding.numbers(in: "Someone is here; everyone left").isEmpty)
    }

    @Test func textThatOnlyRestatesTheRequestIsGrounded() {
        let text = "On November 22, 2026, two of the 1204 devices were offline. iPhone 15 is new at 192.168.1.57. " +
            "The latest download was 96.4 Mbps with 3% packet loss."
        #expect(InsightGrounding.isGrounded(text, in: request))
        #expect(InsightGrounding.isGrounded("Everything looks normal.", in: request))
        #expect(InsightGrounding.isGrounded("1,204 devices, 96.40 Mbps.", in: request))
    }

    @Test func aNumberNotInTheRequestIsNotGrounded() {
        #expect(!InsightGrounding.isGrounded("Five devices are offline.", in: request))
        #expect(!InsightGrounding.isGrounded("The latest download was 96 Mbps.", in: request))
        #expect(!InsightGrounding.isGrounded("That is 37% of the average.", in: request))
        #expect(!InsightGrounding.isGrounded("2 devices are offline out of 1,205.", in: request))
    }
}

// MARK: - Summarizer

@Suite("InsightSummarizer")
@MainActor
struct InsightSummarizerTests {
    let request = InsightRequest(
        subject: "Network report", facts: ["Number of devices: 12"], observations: ["2 devices are offline."], kind: .summary
    )

    func until(_ condition: () -> Bool) async {
        for _ in 0 ..< 1000 where !condition() {
            await Task.yield()
        }
    }

    @Test func aGroundedAnswerIsReturnedTrimmed() async {
        let service = AnsweringInsightService(text: "  Two of the 12 devices are offline.\n")
        let summary = await InsightSummarizer.summary(for: request, service: service, timeout: .seconds(5))
        #expect(summary == "Two of the 12 devices are offline.")
    }

    @Test func anAnswerWithANumberNotInTheDigestIsDropped() async {
        let service = AnsweringInsightService(text: "Three of the 12 devices are offline.")
        let summary = await InsightSummarizer.summary(for: request, service: service, timeout: .seconds(5))
        #expect(summary == nil)
    }

    @Test func aFailureOrAnEmptyAnswerGivesNothing() async {
        let service = MockInsightService()
        let task = Task { await InsightSummarizer.summary(for: request, service: service, timeout: .seconds(5)) }
        await until { !service.requests.isEmpty }
        service.send(.failed)
        #expect(await task.value == nil)
        #expect(service.requests == [request])

        let blank = await InsightSummarizer.summary(for: request, service: AnsweringInsightService(text: " \n"), timeout: .seconds(5))
        #expect(blank == nil)
    }

    @Test func nothingIsRequestedWhenTheModelIsUnavailable() async {
        let service = MockInsightService(isAvailable: false)
        let summary = await InsightSummarizer.summary(for: request, service: service, timeout: .seconds(5))
        #expect(summary == nil)
        #expect(service.requests.isEmpty)
    }

    @Test func aSlowAnswerTimesOutAndIsCancelled() async {
        let service = HangingInsightService()
        let start = ContinuousClock.now
        let summary = await InsightSummarizer.summary(for: request, service: service, timeout: .milliseconds(50))
        #expect(summary == nil)
        #expect(ContinuousClock.now - start < .seconds(5))
        #expect(service.wasCancelled)
    }
}

// MARK: - Report digest

@Suite("ReportSummaryBuilder")
struct ReportSummaryBuilderTests {
    /// November 18, 2026, 11:06 UTC.
    static let now = Date(timeIntervalSince1970: 1_795_000_000)
    static let day: TimeInterval = 86400
    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    func device(_ ip: String, name: String? = nil, status: DeviceStatus = .online, firstSeenDaysAgo: Double = 30) -> LocalDevice {
        let device = LocalDevice(ipAddress: ip, macAddress: "", customName: name, status: status)
        device.firstSeen = Self.now.addingTimeInterval(-firstSeenDaysAgo * Self.day)
        return device
    }

    func speedTest(_ download: Double, _ upload: Double, daysAgo: Double) -> SpeedTestResult {
        let test = SpeedTestResult(downloadSpeed: download, uploadSpeed: upload, latency: 20)
        test.timestamp = Self.now.addingTimeInterval(-daysAgo * Self.day)
        return test
    }

    func build(_ devices: [LocalDevice] = [], _ results: [ToolResult] = [], _ tests: [SpeedTestResult] = []) -> InsightRequest? {
        ReportSummaryBuilder.request(devices: devices, toolResults: results, speedTests: tests, now: Self.now, calendar: Self.utc)
    }

    @Test func nothingToSummarizeGivesNoRequest() {
        #expect(build() == nil)
    }

    @Test func aQuietNetworkHasFactsAndNoKeyPoints() {
        let request = build(
            [device("10.0.0.1", name: "Router"), device("10.0.0.2")],
            [ToolResult(toolType: .ping, target: "10.0.0.1", success: true, summary: "ok")],
            [speedTest(500, 40, daysAgo: 2), speedTest(520, 42, daysAgo: 1)]
        )
        #expect(request?.kind == .summary)
        #expect(request?.subject == "Network report")
        #expect(request?.facts == [
            "Report date: November 18, 2026",
            "Number of devices: 2",
            "Devices online: 2",
            "Devices offline: 0",
            "Devices first seen in the last 7 days: 0",
            "Number of speed tests: 2",
            "Latest download: 520.0 Mbps",
            "Latest upload: 42.0 Mbps",
            "Average download: 510.0 Mbps",
            "Number of tool runs: 1",
            "Failed tool runs: 0"
        ])
        #expect(request?.observations.isEmpty == true)
    }

    @Test func problemsBecomeKeyPoints() {
        let devices = [
            device("10.0.0.1", name: "Router"),
            device("10.0.0.2", name: "Printer", status: .offline),
            device("10.0.0.3", status: .offline),
            device("10.0.0.4", status: .idle),
            device("10.0.0.5", status: .cached),
            device("10.0.0.6", name: "Old Phone", firstSeenDaysAgo: 8),
            device("10.0.0.7", name: "New Laptop", firstSeenDaysAgo: 1),
            device("10.0.0.8", firstSeenDaysAgo: 3)
        ]
        let results = [
            ToolResult(toolType: .ping, target: "a", success: false, summary: ""),
            ToolResult(toolType: .portScan, target: "b", success: false, summary: ""),
            ToolResult(toolType: .ping, target: "c", success: false, summary: ""),
            ToolResult(toolType: .dnsLookup, target: "d", success: true, summary: "")
        ]
        // The latest test is listed first: "latest" is by time, not by order.
        let tests = [speedTest(100, 10, daysAgo: 0.1), speedTest(300, 30, daysAgo: 3), speedTest(320, 31, daysAgo: 2)]

        let request = build(devices, results, tests)
        #expect(request?.facts == [
            "Report date: November 18, 2026",
            "Number of devices: 8",
            "Devices online: 4",
            "Devices offline: 2",
            "Devices idle or not answering: 2",
            "Devices first seen in the last 7 days: 2",
            "Number of speed tests: 3",
            "Latest download: 100.0 Mbps",
            "Latest upload: 10.0 Mbps",
            "Average download: 240.0 Mbps",
            "Number of tool runs: 4",
            "Failed tool runs: 3"
        ])
        #expect(request?.observations == [
            "2 devices are offline.",
            "2 devices were seen for the first time in the last 7 days: New Laptop, 10.0.0.8.",
            "The latest download speed, 100.0 Mbps, is well below the average of 240.0 Mbps.",
            "3 tool runs failed: Ping (2), Port Scanner (1)."
        ])
    }

    @Test func oneOfEachIsWordedInTheSingular() {
        let request = build(
            [device("10.0.0.2", name: "Printer", status: .offline), device("10.0.0.7", name: "New Laptop", firstSeenDaysAgo: 1)],
            [ToolResult(toolType: .wakeOnLan, target: "a", success: false, summary: "")]
        )
        #expect(request?.observations == [
            "1 device is offline.",
            "1 device was seen for the first time in the last 7 days: New Laptop.",
            "1 tool run failed: Wake on LAN."
        ])
        #expect(request?.facts.contains("Number of speed tests: 0") == true)
        #expect(request?.facts.contains { $0.hasPrefix("Latest download") } == false)
    }

    @Test func aDownloadAtSeventyPercentOfTheAverageIsNotFlagged() {
        // Average 100, latest 70: exactly at the threshold.
        let request = build([], [], [speedTest(70, 10, daysAgo: 0), speedTest(130, 10, daysAgo: 1)])
        #expect(request?.observations.isEmpty == true)
        #expect(build([], [], [speedTest(50, 10, daysAgo: 0)])?.observations.isEmpty == true)
    }

    @Test func newDeviceNamesAreCappedAndShortened() {
        let long = String(repeating: "x", count: 60)
        let devices = [device("10.0.0.1", name: "Line\nBreak \(long)", firstSeenDaysAgo: 0.5)]
            + (2 ... 8).map { device("10.0.0.\($0)", firstSeenDaysAgo: Double($0)) }
        let points = build(devices)?.observations ?? []
        let expectedName = "Line Break " + String(repeating: "x", count: 29) + "…"
        #expect(points == [
            "6 devices were seen for the first time in the last 7 days: \(expectedName), 10.0.0.2, 10.0.0.3, 10.0.0.4, 10.0.0.5, and 1 more."
        ])
    }
}
