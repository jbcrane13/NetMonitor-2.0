import Foundation
import Testing
@preconcurrency import UserNotifications
@testable import NetMonitorCore

// MARK: - Builder

@Suite("NotificationSummaryBuilder")
struct NotificationSummaryBuilderTests {
    /// 8:14 PM on 22 November 2026, UTC.
    let now = Date(timeIntervalSince1970: 1_795_378_440)
    var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    @Test func newDeviceStatesNameMakerTypeAddressAndTime() {
        let device = NotificationDevice(name: "Pixel-8", ipAddress: "192.168.1.57", maker: "Google", deviceType: .phone)
        let request = NotificationSummaryBuilder.request(for: .newDevice(device), now: now, calendar: utc)
        #expect(request.kind == .notification)
        #expect(request.subject == "New device alert")
        #expect(request.facts == [
            "Event: joined the network for the first time",
            "Device name: Pixel-8",
            "Maker: Google",
            "Device type: Phone",
            "IP address: 192.168.1.57",
            "Time: 8:14 PM"
        ])
        #expect(request.observations == ["Pixel-8 joined the network for the first time."])
    }

    @Test func newDeviceLeavesOutUnknownMakerAndType() {
        let device = NotificationDevice(name: "192.168.1.57", ipAddress: "192.168.1.57", maker: nil, deviceType: .unknown)
        let request = NotificationSummaryBuilder.request(for: .newDevice(device), now: now, calendar: utc)
        #expect(request.facts == [
            "Event: joined the network for the first time",
            "Device name: 192.168.1.57",
            "IP address: 192.168.1.57",
            "Time: 8:14 PM"
        ])
    }

    @Test func longNamesAreCapped() {
        let long = String(repeating: "a", count: 60)
        let request = NotificationSummaryBuilder.request(for: .targetDown(name: long, host: "10.0.0.1"), now: now, calendar: utc)
        #expect(request.facts[1] == "Name: \(String(repeating: "a", count: 40))…")
    }

    @Test func targetDownAndRecovered() {
        let down = NotificationSummaryBuilder.request(for: .targetDown(name: "NAS", host: "192.168.1.10"), now: now, calendar: utc)
        #expect(down.facts == ["Event: stopped responding", "Name: NAS", "Address: 192.168.1.10", "Time: 8:14 PM"])
        #expect(down.observations == ["NAS (192.168.1.10) is not responding."])

        let up = NotificationSummaryBuilder.request(for: .targetRecovered(name: "NAS", host: "192.168.1.10"), now: now, calendar: utc)
        #expect(up.facts == ["Event: responding again after not responding", "Name: NAS", "Address: 192.168.1.10", "Time: 8:14 PM"])
        #expect(up.observations == ["NAS (192.168.1.10) is responding again."])
    }

    @Test func highLatencyWithAndWithoutName() {
        let named = NotificationSummaryBuilder.request(
            for: .highLatency(name: "Cloudflare", host: "1.1.1.1", latencyMs: 612.4, thresholdMs: 500), now: now, calendar: utc
        )
        #expect(named.facts == [
            "Event: latency above the alert threshold",
            "Name: Cloudflare",
            "Address: 1.1.1.1",
            "Latency: 612 ms",
            "Alert threshold: 500 ms",
            "Time: 8:14 PM"
        ])
        #expect(named.observations == ["The latency of Cloudflare (1.1.1.1) is 612 ms, above the alert threshold of 500 ms."])

        let gateway = NotificationSummaryBuilder.request(
            for: .highLatency(name: nil, host: "192.168.1.1", latencyMs: 140, thresholdMs: 100), now: now, calendar: utc
        )
        #expect(gateway.observations == ["The latency of 192.168.1.1 is 140 ms, above the alert threshold of 100 ms."])
    }

    @Test func notificationPromptAsksForOneOrTwoSentences() {
        let request = NotificationSummaryBuilder.request(for: .targetDown(name: "NAS", host: "192.168.1.10"), now: now, calendar: utc)
        #expect(request.kind.instructions == InsightRequest.notificationInstructions)
        #expect(request.kind.instructions.contains("one or two short sentences"))
        #expect(request.kind.responseTokenLimit == 80)
        #expect(request.prompt.hasSuffix("Write the notification text."))
    }

    /// Numbers the model may echo from the facts (addresses, names with digits, times)
    /// pass the grounding check; others don't.
    @Test func echoedFactsAreGrounded() {
        let device = NotificationDevice(name: "Pixel-8", ipAddress: "192.168.1.57", maker: "Google", deviceType: .phone)
        let request = NotificationSummaryBuilder.request(for: .newDevice(device), now: now, calendar: utc)
        #expect(InsightGrounding.isGrounded("A Google phone, Pixel-8 (192.168.1.57), joined the network at 8:14 PM.", in: request))
        #expect(!InsightGrounding.isGrounded("Pixel-8 joined 3 minutes ago.", in: request))
    }
}

