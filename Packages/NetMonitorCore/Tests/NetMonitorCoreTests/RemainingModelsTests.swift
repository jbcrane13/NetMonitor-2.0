import Testing
import Foundation
import SwiftData
@testable import NetMonitorCore

// MARK: - NavigationSection Tests

@Suite("NavigationSection")
struct NavigationSectionTests {

    @Test("NavigationSection has all expected cases")
    func allCasesExist() {
        let cases = NavigationSection.allCases
        #expect(cases.count == 2)
        #expect(cases.contains(.tools))
        #expect(cases.contains(.settings))
    }

    @Test("NavigationSection rawValues match display names")
    func rawValues() {
        #expect(NavigationSection.tools.rawValue == "Tools")
        #expect(NavigationSection.settings.rawValue == "Settings")
    }

    @Test("NavigationSection id equals rawValue")
    func idEqualsRawValue() {
        for section in NavigationSection.allCases {
            #expect(section.id == section.rawValue)
        }
    }

    @Test("NavigationSection iconName is non-empty for all cases")
    func iconNamesNonEmpty() {
        for section in NavigationSection.allCases {
            #expect(!section.iconName.isEmpty)
        }
    }
}

// MARK: - MeasurementStatistics Tests

@Suite("MeasurementStatistics")
struct MeasurementStatisticsTests {

    @Test("MeasurementStatistics with all nil values formats as dash")
    func nilValuesFormattedAsDash() {
        let stats = MeasurementStatistics(
            averageLatency: nil,
            minLatency: nil,
            maxLatency: nil,
            uptimePercentage: nil
        )
        #expect(stats.averageLatencyFormatted == "—")
        #expect(stats.minLatencyFormatted == "—")
        #expect(stats.maxLatencyFormatted == "—")
        #expect(stats.uptimeFormatted == "—")
    }

    @Test("MeasurementStatistics formats latency as integer ms")
    func latencyFormatting() {
        let stats = MeasurementStatistics(
            averageLatency: 42.7,
            minLatency: 10.0,
            maxLatency: 100.3,
            uptimePercentage: 99.5
        )
        #expect(stats.averageLatencyFormatted == "43")
        #expect(stats.minLatencyFormatted == "10")
        #expect(stats.maxLatencyFormatted == "100")
    }

    @Test("MeasurementStatistics formats uptime with one decimal")
    func uptimeFormatting() {
        let stats = MeasurementStatistics(
            averageLatency: nil,
            minLatency: nil,
            maxLatency: nil,
            uptimePercentage: 98.7
        )
        #expect(stats.uptimeFormatted == "98.7")
    }

    @Test("TargetMeasurement.calculateStatistics returns nil stats for empty array")
    func calculateStatisticsEmpty() {
        let stats = TargetMeasurement.calculateStatistics(from: [])
        #expect(stats.averageLatency == nil)
        #expect(stats.minLatency == nil)
        #expect(stats.maxLatency == nil)
        #expect(stats.uptimePercentage == nil)
    }
}

// MARK: - ToolActivityItem Tests

@Suite("ToolActivityItem")
struct ToolActivityItemTests {

    @Test("ToolActivityItem init stores properties")
    func init_storesProperties() {
        let ts = Date()
        let item = ToolActivityItem(tool: "Ping", target: "8.8.8.8", result: "OK", success: true, timestamp: ts)
        #expect(item.tool == "Ping")
        #expect(item.target == "8.8.8.8")
        #expect(item.result == "OK")
        #expect(item.success == true)
        #expect(item.timestamp == ts)
    }

    @Test("ToolActivityItem id is unique per instance")
    func uniqueIDs() {
        let item1 = ToolActivityItem(tool: "Ping", target: "1.1.1.1", result: "OK", success: true)
        let item2 = ToolActivityItem(tool: "Ping", target: "1.1.1.1", result: "OK", success: true)
        #expect(item1.id != item2.id)
    }

