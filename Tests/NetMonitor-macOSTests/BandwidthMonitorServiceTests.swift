import Testing
import Foundation
@testable import NetMonitor_macOS

// MARK: - BandwidthMonitorService Static Formatter Tests
//
// BandwidthMonitorService polls live network interfaces and cannot be unit-tested
// for its sampling logic without dependency injection of the interface reader.
// The static formatters (formatBytes / formatMbps) are pure functions and are
// fully testable here.

struct BandwidthMonitorFormatBytesTests {

    // MARK: Byte-level values

    @Test func zeroBytesFormatsAsBytes() {
        #expect(BandwidthMonitorService.formatBytes(0) == "0 B")
    }

    @Test func oneByteFFormatsAsBytes() {
        #expect(BandwidthMonitorService.formatBytes(1) == "1 B")
    }

    @Test func oneThousandTwentyThreeBytesFormatsAsBytes() {
        #expect(BandwidthMonitorService.formatBytes(1023) == "1023 B")
    }

    // MARK: Kilobyte boundary

    @Test func exactlyOneKilobyteFormatsAsKB() {
        // 1024 bytes = 1 KB
        #expect(BandwidthMonitorService.formatBytes(1024) == "1 KB")
    }

    @Test func oneAndHalfKilobytesFormatsAsKB() {
        // 1536 bytes = 1.5 KB → "2 KB" (%.0f rounds)
        let result = BandwidthMonitorService.formatBytes(1536)
        #expect(result == "2 KB")
    }

    @Test func tenKilobytesFormatsAsKB() {
        #expect(BandwidthMonitorService.formatBytes(10 * 1024) == "10 KB")
    }

    @Test func justBelowOneMegabyteFormatsAsKB() {
        // 1_048_575 bytes is just under 1 MB
        let result = BandwidthMonitorService.formatBytes(1_048_575)
        #expect(result.hasSuffix("KB"))
    }

    // MARK: Megabyte boundary

    @Test func exactlyOneMegabyteFormatsAsMB() {
        // 1_048_576 bytes = 1.0 MB
        #expect(BandwidthMonitorService.formatBytes(1_048_576) == "1.0 MB")
    }

    @Test func fiveMegabytesFormatsAsMB() {
        #expect(BandwidthMonitorService.formatBytes(5 * 1_048_576) == "5.0 MB")
    }

    @Test func tenPointFiveMegabytesFormatsAsMB() {
        // 10.5 * 1_048_576 = 11_010_048 bytes
        let result = BandwidthMonitorService.formatBytes(11_010_048)
        #expect(result == "10.5 MB")
    }

    @Test func justBelowOneGigabyteFormatsAsMB() {
        // 1_073_741_823 bytes is just under 1 GB
        let result = BandwidthMonitorService.formatBytes(1_073_741_823)
        #expect(result.hasSuffix("MB"))
    }

    // MARK: Gigabyte boundary

    @Test func exactlyOneGigabyteFormatsAsGB() {
        // 1_073_741_824 bytes = 1.00 GB
        #expect(BandwidthMonitorService.formatBytes(1_073_741_824) == "1.00 GB")
    }

    @Test func twoGigabytesFormatsAsGB() {
        #expect(BandwidthMonitorService.formatBytes(2 * 1_073_741_824) == "2.00 GB")
    }

    @Test func tenGigabytesFormatsAsGB() {
        #expect(BandwidthMonitorService.formatBytes(10 * 1_073_741_824) == "10.00 GB")
    }
}

// MARK: - BandwidthMonitorService Static Formatter Tests – formatMbps

struct BandwidthMonitorFormatMbpsTests {

    // MARK: Sub-Mbps (Kbps) range

    @Test func zeroMbpsFormatsAsKbps() {
        // 0 Mbps → 0 Kbps
        #expect(BandwidthMonitorService.formatMbps(0) == "0 Kbps")
    }

    @Test func pointFiveMbpsFormatsAsKbps() {
        // 0.5 * 1000 = 500 Kbps
        #expect(BandwidthMonitorService.formatMbps(0.5) == "500 Kbps")
    }

    @Test func pointNineNineMbpsFormatsAsKbps() {
        // 0.999 * 1000 ≈ 999 Kbps
        #expect(BandwidthMonitorService.formatMbps(0.999) == "999 Kbps")
    }

    // MARK: Mbps range

    @Test func exactlyOneMbpsFormatsAsMbps() {
        #expect(BandwidthMonitorService.formatMbps(1.0) == "1.0 Mbps")
    }

    @Test func tenMbpsFormatsAsMbps() {
        #expect(BandwidthMonitorService.formatMbps(10.0) == "10.0 Mbps")
    }

    @Test func hundredMbpsFormatsAsMbps() {
        #expect(BandwidthMonitorService.formatMbps(100.0) == "100.0 Mbps")
    }

    @Test func justBelowOneGbpsFormatsAsMbps() {
        // 999.9 Mbps should still format as Mbps
        let result = BandwidthMonitorService.formatMbps(999.9)
        #expect(result.hasSuffix("Mbps"))
    }

    // MARK: Gbps range

    @Test func exactlyOneGbpsFormatsAsGbps() {
        // 1000 Mbps = 1.00 Gbps
        #expect(BandwidthMonitorService.formatMbps(1000.0) == "1.00 Gbps")
    }

    @Test func tenGbpsFormatsAsGbps() {
        #expect(BandwidthMonitorService.formatMbps(10_000.0) == "10.00 Gbps")
    }

    @Test func onePointFiveGbpsFormatsAsGbps() {
        // 1500 Mbps = 1.50 Gbps
        #expect(BandwidthMonitorService.formatMbps(1500.0) == "1.50 Gbps")
    }
}

// MARK: - BandwidthMonitorService Initial State Tests

@MainActor
struct BandwidthMonitorInitialStateTests {

    @Test func initialDownloadMbpsIsZero() {
        let service = BandwidthMonitorService(interfaceName: "en0")
        #expect(service.downloadMbps == 0)
    }

    @Test func initialUploadMbpsIsZero() {
        let service = BandwidthMonitorService(interfaceName: "en0")
        #expect(service.uploadMbps == 0)
    }

    @Test func initialDownloadHistoryIsEmpty() {
        let service = BandwidthMonitorService(interfaceName: "en0")
        #expect(service.downloadHistory.isEmpty)
    }

    @Test func initialUploadHistoryIsEmpty() {
        let service = BandwidthMonitorService(interfaceName: "en0")
        #expect(service.uploadHistory.isEmpty)
    }

    @Test func initialSessionDownBytesIsZero() {
        let service = BandwidthMonitorService(interfaceName: "en0")
        #expect(service.sessionDownBytes == 0)
    }

    @Test func initialSessionUpBytesIsZero() {
        let service = BandwidthMonitorService(interfaceName: "en0")
        #expect(service.sessionUpBytes == 0)
    }

    @Test func interfaceNameStoredCorrectly() {
        let service = BandwidthMonitorService(interfaceName: "en1")
        #expect(service.interfaceName == "en1")
    }

    @Test func arbitraryInterfaceNameStoredCorrectly() {
        let service = BandwidthMonitorService(interfaceName: "utun0")
        #expect(service.interfaceName == "utun0")
    }
}
