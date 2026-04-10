import XCTest
import Testing
@testable import NetMonitor_iOS
@testable import NetMonitorCore

@MainActor
final class SubnetCalculatorToolViewModelTests: XCTestCase {

    func testValidCIDR_24_producesCorrectResults() {
        let vm = SubnetCalculatorToolViewModel()
        vm.cidrInput = "192.168.1.0/24"
        vm.calculate()

        let info = vm.subnetInfo
        XCTAssertNotNil(info)
        XCTAssertEqual(info?.networkAddress, "192.168.1.0")
        XCTAssertEqual(info?.broadcastAddress, "192.168.1.255")
        XCTAssertEqual(info?.subnetMask, "255.255.255.0")
        XCTAssertEqual(info?.firstHost, "192.168.1.1")
        XCTAssertEqual(info?.lastHost, "192.168.1.254")
        XCTAssertEqual(info?.usableHosts, 254)
        XCTAssertEqual(info?.prefixLength, 24)
        XCTAssertNil(vm.errorMessage)
    }

    func testValidCIDR_8_producesCorrectResults() {
        let vm = SubnetCalculatorToolViewModel()
        vm.cidrInput = "10.0.0.0/8"
        vm.calculate()

        let info = vm.subnetInfo
        XCTAssertNotNil(info)
        XCTAssertEqual(info?.networkAddress, "10.0.0.0")
        XCTAssertEqual(info?.broadcastAddress, "10.255.255.255")
        XCTAssertEqual(info?.subnetMask, "255.0.0.0")
        XCTAssertEqual(info?.usableHosts, 16777214)
        XCTAssertNil(vm.errorMessage)
    }

    func testValidCIDR_16_producesCorrectResults() {
        let vm = SubnetCalculatorToolViewModel()
        vm.cidrInput = "172.16.0.0/16"
        vm.calculate()

        let info = vm.subnetInfo
        XCTAssertNotNil(info)
        XCTAssertEqual(info?.networkAddress, "172.16.0.0")
        XCTAssertEqual(info?.broadcastAddress, "172.16.255.255")
        XCTAssertEqual(info?.subnetMask, "255.255.0.0")
        XCTAssertEqual(info?.usableHosts, 65534)
        XCTAssertNil(vm.errorMessage)
    }

    func testValidCIDR_32_singleHost() {
        let vm = SubnetCalculatorToolViewModel()
        vm.cidrInput = "192.168.1.1/32"
        vm.calculate()

        let info = vm.subnetInfo
        XCTAssertNotNil(info)
        XCTAssertEqual(info?.networkAddress, "192.168.1.1")
        XCTAssertEqual(info?.broadcastAddress, "192.168.1.1")
        XCTAssertEqual(info?.usableHosts, 1)
        XCTAssertNil(vm.errorMessage)
    }

    func testValidCIDR_31_pointToPoint() {
        let vm = SubnetCalculatorToolViewModel()
        vm.cidrInput = "192.168.1.0/31"
        vm.calculate()

        let info = vm.subnetInfo
        XCTAssertNotNil(info)
        XCTAssertEqual(info?.usableHosts, 2)
        XCTAssertNil(vm.errorMessage)
    }

    func testValidCIDR_0_allAddresses() {
        let vm = SubnetCalculatorToolViewModel()
        vm.cidrInput = "0.0.0.0/0"
        vm.calculate()

        XCTAssertNotNil(vm.subnetInfo)
        XCTAssertNil(vm.errorMessage)
        XCTAssertEqual(vm.subnetInfo?.subnetMask, "0.0.0.0")
    }

    func testInvalidCIDR_badPrefix_setsError() {
        let vm = SubnetCalculatorToolViewModel()
        vm.cidrInput = "192.168.1.0/99"
        vm.calculate()

        XCTAssertNil(vm.subnetInfo)
        XCTAssertNotNil(vm.errorMessage)
    }

    func testInvalidCIDR_noSlash_setsError() {
        let vm = SubnetCalculatorToolViewModel()
        vm.cidrInput = "192.168.1.0"
        vm.calculate()

        XCTAssertNil(vm.subnetInfo)
        XCTAssertNotNil(vm.errorMessage)
    }

    func testInvalidCIDR_badIP_setsError() {
        let vm = SubnetCalculatorToolViewModel()
        vm.cidrInput = "999.999.999.999/24"
        vm.calculate()

        XCTAssertNil(vm.subnetInfo)
        XCTAssertNotNil(vm.errorMessage)
    }

