import Foundation
import Network
import NetworkScanKit

@MainActor
@Observable
public final class WakeOnLANService: WakeOnLANServiceProtocol {
    public private(set) var lastResult: WakeOnLANResult?
    public private(set) var isSending: Bool = false
    public private(set) var lastError: String?

    public init() {}

    public func wake(macAddress: String, broadcastAddress: String = "255.255.255.255", port: UInt16 = 9) async -> Bool {
        isSending = true
        lastError = nil

        defer { isSending = false }

        guard let packet = createMagicPacket(macAddress: macAddress) else {
            lastError = "Invalid MAC address format"
            lastResult = WakeOnLANResult(macAddress: macAddress, success: false, error: lastError)
            return false
        }

        let success = await sendPacket(packet, to: broadcastAddress, port: port)

        lastResult = WakeOnLANResult(
            macAddress: macAddress,
            success: success,
            error: success ? nil : "Failed to send packet"
        )

        return success
    }

    func createMagicPacket(macAddress: String) -> Data? {
        let cleanedMAC = macAddress
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .uppercased()

        guard cleanedMAC.count == 12,
              let macBytes = hexStringToBytes(cleanedMAC) else {
            return nil
        }

        var packet = Data(repeating: 0xFF, count: 6)

        for _ in 0..<16 {
            packet.append(contentsOf: macBytes)
        }

        return packet
    }

    func hexStringToBytes(_ hex: String) -> [UInt8]? {
        guard hex.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        var index = hex.startIndex

        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else {
                return nil
            }
            bytes.append(byte)
            index = nextIndex
        }

        return bytes
    }

    private func sendPacket(_ packet: Data, to address: String, port: UInt16) async -> Bool {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(address),
            port: NWEndpoint.Port(rawValue: port)!
        )

        let parameters = NWParameters.udp
        parameters.allowLocalEndpointReuse = true

        let connection = NWConnection(to: endpoint, using: parameters)
        defer {
            connection.stateUpdateHandler = nil
            connection.cancel()
        }

        let conn = connection

        return await withCheckedContinuation { continuation in
            let resumed = ResumeState()

            let timeoutTask = Task {
                try? await Task.sleep(for: .seconds(5))
                guard await resumed.tryResume() else { return }
                conn.cancel()
                continuation.resume(returning: false)
            }

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    conn.send(content: packet, completion: .contentProcessed { error in
                        Task {
                            guard await resumed.tryResume() else { return }
                            timeoutTask.cancel()
                            conn.cancel()
                            continuation.resume(returning: error == nil)
                        }
                    })
                case .failed, .cancelled:
                    Task {
                        guard await resumed.tryResume() else { return }
                        timeoutTask.cancel()
                        continuation.resume(returning: false)
                    }
                default:
                    break
                }
            }

            conn.start(queue: .global())
        }
    }
}