// MARK: - Writer

@Suite("NotificationTextWriter")
@MainActor
struct NotificationTextWriterTests {
    let down = NotificationEvent.targetDown(name: "NAS", host: "192.168.1.10")
    let answer = "NAS (192.168.1.10) is not responding."

    /// Lets the writer's tasks run until `condition` holds.
    func until(_ condition: () -> Bool) async {
        for _ in 0 ..< 2000 where !condition() {
            await Task.yield()
        }
    }

    /// Starts wording `events` and returns the task.
    func start(_ writer: NotificationTextWriter, _ events: [NotificationEvent]) -> Task<[String?], Never> {
        Task { await writer.bodies(for: events) }
    }

    @Test func groundedAnswerIsTheBody() async {
        let service = MockInsightService()
        let writer = NotificationTextWriter(service: service) { false }
        let task = start(writer, [down])
        await until { service.requests.count == 1 }
        #expect(service.requests.first?.kind == .notification)
        service.send(.finished(answer))
        #expect(await task.value == [answer])
    }

    @Test func unavailableModelKeepsFixedTextWithoutAsking() async {
        let service = MockInsightService(isAvailable: false)
        let writer = NotificationTextWriter(service: service) { false }
        #expect(await writer.body(for: down) == nil)
        #expect(service.requests.isEmpty)
    }

    @Test func noInferenceWhileScanning() async {
        let service = MockInsightService()
        var scanning = true
        let writer = NotificationTextWriter(service: service) { scanning }
        #expect(await writer.bodies(for: [down, down]) == [nil, nil])
        #expect(service.requests.isEmpty)

        // The scan state is read when wording starts, so events reported as a scan ends get
        // model text once it has ended.
        scanning = false
        let task = start(writer, [down])
        await until { service.requests.count == 1 }
        service.send(.finished(answer))
        #expect(await task.value == [answer])
    }

    @Test func ungroundedAnswerKeepsFixedText() async {
        let service = MockInsightService()
        let writer = NotificationTextWriter(service: service) { false }
        let task = start(writer, [down])
        await until { service.requests.count == 1 }
        service.send(.finished("NAS has been down for 15 minutes."))
        #expect(await task.value == [nil])
    }

    @Test func cutOffAnswerKeepsFixedText() async {
        let service = MockInsightService()
        let writer = NotificationTextWriter(service: service) { false }
        let task = start(writer, [down])
        await until { service.requests.count == 1 }
        service.send(.finished("NAS (192.168.1.10) is not"))
        #expect(await task.value == [nil])
    }

    @Test func answerOnSeveralLinesKeepsItsFirstLine() async {
        let service = MockInsightService()
        let writer = NotificationTextWriter(service: service) { false }
        let task = start(writer, [down])
        await until { service.requests.count == 1 }
        // The recited facts after the first line are dropped; a cut-off recital doesn't
        // cost the sentence before it.
        service.send(.finished("NAS (192.168.1.10) is not responding.  \nEvent: stopped responding, Name: NAS, Time: 8:"))
        #expect(await task.value == [answer])
    }

    @Test func failedAnswerKeepsFixedText() async {
        let service = MockInsightService()
        let writer = NotificationTextWriter(service: service) { false }
        let task = start(writer, [down])
        await until { service.requests.count == 1 }
        service.send(.failed)
        #expect(await task.value == [nil])
    }

    @Test func burstShareOneDeadline() async {
        let service = MockInsightService()
        let writer = NotificationTextWriter(service: service) { false }
        let clock = ContinuousClock()
        let started = clock.now
        // Nothing answers: the first event uses the whole budget and the rest aren't asked.
        #expect(await writer.bodies(for: [down, down, down]) == [nil, nil, nil])
        #expect(clock.now - started < NotificationTextWriter.timeout + .seconds(1))
        #expect(service.requests.count == 1)
    }

    @Test func slowAnswerKeepsFixedTextAfterTheTimeout() async {
        let service = MockInsightService()
        let writer = NotificationTextWriter(service: service) { false }
        let clock = ContinuousClock()
        let started = clock.now
        #expect(await writer.body(for: down) == nil)
        let elapsed = clock.now - started
        #expect(elapsed >= NotificationTextWriter.timeout)
        #expect(elapsed < NotificationTextWriter.timeout + .seconds(1))
    }

