import Foundation
import SwiftData
import NetMonitorCore
import os

@MainActor
@Observable
final class DeviceDiscoveryCoordinator {

    private(set) var isScanning: Bool = false
    private(set) var discoveredDevices: [LocalDevice] = []
    private(set) var lastScanTime: Date?
    private(set) var scanProgress: Double = 0.0
    private(set) var networkProfile: NetworkProfile?

    private let modelContext: ModelContext
    private let arpScanner: ARPScannerService
    let bonjourScanner: BonjourDiscoveryService
    private let nameResolver: DeviceNameResolver
    private let macVendorService: MACVendorLookupService
    let networkProfileManager: NetworkProfileManager

    private var scanTask: Task<Void, Never>?

    init(
        modelContext: ModelContext,
        arpScanner: ARPScannerService,
        bonjourScanner: BonjourDiscoveryService,
        nameResolver: DeviceNameResolver = DeviceNameResolver(),
        macVendorService: MACVendorLookupService = MACVendorLookupService(),
        networkProfileManager: NetworkProfileManager
    ) {
        self.modelContext = modelContext
        self.arpScanner = arpScanner
        self.bonjourScanner = bonjourScanner
        self.nameResolver = nameResolver
        self.macVendorService = macVendorService
        self.networkProfileManager = networkProfileManager
        loadPersistedDevices(for: effectiveProfileID())
    }

    var selectedInterface: String? {
        networkProfile?.interfaceName
    }

    func startScan() {
        guard !isScanning else { return }
        isScanning = true
        scanProgress = 0.0

        let profileID = effectiveProfileID()
        loadPersistedDevices(for: profileID)

        scanTask = Task {
            do {
                try Task.checkCancellation()

                scanProgress = 0.1
                let arpDevices = try await arpScanner.scanNetwork(interface: selectedInterface)
                try Task.checkCancellation()
                scanProgress = 0.6

                var bonjourDevices: [LocalDiscoveredDevice] = []
                let bonjourStream = await bonjourScanner.discoveryStream(serviceType: nil)
                let bonjourTask = Task {
                    for await service in bonjourStream {
                        if let host = service.hostName {
                            bonjourDevices.append(LocalDiscoveredDevice(
                                ipAddress: service.addresses.first ?? host,
                                macAddress: "",
                                hostname: host
                            ))
                        }
                    }
                }
                try? await Task.sleep(for: .seconds(5))
                bonjourTask.cancel()
                await bonjourScanner.stopDiscovery()

                try Task.checkCancellation()
                scanProgress = 0.9

                let allDiscovered = mergeDiscoveryResults(arp: arpDevices, bonjour: bonjourDevices)
                mergeDiscoveredDevices(allDiscovered, profileID: profileID)

                try Task.checkCancellation()
                scanProgress = 0.95

                await resolveDeviceNames(profileID: profileID)
                await resolveDeviceVendors(profileID: profileID)
                markOfflineDevices(currentIPs: Set(allDiscovered.map(\.ipAddress)), profileID: profileID)

                scanProgress = 1.0
                lastScanTime = Date()

                if let profileID {
                    let gatewayIP = networkProfile?.gatewayIP
                        ?? networkProfileManager.profiles.first(where: { $0.id == profileID })?.gatewayIP
                    let gatewayReachable = gatewayIP.map { gateway in
                        allDiscovered.contains(where: { $0.ipAddress == gateway })
                    }
                    networkProfileManager.updateProfileScanInfo(
                        id: profileID,
                        lastScanned: Date(),
                        deviceCount: discoveredDevices.count,
                        gatewayReachable: gatewayReachable
                    )
                }
            } catch is CancellationError {
            } catch {
                Logger.discovery.error("Scan error: \(error, privacy: .public)")
            }
            isScanning = false
        }
    }

    func scanNetwork(_ profile: NetworkProfile) {
        networkProfile = profile
        _ = networkProfileManager.switchProfile(id: profile.id)
        loadPersistedDevices(for: profile.id)
        startScan()
    }

    func stopScan() {
        scanTask?.cancel()
        scanTask = nil
        Task {
            await arpScanner.stopScan()
            await bonjourScanner.stopDiscovery()
        }
        isScanning = false
    }

