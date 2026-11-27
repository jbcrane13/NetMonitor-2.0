import Foundation
import SwiftData
import Testing
import NetMonitorCore
import NetworkScanKit
@testable import NetMonitor_macOS

@Suite(.serialized)
@MainActor
struct CompanionMessageHandlerTests {

    @Test func handleHeartbeatReturnsHeartbeatMessage() async throws {
        let (container, _, handler, _, _) = try makeFixture()
        _ = container

        let response = await handler.handle(.heartbeat(HeartbeatPayload()), from: UUID(), authorization: .always)
        if case .heartbeat? = response {
            #expect(true)
        } else {
            #expect(Bool(false))
        }
    }

    @Test func unsupportedCommandReturnsStructuredError() async throws {
        let (container, _, handler, _, _) = try makeFixture()
        _ = container

        let response = await handler.handle(.command(CommandPayload(action: .traceroute)), from: UUID(), authorization: .always)
        guard case .error(let payload)? = response else {
            #expect(Bool(false))
            return
        }

        #expect(payload.code == "UNSUPPORTED_COMMAND")
        #expect(payload.message.contains("traceroute"))
    }

    @Test func pingCommandWithoutHostReturnsMissingParameterError() async throws {
        let (container, _, handler, _, _) = try makeFixture()
        _ = container

        let response = await handler.handle(
            .command(CommandPayload(action: .ping, parameters: [:])),
            from: UUID(),
            authorization: .always
        )
        guard case .error(let payload)? = response else {
            #expect(Bool(false))
            return
        }

        #expect(payload.code == "MISSING_PARAMETER")
        #expect(payload.message.contains("host"))
    }

    @Test("A handler given a link that is no longer authorised does nothing (#590)")
    func revokedLinkGetsNothing() async throws {
        let (container, _, handler, _, _) = try makeFixture()
        _ = container
        let revoked = CompanionAuthorization { false }
        #expect(await handler.handle(.heartbeat(HeartbeatPayload()), from: UUID(), authorization: revoked) == nil)
        let ping = CompanionMessage.command(CommandPayload(action: .ping, parameters: ["host": "127.0.0.1"]))
        #expect(await handler.handle(ping, from: UUID(), authorization: revoked) == nil)
    }

    @Test func wakeOnLanCommandWithoutMacReturnsMissingParameterError() async throws {
        let (container, _, handler, _, _) = try makeFixture()
        _ = container

        let response = await handler.handle(
            .command(CommandPayload(action: .wakeOnLan, parameters: [:])),
            from: UUID(),
            authorization: .always
        )
        guard case .error(let payload)? = response else {
            #expect(Bool(false))
            return
        }

        #expect(payload.code == "MISSING_PARAMETER")
        #expect(payload.message.contains("mac"))
    }

    @Test func refreshTargetsCommandReturnsPersistedTargets() async throws {
        let (container, context, handler, _, _) = try makeFixture()
        _ = container

        context.insert(NetworkTarget(
            name: "Gateway",
            host: "192.168.1.1",
            targetProtocol: .icmp
        ))
        context.insert(NetworkTarget(
            name: "Cloudflare",
            host: "1.1.1.1",
            targetProtocol: .icmp
        ))
        try context.save()

        let response = await handler.handle(.command(CommandPayload(action: .refreshTargets)), from: UUID(), authorization: .always)
        guard case .targetList(let payload)? = response else {
            #expect(Bool(false))
            return
        }

        #expect(payload.targets.count == 2)
        #expect(Set(payload.targets.map(\.name)) == Set(["Gateway", "Cloudflare"]))
    }

    @Test func startMonitoringWithNoEnabledTargetsReturnsStatusUpdateNotMonitoring() async throws {
        let (container, context, handler, _, _) = try makeFixture()
        _ = container

        context.insert(NetworkTarget(
            name: "Disabled",
            host: "8.8.8.8",
            targetProtocol: .icmp,
            isEnabled: false
        ))
        try context.save()

        let response = await handler.handle(.command(CommandPayload(action: .startMonitoring)), from: UUID(), authorization: .always)
        guard case .statusUpdate(let payload)? = response else {
            #expect(Bool(false))
            return
        }

        #expect(payload.isMonitoring == false)
        #expect(payload.onlineTargets == 0)
        #expect(payload.offlineTargets == 0)
    }