    @Test("timeAgoText returns 'Just now' for recent timestamp")
    func timeAgoTextJustNow() {
        let item = ToolActivityItem(tool: "Ping", target: "1.1.1.1", result: "OK", success: true, timestamp: Date())
        #expect(item.timeAgoText == "Just now")
    }

    @Test("timeAgoText returns minutes for timestamps 1-59 minutes ago")
    func timeAgoTextMinutes() {
        let twoMinutesAgo = Date().addingTimeInterval(-120)
        let item = ToolActivityItem(tool: "Ping", target: "1.1.1.1", result: "OK", success: true, timestamp: twoMinutesAgo)
        #expect(item.timeAgoText == "2m ago")
    }

    @Test("timeAgoText returns hours for timestamps 1+ hours ago")
    func timeAgoTextHours() {
        let twoHoursAgo = Date().addingTimeInterval(-7200)
        let item = ToolActivityItem(tool: "Ping", target: "1.1.1.1", result: "OK", success: true, timestamp: twoHoursAgo)
        #expect(item.timeAgoText == "2h ago")
    }
}

// MARK: - ToolActivityLog Tests

@Suite("ToolActivityLog")
struct ToolActivityLogTests {

    @Test("ToolActivityLog add inserts entry at front")
    @MainActor
    func addInsertsAtFront() {
        let log = ToolActivityLog.shared
        log.clear()
        log.add(tool: "Ping", target: "1.1.1.1", result: "OK", success: true)
        log.add(tool: "DNS", target: "google.com", result: "resolved", success: true)
        #expect(log.entries.first?.tool == "DNS")
        log.clear()
    }

    @Test("ToolActivityLog clear empties entries")
    @MainActor
    func clearEmptiesEntries() {
        let log = ToolActivityLog.shared
        log.add(tool: "Ping", target: "1.1.1.1", result: "OK", success: true)
        log.clear()
        #expect(log.entries.isEmpty)
    }

    @Test("ToolActivityLog caps entries at 20")
    @MainActor
    func capsAt20Entries() {
        let log = ToolActivityLog.shared
        log.clear()
        for i in 0..<25 {
            log.add(tool: "Ping", target: "\(i)", result: "OK", success: true)
        }
        #expect(log.entries.count == 20)
        log.clear()
    }

    // MARK: - Additional ToolActivityLog Tests (6B)

    @Test("ToolActivityLog add stores correct entry properties")
    @MainActor
    func addEntryProperties() {
        let log = ToolActivityLog.shared
        log.clear()
        log.add(tool: "DNS", target: "example.com", result: "Resolved", success: true)
        #expect(log.entries.count == 1)
        let entry = log.entries.first
        #expect(entry?.tool == "DNS")
        #expect(entry?.target == "example.com")
        #expect(entry?.result == "Resolved")
        #expect(entry?.success == true)
        log.clear()
    }

    @Test("ToolActivityLog add with failure records success=false")
    @MainActor
    func addFailureEntry() {
        let log = ToolActivityLog.shared
        log.clear()
        log.add(tool: "Ping", target: "10.0.0.1", result: "Timeout", success: false)
        #expect(log.entries.first?.success == false)
        log.clear()
    }

    @Test("ToolActivityLog clear removes all entries after multiple adds")
    @MainActor
    func clearRemovesMultiple() {
        let log = ToolActivityLog.shared
        log.clear()
        log.add(tool: "Ping", target: "1", result: "OK", success: true)
        log.add(tool: "DNS", target: "2", result: "OK", success: true)
        log.add(tool: "WHOIS", target: "3", result: "OK", success: true)
        #expect(log.entries.count == 3)
        log.clear()
        #expect(log.entries.isEmpty)
    }

    @Test("ToolActivityLog clear on empty log is safe")
    @MainActor
    func clearOnEmptyIsSafe() {
        let log = ToolActivityLog.shared
        log.clear()
        log.clear()
        #expect(log.entries.isEmpty)
    }

