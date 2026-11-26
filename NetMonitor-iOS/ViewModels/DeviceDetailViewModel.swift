import Foundation
import NetMonitorCore
import SwiftData
import NetworkScanKit

@MainActor
@Observable
final class DeviceDetailViewModel {
    /// The device's primary row (#594): its name, notes, type and rules. For a device of one row,
    /// that row.
    var device: LocalDevice?
    /// The device as lists show it: every member, the current one first (``members``).
    private(set) var projection: DeviceProjection?
    /// The row detail was opened on from the scan's list, whose address it may probe.
    private var openedMember: LocalDevice?
    var isLoading: Bool = false
    var error: String?
    var isScanning: Bool = false
    var isDiscovering: Bool = false
    /// What the last "wake every interface" said (#594).
    private(set) var wakeResult: String?
    /// Whether the detail shows a maker, model or type the on-device model suggested (#449).
    private(set) var isShowingSuggestion = false
    /// The type the model suggested while the device's type is unknown; written only on accept.
    private(set) var suggestedType: DeviceType?

    private let macLookupService: any MACVendorLookupServiceProtocol
    private let nameResolver: any DeviceNameResolverProtocol
    private let portScanner: any PortScannerServiceProtocol
    private let bonjourService: any BonjourDiscoveryServiceProtocol
    private let deviceDiscoveryService: any DeviceDiscoveryServiceProtocol
    private let suggester: DeviceSuggester
    private let wakeService: any WakeOnLANServiceProtocol
    /// The reconciled scans, for "seen by the previous scan" in the row match (#596).
    private let scanHistory: ScanHistory
    private var modelContext: ModelContext?
    /// The running suggestion. Cancelled on reload and when the view model goes away, so it
    /// never writes to a row that has been replaced or deleted.
    nonisolated(unsafe) private(set) var suggestionTask: Task<Void, Never>?
    /// Fingerprint of the evidence the running or last suggestion pass was started with.
    private var suggestionFingerprint: String?
    /// Which address DNS, the port scan and service discovery may probe (``probeAddress``).
    private enum NameLookup {
        /// The row's own address: detail was opened on it from the scan's list.
        case savedAddress
        /// Opened by ID (#584): wherever the latest completed scan confirms a member's real MAC,
        /// checked again at every probe, since a newer scan can move the device.
        case confirmedByScan
    }

    private var nameLookup = NameLookup.savedAddress
    private let maxServiceResolves = 80
    private let maxServiceResolveConcurrency = 8

    init(
        macLookupService: any MACVendorLookupServiceProtocol = MACVendorLookupService(),
        nameResolver: any DeviceNameResolverProtocol = DeviceNameResolver(),
        portScanner: any PortScannerServiceProtocol = PortScannerService(),
        bonjourService: any BonjourDiscoveryServiceProtocol = BonjourDiscoveryService(),
        deviceDiscoveryService: any DeviceDiscoveryServiceProtocol = DeviceDiscoveryService.shared,
        suggester: DeviceSuggester = DeviceSuggester(service: UITestFakeDeviceFeed.insightService, store: DeviceSuggestionStore()),
        wakeService: any WakeOnLANServiceProtocol = WakeOnLANService(),
        scanHistory: ScanHistory = ScanHistory()
    ) {
        self.macLookupService = macLookupService
        self.nameResolver = nameResolver
        self.portScanner = portScanner
        self.bonjourService = bonjourService
        self.deviceDiscoveryService = deviceDiscoveryService
        self.suggester = suggester
        self.wakeService = wakeService
        self.scanHistory = scanHistory
    }

    deinit {
        suggestionTask?.cancel()
    }

    /// The ports a device-page scan probes: common service ports plus every port a device-type
    /// rule reads, such as a printer's 9100, so a described rule's target can probe one (#572).
    private let commonPorts = Set([
        21, 22, 23, 25, 53, 80, 110, 143, 443, 445, 548, 631,
        993, 995, 3306, 3389, 5432, 5900, 8080, 8443
    ]).union(DeviceTypeInferenceService.rulePorts).sorted()

