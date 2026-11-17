import Testing
@testable import NetMonitor_macOS

@Suite("Port Forwards tool (#400)")
struct PortForwardsToolRegistrationTests {
    @Test("Port Forwards is listed under Discovery with its label and icon")
    func listedUnderDiscovery() {
        #expect(ToolCategory.discovery.tools.contains(.portForwards))
        #expect(NetworkTool.portForwards.rawValue == "Port Forwards")
        #expect(NetworkTool.portForwards.description == "Router UPnP port forwards")
        #expect(ToolCategory.allCases.filter { $0.tools.contains(.portForwards) } == [.discovery])
    }
}