    @Test("ToolActivityLog maxEntries rotation drops oldest entries")
    @MainActor
    func maxEntriesDropsOldest() {
        let log = ToolActivityLog.shared
        log.clear()
        for i in 0..<20 {
            log.add(tool: "Ping", target: "target-\(i)", result: "OK", success: true)
        }
        #expect(log.entries.count == 20)
        // The first added (target-0) should be last in list (newest-first order)
        #expect(log.entries.last?.target == "target-0")

        // Add one more — should drop target-0 (the oldest)
        log.add(tool: "Ping", target: "target-20", result: "OK", success: true)
        #expect(log.entries.count == 20)
        #expect(log.entries.first?.target == "target-20")
        // target-0 should no longer be present
        let containsTarget0 = log.entries.contains { $0.target == "target-0" }
        #expect(!containsTarget0)
        log.clear()
    }

    @Test("ToolActivityLog entries are ordered newest first")
    @MainActor
    func entriesNewestFirst() {
        let log = ToolActivityLog.shared
        log.clear()
        log.add(tool: "First", target: "1", result: "OK", success: true)
        log.add(tool: "Second", target: "2", result: "OK", success: true)
        log.add(tool: "Third", target: "3", result: "OK", success: true)
        #expect(log.entries[0].tool == "Third")
        #expect(log.entries[1].tool == "Second")
        #expect(log.entries[2].tool == "First")
        log.clear()
    }

    @Test("ToolActivityLog add at exactly maxEntries boundary keeps count at 20")
    @MainActor
    func addAtBoundaryDoesNotExceed() {
        let log = ToolActivityLog.shared
        log.clear()
        for i in 0..<20 {
            log.add(tool: "Ping", target: "\(i)", result: "OK", success: true)
        }
        #expect(log.entries.count == 20)
        log.add(tool: "Extra", target: "extra", result: "OK", success: true)
        #expect(log.entries.count == 20)
        log.clear()
    }
}

// MARK: - MonitoringTarget Tests

