import Foundation
import Observation

/// The measurements a troubleshooting script makes, one call per check (#451). Both apps use
/// `ServiceTroubleshootProbes` over their existing services; tests and UI tests use stubs.
@MainActor
public protocol TroubleshootProbing: AnyObject {
    /// The router's address, or nil when none is found.
    func gatewayAddress() async -> String?
    /// The round trips of the replies to `count` pings; lost pings are missing.
    func ping(_ host: String, count: Int) async -> [Double]
    /// How long resolving `host` took, in milliseconds, or nil when it didn't resolve.
    func lookup(_ host: String) async -> Double?
    /// The Wi-Fi signal now, or nil when this device or connection has no reading.
    func wifiReading() async -> WiFiReading?
    /// The download speed, or why there is none.
    func downloadSpeed() async -> SpeedTestOutcome
    /// Which of `ports` accept a TCP connection on `host`.
    func openPorts(on host: String, among ports: [Int]) async -> [Int]
}

/// What a speed test step got.
public enum SpeedTestOutcome: Equatable, Sendable {
    case measured(downloadMbps: Double)
    /// Another speed test (scheduled, or the Speed Test tool) is using the connection.
    case busy
    /// The test failed or was stopped.
    case failed
}

/// One step of a run: its check and how far it got.
public struct TroubleshootStep: Identifiable, Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case pending
        case running
        case done(TroubleshootResult)
        /// Cancelled, or not run because the run stopped.
        case cancelled

        public var isDone: Bool {
            if case .done = self {
                true
            } else {
                false
            }
        }

        /// How a step looks, for both apps' icons.
        public enum Tone: Equatable, Sendable {
            case pending, running, measured, unmeasured, cancelled
        }

        public var tone: Tone {
            switch self {
            case .pending: .pending
            case .running: .running
            case let .done(result): result.isUnmeasured ? .unmeasured : .measured
            case .cancelled: .cancelled
            }
        }

        /// The line under the step's heading.
        public var text: String {
            switch self {
            case .pending: "Waiting"
            case .running: "Running…"
            case let .done(result): result.text
            case .cancelled: "Not run"
            }
        }
    }

    /// The step's position, from 1.
    public let id: Int
    public let check: TroubleshootCheck
    public internal(set) var status: Status
}

/// The guided troubleshooter on both apps (#451).
///
/// The user describes a symptom, which the on-device model sorts into a `SymptomKind`, or picks
/// the kind from buttons. The app runs that kind's fixed script (`TroubleshootScript`) through
/// `TroubleshootProbing`, showing each step's raw result as it lands, ranks the likely causes
/// (`TroubleshootRules`) and asks the model to word them (`TroubleshootReportBuilder`). The model
/// never chooses or calls a check, and its explanation is dropped unless it names the top cause.
///
/// Nothing runs during a device scan. Cancelling keeps the results so far; a run that didn't
/// finish shows what it measured but never "no problem found", and is not explained.
@MainActor
@Observable
public final class TroubleshootState {
    public enum Phase: Equatable, Sendable {
        case idle
        /// The model is reading the symptom.
        case classifying
        /// The symptom isn't one the troubleshooter checks, or the model couldn't read it: the
        /// user picks a kind from the buttons.
        case unsupported
        /// The user picks the device to check.
        case needsDevice([TroubleshootDevice])
        /// The user types the website to check.
        case needsHost
        case running
        /// Every step ran; the findings are complete.
        case finished
        /// The run stopped early or couldn't start, with why.
        case stopped(String)
    }

    public static let scanMessage = "A device scan is running. Try again when it finishes."
    public static let cancelledMessage = "Cancelled. The results so far are below."
    public static let nothingMeasuredMessage = "None of the checks could measure on this device or connection, so there's nothing to judge."
    public static let noDevicesMessage = "No saved devices yet. Scan the network first, then try again."
    /// Shown above the buttons when the symptom wasn't understood.
    public static let unsupportedMessage = SymptomIntent.unsupportedMessage

    public private(set) var phase: Phase = .idle
    /// The kind of symptom being checked.
    public private(set) var kind: SymptomKind?
    /// What the model read from the symptom, such as the room; nil for a picked kind.
    public private(set) var intent: SymptomIntent?
    public private(set) var steps: [TroubleshootStep] = []
    /// Ranked likely causes; set when a run ends.
    public private(set) var findings: [TroubleshootFinding] = []
    /// The model's wording of the findings, or nil.
    public private(set) var explanation: String?
    public private(set) var isExplaining = false

    private let probes: any TroubleshootProbing
    private let classifier: any SymptomClassifierProtocol
    private let insight: any InsightServiceProtocol
    private let devices: @MainActor () -> [TroubleshootDevice]
    private let isScanning: @MainActor () -> Bool
    private let speedBaseline: @MainActor () -> Double?
    private let readingInterval: Duration
    private let timeout: Duration
    private var runTask: Task<Void, Never>?
    private var stepTask: Task<TroubleshootResult, Never>?
    private var classifyTask: Task<SymptomIntent?, Never>?
    private var explainTask: Task<String?, Never>?
    /// Goes up when a run is cleared or its classification is cancelled; model work started
    /// under an earlier value is discarded when it returns.
    private var runID = 0
    private var isCancelled = false
    private var skipRequested = false