    @Test func burstGetsModelTextForTheFirstThreeOnly() async {
        let service = MockInsightService()
        let writer = NotificationTextWriter(service: service) { false }
        let events = (1 ... 5).map { NotificationEvent.targetDown(name: "Host \($0)", host: "10.0.0.\($0)") }
        let task = start(writer, events)
        // One at a time: each is asked after the one before answers.
        for index in 0 ..< 3 {
            await until { service.requests.count == index + 1 }
            service.send(.finished("Host \(index + 1) (10.0.0.\(index + 1)) is not responding."), to: index)
        }
        let bodies = await task.value
        #expect(service.requests.count == NotificationTextWriter.burstLimit)
        #expect(bodies == [
            "Host 1 (10.0.0.1) is not responding.",
            "Host 2 (10.0.0.2) is not responding.",
            "Host 3 (10.0.0.3) is not responding.",
            nil,
            nil
        ])
    }

    @Test func burstLimitCountsEventsStillBeingWorded() async {
        let service = MockInsightService()
        let writer = NotificationTextWriter(service: service) { false }
        let first = start(writer, [down, down, down])
        await until { service.requests.count == 1 }
        // Three are being worded, so a fourth event right after gets fixed text.
        #expect(await writer.body(for: down) == nil)
        #expect(service.requests.count == 1)
        for index in 0 ..< 3 {
            await until { service.requests.count == index + 1 }
            service.send(.finished(answer), to: index)
        }
        #expect(await first.value == [answer, answer, answer])

        // Once those finish, the next event is worded again.
        let next = start(writer, [down])
        await until { service.requests.count == 4 }
        service.send(.finished(answer), to: 3)
        #expect(await next.value == [answer])
    }
}

// MARK: - Posting

@MainActor
private final class RecordingPoster: NotificationRequestPosting {
    private(set) var requests: [UNNotificationRequest] = []
    func post(_ request: UNNotificationRequest) { requests.append(request) }
}

@Suite("NotificationService generated bodies")
@MainActor
struct NotificationGeneratedBodyTests {
    private func makeService() -> (NotificationService, RecordingPoster, UserDefaults, String) {
        let suite = "NotificationGeneratedBodyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        let poster = RecordingPoster()
        return (NotificationService(poster: poster, defaults: defaults), poster, defaults, suite)
    }

    @Test func generatedBodyReplacesTheBodyAndIsMarked() {
        let (service, poster, defaults, suite) = makeService()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "highLatencyAlertEnabled")
        let text = "Worded by the model."

        service.notifyTargetDown(name: "NAS", host: "192.168.1.10", generatedBody: text)
        service.notifyTargetRecovered(name: "NAS", host: "192.168.1.10", generatedBody: text)
        service.notifyTargetLatency(name: "NAS", host: "192.168.1.10", latency: 612, thresholdMs: 500, generatedBody: text)
        service.notifyHighLatency(host: "192.168.1.1", latency: 140, generatedBody: text)
        service.notifyNewDevice(ipAddress: "192.168.1.57", hostname: "Pixel-8", generatedBody: text)

        #expect(poster.requests.count == 5)
        #expect(poster.requests.allSatisfy { $0.content.body == text })
        #expect(poster.requests.allSatisfy { $0.content.subtitle == "Written on device" })
        #expect(poster.requests.map(\.content.title) == [
            "Target Down", "Target Recovered", "High Latency Detected", "High Latency Detected", "New Device Detected"
        ])
    }

    @Test func withoutGeneratedBodyTheFixedTextIsUnmarked() {
        let (service, poster, defaults, suite) = makeService()
        defer { defaults.removePersistentDomain(forName: suite) }

        service.notifyTargetDown(name: "NAS", host: "192.168.1.10")
        service.notifyNewDevice(ipAddress: "192.168.1.57", hostname: "Pixel-8", generatedBody: nil)

        #expect(poster.requests.map(\.content.body) == [
            "NAS (192.168.1.10) is not responding", "Pixel-8 (192.168.1.57) joined the network"
        ])
        #expect(poster.requests.allSatisfy { $0.content.subtitle.isEmpty })
    }

    @Test func alertTogglesAreReadable() {
        let (service, _, defaults, suite) = makeService()
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(service.isTargetDownAlertEnabled && service.isNewDeviceAlertEnabled && service.isTargetRecoveryAlertEnabled)
        #expect(service.highLatencyAlertThreshold == nil)
        defaults.set(true, forKey: "highLatencyAlertEnabled")
        #expect(service.highLatencyAlertThreshold == 100)
        defaults.set(250, forKey: "highLatencyThreshold")
        #expect(service.highLatencyAlertThreshold == 250)
        defaults.set(false, forKey: NotificationService.targetDownAlertKey)
        #expect(!service.isTargetDownAlertEnabled)
    }
}