@Suite("MonitoringTarget")
struct MonitoringTargetTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: MonitoringTarget.self, configurations: config)
    }

    @Test("MonitoringTarget init sets defaults correctly")
    @MainActor
    func initDefaults() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let target = MonitoringTarget(name: "Router", host: "192.168.1.1")
        context.insert(target)

        #expect(target.name == "Router")
        #expect(target.host == "192.168.1.1")
        #expect(target.port == nil)
        #expect(target.targetProtocol == .icmp)
        #expect(target.isEnabled == true)
        #expect(target.checkInterval == 60)
        #expect(target.timeout == 5)
        #expect(target.isOnline == false)
        #expect(target.consecutiveFailures == 0)
        #expect(target.totalChecks == 0)
        #expect(target.successfulChecks == 0)
    }

    @Test("MonitoringTarget statusType reflects isOnline")
    @MainActor
    func statusType() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let target = MonitoringTarget(name: "Test", host: "10.0.0.1")
        context.insert(target)

        #expect(target.statusType == .offline)
        target.isOnline = true
        #expect(target.statusType == .online)
    }

    @Test("MonitoringTarget uptimePercentage is 0 with no checks")
    @MainActor
    func uptimePercentageZeroChecks() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let target = MonitoringTarget(name: "Test", host: "10.0.0.1")
        context.insert(target)

        #expect(target.uptimePercentage == 0.0)
    }

    @Test("MonitoringTarget uptimePercentage calculates correctly")
    @MainActor
    func uptimePercentageCalculation() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let target = MonitoringTarget(name: "Test", host: "10.0.0.1")
        context.insert(target)

        target.totalChecks = 4
        target.successfulChecks = 3
        #expect(target.uptimePercentage == 75.0)
    }

    @Test("MonitoringTarget uptimeText is formatted with one decimal")
    @MainActor
    func uptimeText() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let target = MonitoringTarget(name: "Test", host: "10.0.0.1")
        context.insert(target)

        target.totalChecks = 3
        target.successfulChecks = 1
        #expect(target.uptimeText == "33.3%")
    }

    @Test("MonitoringTarget latencyText is nil when no latency")
    @MainActor
    func latencyTextNil() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let target = MonitoringTarget(name: "Test", host: "10.0.0.1")
        context.insert(target)

        #expect(target.latencyText == nil)
    }

    @Test("MonitoringTarget latencyText formats sub-ms as <1 ms")
    @MainActor
    func latencyTextSubMs() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let target = MonitoringTarget(name: "Test", host: "10.0.0.1")
        context.insert(target)

        target.currentLatency = 0.5
        #expect(target.latencyText == "<1 ms")
    }

    @Test("MonitoringTarget latencyText formats normal latency")
    @MainActor
    func latencyTextNormal() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let target = MonitoringTarget(name: "Test", host: "10.0.0.1")
        context.insert(target)

        target.currentLatency = 42.0
        #expect(target.latencyText == "42 ms")
    }

    @Test("MonitoringTarget hostWithPort without port returns host only")
    @MainActor
    func hostWithPortNoPort() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let target = MonitoringTarget(name: "Test", host: "10.0.0.1")
        context.insert(target)

        #expect(target.hostWithPort == "10.0.0.1")
    }

    @Test("MonitoringTarget hostWithPort with port returns host:port")
    @MainActor
    func hostWithPortWithPort() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let target = MonitoringTarget(name: "Test", host: "10.0.0.1", port: 443)
        context.insert(target)

        #expect(target.hostWithPort == "10.0.0.1:443")
    }

    @Test("recordSuccess updates stats and sets online")
    @MainActor
    func recordSuccess() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let target = MonitoringTarget(name: "Test", host: "10.0.0.1")
        context.insert(target)

        target.recordSuccess(latency: 20.0)
        #expect(target.isOnline == true)
        #expect(target.totalChecks == 1)
        #expect(target.successfulChecks == 1)
        #expect(target.consecutiveFailures == 0)
        #expect(target.currentLatency == 20.0)
        #expect(target.averageLatency == 20.0)
        #expect(target.minLatency == 20.0)
        #expect(target.maxLatency == 20.0)
    }

    @Test("recordFailure increments consecutive failures and clears latency")
    @MainActor
    func recordFailure() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let target = MonitoringTarget(name: "Test", host: "10.0.0.1")
        context.insert(target)
        target.isOnline = true
        target.currentLatency = 10.0

        target.recordFailure()
        #expect(target.totalChecks == 1)
        #expect(target.consecutiveFailures == 1)
        #expect(target.currentLatency == nil)
        #expect(target.isOnline == true)  // still online; needs 3 consecutive failures
    }

    @Test("recordFailure sets offline after 3 consecutive failures")
    @MainActor
    func recordFailureGoesOffline() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let target = MonitoringTarget(name: "Test", host: "10.0.0.1")
        context.insert(target)
        target.isOnline = true

        target.recordFailure()
        target.recordFailure()
        target.recordFailure()
        #expect(target.isOnline == false)
        #expect(target.consecutiveFailures == 3)
    }

    @Test("recordSuccess after failure resets consecutiveFailures")
    @MainActor
    func recordSuccessResetsFailures() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let target = MonitoringTarget(name: "Test", host: "10.0.0.1")
        context.insert(target)

        target.recordFailure()
        target.recordFailure()
        target.recordSuccess(latency: 15.0)
        #expect(target.consecutiveFailures == 0)
        #expect(target.isOnline == true)
    }

    @Test("updateLatencyStats tracks min and max correctly")
    @MainActor
    func updateLatencyStatsMinMax() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let target = MonitoringTarget(name: "Test", host: "10.0.0.1")
        context.insert(target)

        target.recordSuccess(latency: 50.0)
        target.recordSuccess(latency: 10.0)
        target.recordSuccess(latency: 100.0)

        #expect(target.minLatency == 10.0)
        #expect(target.maxLatency == 100.0)
    }
}

