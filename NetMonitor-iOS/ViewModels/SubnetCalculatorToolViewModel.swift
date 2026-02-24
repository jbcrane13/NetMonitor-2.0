import Foundation
import NetMonitorCore

/// ViewModel for the Subnet Calculator tool
@MainActor
@Observable
final class SubnetCalculatorToolViewModel {
    // MARK: - Input

    var cidrInput: String = ""

    // MARK: - State

    var subnetInfo: SubnetInfo?
    var errorMessage: String?

    // MARK: - Examples

    let examples: [(label: String, cidr: String)] = [
        ("192.168.1.0/24", "192.168.1.0/24"),
        ("10.0.0.0/8", "10.0.0.0/8"),
        ("172.16.0.0/12", "172.16.0.0/12"),
        ("192.168.0.0/16", "192.168.0.0/16")
    ]

    // MARK: - Computed

    var canCalculate: Bool {
        !cidrInput.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var hasResult: Bool {
        subnetInfo != nil || errorMessage != nil
    }

    // MARK: - Actions

    func calculate() {
        let input = cidrInput.trimmingCharacters(in: .whitespaces)
        guard !input.isEmpty else { return }

        if let info = parseAndCalculate(cidr: input) {
            subnetInfo = info
            errorMessage = nil
        } else {
            subnetInfo = nil
            errorMessage = "Invalid CIDR notation. Expected format: 192.168.1.0/24 (prefix 0–32)"
        }
    }

    func selectExample(_ cidr: String) {
        cidrInput = cidr
        calculate()
    }

    func clear() {
        cidrInput = ""
        subnetInfo = nil
        errorMessage = nil
    }

    // MARK: - Subnet Math

    private func parseAndCalculate(cidr: String) -> SubnetInfo? {
        let parts = cidr.split(separator: "/")
        guard parts.count == 2,
              let prefix = Int(parts[1]),
              prefix >= 0, prefix <= 32 else { return nil }

        let ipString = String(parts[0])
        guard let ipUInt32 = NetworkUtilities.ipv4ToUInt32(ipString) else { return nil }

        // Safe left-shift: avoid UB when prefix == 0
        let netmask: UInt32 = prefix == 0 ? 0 : (UInt32(0xFFFFFFFF) << (32 - prefix))
        let networkAddr = ipUInt32 & netmask
        let broadcastAddr = networkAddr | ~netmask

        let firstHost: UInt32
        let lastHost: UInt32
        let usable: Int

        switch prefix {
        case 32:
            firstHost = networkAddr
            lastHost = networkAddr
            usable = 1
        case 31:
            firstHost = networkAddr
            lastHost = broadcastAddr
            usable = 2
        default:
            firstHost = networkAddr &+ 1
            lastHost = broadcastAddr &- 1
            usable = max(0, Int(broadcastAddr) - Int(networkAddr) - 1)
        }

        return SubnetInfo(
            cidr: "\(NetworkUtilities.uint32ToIPv4(networkAddr))/\(prefix)",
            networkAddress: NetworkUtilities.uint32ToIPv4(networkAddr),
            broadcastAddress: NetworkUtilities.uint32ToIPv4(broadcastAddr),
            subnetMask: NetworkUtilities.uint32ToIPv4(netmask),
            firstHost: NetworkUtilities.uint32ToIPv4(firstHost),
            lastHost: NetworkUtilities.uint32ToIPv4(lastHost),
            usableHosts: usable,
            prefixLength: prefix
        )
    }
}