    /// Loads the saved row for the device at `ipAddress` on `networkID` (the network the list
    /// showed it on), creating one if none matches.
    /// `macAddress` is the MAC the list showed, used when the live scan doesn't have the device
    /// (a cached result), so a device whose IP changed still matches its row.
    func loadDevice(ipAddress: String, networkID: UUID? = nil, macAddress: String? = nil, context: ModelContext) {
        suggestionTask?.cancel()
        suggestionTask = nil
        suggestionFingerprint = nil
        modelContext = context
        nameLookup = .savedAddress
        let live = Self.liveScan(deviceDiscoveryService)
        let scanned = live.first { $0.ipAddress == ipAddress && (networkID == nil || $0.networkProfileID == networkID) }
        let network = networkID ?? scanned?.networkProfileID
        let row = Self.savedRow(
            ipAddress: ipAddress,
            scanned: scanned,
            macAddress: scanned?.macAddress ?? macAddress,
            networkID: network,
            scan: live.filter { $0.networkProfileID == network },
            scanTime: deviceDiscoveryService.lastScanDate ?? Date(),
            previousScan: deviceDiscoveryService.lastScanDate.flatMap { scanHistory.previousReconciled(beforeScan: $0, for: network) },
            in: context
        )
        openedMember = row
        // The row is one interface; detail shows its device (#594).
        showDevice(of: row)
        // The scan knows more than a fresh row: merge its maker, model and friendly name by
        // rank (ADR-022), and fill the MAC-prefix maker, MAC and hostname where the row has
        // none (#426), into the interface the scan saw. The header shows `maker`.
        defer { startSuggestion() }
        guard let scanned else {
            return
        }
        Self.adopt(scanned, into: row)
    }

    /// Merges what a scan knows into a saved row, as detail does when it opens: maker, model and
    /// friendly name by rank (ADR-022), and the MAC-prefix maker, MAC and hostname where the row
    /// has none (#426). Described rules save rows the same way (#571).
    static func adopt(_ scanned: DiscoveredDevice, into device: LocalDevice) {
        device.mergeIdentity(scanned.identity)
        if device.vendor?.isEmpty ?? true, let vendor = scanned.vendor, !vendor.isEmpty {
            device.vendor = vendor
        }
        if device.macAddress.isEmpty, let mac = scanned.macAddress, !mac.isEmpty {
            device.macAddress = mac
        }
        if device.hostname?.isEmpty ?? true, let name = scanned.hostname, !name.isEmpty {
            device.hostname = name
        }
    }

    /// The latest scan, as device detail matches rows against it. Under the UI-test fixture
    /// the dashboard lists fake devices; detail sees them too. The label sheet's duplicate-MAC
    /// check uses the same list (#456).
    static func liveScan(_ service: any DeviceDiscoveryServiceProtocol = DeviceDiscoveryService.shared) -> [DiscoveredDevice] {
        service.discoveredDevices + (UITestFakeDeviceFeed.suggestsIdentity ? UITestFakeDeviceFeed().devices : [])
    }

    // MARK: - Identity suggestion (#449)

    /// Asks the on-device model about the loaded row without blocking the load. Called again
    /// when enrichment, a port scan or service discovery changes the evidence; a pass already
    /// started on the same evidence keeps running.
    private func startSuggestion() {
        refreshSuggestionState()
        guard let device else {
            return
        }
        let fingerprint = DeviceEvidence(device: device).fingerprint
        guard fingerprint != suggestionFingerprint else {
            return
        }
        suggestionFingerprint = fingerprint
        suggestionTask?.cancel()
        suggestionTask = Task { [weak self, suggester] in
            await suggester.suggest(for: [device])
            guard !Task.isCancelled, let self else {
                return
            }
            self.saveContext()
            self.refreshSuggestionState()
        }
    }

    func acceptSuggestion() {
        guard let device else {
            return
        }
        suggester.accept(device)
        saveContext()
        refreshSuggestionState()
    }

    func dismissSuggestion() {
        guard let device else {
            return
        }
        suggester.dismiss(device)
        saveContext()
        refreshSuggestionState()
    }

    private func refreshSuggestionState() {
        guard let device else {
            isShowingSuggestion = false
            suggestedType = nil
            return
        }
        isShowingSuggestion = suggester.isShowingSuggestion(device)
        suggestedType = suggester.suggestedType(for: device)
    }

    private func saveContext() {
        try? modelContext?.save()
    }