    func mergeDiscoveredDevices(_ devices: [LocalDiscoveredDevice], profileID: UUID?) {
        for discovered in devices {
            let predicate: Predicate<LocalDevice>
            if !discovered.macAddress.isEmpty {
                let mac = discovered.macAddress
                if let profileID {
                    predicate = #Predicate<LocalDevice> { $0.networkProfileID == profileID && $0.macAddress == mac }
                } else {
                    predicate = #Predicate<LocalDevice> { $0.networkProfileID == nil && $0.macAddress == mac }
                }
            } else {
                let ip = discovered.ipAddress
                if let profileID {
                    predicate = #Predicate<LocalDevice> { $0.networkProfileID == profileID && $0.ipAddress == ip }
                } else {
                    predicate = #Predicate<LocalDevice> { $0.networkProfileID == nil && $0.ipAddress == ip }
                }
            }

            let descriptor = FetchDescriptor<LocalDevice>(predicate: predicate)
            let existing = try? modelContext.fetch(descriptor).first

            if let existing {
                existing.ipAddress = discovered.ipAddress
                if let hostname = discovered.hostname, !hostname.isEmpty {
                    existing.hostname = hostname
                }
                existing.lastSeen = Date()
                existing.status = .online
            } else {
                let newDevice = LocalDevice(
                    ipAddress: discovered.ipAddress,
                    macAddress: discovered.macAddress,
                    hostname: discovered.hostname,
                    vendor: nil,
                    deviceType: .unknown,
                    networkProfileID: profileID
                )
                modelContext.insert(newDevice)
            }
        }

        do { try modelContext.save() } catch {
            Logger.discovery.error("Failed to save discovered devices: \(error)")
        }
        loadPersistedDevices(for: profileID)
    }

    func markOfflineDevices(currentIPs: Set<String>, profileID: UUID?) {
        for device in discoveredDevices {
            if device.networkProfileID != profileID {
                continue
            }
            if !currentIPs.contains(device.ipAddress) {
                device.status = .offline
            }
        }
        do { try modelContext.save() } catch {
            Logger.discovery.error("Failed to save offline status: \(error)")
        }
        loadPersistedDevices(for: profileID)
    }

    private func resolveDeviceNames(profileID: UUID?) async {
        let devices = fetchDevices(for: profileID).filter { $0.hostname == nil || $0.hostname == "" }
        guard !devices.isEmpty else { return }

        await withTaskGroup(of: (UUID, String?).self) { group in
            var activeCount = 0
            var iter = devices.makeIterator()

            while activeCount < 10, let device = iter.next() {
                let id = device.id
                let ip = device.ipAddress
                group.addTask { (id, await self.nameResolver.resolveName(for: ip)) }
                activeCount += 1
            }

            for await (id, name) in group {
                if let name, let device = devices.first(where: { $0.id == id }) {
                    device.hostname = name
                }
                if let next = iter.next() {
                    let id = next.id; let ip = next.ipAddress
                    group.addTask { (id, await self.nameResolver.resolveName(for: ip)) }
                }
            }
        }

        do { try modelContext.save() } catch {
            Logger.discovery.error("Failed to save device names: \(error)")
        }
    }

    private func resolveDeviceVendors(profileID: UUID?) async {
        let devices = fetchDevices(for: profileID).filter {
            !$0.macAddress.isEmpty && ($0.vendor == nil || $0.vendor == "")
        }
        guard !devices.isEmpty else { return }

        await withTaskGroup(of: (UUID, String?).self) { group in
            var activeCount = 0
            var iter = devices.makeIterator()

            while activeCount < 5, let device = iter.next() {
                let id = device.id; let mac = device.macAddress
                group.addTask { (id, await self.macVendorService.lookupVendorEnhanced(macAddress: mac)) }
                activeCount += 1
            }

            for await (id, vendor) in group {
                if let vendor, let device = devices.first(where: { $0.id == id }) {
                    device.vendor = vendor
                }
                if let next = iter.next() {
                    let id = next.id; let mac = next.macAddress
                    group.addTask { (id, await self.macVendorService.lookupVendorEnhanced(macAddress: mac)) }
                }
            }
        }

        do { try modelContext.save() } catch {
            Logger.discovery.error("Failed to save device vendors: \(error)")
        }
    }

    private func loadPersistedDevices(for profileID: UUID?) {
        let devices = fetchDevices(for: profileID)
        discoveredDevices = devices.sorted { $0.lastSeen > $1.lastSeen }
    }

    private func fetchDevices(for profileID: UUID?) -> [LocalDevice] {
        let descriptor: FetchDescriptor<LocalDevice>
        if let profileID {
            let predicate = #Predicate<LocalDevice> { $0.networkProfileID == profileID }
            descriptor = FetchDescriptor<LocalDevice>(predicate: predicate)
        } else {
            let predicate = #Predicate<LocalDevice> { $0.networkProfileID == nil }
            descriptor = FetchDescriptor<LocalDevice>(predicate: predicate)
        }

        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func mergeDiscoveryResults(
        arp: [LocalDiscoveredDevice],
        bonjour: [LocalDiscoveredDevice]
    ) -> [LocalDiscoveredDevice] {
        var merged: [String: LocalDiscoveredDevice] = [:]
        for d in arp { merged[d.ipAddress] = d }
        for d in bonjour {
            if let existing = merged[d.ipAddress] {
                if existing.hostname == nil, d.hostname != nil {
                    merged[d.ipAddress] = LocalDiscoveredDevice(
                        ipAddress: existing.ipAddress,
                        macAddress: existing.macAddress,
                        hostname: d.hostname
                    )
                }
            } else {
                merged[d.ipAddress] = d
            }
        }
        return Array(merged.values)
    }

    private func effectiveProfileID() -> UUID? {
        networkProfile?.id ?? networkProfileManager.activeProfile?.id
    }
}
