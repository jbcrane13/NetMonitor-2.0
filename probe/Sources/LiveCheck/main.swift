import Foundation
import NetMonitorCore
// Real services once: the network ids the apps compare, and a silent address's timing. Not published.
@MainActor func run() async {
  let current = NetworkProfileManager.currentProfile()
  let manager = NetworkProfileManager()
  print("currentProfile id == savedLocal id:", current?.id == NetworkProfileManager.savedLocalProfile()?.id, "nil?", current == nil)
  print("currentProfile id == manager.localProfile id:", current?.id == manager.localProfile?.id)
  print("connectedLocalProfile == localProfile:", manager.connectedLocalProfile?.id == manager.localProfile?.id)
  guard let active = NetworkProfileManager.detectActiveProfiles().first(where: { $0.interfaceName == "en0" }) ?? NetworkProfileManager.detectActiveProfiles().first else { print("no interface"); return }
  let net = active.network
  let silent = NetworkUtilities.uint32ToIPv4(net.broadcastAddress &- 3)
  let snapshot = AskSnapshot(devices: [AskDevice(id: UUID(), displayName: "Silent Test", deviceType: .unknown, maker: nil, ipAddress: silent,
    status: .offline, lastSeen: Date(), lastLatency: nil, latencyHistory: [])], events: [], networkProfileID: nil, lastScan: nil, now: Date())
  let toolbox = AskToolbox(snapshot: snapshot, live: AskLiveTools(pinger: PingService(), currentNetwork: { active }, connection: { .init(type: .wifi, gatewayIP: NetworkUtilities.detectRoutedGateway()) }, isScanning: { false }))
  let clock = ContinuousClock(); let t0 = clock.now
  let out = await toolbox.pingDevice("dev-a")
  print("silent ping:", out.replacingOccurrences(of: silent, with: "<addr>"), "took", clock.now - t0)
  let gw = AskToolbox(snapshot: snapshot, live: AskLiveTools(pinger: PingService(), currentNetwork: { active }, connection: { .init(type: .wifi, gatewayIP: NetworkUtilities.detectRoutedGateway()) }, isScanning: { false }))
  let t1 = clock.now
  let status = await gw.networkStatus()
  print("status took", clock.now - t1, "shape:", status.replacingOccurrences(of: #"\d+\.\d+\.\d+\.\d+"#, with: "<ip>", options: .regularExpression))
}
await run()