    /// - Parameters:
    ///   - devices: the saved devices on the current network, through the identity seam.
    ///   - isScanning: whether a device scan is running.
    ///   - speedBaseline: the last saved speed test's download, in Mbps.
    ///   - readingInterval: the wait between Wi-Fi readings; three readings span twice this.
    public init(
        probes: any TroubleshootProbing,
        classifier: any SymptomClassifierProtocol,
        insight: any InsightServiceProtocol,
        devices: @escaping @MainActor () -> [TroubleshootDevice],
        isScanning: @escaping @MainActor () -> Bool,
        speedBaseline: @escaping @MainActor () -> Double?,
        readingInterval: Duration = .seconds(5),
        timeout: Duration = ChangeBriefState.timeout
    ) {
        self.probes = probes
        self.classifier = classifier
        self.insight = insight
        self.devices = devices
        self.isScanning = isScanning
        self.speedBaseline = speedBaseline
        self.readingInterval = readingInterval
        self.timeout = timeout
    }

    /// Whether the symptom field shows: the model can read a typed symptom.
    public var canDescribe: Bool { classifier.isAvailable }

    /// Whether the user can skip the step that is running.
    public var canSkipCurrentStep: Bool {
        steps.first { $0.status == .running }?.check.isSkippable ?? false
    }

    /// Whether a run is in progress.
    public var isRunning: Bool { phase == .running || phase == .classifying }

    // MARK: - Starting

    /// Reads `symptom` with the model and runs the script for it. Does nothing without the model.
    public func describe(_ symptom: String) async {
        let text = symptom.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canDescribe, !text.isEmpty, !isRunning else { return }
        guard !isScanning() else {
            stop(Self.scanMessage)
            return
        }
        clear()
        let run = runID
        phase = .classifying
        let task = Task { [classifier] in await classifier.classify(text) }
        classifyTask = task
        let classified = await task.value
        // Cancelled or reset while the model was reading: start nothing.
        guard run == runID else { return }
        classifyTask = nil
        guard let intent = classified, intent.kind != .unsupported else {
            phase = .unsupported
            return
        }
        self.intent = intent
        await route(intent)
    }

    /// Runs the script for a kind the user picked.
    public func choose(_ kind: SymptomKind) async {
        guard !isRunning, kind != .unsupported else { return }
        clear()
        await route(SymptomIntent(kind: kind))
    }

    /// Runs the device script on the device the user picked.
    public func pick(_ device: TroubleshootDevice) async {
        guard case .needsDevice = phase else { return }
        await run(.deviceUnreachable, device: device)
    }

    /// Runs the website script on `host`, typed by the user. A scheme or path is dropped.
    public func useHost(_ host: String) async {
        guard phase == .needsHost, let host = Self.hostName(host) else { return }
        await run(.websiteNotLoading, host: host)
    }

    /// Cancels the run; the results so far stay. Cancelling while the symptom is being read goes
    /// back to the symptom field and runs nothing.
    public func cancel() {
        if phase == .classifying {
            runID += 1
            classifyTask?.cancel()
            classifyTask = nil
            phase = .idle
            return
        }
        guard phase == .running else { return }
        isCancelled = true
        stepTask?.cancel()
        runTask?.cancel()
    }

    /// Skips the running step, when it is skippable (the speed test), and goes on.
    public func skipCurrentStep() {
        guard canSkipCurrentStep else { return }
        skipRequested = true
        stepTask?.cancel()
    }

    /// Back to the symptom field.
    public func reset() {
        cancel()
        clear()
    }

    // MARK: - Running

    private func clear() {
        runID += 1
        explainTask?.cancel()
        explainTask = nil
        isExplaining = false
        phase = .idle
        kind = nil
        intent = nil
        steps = []
        findings = []
        explanation = nil
    }

    private func route(_ intent: SymptomIntent) async {
        kind = intent.kind
        switch intent.kind {
        case .deviceUnreachable:
            let saved = devices()
            guard !saved.isEmpty else {
                stop(Self.noDevicesMessage)
                return
            }
            let resolution = intent.devicePhrase.map { DevicePhraseResolver.resolve($0, among: saved) } ?? .none
            switch resolution {
            case let .one(device):
                await run(.deviceUnreachable, device: device)
            case let .several(matches):
                phase = .needsDevice(matches)
            case .none:
                phase = .needsDevice(saved)
            }
        case .websiteNotLoading:
            if let host = intent.host.flatMap(Self.hostName) {
                await run(.websiteNotLoading, host: host)
            } else {
                phase = .needsHost
            }
        case .slowOrUnstableInternet, .weakWiFi:
            await run(intent.kind)
        case .unsupported:
            phase = .unsupported
        }
    }

