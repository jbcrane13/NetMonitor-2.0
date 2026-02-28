import Testing
@testable import NetMonitorCore

@Test func versionIsSet() throws {
    #expect(!netMonitorCoreVersion.isEmpty)
}