    @Test func generateDeviceListMapsCoordinatorDevicesToCompanionPayload() throws {
        let (container, _, handler, coordinator, _) = try makeFixture()
        _ = container

        coordinator.reconcileScan([
            LocalDiscoveredDevice(
                ipAddress: "192.168.1.44",
                macAddress: "AA:BB:CC:DD:EE:44",
                hostname: "office-printer.local"
            )
        ], profileID: nil)

        let message = handler.generateDeviceList()
        guard case .deviceList(let payload) = message else {
            #expect(Bool(false))
            return
        }

        #expect(payload.devices.count == 1)
        #expect(payload.devices[0].ipAddress == "192.168.1.44")
        #expect(payload.devices[0].hostname == "office-printer.local")
        #expect(payload.devices[0].isOnline == true)
    }

    /// #583, #598: a device the latest scan found only in the ARP cache didn't answer, so the feed
    /// doesn't report it online, though it reads Online in the Mac's list within grace.
    @Test func generateDeviceListReportsOnlyDevicesThatAnsweredTheLatestScan() throws {
        let (container, _, handler, coordinator, _) = try makeFixture()
        _ = container
        let printer = LocalDiscoveredDevice(ipAddress: "192.168.1.44", macAddress: "AA:BB:CC:DD:EE:44", hostname: "printer.local")
        let phone = LocalDiscoveredDevice(ipAddress: "192.168.1.45", macAddress: "AA:BB:CC:DD:EE:45", hostname: "phone.local")
        let start = Date()
        coordinator.reconcileScan([printer, phone], profileID: nil, now: start)
        let cachedPrinter = LocalDiscoveredDevice(
            ipAddress: "192.168.1.44", macAddress: "AA:BB:CC:DD:EE:44", hostname: "printer.local", isCached: true
        )
        coordinator.reconcileScan([cachedPrinter, phone], profileID: nil, now: start.addingTimeInterval(60))

        guard case .deviceList(let payload) = handler.generateDeviceList() else {
            Issue.record("Expected a device list")
            return
        }
        let online = Dictionary(uniqueKeysWithValues: payload.devices.map { ($0.ipAddress, $0.isOnline) })
        #expect(online["192.168.1.45"] == true)
        #expect(online["192.168.1.44"] == false)
    }

    /// #462 keeps friendly names out of `hostname`; the feed has no friendly-name field (#427),
    /// so a device known only by its UPnP or UniFi name still reaches iOS with that name.
    @Test func generateDeviceListSendsTheFriendlyNameWithoutAHostname() throws {
        let (container, _, handler, coordinator, _) = try makeFixture()
        _ = container

        coordinator.reconcileScan([
            LocalDiscoveredDevice(
                ipAddress: "192.168.1.45", macAddress: "", hostname: nil,
                identity: DeviceIdentity(friendlyName: IdentityValue("Living Room TV", source: .upnp))
            )
        ], profileID: nil)

        guard case .deviceList(let payload) = handler.generateDeviceList() else {
            #expect(Bool(false))
            return
        }
        #expect(payload.devices.first?.hostname == "Living Room TV")
    }

    /// #449: the feed carries what the device and the user said, never a model suggestion.
    @Test func generateDeviceListLeavesOutASuggestedMaker() throws {
        let (container, _, handler, coordinator, _) = try makeFixture()
        _ = container

        coordinator.reconcileScan([
            LocalDiscoveredDevice(ipAddress: "192.168.1.46", macAddress: "", hostname: "box-46.lan"),
            LocalDiscoveredDevice(
                ipAddress: "192.168.1.47", macAddress: "", hostname: "box-47.lan",
                identity: DeviceIdentity(maker: IdentityValue("Globex", source: .upnp))
            )
        ], profileID: nil)
        for device in coordinator.discoveredDevices {
            device.mergeIdentity(DeviceIdentity(maker: IdentityValue("Acme", source: .modelSuggestion)))
        }

        guard case .deviceList(let payload) = handler.generateDeviceList() else {
            #expect(Bool(false))
            return
        }
        let vendors = Dictionary(uniqueKeysWithValues: payload.devices.map { ($0.ipAddress, $0.vendor) })
        #expect(coordinator.discoveredDevices.first { $0.ipAddress == "192.168.1.46" }?.maker == "Acme")
        #expect(vendors["192.168.1.46"] == .some(nil))
        #expect(vendors["192.168.1.47"] == "Globex")
    }

    // MARK: - Insight for the iPhone (#457)

    private static let insightRequest = InsightRequestPayload(
        requestID: UUID(),
        request: InsightRequest(subject: "Port scan of 192.168.1.20", facts: ["Open ports (1): 22 (SSH)"], observations: ["SSH is open"])
    )

