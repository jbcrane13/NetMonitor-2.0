import Testing
import Foundation
import SwiftData
@testable import NetMonitorCore

// MARK: - ConnectivityRecord Tests

struct ConnectivityRecordTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: ConnectivityRecord.self, configurations: config)
    }

    @Test("init with required fields sets defaults correctly")
    @MainActor
    func initWithRequiredFields() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let profileID = UUID()
        let record = ConnectivityRecord(profileID: profileID, isOnline: true)
        context.insert(record)

        #expect(record.profileID == profileID)
        #expect(record.isOnline == true)
        #expect(record.latencyMs == nil)
        #expect(record.isSample == false)
        #expect(record.publicIP == nil)
    }

    @Test("init with all fields stores them correctly")
    @MainActor
    func initWithAllFields() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let id = UUID()
        let profileID = UUID()
        let timestamp = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let record = ConnectivityRecord(
            id: id,
            profileID: profileID,
            timestamp: timestamp,
            isOnline: true,
            latencyMs: 25.5,
            isSample: true,
            publicIP: "93.184.216.34"
        )
        context.insert(record)

        #expect(record.id == id)
        #expect(record.profileID == profileID)
        #expect(record.isOnline == true)
        #expect(record.latencyMs == 25.5)
        #expect(record.isSample == true)
        #expect(record.publicIP == "93.184.216.34")
    }

    @Test("offline record has nil latencyMs by convention")
    @MainActor
    func offlineRecordNilLatency() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let record = ConnectivityRecord(profileID: UUID(), isOnline: false)
        context.insert(record)

        #expect(record.isOnline == false)
        #expect(record.latencyMs == nil)
    }

    @Test("sample record vs transition record distinguished by isSample")
    @MainActor
    func sampleVsTransition() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let profileID = UUID()

        let transition = ConnectivityRecord(profileID: profileID, isOnline: true, isSample: false)
        let sample = ConnectivityRecord(profileID: profileID, isOnline: true, latencyMs: 12.3, isSample: true)
        context.insert(transition)
        context.insert(sample)

        #expect(transition.isSample == false)
        #expect(sample.isSample == true)
        #expect(sample.latencyMs == 12.3)
    }

    @Test("publicIP can detect IP address changes across records")
    @MainActor
    func publicIPChangeDetection() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let profileID = UUID()

        let record1 = ConnectivityRecord(profileID: profileID, isOnline: true, publicIP: "1.2.3.4")
        let record2 = ConnectivityRecord(profileID: profileID, isOnline: true, publicIP: "5.6.7.8")
        context.insert(record1)
        context.insert(record2)

        #expect(record1.publicIP != record2.publicIP)
    }
}

// MARK: - LocalDevice latencyHistory buffer tests

struct LocalDeviceLatencyHistoryTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: LocalDevice.self, configurations: config)
    }

    @Test("latencyHistory starts empty")
    @MainActor
    func latencyHistoryStartsEmpty() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let device = LocalDevice(ipAddress: "10.0.0.1", macAddress: "AA:BB:CC:DD:EE:FF")
        context.insert(device)
        #expect(device.latencyHistory.isEmpty)
    }

    @Test("updateLatency appends to latencyHistory")
    @MainActor
    func updateLatencyAppendsToHistory() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let device = LocalDevice(ipAddress: "10.0.0.1", macAddress: "AA:BB:CC:DD:EE:FF")
        context.insert(device)

        device.updateLatency(10.0)
        device.updateLatency(20.0)
        device.updateLatency(30.0)

        #expect(device.latencyHistory.count == 3)
        #expect(device.latencyHistory == [10.0, 20.0, 30.0])
    }

    @Test("latencyHistory caps at 20 entries")
    @MainActor
    func latencyHistoryCapsAt20() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let device = LocalDevice(ipAddress: "10.0.0.1", macAddress: "AA:BB:CC:DD:EE:FF")
        context.insert(device)

        for i in 1...25 {
            device.updateLatency(Double(i))
        }

        #expect(device.latencyHistory.count == 20)
        // Oldest entries (1-5) should have been dropped
        #expect(device.latencyHistory.first == 6.0)
        #expect(device.latencyHistory.last == 25.0)
    }
}

// MARK: - NavigationSection updated tests

struct NavigationSectionCompleteTests {

    @Test("all cases includes devices, tools, settings")
    func allCasesComplete() {
        let cases = NavigationSection.allCases
        #expect(cases.count == 3)
        #expect(cases.contains(.devices))
        #expect(cases.contains(.tools))
        #expect(cases.contains(.settings))
    }

    @Test("devices rawValue is Devices")
    func devicesRawValue() {
        #expect(NavigationSection.devices.rawValue == "Devices")
    }

    @Test("devices iconName is list.bullet.rectangle")
    func devicesIconName() {
        #expect(NavigationSection.devices.iconName == "list.bullet.rectangle")
    }

    @Test("tools iconName is wrench.and.screwdriver")
    func toolsIconName() {
        #expect(NavigationSection.tools.iconName == "wrench.and.screwdriver")
    }

    @Test("settings iconName is gearshape")
    func settingsIconName() {
        #expect(NavigationSection.settings.iconName == "gearshape")
    }
}

// MARK: - ToolResult edge case tests

struct ToolResultEdgeCaseTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: ToolResult.self, configurations: config)
    }

    @Test("formattedDuration at exactly 1 second shows seconds format")
    @MainActor
    func formattedDurationExactlyOneSecond() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let result = ToolResult(toolType: .ping, target: "8.8.8.8", duration: 1.0, success: true, summary: "OK")
        context.insert(result)
        #expect(result.formattedDuration == "1.00 s")
    }

    @Test("formattedDuration at zero shows 0 ms")
    @MainActor
    func formattedDurationZero() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let result = ToolResult(toolType: .dnsLookup, target: "example.com", duration: 0, success: true, summary: "OK")
        context.insert(result)
        #expect(result.formattedDuration == "0 ms")
    }

    @Test("errorMessage is nil when not provided")
    @MainActor
    func errorMessageNilByDefault() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let result = ToolResult(toolType: .ping, target: "1.1.1.1", success: true, summary: "OK")
        context.insert(result)
        #expect(result.errorMessage == nil)
    }
}
