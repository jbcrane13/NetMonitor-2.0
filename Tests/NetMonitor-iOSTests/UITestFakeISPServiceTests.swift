import Foundation
import Testing
import NetMonitorCore
@testable import NetMonitor_iOS

#if DEBUG
@Suite("UITestFakeISPService")
@MainActor
struct UITestFakeISPServiceTests {
    @Test func theFixtureUsesDocumentationValuesAndIsOffOutsideUITests() async {
        let service = UITestFakeISPService()
        #expect(service.ispInfo == nil)
        await service.fetchPublicIP(forceRefresh: false)
        #expect(service.ispInfo?.ispName == "Example Test ISP")
        #expect(service.ispInfo?.publicIP == "203.0.113.7")
        #expect(!UITestFakeISPService.isEnabled, "not enabled without --uitesting and UITEST_FAKE_ISP=1")
    }
}
#endif