    @Test("the heartbeat reply advertises insight.v1 only while this Mac's model can answer")
    func heartbeatAdvertisesInsightWithModel() async throws {
        UserDefaults.standard.set(true, forKey: CompanionMessageHandler.answersInsightKey)
        defer { UserDefaults.standard.removeObject(forKey: CompanionMessageHandler.answersInsightKey) }
        let (container, _, withModel, _, _) = try makeFixture(insightService: FixedAnswerInsightService(answer: "SSH is open."))
        let (otherContainer, _, withoutModel, _, _) = try makeFixture()
        _ = (container, otherContainer)

        guard case let .heartbeat(offered)? = await withModel.handle(.heartbeat(HeartbeatPayload()), from: UUID(), authorization: .always),
              case let .heartbeat(plain)? = await withoutModel.handle(.heartbeat(HeartbeatPayload()), from: UUID(), authorization: .always)
        else {
            Issue.record("expected heartbeat replies")
            return
        }
        #expect(offered.capabilities == ["insight.v1", "inventory.v1"])
        #expect(plain.capabilities == ["inventory.v1"])
    }

    @Test("while the Mac scans its heartbeat drops insight.v1, and a fresh heartbeat goes out when a scan starts and ends")
    func scanWithdrawsInsight() async throws {
        UserDefaults.standard.set(true, forKey: CompanionMessageHandler.answersInsightKey)
        defer { UserDefaults.standard.removeObject(forKey: CompanionMessageHandler.answersInsightKey) }
        let (container, _, handler, discovery, _) = try makeFixture(insightService: FixedAnswerInsightService(answer: "SSH is open."))
        _ = container
        var sent: [HeartbeatPayload] = []
        handler.onScanningChange { sent.append($0) }

        discovery.setScanningForTesting(true)
        try await waitUntil { sent.count == 1 }
        #expect(handler.heartbeat().capabilities == ["inventory.v1"])
        #expect(sent.last?.capabilities == ["inventory.v1"])
        let reply = await handler.handle(.insightRequest(Self.insightRequest), from: UUID(), authorization: .always)
        guard case let .insightResponse(response)? = reply else {
            Issue.record("expected an insight response")
            return
        }
        #expect(response.failureReason == .busy)

        discovery.setScanningForTesting(false)
        try await waitUntil { sent.count == 2 }
        #expect(sent.last?.capabilities == ["insight.v1", "inventory.v1"])
    }

    @Test("a message type this build doesn't know gets no reply")
    func unknownTypeGetsNoReply() async throws {
        let (container, _, handler, _, _) = try makeFixture()
        _ = container
        #expect(await handler.handle(.unknown(type: "futureThing"), from: UUID(), authorization: .always) == nil)
    }

    @Test("an insight request is handled apart from its batch; other messages keep their order")
    func insightRequestsRunOffBatch() {
        #expect(CompanionService.answersOffBatch(.insightRequest(Self.insightRequest)))
        #expect(!CompanionService.answersOffBatch(.heartbeat(HeartbeatPayload())))
        #expect(!CompanionService.answersOffBatch(.command(CommandPayload(action: .refreshDevices))))
    }

    @Test("an insight request is answered by the model, under the request's id")
    func insightRequestAnswered() async throws {
        UserDefaults.standard.set(true, forKey: CompanionMessageHandler.answersInsightKey)
        defer { UserDefaults.standard.removeObject(forKey: CompanionMessageHandler.answersInsightKey) }
        let (container, _, handler, _, _) = try makeFixture(insightService: FixedAnswerInsightService(answer: "SSH is open on this device."))
        _ = container

        let reply = await handler.handle(.insightRequest(Self.insightRequest), from: UUID(), authorization: .always)
        guard case let .insightResponse(response)? = reply else {
            Issue.record("expected an insight response")
            return
        }
        #expect(response.requestID == Self.insightRequest.requestID)
        #expect(response.answer == "SSH is open on this device.")
    }

    @Test("answering is on until the owner turns it off: the default advertises insight.v1 and requests are answered")
    func insightOnByDefault() async throws {
        UserDefaults.standard.removeObject(forKey: CompanionMessageHandler.answersInsightKey)
        let model = FixedAnswerInsightService(answer: "SSH is open.")
        let (container, _, handler, _, _) = try makeFixture(insightService: model)
        _ = container

        #expect(CompanionMessageHandler.answersInsight)
        #expect(handler.heartbeat().capabilities == ["insight.v1", "inventory.v1"])
        guard case let .insightResponse(response)? = await handler.handle(.insightRequest(Self.insightRequest), from: UUID(), authorization: .always)
        else {
            Issue.record("expected an insight reply")
            return
        }
        #expect(response.answer == "SSH is open.")
    }

