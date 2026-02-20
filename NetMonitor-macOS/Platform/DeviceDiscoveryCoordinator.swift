import Foundation
import SwiftData
import NetMonitorCore
import os

/// Coordinates device discovery using ARP scanning + Bonjour discovery,
/// and persists results into LocalDevice SwiftData models.
@MainActor
@Observable
final class DeviceDiscoveryCoordinator {

    private(set) var isScanning: Bool = false
    private(set) var discoveredDevices: [LocalDevice] = []
    private(set) var lastScanTime: Date?
    private(set) var scanProgress: Double = 0.0

    private let modelContext: ModelContext
    private let arpScanner: ARPScannerService
    let bonjourScanner: BonjourDiscoveryService
    private let nameResolver: DeviceNameResolver
    private let macVendorService: MACVendorLookupService

    private var scanTask: Task<Void, Never>?

    init(
        modelContext: ModelContext,
        arpScanner: ARPScannerService,
        bonjourScanner: BonjourDiscoveryService,
        nameResolver: DeviceNameResolver = DeviceNameResolver(),
        macVendorService: MACVendorLookupService = MACVendorLookupService()
    ) {
        self.modelContext = modelContext
        self.arpScanner = arpScanner
        self.bonjourScanner = bonjourScanner
        self.nameResolver = nameResolver
        self.macVendorService = macVendorService
        loadPersistedDevices()
    }

    // MARK: - Public API

    /// The interface name to scan, or nil for auto-detect.
    var selectedInterface: String?

    func startScan() {
        guard !isScanning else { return }
        isScanning = true
        scanProgress = 0.0

        scanTask = Task {
            do {
                try Task.checkCancellation()

                // Phase 1: ARP Scan
                scanProgress = 0.1
                let arpDevices = try await arpScanner.scanNetwork(interface: selectedInterface)
                try Task.checkCancellation()
                scanProgress = 0.6

                // Phase 2: Bonjour — collect a window of discoveries
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
                // Give Bonjour 5 seconds
                try? await Task.sleep(for: .seconds(5))
                bonjourTask.cancel()
                await bonjourScanner.stopDiscovery()

                try Task.checkCancellation()
                scanProgress = 0.9

                // Merge results
                let allDiscovered = mergeDiscoveryResults(arp: arpDevices, bonjour: bonjourDevices)
                mergeDiscoveredDevices(allDiscovered)

                try Task.checkCancellation()
                scanProgress = 0.95

                await resolveDeviceNames()
                await resolveDeviceVendors()
                markOfflineDevices(currentIPs: Set(allDiscovered.map(\.ipAddress)))

                scanProgress = 1.0
                lastScanTime = Date()
            } catch is CancellationError {
                // Cancelled gracefully
            } catch {
                Logger.discovery.error("Scan error: \(error, privacy: .public)")
            }
            isScanning = false
        }
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

    // MARK: - Private

    func mergeDiscoveredDevices(_ devices: [LocalDiscoveredDevice]) {
        for discovered in devices {
            let predicate: Predicate<LocalDevice>
            if !discovered.macAddress.isEmpty {
                let mac = discovered.macAddress
                predicate = #Predicate<LocalDevice> { $0.macAddress == mac }
            } else {
                let ip = discovered.ipAddress
                predicate = #Predicate<LocalDevice> { $0.ipAddress == ip }
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
                    deviceType: .unknown
                )
                modelContext.insert(newDevice)
            }
        }

        do { try modelContext.save() } catch {
            Logger.discovery.error("Failed to save discovered devices: \(error)")
        }
        loadPersistedDevices()
    }

    func markOfflineDevices(currentIPs: Set<String>) {
        for device in discoveredDevices {
            if !currentIPs.contains(device.ipAddress) {
                device.status = .offline
            }
        }
        do { try modelContext.save() } catch {
            Logger.discovery.error("Failed to save offline status: \(error)")
        }
    }

    private func resolveDeviceNames() async {
        let predicate = #Predicate<LocalDevice> { $0.hostname == nil || $0.hostname == "" }
        let descriptor = FetchDescriptor<LocalDevice>(predicate: predicate)
        guard let devices = try? modelContext.fetch(descriptor) else { return }

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

    private func resolveDeviceVendors() async {
        let predicate = #Predicate<LocalDevice> { !$0.macAddress.isEmpty && ($0.vendor == nil || $0.vendor == "") }
        let descriptor = FetchDescriptor<LocalDevice>(predicate: predicate)
        guard let devices = try? modelContext.fetch(descriptor) else { return }

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

    private func loadPersistedDevices() {
        let descriptor = FetchDescriptor<LocalDevice>(
            sortBy: [SortDescriptor(\.lastSeen, order: .reverse)]
        )
        discoveredDevices = (try? modelContext.fetch(descriptor)) ?? []
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
}