    /// Enrich device data with the MAC-prefix maker and resolved hostname, on the probed member
    /// (else the current one): both describe one interface.
    func enrichDevice(bonjourServices _: [BonjourService]) async {
        guard let device = probedMember?.row ?? current else { return }
        isLoading = true
        defer { isLoading = false }

        // Extract Sendable values before async work
        let macAddress = device.macAddress
        let ipAddress = probedMember.flatMap { $0.row === device ? $0.address : nil }

        // Look up the MAC-prefix maker (`vendor`, ADR-022); skip without a MAC
        if device.vendor?.isEmpty ?? true, !macAddress.isEmpty {
            let vendor: String? = await withTaskGroup(of: String?.self) { group in
                group.addTask {
                    await self.macLookupService.lookup(macAddress: macAddress)
                }
                group.addTask {
                    try? await Task.sleep(for: .seconds(5))
                    return nil
                }
                let result = await group.next()
                group.cancelAll()
                return result.flatMap { $0 }
            }
            if !Task.isCancelled {
                device.vendor = vendor
            }
        }

        guard !Task.isCancelled else { return }

        // Resolve hostname with timeout to prevent hanging on DNS
        if device.resolvedHostname == nil, let ipAddress {
            let hostname: String? = await withTaskGroup(of: String?.self) { group in
                group.addTask {
                    await self.nameResolver.resolve(ipAddress: ipAddress)
                }
                group.addTask {
                    try? await Task.sleep(for: .seconds(5))
                    return nil
                }
                let result = await group.next()
                group.cancelAll()
                return result.flatMap { $0 }
            }
            // Only if the device is still at that address after the wait.
            if !Task.isCancelled, probeAddress == ipAddress {
                device.resolvedHostname = hostname
            }
        }
        guard !Task.isCancelled else { return }
        startSuggestion()
    }

    /// Discover Bonjour services at ``probeAddress``; they are saved on the member probed.
    func discoverServices() async {
        guard let (device, deviceIP) = probedMember else { return }
        isDiscovering = true
        defer { isDiscovering = false }

        // Phase 1: Collect services from stream (up to 10 seconds)
        var collectedServices: [BonjourService] = []
        let stream = bonjourService.discoveryStream(serviceType: nil)

        let timeoutTask = Task {
            try? await Task.sleep(for: .seconds(10))
            bonjourService.stopDiscovery()
        }

        for await service in stream {
            collectedServices.append(service)
        }
        timeoutTask.cancel()

        // Phase 2: Resolve and match services (bounded concurrency)
        var discoveredServiceNames: [String] = []
        let servicesToResolve = Array(uniqueServices(from: collectedServices).prefix(maxServiceResolves))

        await withTaskGroup(of: String?.self) { group in
            var pending = 0
            var iterator = servicesToResolve.makeIterator()

            while pending < maxServiceResolveConcurrency, let service = iterator.next() {
                pending += 1
                group.addTask { [deviceIP] in
                    guard let resolved = await self.bonjourService.resolveService(service),
                          await Self.serviceMatchesDeviceIP(resolved, deviceIP: deviceIP) else {
                        return nil
                    }
                    return "\(service.name) (\(service.type))"
                }
            }

            while pending > 0 {
                guard let name = await group.next() else { break }
                pending -= 1

                if let name, !discoveredServiceNames.contains(name) {
                    discoveredServiceNames.append(name)
                }

                if let nextService = iterator.next() {
                    pending += 1
                    group.addTask { [deviceIP] in
                        guard let resolved = await self.bonjourService.resolveService(nextService),
                              await Self.serviceMatchesDeviceIP(resolved, deviceIP: deviceIP) else {
                            return nil
                        }
                        return "\(nextService.name) (\(nextService.type))"
                    }
                }
            }
        }

        guard probeAddress == deviceIP, probedMember?.row === device else { return }
        device.discoveredServices = discoveredServiceNames
        startSuggestion()
    }

    private func uniqueServices(from services: [BonjourService]) -> [BonjourService] {
        var seen: Set<String> = []
        var unique: [BonjourService] = []
        unique.reserveCapacity(services.count)

        for service in services {
            let key = "\(service.name)|\(service.type)|\(service.domain)"
            if seen.insert(key).inserted {
                unique.append(service)
            }
        }
        return unique
    }