// MARK: - PairedMac Tests

@Suite("PairedMac")
struct PairedMacTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: PairedMac.self, configurations: config)
    }

    @Test("PairedMac displayAddress shows ip:port when IP is set")
    @MainActor
    func displayAddressWithIP() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let mac = PairedMac(name: "My Mac", ipAddress: "192.168.1.50", port: 8849)
        context.insert(mac)
        #expect(mac.displayAddress == "192.168.1.50:8849")
    }

    @Test("PairedMac displayAddress falls back to hostname:port")
    @MainActor
    func displayAddressWithHostname() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let mac = PairedMac(name: "My Mac", hostname: "mac.local", port: 8849)
        context.insert(mac)
        #expect(mac.displayAddress == "mac.local:8849")
    }

    @Test("PairedMac displayAddress shows Not configured when neither is set")
    @MainActor
    func displayAddressNotConfigured() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let mac = PairedMac(name: "My Mac")
        context.insert(mac)
        #expect(mac.displayAddress == "Not configured")
    }

    @Test("PairedMac connectionStatusText when connected")
    @MainActor
    func connectionStatusTextConnected() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let mac = PairedMac(name: "My Mac", isConnected: true)
        context.insert(mac)
        #expect(mac.connectionStatusText == "Connected")
    }

    @Test("PairedMac connectionStatusText when disconnected with history")
    @MainActor
    func connectionStatusTextDisconnected() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let mac = PairedMac(name: "My Mac", lastConnected: Date(), isConnected: false)
        context.insert(mac)
        #expect(mac.connectionStatusText == "Disconnected")
    }

    @Test("PairedMac connectionStatusText when never connected")
    @MainActor
    func connectionStatusTextNeverConnected() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let mac = PairedMac(name: "My Mac")
        context.insert(mac)
        #expect(mac.connectionStatusText == "Never connected")
    }

    @Test("PairedMac init default port is 8849")
    @MainActor
    func defaultPort() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let mac = PairedMac(name: "My Mac")
        context.insert(mac)
        #expect(mac.port == 8849)
    }
}

// MARK: - SessionRecord Tests

@Suite("SessionRecord")
struct SessionRecordTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: SessionRecord.self, configurations: config)
    }

    @Test("SessionRecord init defaults to active with no paused/stopped dates")
    @MainActor
    func initDefaults() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let record = SessionRecord()
        context.insert(record)

        #expect(record.isActive == true)
        #expect(record.pausedAt == nil)
        #expect(record.stoppedAt == nil)
    }

    @Test("SessionRecord init accepts custom values")
    @MainActor
    func initCustomValues() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let start = Date().addingTimeInterval(-3600)
        let record = SessionRecord(startedAt: start, isActive: false)
        context.insert(record)

        #expect(record.startedAt == start)
        #expect(record.isActive == false)
    }
}

// MARK: - LocalDevice Tests

