import Testing
import Foundation
import NetMonitorCore
@testable import NetMonitor_macOS

// MARK: - Security readout (#454)

@Suite("SecurityReadoutMacViewModel")
@MainActor
struct SecurityReadoutMacViewModelTests {
    let home = UUID()

    var devices: [LocalDevice] {
        [
            LocalDevice(ipAddress: "192.168.77.40", macAddress: "AA:00:00:00:00:40", deviceType: .storage, customName: "NAS",
                        openPorts: [445], networkProfileID: home),
            LocalDevice(ipAddress: "192.168.77.30", macAddress: "AA:00:00:00:00:30", deviceType: .camera, customName: "Camera",
                        openPorts: [80, 23], networkProfileID: home)
        ]
    }

    @Test func theListIsTheAppsRankedListWhateverTheModelSays() async {
        // The model's paragraph puts the NAS first; the rendered list doesn't follow it.
        let answer = "The NAS shares files and the camera has Telnet open."
        let viewModel = SecurityReadoutMacViewModel(service: FixedAnswerInsightService(answer: answer))

        await viewModel.refresh(devices: devices, networkProfileID: home, isScanning: false)

        #expect(viewModel.findings.map(\.title) == [
            "Telnet port 23 is open", "HTTP admin page port 80 is open", "SMB file sharing port 445 is open"
        ])
        #expect(viewModel.findings.map(\.deviceName) == ["Camera", "Camera", "NAS"])
        #expect(viewModel.overview == answer)
    }

    @Test func withoutTheModelTheFindingsAndFixedTextStillShow() async {
        let viewModel = SecurityReadoutMacViewModel(service: UnavailableInsightService())

        await viewModel.refresh(devices: devices, networkProfileID: home, isScanning: false)

        #expect(viewModel.overview == nil)
        #expect(viewModel.findings.count == 3)
        #expect(viewModel.findings.first?.explanation.hasPrefix("Telnet sends the password") == true)
        #expect(viewModel.findings.first?.remedy.hasPrefix("Turn Telnet off") == true)
    }

    @Test func anUngroundedAnswerFallsBackToTheFixedText() async {
        // "4" is in no fact: InsightSummarizer drops the answer.
        let viewModel = SecurityReadoutMacViewModel(service: FixedAnswerInsightService(answer: "There are 4 problems."))

        await viewModel.refresh(devices: devices, networkProfileID: home, isScanning: false)

        #expect(viewModel.overview == nil)
        #expect(viewModel.findings.count == 3)
    }

    @Test func nothingIsAskedDuringAScan() async {
        let insight = MockInsightService()
        let viewModel = SecurityReadoutMacViewModel(service: insight)

        await viewModel.refresh(devices: devices, networkProfileID: home, isScanning: true)

        #expect(insight.requests.isEmpty)
        #expect(viewModel.findings.count == 3)
    }

    @Test func theSameFindingsAreAskedAboutOnce() async {
        let insight = MockInsightService()
        let viewModel = SecurityReadoutMacViewModel(service: insight)
        let first = Task { await viewModel.refresh(devices: devices, networkProfileID: home, isScanning: false) }
        await waitUntil { insight.requests.count == 1 }
        insight.send(.finished("The camera has Telnet open."))
        await first.value

        await viewModel.refresh(devices: devices, networkProfileID: home, isScanning: false)

        #expect(insight.requests.count == 1)
        #expect(viewModel.overview == "The camera has Telnet open.")
    }

    @Test func anOverviewOfOldFindingsHidesWhileAScanHoldsBackTheNewOne() async {
        let answer = "The camera has Telnet open."
        let viewModel = SecurityReadoutMacViewModel(service: FixedAnswerInsightService(answer: answer))
        await viewModel.refresh(devices: devices, networkProfileID: home, isScanning: false)
        #expect(viewModel.overview == answer)

        // A scan finds one more port: the list updates, and the overview no longer describes it.
        let router = LocalDevice(ipAddress: "192.168.77.1", macAddress: "AA:00:00:00:00:01", deviceType: .router,
                                 customName: "Router", openPorts: [23], networkProfileID: home)
        await viewModel.refresh(devices: devices + [router], networkProfileID: home, isScanning: true)
        #expect(viewModel.findings.count == 4)
        #expect(viewModel.overview == nil)

        // Back to the findings it described: the cached overview shows again without asking.
        await viewModel.refresh(devices: devices, networkProfileID: home, isScanning: true)
        #expect(viewModel.overview == answer)
    }

    @Test func anotherNetworkWithTheSameCountsGetsItsOwnOverview() async {
        // Counts-only requests can match across networks; switching must not leave the readout blank.
        let office = UUID()
        let camera = { (network: UUID) in
            LocalDevice(ipAddress: "192.168.77.30", macAddress: "AA:00:00:00:00:30", deviceType: .camera, customName: "Camera",
                        openPorts: [23], networkProfileID: network)
        }
        let viewModel = SecurityReadoutMacViewModel(service: FixedAnswerInsightService(answer: "A camera has Telnet open."))
        await viewModel.refresh(devices: [camera(home)], networkProfileID: home, isScanning: false)
        #expect(viewModel.overview == "A camera has Telnet open.")

        await viewModel.refresh(devices: [camera(office)], networkProfileID: office, isScanning: false)

        #expect(viewModel.overview == "A camera has Telnet open.")
    }

    @Test func onlyTheNetworksDevicesAndUnassignedOnesCount() async {
        let elsewhere = LocalDevice(ipAddress: "10.0.0.5", macAddress: "AA:00:00:00:00:05", deviceType: .camera, customName: "Other",
                                    openPorts: [23], networkProfileID: UUID())
        let unassigned = LocalDevice(ipAddress: "192.168.77.50", macAddress: "AA:00:00:00:00:50", deviceType: .router,
                                     customName: "Router", openPorts: [23])
        let viewModel = SecurityReadoutMacViewModel(service: UnavailableInsightService())

        await viewModel.refresh(devices: devices + [elsewhere, unassigned], networkProfileID: home, isScanning: false)

        #expect(Set(viewModel.findings.map(\.deviceName)) == ["Camera", "NAS", "Router"])
    }

    @Test func noFindingsAsksNothing() async {
        let insight = MockInsightService()
        let viewModel = SecurityReadoutMacViewModel(service: insight)
        let clean = LocalDevice(ipAddress: "192.168.77.9", macAddress: "AA:00:00:00:00:09", openPorts: [443], networkProfileID: home)

        await viewModel.refresh(devices: [clean], networkProfileID: home, isScanning: false)

        #expect(viewModel.findings.isEmpty)
        #expect(insight.requests.isEmpty)
        #expect(viewModel.overview == nil)
    }

    @Test func theUITestAnswerPassesTheChecks() async {
        let viewModel = SecurityReadoutMacViewModel(service: FixedAnswerInsightService(answer: SecurityReadoutMacViewModel.uiTestAnswer))

        await viewModel.refresh(devices: devices, networkProfileID: home, isScanning: false)

        #expect(viewModel.overview == SecurityReadoutMacViewModel.uiTestAnswer)
    }
}

@MainActor
private func waitUntil(timeout: Duration = .seconds(5), _ condition: () -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

@Suite("Security Readout tool (#454)")
struct SecurityReadoutToolRegistrationTests {
    @Test func listedUnderDiscovery() {
        #expect(ToolCategory.allCases.filter { $0.tools.contains(.securityReadout) } == [.discovery])
        #expect(NetworkTool.securityReadout.rawValue == "Security Readout")
        #expect(NetworkTool.securityReadout.cardIdentifier == "tools_card_security_readout")
    }
}