    nonisolated private static func serviceMatchesDeviceIP(_ resolved: BonjourService, deviceIP: String) async -> Bool {
        var candidates: Set<String> = []

        for address in resolved.addresses where isIPv4Address(address) {
            candidates.insert(address)
        }

        if let hostName = resolved.hostName {
            let normalizedHost = normalizeHostName(hostName)
            if isIPv4Address(normalizedHost) {
                candidates.insert(normalizedHost)
            } else if !normalizedHost.isEmpty {
                let resolvedIPs = await resolveIPv4Addresses(for: normalizedHost)
                for ip in resolvedIPs {
                    candidates.insert(ip)
                }
            }
        }

        return candidates.contains(deviceIP)
    }

    nonisolated private static func normalizeHostName(_ host: String) -> String {
        host.split(separator: "%", maxSplits: 1).first.map(String.init) ?? host
    }

    nonisolated private static func isIPv4Address(_ value: String) -> Bool {
        ServiceUtilities.isIPv4Address(value)
    }

    nonisolated private static func resolveIPv4Addresses(for host: String) async -> [String] {
        await withCheckedContinuation { continuation in
            let cfHost = CFHostCreateWithName(nil, host as CFString).takeRetainedValue()
            var streamError = CFStreamError()

            guard CFHostStartInfoResolution(cfHost, .addresses, &streamError),
                  let addresses = CFHostGetAddressing(cfHost, nil)?.takeUnretainedValue() as? [Data] else {
                continuation.resume(returning: [])
                return
            }

            var resolved: Set<String> = []
            resolved.reserveCapacity(addresses.count)

            for addressData in addresses {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                addressData.withUnsafeBytes { ptr in
                    guard let sockaddr = ptr.bindMemory(to: sockaddr.self).baseAddress else { return }
                    getnameinfo(
                        sockaddr,
                        socklen_t(addressData.count),
                        &hostname,
                        socklen_t(hostname.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    )
                }

                let length = strnlen(hostname, hostname.count)
                let bytes = hostname.prefix(length).map { UInt8(bitPattern: $0) }
                guard let ip = String(bytes: bytes, encoding: .utf8) else { continue }

                if isIPv4Address(ip) {
                    resolved.insert(ip)
                }
            }

            continuation.resume(returning: Array(resolved))
        }
    }
}

// MARK: - Opening by ID (#584)

extension DeviceDetailViewModel {
    /// Loads the saved device `id` names, for links that carry `LocalDevice.id` (Ask citations,
    /// rule targets, Timeline events; #584) or a device's own ID from a list (a group's, #594).
    /// Never matches by IP: when DHCP gave the device's address to another device, the link still
    /// opens this one. The latest scan's identity is merged into a member only from the one device
    /// that answered the latest scan with that member's real MAC, and DNS is asked for a name only
    /// at the address that device answered from. A row that no longer exists loads nothing.
    func loadDevice(id: UUID, context: ModelContext) {
        suggestionTask?.cancel()
        suggestionTask = nil
        suggestionFingerprint = nil
        modelContext = context
        openedMember = nil
        showDevice(of: Self.row(named: id, in: context))
        // No address is probed unless the latest completed scan confirms the device is there:
        // DHCP may have given the saved address to another device.
        nameLookup = .confirmedByScan
        defer { startSuggestion() }
        for member in members {
            if let scanned = confirmedSighting(of: member) {
                Self.adopt(scanned, into: member)
            }
        }
    }