@Suite("LocalDevice")
struct LocalDeviceTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: LocalDevice.self, configurations: config)
    }

    @Test("displayName uses customName first")
    @MainActor
    func displayNameCustomName() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let device = LocalDevice(
            ipAddress: "192.168.1.5",
            macAddress: "AA:BB:CC:DD:EE:FF",
            hostname: "device.local",
            customName: "My Device",
            resolvedHostname: "resolved.local"
        )
        context.insert(device)
        #expect(device.displayName == "My Device")
    }

    @Test("displayName falls back to resolvedHostname when no customName")
    @MainActor
    func displayNameResolvedHostname() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let device = LocalDevice(
            ipAddress: "192.168.1.5",
            macAddress: "AA:BB:CC:DD:EE:FF",
            hostname: "device.local",
            resolvedHostname: "resolved.local"
        )
        context.insert(device)
        #expect(device.displayName == "resolved.local")
    }

    @Test("displayName falls back to hostname when no customName or resolvedHostname")
    @MainActor
    func displayNameHostname() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let device = LocalDevice(
            ipAddress: "192.168.1.5",
            macAddress: "AA:BB:CC:DD:EE:FF",
            hostname: "device.local"
        )
        context.insert(device)
        #expect(device.displayName == "device.local")
    }

    @Test("displayName falls back to ipAddress when all else nil")
    @MainActor
    func displayNameIPAddress() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let device = LocalDevice(ipAddress: "192.168.1.5", macAddress: "AA:BB:CC:DD:EE:FF")
        context.insert(device)
        #expect(device.displayName == "192.168.1.5")
    }

    @Test("formattedMacAddress is uppercased")
    @MainActor
    func formattedMacAddress() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let device = LocalDevice(ipAddress: "192.168.1.5", macAddress: "aa:bb:cc:dd:ee:ff")
        context.insert(device)
        #expect(device.formattedMacAddress == "AA:BB:CC:DD:EE:FF")
    }

    @Test("latencyText is nil when no lastLatency")
    @MainActor
    func latencyTextNil() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let device = LocalDevice(ipAddress: "192.168.1.5", macAddress: "AA:BB:CC:DD:EE:FF")
        context.insert(device)
        #expect(device.latencyText == nil)
    }

    @Test("latencyText is '<1 ms' for sub-millisecond latency")
    @MainActor
    func latencyTextSubMs() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let device = LocalDevice(
            ipAddress: "192.168.1.5",
            macAddress: "AA:BB:CC:DD:EE:FF",
            lastLatency: 0.3
        )
        context.insert(device)
        #expect(device.latencyText == "<1 ms")
    }

    @Test("latencyText formats normal latency")
    @MainActor
    func latencyTextNormal() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let device = LocalDevice(
            ipAddress: "192.168.1.5",
            macAddress: "AA:BB:CC:DD:EE:FF",
            lastLatency: 25.0
        )
        context.insert(device)
        #expect(device.latencyText == "25 ms")
    }

    @Test("updateStatus changes status and updates lastSeen")
    @MainActor
    func updateStatus() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let device = LocalDevice(ipAddress: "192.168.1.5", macAddress: "AA:BB:CC:DD:EE:FF")
        context.insert(device)

        let before = Date()
        device.updateStatus(to: .offline)
        #expect(device.status == .offline)
        #expect(device.lastSeen >= before)
    }

    @Test("updateLatency sets latency and marks device online if it was offline")
    @MainActor
    func updateLatencyBringsOnline() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let device = LocalDevice(
            ipAddress: "192.168.1.5",
            macAddress: "AA:BB:CC:DD:EE:FF",
            status: .offline
        )
        context.insert(device)

        device.updateLatency(15.0)
        #expect(device.lastLatency == 15.0)
        #expect(device.status == .online)
    }

    @Test("updateLatency does not change status when already online")
    @MainActor
    func updateLatencyKeepsOnline() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let device = LocalDevice(
            ipAddress: "192.168.1.5",
            macAddress: "AA:BB:CC:DD:EE:FF",
            status: .online
        )
        context.insert(device)

        device.updateLatency(10.0)
        #expect(device.status == .online)
        #expect(device.lastLatency == 10.0)
    }

    @Test("networkProfileID stores per-network association")
    @MainActor
    func networkProfileIDAssociation() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let profileID = UUID()
        let device = LocalDevice(
            ipAddress: "192.168.1.5",
            macAddress: "AA:BB:CC:DD:EE:FF",
            networkProfileID: profileID
        )
        context.insert(device)
        #expect(device.networkProfileID == profileID)
    }

    /// Regression test for bug_nm2_coredata_isgateway: LocalDevice was missing default values
    /// for isGateway and supportsWakeOnLan, causing SwiftData migration to crash on upgrade
    /// from stores created before these columns existed. Fix: default = false (commit ab05737).
    @Test("isGateway defaults to false (regression: bug_nm2_coredata_isgateway)")
    @MainActor
    func isGatewayDefaultsFalse() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let device = LocalDevice(ipAddress: "10.0.0.1", macAddress: "00:11:22:33:44:55")
        context.insert(device)
        #expect(device.isGateway == false, "isGateway must default to false for SwiftData migration compatibility")
    }

    @Test("supportsWakeOnLan defaults to false (regression: bug_nm2_coredata_isgateway)")
    @MainActor
    func supportsWakeOnLanDefaultsFalse() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let device = LocalDevice(ipAddress: "10.0.0.1", macAddress: "00:11:22:33:44:55")
        context.insert(device)
        #expect(device.supportsWakeOnLan == false, "supportsWakeOnLan must default to false for SwiftData migration compatibility")
    }
}