    private func stop(_ message: String) {
        phase = .stopped(message)
    }

    private func run(_ kind: SymptomKind, device: TroubleshootDevice? = nil, host: String? = nil) async {
        guard !isScanning() else {
            stop(Self.scanMessage)
            return
        }
        self.kind = kind
        let checks = TroubleshootScript.checks(for: kind, device: device, host: host)
        steps = checks.enumerated().map { TroubleshootStep(id: $0.offset + 1, check: $0.element, status: .pending) }
        findings = []
        explanation = nil
        isCancelled = false
        phase = .running
        let task = Task { await self.runSteps() }
        runTask = task
        await task.value
        runTask = nil

        let completed = steps.allSatisfy(\.status.isDone)
        findings = TroubleshootRules.findings(for: steps.compactMap { step in
            if case let .done(result) = step.status {
                result
            } else {
                nil
            }
        }, completed: completed, unprobedHosts: Set(steps.compactMap { step in
            // A port check that was cancelled or never started says nothing about the ports.
            if case let .ports(host, _) = step.check, !step.status.isDone {
                host
            } else {
                nil
            }
        }))
        if isCancelled {
            stop(Self.cancelledMessage)
        } else if !completed {
            stop(Self.scanMessage)
        } else if findings.isEmpty {
            stop(Self.nothingMeasuredMessage)
        } else {
            phase = .finished
            await explain(kind)
        }
    }

    /// Runs each step in turn until one is cancelled or a scan starts.
    private func runSteps() async {
        for index in steps.indices {
            guard !Task.isCancelled, !isScanning() else { break }
            steps[index].status = .running
            skipRequested = false
            let check = steps[index].check
            let task = Task { await self.measure(check) }
            stepTask = task
            let result = await task.value
            stepTask = nil
            if skipRequested {
                steps[index].status = .done(.skipped)
            } else if isCancelled {
                break
            } else {
                steps[index].status = .done(result)
            }
        }
        for index in steps.indices where !steps[index].status.isDone {
            steps[index].status = .cancelled
        }
    }

    private func measure(_ check: TroubleshootCheck) async -> TroubleshootResult {
        switch check {
        case let .ping(target, count):
            let host: String
            switch target {
            case .gateway:
                guard let gateway = await probes.gatewayAddress() else { return .unavailable("No router address found") }
                host = gateway
            case let .device(_, address): host = address
            case let .host(name): host = name
            }
            return await .ping(PingSummary(target: target, sent: count, times: probes.ping(host, count: count)))
        case let .dnsLookup(host, _):
            return await .dns(host: host, milliseconds: probes.lookup(host))
        case let .wifiSignal(count):
            var readings: [WiFiReading] = []
            for index in 0..<count {
                if index > 0 {
                    try? await Task.sleep(for: readingInterval)
                }
                guard !Task.isCancelled else { break }
                if let reading = await probes.wifiReading() {
                    readings.append(reading)
                }
            }
            return readings.isEmpty ? .unavailable("No Wi-Fi signal reading on this device or connection") : .wifi(readings)
        case .speedTest:
            // Read first: the test about to run must not become its own baseline.
            let baseline = speedBaseline()
            switch await probes.downloadSpeed() {
            case let .measured(download): return .speed(downloadMbps: download, baselineMbps: baseline)
            case .busy: return .unavailable("A speed test is already running")
            case .failed: return .unavailable("The speed test didn't finish")
            }
        case let .ports(host, ports):
            let open = await probes.openPorts(on: host, among: ports)
            return .ports(host: host, open: ports.filter(open.contains), closed: ports.filter { !open.contains($0) })
        }
    }

    private func explain(_ kind: SymptomKind) async {
        guard insight.isAvailable, !isScanning(), let report = TroubleshootReportBuilder.report(for: kind, findings: findings) else { return }
        let run = runID
        isExplaining = true
        let task = Task { [insight, timeout] in
            await InsightSummarizer.summary(for: report.request, service: insight, timeout: timeout)
        }
        explainTask = task
        let text = await task.value
        // Another run replaced this one while the model was writing: its findings aren't these.
        guard run == runID else { return }
        explainTask = nil
        isExplaining = false
        explanation = text.flatMap { report.accepts($0) ? $0 : nil }
    }

    /// The host in what the user typed: "https://GitHub.com:8443/login" → "github.com". Nil when it
    /// isn't a plausible host; the views disable their Check button then.
    public static func hostName(_ text: String) -> String? {
        var host = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let scheme = host.range(of: "://") {
            host = String(host[scheme.upperBound...])
        }
        host = String(host.prefix { $0 != "/" && $0 != "?" && $0 != "#" && $0 != ":" })
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-"))
        guard host.contains("."), host.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return host
    }
}