    @Test("with the model unavailable an insight request is answered unavailable")
    func insightRequestModelUnavailable() async throws {
        let (container, _, handler, _, _) = try makeFixture()
        _ = container

        let reply = await handler.handle(.insightRequest(Self.insightRequest), from: UUID(), authorization: .always)
        guard case let .insightResponse(response)? = reply else {
            Issue.record("expected an insight response")
            return
        }
        #expect(response.failureReason == .unavailable)
    }

    @Test("with answering turned off in Settings, no capability is offered and requests are unavailable")
    func insightTurnedOff() async throws {
        UserDefaults.standard.set(false, forKey: CompanionMessageHandler.answersInsightKey)
        defer { UserDefaults.standard.removeObject(forKey: CompanionMessageHandler.answersInsightKey) }
        let (container, _, handler, _, _) = try makeFixture(insightService: FixedAnswerInsightService(answer: "SSH is open."))
        _ = container

        #expect(handler.heartbeat().capabilities == ["inventory.v1"])
        let reply = await handler.handle(.insightRequest(Self.insightRequest), from: UUID(), authorization: .always)
        guard case let .insightResponse(response)? = reply else {
            Issue.record("expected an insight response")
            return
        }
        #expect(response.failureReason == .unavailable)
    }

    @Test("rules.v1 and symptoms.v1 are listed while the model answers, even during a scan, and a typed rule is read (#586)")
    func modelSchemas() async throws {
        let model = StubCompanionModel(output: .rules(RuleIntentRaw(kind: "deviceOffline", device: "NAS")))
        let (container, _, handler, discovery, _) = try makeFixture(companionModel: model)
        _ = container
        #expect(handler.heartbeat().capabilities == ["rules.v1", "symptoms.v1", "identity.v1", "inventory.v1"])
        discovery.setScanningForTesting(true)
        #expect(handler.heartbeat().capabilities == ["rules.v1", "symptoms.v1", "identity.v1", "inventory.v1"])
        let busy = await handler.handle(.modelRequest(ModelRequestPayload(requestID: UUID(), input: .rules(text: "NAS offline"))),
                                        from: UUID(), authorization: .always)
        guard case let .modelResponse(during)? = busy else {
            Issue.record("expected a model reply")
            return
        }
        #expect(during.result(expecting: .rules) == .failure(.busy), "never asked during a scan")
        discovery.setScanningForTesting(false)

        let request = ModelRequestPayload(requestID: UUID(), input: .rules(text: "tell me if the NAS goes offline"))
        guard case let .modelResponse(response)? = await handler.handle(.modelRequest(request), from: UUID(), authorization: .always) else {
            Issue.record("expected a model reply")
            return
        }
        #expect(response.requestID == request.requestID)
        #expect(response.result(expecting: .rules) == .output(.rules(RuleIntentRaw(kind: "deviceOffline", device: "NAS"))))
    }

    // swiftlint:disable large_tuple
    private func makeFixture(
        insightService: any InsightServiceProtocol = UnavailableInsightService(),
        companionModel: any CompanionModelAnswering = UnavailableCompanionModel()
    ) throws -> (
        ModelContainer,
        ModelContext,
        CompanionMessageHandler,
        DeviceDiscoveryCoordinator,
        MonitoringSession
    ) {
        // swiftlint:enable large_tuple
        let schema = Schema([
            NetworkTarget.self,
            TargetMeasurement.self,
            SessionRecord.self,
            LocalDevice.self
        ])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let networkProfileManager = NetworkProfileManager()
        let monitoringSession = MonitoringSession(modelContext: context)
        let deviceDiscovery = DeviceDiscoveryCoordinator(
            modelContext: context,
            bonjourScanner: BonjourDiscoveryService(),
            networkProfileManager: networkProfileManager,
            scanHistory: .forTesting(),
            dispatcher: DeviceEventDispatcher()
        )

        let handler = CompanionMessageHandler(
            modelContext: context,
            monitoringSession: monitoringSession,
            deviceDiscovery: deviceDiscovery,
            wakeOnLanService: WakeOnLANService(),
            icmpService: ICMPMonitorService(),
            networkProfileManager: networkProfileManager,
            insightService: insightService,
            companionModel: companionModel,
            modelAdmission: ModelAdmission()
        )

        return (container, context, handler, deviceDiscovery, monitoringSession)
    }
}

@MainActor
private func waitUntil(timeout: Duration = .seconds(5), _ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
}

/// A Mac model that answers every input with `output`.
private struct StubCompanionModel: CompanionModelAnswering {
    let output: ModelOutput
    var isAvailable: Bool { true }
    func answer(_ input: ModelInput, submission: ModelSubmission) async -> ModelOutput? {
        try? await submission.run { output }
    }
}