// MARK: - NetworkTarget Tests

@Suite("NetworkTarget")
struct NetworkTargetTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: NetworkTarget.self, TargetMeasurement.self, configurations: config)
    }

    @Test("NetworkTarget init stores properties correctly")
    @MainActor
    func initStoresProperties() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let target = NetworkTarget(name: "Google DNS", host: "8.8.8.8", targetProtocol: .icmp)
        context.insert(target)

        #expect(target.name == "Google DNS")
        #expect(target.host == "8.8.8.8")
        #expect(target.targetProtocol == .icmp)
        #expect(target.port == nil)
        #expect(target.isEnabled == true)
        #expect(target.checkInterval == 5.0)
        #expect(target.timeout == 3.0)
    }

    @Test("NetworkTarget init with custom port and interval")
    @MainActor
    func initWithCustomValues() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let target = NetworkTarget(
            name: "Web Server",
            host: "example.com",
            port: 443,
            targetProtocol: .https,
            checkInterval: 30.0,
            timeout: 10.0,
            isEnabled: false
        )
        context.insert(target)

        #expect(target.port == 443)
        #expect(target.targetProtocol == .https)
        #expect(target.checkInterval == 30.0)
        #expect(target.timeout == 10.0)
        #expect(target.isEnabled == false)
    }

    @Test("NetworkTarget starts with empty measurements")
    @MainActor
    func startsWithEmptyMeasurements() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let target = NetworkTarget(name: "Test", host: "10.0.0.1", targetProtocol: .icmp)
        context.insert(target)

        #expect(target.measurements.isEmpty)
    }
}

// MARK: - TargetMeasurement.calculateStatistics with data

@Suite("TargetMeasurement.calculateStatistics")
struct TargetMeasurementStatisticsTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: NetworkTarget.self, TargetMeasurement.self, configurations: config)
    }

    @Test("calculateStatistics with all reachable measurements")
    @MainActor
    func calculateStatisticsAllReachable() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let m1 = TargetMeasurement(latency: 10.0, isReachable: true)
        let m2 = TargetMeasurement(latency: 20.0, isReachable: true)
        let m3 = TargetMeasurement(latency: 30.0, isReachable: true)
        context.insert(m1)
        context.insert(m2)
        context.insert(m3)

        let stats = TargetMeasurement.calculateStatistics(from: [m1, m2, m3])
        #expect(stats.averageLatency == 20.0)
        #expect(stats.minLatency == 10.0)
        #expect(stats.maxLatency == 30.0)
        #expect(stats.uptimePercentage == 100.0)
    }

    @Test("calculateStatistics with mixed reachability")
    @MainActor
    func calculateStatisticsMixedReachability() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let m1 = TargetMeasurement(latency: 15.0, isReachable: true)
        let m2 = TargetMeasurement(latency: nil, isReachable: false)
        let m3 = TargetMeasurement(latency: nil, isReachable: false)
        let m4 = TargetMeasurement(latency: 25.0, isReachable: true)
        context.insert(m1)
        context.insert(m2)
        context.insert(m3)
        context.insert(m4)

        let stats = TargetMeasurement.calculateStatistics(from: [m1, m2, m3, m4])
        #expect(stats.averageLatency == 20.0)   // (15 + 25) / 2
        #expect(stats.uptimePercentage == 50.0)  // 2 of 4 reachable
    }

    @Test("calculateStatistics with no latency values returns nil latency stats")
    @MainActor
    func calculateStatisticsNoLatency() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let m1 = TargetMeasurement(latency: nil, isReachable: false)
        let m2 = TargetMeasurement(latency: nil, isReachable: false)
        context.insert(m1)
        context.insert(m2)

        let stats = TargetMeasurement.calculateStatistics(from: [m1, m2])
        #expect(stats.averageLatency == nil)
        #expect(stats.minLatency == nil)
        #expect(stats.maxLatency == nil)
        #expect(stats.uptimePercentage == 0.0)
    }
}

