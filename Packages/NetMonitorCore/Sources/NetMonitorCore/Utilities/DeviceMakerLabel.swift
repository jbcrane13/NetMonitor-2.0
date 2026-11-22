import Foundation
import NetworkScanKit

/// The maker and model label device rows show on both platforms (#446): "Apple · Mac16,11",
/// "Sonos · Arc Ultra", the model alone, or the private-address label.
public extension DiscoveredDevice {
    var makerLabel: String? {
        MACAddress.makerLabel(vendor: maker, macAddress: macAddress, model: modelName)
    }
}

public extension LocalDevice {
    var makerLabel: String? {
        MACAddress.makerLabel(vendor: maker, macAddress: macAddress, model: modelName)
    }
}
