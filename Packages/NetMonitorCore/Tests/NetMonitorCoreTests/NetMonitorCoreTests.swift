import Testing
@testable import NetMonitorCore

@Test func versionIsSet() async throws {
    #expect(!netMonitorCoreVersion.isEmpty)
}