// MARK: - ToolResult Tests

@Suite("ToolResult")
struct ToolResultTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: ToolResult.self, configurations: config)
    }

    @Test("ToolResult formattedDuration shows ms for sub-second durations")
    @MainActor
    func formattedDurationMs() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let result = ToolResult(toolType: .ping, target: "8.8.8.8", duration: 0.5, success: true, summary: "OK")
        context.insert(result)
        #expect(result.formattedDuration == "500 ms")
    }

    @Test("ToolResult formattedDuration shows seconds for 1+ second durations")
    @MainActor
    func formattedDurationSeconds() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let result = ToolResult(toolType: .ping, target: "8.8.8.8", duration: 2.5, success: true, summary: "OK")
        context.insert(result)
        #expect(result.formattedDuration == "2.50 s")
    }

    @Test("ToolResult init stores properties correctly")
    @MainActor
    func initStoresProperties() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let result = ToolResult(
            toolType: .traceroute,
            target: "google.com",
            duration: 1.0,
            success: false,
            summary: "Timed out",
            details: "3 hops",
            errorMessage: "timeout"
        )
        context.insert(result)
        #expect(result.toolType == .traceroute)
        #expect(result.target == "google.com")
        #expect(result.success == false)
        #expect(result.summary == "Timed out")
        #expect(result.details == "3 hops")
        #expect(result.errorMessage == "timeout")
    }
}

// MARK: - SpeedTestResult Tests

@Suite("SpeedTestResult")
struct SpeedTestResultTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: SpeedTestResult.self, configurations: config)
    }

    @Test("SpeedTestResult downloadSpeedText formats Mbps correctly")
    @MainActor
    func downloadSpeedTextMbps() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let result = SpeedTestResult(downloadSpeed: 150.5, uploadSpeed: 50.0, latency: 10.0)
        context.insert(result)
        #expect(result.downloadSpeedText == "150 Mbps")
    }

    @Test("SpeedTestResult downloadSpeedText formats Gbps for 1000+ Mbps")
    @MainActor
    func downloadSpeedTextGbps() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let result = SpeedTestResult(downloadSpeed: 1500.0, uploadSpeed: 500.0, latency: 5.0)
        context.insert(result)
        #expect(result.downloadSpeedText == "1.50 Gbps")
    }

    @Test("SpeedTestResult latencyText formats as integer ms")
    @MainActor
    func latencyText() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let result = SpeedTestResult(downloadSpeed: 100.0, uploadSpeed: 50.0, latency: 12.0)
        context.insert(result)
        #expect(result.latencyText == "12 ms")
    }

    @Test("SpeedTestResult uploadSpeedText formats correctly")
    @MainActor
    func uploadSpeedText() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let result = SpeedTestResult(downloadSpeed: 100.0, uploadSpeed: 25.3, latency: 10.0)
        context.insert(result)
        #expect(result.uploadSpeedText == "25.3 Mbps")
    }
}
