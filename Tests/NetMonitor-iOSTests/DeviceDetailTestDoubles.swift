import Foundation
@testable import NetMonitor_iOS
import NetMonitorCore

// Test doubles for `DeviceDetailViewModelTests`, kept apart so that file stays under the length limit.

final class MockMACVendorLookupService: MACVendorLookupServiceProtocol, @unchecked Sendable {
    private let vendor: String?
    private(set) var lookupCallCount = 0

    init(vendor: String?) {
        self.vendor = vendor
    }

    func lookup(macAddress: String) async -> String? {
        lookupCallCount += 1
        return vendor
    }
}

final class MockDeviceNameResolver: DeviceNameResolverProtocol, @unchecked Sendable {
    private let hostname: String?
    private(set) var resolveCallCount = 0
    private(set) var resolvedAddresses: [String] = []

    init(hostname: String?) {
        self.hostname = hostname
    }

    func resolve(ipAddress: String) async -> String? {
        resolveCallCount += 1
        resolvedAddresses.append(ipAddress)
        return hostname
    }
}