    /// The row with `id`, else a member of the group with that ID.
    static func row(named id: UUID, in context: ModelContext) -> LocalDevice? {
        var byRow = FetchDescriptor<LocalDevice>(predicate: #Predicate { $0.id == id })
        byRow.fetchLimit = 1
        if let row = (try? context.fetch(byRow))?.first {
            return row
        }
        let group: UUID? = id
        var byGroup = FetchDescriptor<LocalDevice>(predicate: #Predicate { $0.deviceGroupID == group })
        byGroup.fetchLimit = 1
        return (try? context.fetch(byGroup))?.first
    }

    /// The address DNS, the port scan and service discovery may probe for the loaded device, and
    /// write what they find onto that member's row: where it was opened from the list, or, opened
    /// by ID, where the latest scan confirmed a member's real MAC (the current member first). Nil
    /// when that can't be established (DHCP may have given the saved address to another device);
    /// the views disable those actions then.
    var probeAddress: String? {
        probedMember?.address
    }

    /// The member ``probeAddress`` belongs to; probes write to its row (#594: ports and services
    /// stay on the interface they were measured on).
    var probedMember: (row: LocalDevice, address: String)? {
        guard device != nil else { return nil }
        switch nameLookup {
        case .savedAddress:
            guard let row = openedMember ?? current else { return nil }
            return (row, row.ipAddress)
        case .confirmedByScan:
            for member in members {
                if let sighting = confirmedSighting(of: member) {
                    return (member, sighting.ipAddress)
                }
            }
            return nil
        }
    }

    /// The one device that answered the latest completed scan (`completedScanDevices`, never a
    /// running or stopped scan's progress list, which hides which entries only the ARP cache lists),
    /// on the row's network, with the row's real MAC. None while a scan runs, for a placeholder
    /// MAC, or for a cached sighting.
    private func confirmedSighting(of device: LocalDevice) -> DiscoveredDevice? {
        guard !deviceDiscoveryService.isScanning, let mac = DeviceMatcher.normalizedMAC(device.macAddress) else { return nil }
        let completed = deviceDiscoveryService.completedScanDevices
            + (UITestFakeDeviceFeed.suggestsIdentity ? UITestFakeDeviceFeed().devices : [])
        let confirmed = completed.filter { scanned in
            !scanned.isCached && scanned.networkProfileID == device.networkProfileID
                && DeviceMatcher.normalizedMAC(scanned.macAddress) == mac
        }
        return confirmed.count == 1 ? confirmed[0] : nil
    }

    /// Scan common ports on the device, at ``probeAddress``.
    func scanPorts() async {
        guard let (device, address) = probedMember else { return }
        isScanning = true
        defer { isScanning = false }

        var openPorts: [Int] = []

        for await result in await portScanner.scan(host: address, ports: commonPorts, timeout: 1.5) where result.state == .open {
            openPorts.append(result.port)
        }

        // A newer scan may have moved the device meanwhile: those ports are another device's.
        guard probeAddress == address, probedMember?.row === device else { return }
        device.openPorts = openPorts.sorted()
        startSuggestion()
    }
}

// MARK: - Saved row

extension DeviceDetailViewModel {
    /// The row for a device, found by the device match (#461: MAC, else IP, with private-MAC
    /// rotation) among the rows of the device's network (#463), so two networks that use the
    /// same addresses keep separate rows. `scan` is every device the latest scan saw on that
    /// network; the match needs them all so it never hands one device's row to another, such
    /// as a newcomer at the old address of a device that moved. `scanTime` is when that scan
    /// finished: the match judges "seen within grace" against it, and `previousScan` (when the scan
    /// before it was reconciled, from `ScanHistory`) counts a row it saw as recent. A row saved before rows had a
    /// network (every detail row before #463) is adopted by the first network it's opened on.
    static func savedRow(
        ipAddress: String,
        scanned: DiscoveredDevice?,
        macAddress: String? = nil,
        networkID: UUID?,
        scan: [DiscoveredDevice],
        scanTime: Date = Date(),
        previousScan: Date? = nil,
        in context: ModelContext
    ) -> LocalDevice {
        let rows = ((try? context.fetch(FetchDescriptor<LocalDevice>())) ?? []).sorted { $0.lastSeen > $1.lastSeen }
        let observation = DeviceMatchCandidate(ipAddress: ipAddress, macAddress: macAddress ?? scanned?.macAddress, name: scanned?.matchName)
        // The scan as the reconciler sees it: one observation per real MAC, at the address it
        // answered from, so a cached old address opens the same row and doesn't move it back.
        let canonical = PresenceMatch.onePerMAC(scan)
        var observed = canonical.map { DeviceMatchCandidate(ipAddress: $0.ipAddress, macAddress: $0.macAddress, name: $0.matchName) }
        var address = ipAddress
        let position: Int
        if let mac = DeviceMatcher.normalizedMAC(observation.macAddress),
           let index = canonical.firstIndex(where: { DeviceMatcher.normalizedMAC($0.macAddress) == mac }) {
            position = index
            address = canonical[index].ipAddress
        } else if let index = observed.firstIndex(of: observation) {
            position = index
        } else {
            observed.append(observation)
            position = observed.count - 1
        }
        var pools = [rows.filter { $0.networkProfileID == networkID }]
        if networkID != nil {
            pools.append(rows.filter { $0.networkProfileID == nil })
        }
        for (poolIndex, pool) in pools.enumerated() {
            // The rule scans save rows by (#582, `PresenceMatch`): the other devices in the scan
            // claim their own rows first, and an address alone never opens a row whose name differs.
            let known = pool.map {
                PresenceMatch.Known(DeviceMatchCandidate(ipAddress: $0.ipAddress, macAddress: $0.macAddress, name: $0.matchName),
                    lastSeen: $0.lastSeen)
            }
            // "Seen within grace" is judged at the scan's time, as the reconciler judged it, not
            // when detail opens.
            // The previous scan is the network's; rows saved without a network (the second pool)
            // judge recency by the grace window only, as the reconciler's held-for-detail check does.
            let isNetworksOwnPool = networkID != nil && poolIndex == 0
            let assignment = PresenceMatch.assign(
                known: known, observed: observed, now: scanTime, window: DeviceGracePolicy().interval,
                previousScan: isNetworksOwnPool ? previousScan : nil
            )
            guard let index = assignment[position] else { continue }
            let row = pool[index]
            if let mac = DeviceMatcher.normalizedMAC(observation.macAddress), DeviceMatcher.normalizedMAC(row.macAddress) != mac {
                row.macAddress = mac
            }
            row.ipAddress = address
            row.networkProfileID = networkID
            return row
        }
        let row = LocalDevice(ipAddress: ipAddress, macAddress: macAddress ?? scanned?.macAddress ?? "", networkProfileID: networkID)
        context.insert(row)
        return row
    }
}

// MARK: - Showing and changing a device's interfaces (#594)

extension DeviceDetailViewModel {
    /// Shows the device `row` is an interface of: its primary as ``device``, and every member,
    /// fetched in this context (a group lives on one network).
    func showDevice(of row: LocalDevice?) {
        guard let row else {
            device = nil
            projection = nil
            return
        }
        var rows = [row]
        if let group = row.deviceGroupID, let modelContext {
            let groupID: UUID? = group
            let network = row.networkProfileID
            let descriptor = FetchDescriptor<LocalDevice>(predicate: #Predicate { $0.deviceGroupID == groupID && $0.networkProfileID == network })
            rows = (try? modelContext.fetch(descriptor)) ?? rows
        }
        let shown = DeviceGroups.project(rows).first { $0.contains(row.id) }
        projection = shown
        device = shown?.primary ?? row
    }

    /// "Remove this interface": deletes the member's row through `DeviceGroupWriter`. The device
    /// stays open on the members that remain (a group left with one becomes that row). Edits
    /// waiting in the context are saved first, since a failed removal rolls the context back.
    func removeInterface(_ member: LocalDevice) {
        guard let modelContext, let projection, projection.isGroup,
              let survivor = projection.members.first(where: { $0.id != member.id })?.id
        else { return }
        suggestionTask?.cancel()
        saveContext()
        if openedMember === member {
            openedMember = nil
            nameLookup = .confirmedByScan
        }
        do {
            try DeviceGroupWriter(context: modelContext).removeInterface(member.id)
        } catch {
            self.error = "The interface couldn't be removed. Try again."
            return
        }
        showDevice(of: Self.row(named: survivor, in: modelContext))
        startSuggestion()
    }

    /// Wake on LAN to every member's real MAC (#594): any interface may be the one that wakes it.
    /// Returns how many packets were sent.
    @discardableResult
    func wakeAllInterfaces() async -> Int {
        guard let projection else { return 0 }
        var sent = 0
        for mac in projection.realMACs where await wakeService.wake(macAddress: mac, broadcastAddress: "255.255.255.255", port: 9) {
            sent += 1
        }
        wakeResult = sent == projection.realMACs.count
            ? "Wake packet sent to \(sent) \(sent == 1 ? "interface" : "interfaces")"
            : "Wake packet sent to \(sent) of \(projection.realMACs.count) interfaces"
        return sent
    }
}
