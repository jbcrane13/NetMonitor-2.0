import Foundation

// MARK: - DeviceTypeInferenceService

/// A stateless service that infers `DeviceType` from network scan data
/// using a priority-based heuristic chain.
public struct DeviceTypeInferenceService: Sendable {

    public init() {}

    /// Infers the device type for a given `LocalDevice` based on network scan data.
    ///
    /// Only updates if the current `deviceType` is `.unknown` — never overrides
    /// user-set or previously inferred types.
    ///
    /// Priority chain (first match wins):
    /// 1. Gateway flag
    /// 2. Hostname patterns
    /// 3. Bonjour services
    /// 4. Open ports
    /// 5. Vendor / manufacturer
    /// 6. Falls back to current `device.deviceType`
    public func inferDeviceType(for device: LocalDevice) -> DeviceType {
        guard device.deviceType == .unknown else {
            return device.deviceType
        }

        // 1. Gateway check
        if device.isGateway {
            return .router
        }

        // 2. Hostname-based inference
        if let result = inferFromHostnames(device) {
            return result
        }

        // 3. Bonjour services
        if let result = inferFromServices(device) {
            return result
        }

        // 4. Open ports
        if let result = inferFromPorts(device) {
            return result
        }

        // 5. Vendor / manufacturer
        if let result = inferFromVendor(device) {
            return result
        }

        // 6. No match — preserve current type
        return device.deviceType
    }

    // MARK: - Hostname Inference

    private func inferFromHostnames(_ device: LocalDevice) -> DeviceType? {
        let names = [device.hostname, device.resolvedHostname, device.customName]
            .compactMap { $0?.lowercased() }

        for name in names {
            if name.contains("iphone") { return .phone }
            if name.contains("ipad") { return .tablet }
            if name.contains("android") { return .phone }
            if name.contains("macbook") || name.contains("laptop") { return .laptop }
            if name.contains("imac") || name.contains("mac-pro")
                || name.contains("mac-mini") || name.contains("mac-studio") { return .computer }
            if name.contains("appletv") || name.contains("apple-tv") { return .tv }
            if name.contains("homepod") { return .speaker }
            if name.contains("nas") || name.contains("synology")
                || name.contains("qnap") || name.contains("drobo") { return .storage }
            if name.contains("printer") || name.contains("canon")
                || name.contains("epson") || name.contains("brother") { return .printer }
            if name.contains("camera") || name.contains("cam") { return .camera }
            if name.contains("playstation") || name.contains("xbox")
                || name.contains("nintendo") || name.contains("switch") { return .gaming }
        }

        return nil
    }

    // MARK: - Bonjour Service Inference

    private func inferFromServices(_ device: LocalDevice) -> DeviceType? {
        guard let services = device.discoveredServices else { return nil }

        let serviceSet = Set(services)

        if serviceSet.contains("_printer._tcp") || serviceSet.contains("_ipp._tcp")
            || serviceSet.contains("_pdl-datastream._tcp") {
            return .printer
        }
        if serviceSet.contains("_raop._tcp") {
            return .speaker
        }
        if serviceSet.contains("_airplay._tcp") {
            return .tv
        }
        if (serviceSet.contains("_smb._tcp") || serviceSet.contains("_afpovertcp._tcp"))
            && serviceSet.contains("_timemachine._tcp") {
            return .storage
        }

        return nil
    }

    // MARK: - Port-Based Inference

    private func inferFromPorts(_ device: LocalDevice) -> DeviceType? {
        guard let ports = device.openPorts else { return nil }

        let portSet = Set(ports)

        if portSet.contains(80) && portSet.contains(443) && portSet.contains(53) {
            return .router
        }
        if portSet.contains(631) || portSet.contains(9100) {
            return .printer
        }
        if portSet.contains(8008) || portSet.contains(8009) {
            return .tv
        }
        if portSet.contains(32400) {
            return .storage
        }

        return nil
    }

    // MARK: - Vendor / Manufacturer Inference

    private func inferFromVendor(_ device: LocalDevice) -> DeviceType? {
        let vendors = [device.vendor, device.manufacturer]
            .compactMap { $0?.lowercased() }

        guard !vendors.isEmpty else { return nil }

        for v in vendors {
            // Speakers
            if v.contains("sonos") || v.contains("bose") || v.contains("harman") {
                return .speaker
            }
            // TVs
            if v.contains("roku") || v.contains("lg electronics") {
                return .tv
            }
            // Samsung — only TV if it has Tizen/smart-TV ports
            if v.contains("samsung") {
                let ports = Set(device.openPorts ?? [])
                if ports.contains(8001) || ports.contains(8002) {
                    return .tv
                }
                // Otherwise fall through — don't return unknown yet
            }
            // Storage
            if v.contains("synology") || v.contains("qnap")
                || v.contains("western digital") || v.contains("drobo") {
                return .storage
            }
            // IoT
            if v.contains("raspberry pi") || v.contains("espressif") || v.contains("tuya") {
                return .iot
            }
            // Cameras
            if v.contains("ring") || v.contains("nest") || v.contains("wyze")
                || v.contains("hikvision") || v.contains("dahua") {
                return .camera
            }
            // Printers
            if v.contains("canon") || v.contains("epson") || v.contains("brother")
                || v.contains("hp inc") || v.contains("hewlett packard") {
                return .printer
            }
            // Gaming
            if v.contains("nintendo") || v.contains("sony interactive") {
                return .gaming
            }
            if v.contains("microsoft") {
                let ports = Set(device.openPorts ?? [])
                if ports.contains(3074) {
                    return .gaming
                }
            }
            // Apple (generic fallback)
            if v.contains("apple") {
                return .computer
            }
            // Computers
            if v.contains("intel") || v.contains("dell") || v.contains("lenovo")
                || v.contains("asus") || v.contains("hewlett-packard") {
                return .computer
            }
        }

        return nil
    }
}