    func testInvalidCIDR_emptyInput_doesNothing() {
        let vm = SubnetCalculatorToolViewModel()
        vm.cidrInput = "   "
        vm.calculate()

        XCTAssertNil(vm.subnetInfo)
        XCTAssertNil(vm.errorMessage)
    }

    func testSelectExample_calculatesAndPopulates() {
        let vm = SubnetCalculatorToolViewModel()
        vm.selectExample("10.0.0.0/8")

        XCTAssertEqual(vm.cidrInput, "10.0.0.0/8")
        XCTAssertNotNil(vm.subnetInfo)
        XCTAssertNil(vm.errorMessage)
    }

    func testClear_resetsAllState() {
        let vm = SubnetCalculatorToolViewModel()
        vm.cidrInput = "192.168.1.0/24"
        vm.calculate()
        XCTAssertNotNil(vm.subnetInfo)

        vm.clear()

        XCTAssertEqual(vm.cidrInput, "")
        XCTAssertNil(vm.subnetInfo)
        XCTAssertNil(vm.errorMessage)
    }

    func testCanCalculate_emptyInput_returnsFalse() {
        let vm = SubnetCalculatorToolViewModel()
        XCTAssertFalse(vm.canCalculate)
    }

    func testCanCalculate_withInput_returnsTrue() {
        let vm = SubnetCalculatorToolViewModel()
        vm.cidrInput = "10.0.0.0/8"
        XCTAssertTrue(vm.canCalculate)
    }

    func testHasResult_afterCalculation_returnsTrue() {
        let vm = SubnetCalculatorToolViewModel()
        vm.cidrInput = "192.168.1.0/24"
        vm.calculate()
        XCTAssertTrue(vm.hasResult)
    }

    func testHasResult_afterError_returnsTrue() {
        let vm = SubnetCalculatorToolViewModel()
        vm.cidrInput = "bad/input"
        vm.calculate()
        XCTAssertTrue(vm.hasResult)
    }

    func testNonNetworkAddress_stillParsed() {
        // Input IP is a host address, not network address — should still parse
        let vm = SubnetCalculatorToolViewModel()
        vm.cidrInput = "192.168.1.100/24"
        vm.calculate()

        // Network address should be masked correctly
        XCTAssertNotNil(vm.subnetInfo)
        XCTAssertEqual(vm.subnetInfo?.networkAddress, "192.168.1.0")
    }

    func testExamplesNotEmpty() {
        let vm = SubnetCalculatorToolViewModel()
        XCTAssertFalse(vm.examples.isEmpty)
    }
}

// MARK: - Swift Testing Suite

@MainActor
struct SubnetCalculatorToolViewModelEdgeCaseTests {

    @Test func invalidCIDRFormatSetsError() {
        let vm = SubnetCalculatorToolViewModel()
        vm.cidrInput = "not-a-cidr"
        vm.calculate()
        #expect(vm.subnetInfo == nil)
        #expect(vm.errorMessage != nil)
    }

    @Test func slash32SubnetHasOneUsableHost() {
        let vm = SubnetCalculatorToolViewModel()
        vm.cidrInput = "10.0.0.1/32"
        vm.calculate()
        #expect(vm.subnetInfo != nil)
        #expect(vm.subnetInfo?.usableHosts == 1)
        // For /32, network == broadcast == host
        #expect(vm.subnetInfo?.networkAddress == vm.subnetInfo?.broadcastAddress)
    }

    @Test func slash32FirstAndLastHostMatchNetworkAddress() {
        let vm = SubnetCalculatorToolViewModel()
        vm.cidrInput = "192.168.50.1/32"
        vm.calculate()
        #expect(vm.subnetInfo?.firstHost == "192.168.50.1")
        #expect(vm.subnetInfo?.lastHost == "192.168.50.1")
    }

    @Test func prefixAbove32SetsError() {
        let vm = SubnetCalculatorToolViewModel()
        vm.cidrInput = "192.168.1.0/33"
        vm.calculate()
        #expect(vm.subnetInfo == nil)
        #expect(vm.errorMessage != nil)
    }

    @Test func negativePrefixSetsError() {
        let vm = SubnetCalculatorToolViewModel()
        vm.cidrInput = "192.168.1.0/-1"
        vm.calculate()
        #expect(vm.subnetInfo == nil)
        #expect(vm.errorMessage != nil)
    }

    @Test func clearResetsAllFields() {
        let vm = SubnetCalculatorToolViewModel()
        vm.cidrInput = "10.0.0.0/8"
        vm.calculate()
        #expect(vm.subnetInfo != nil)
        vm.clear()
        #expect(vm.cidrInput == "")
        #expect(vm.subnetInfo == nil)
        #expect(vm.errorMessage == nil)
    }
}
