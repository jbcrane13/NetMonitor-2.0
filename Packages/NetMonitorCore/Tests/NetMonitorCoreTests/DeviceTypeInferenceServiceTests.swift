import Testing
import Foundation
@testable import NetMonitorCore

// MARK: - Helpers

private func makeDevice(
    hostname: String? = nil,
    resolvedHostname: String? = nil,
    customName: String? = nil,
    isGateway: Bool = false,
    discoveredServices: [String]? = nil,
    openPorts: [Int]? = nil,
    vendor: String? = nil,
    manufacturer: String? = nil,
    deviceType: DeviceType = .unknown
) -> LocalDevice {
    LocalDevice(
        ipAddress: "192.168.1.100",
        macAddress: "AA:BB:CC:DD:EE:FF",
        hostname: hostname,
        vendor: vendor,
        deviceType: deviceType,
        customName: customName,
        resolvedHostname: resolvedHostname,
        manufacturer: manufacturer,
        openPorts: openPorts,
        discoveredServices: discoveredServices
    )
}

// MARK: - Guard: already-typed devices

@Suite("DeviceTypeInferenceService — guard: already-typed devices")
struct DeviceTypeInferenceGuardTests {

    let sut = DeviceTypeInferenceService()

    @Test("Non-unknown device type is preserved unchanged")
    func preservesExistingDeviceType() {
        let device = makeDevice(hostname: "iphone-of-blake", deviceType: .laptop)
        #expect(sut.inferDeviceType(for: device) == .laptop)
    }

    @Test("Preserves all non-unknown types without mutation", arguments: [
        DeviceType.router, .computer, .phone, .tablet, .laptop, .tv,
        .speaker, .storage, .printer, .camera, .gaming, .iot
    ])
    func preservesAllKnownTypes(type: DeviceType) {
        let device = makeDevice(deviceType: type)
        #expect(sut.inferDeviceType(for: device) == type)
    }
}

// MARK: - Level 1: Gateway flag

@Suite("DeviceTypeInferenceService — Level 1: gateway flag")
struct DeviceTypeInferenceGatewayTests {

    let sut = DeviceTypeInferenceService()

    @Test("Gateway flag resolves to router")
    func gatewayFlagResolvesToRouter() {
        let device = makeDevice(isGateway: true)
        #expect(sut.inferDeviceType(for: device) == .router)
    }

    @Test("Gateway flag takes priority over hostname")
    func gatewayFlagTakesPriorityOverHostname() {
        let device = makeDevice(hostname: "iphone-blake", isGateway: true)
        #expect(sut.inferDeviceType(for: device) == .router)
    }

    @Test("Gateway flag takes priority over services")
    func gatewayFlagTakesPriorityOverServices() {
        let device = makeDevice(isGateway: true, discoveredServices: ["_airplay._tcp"])
        #expect(sut.inferDeviceType(for: device) == .router)
    }
}

// MARK: - Level 2: Hostname inference

@Suite("DeviceTypeInferenceService — Level 2: hostname inference")
struct DeviceTypeInferenceHostnameTests {

    let sut = DeviceTypeInferenceService()

    @Test("Hostname 'iphone' resolves to phone")
    func hostnameIphoneResolvesToPhone() {
        #expect(sut.inferDeviceType(for: makeDevice(hostname: "Blakes-iPhone")) == .phone)
    }

    @Test("Hostname 'ipad' resolves to tablet")
    func hostnameIpadResolvesToTablet() {
        #expect(sut.inferDeviceType(for: makeDevice(hostname: "Blakes-iPad-Pro")) == .tablet)
    }

    @Test("Hostname 'android' resolves to phone")
    func hostnameAndroidResolvesToPhone() {
        #expect(sut.inferDeviceType(for: makeDevice(hostname: "android-samsung-s24")) == .phone)
    }

    @Test("Hostname 'macbook' resolves to laptop")
    func hostnameMacbookResolvesToLaptop() {
        #expect(sut.inferDeviceType(for: makeDevice(hostname: "Blakes-MacBook-Pro")) == .laptop)
    }

    @Test("Hostname 'laptop' resolves to laptop")
    func hostnameLaptopResolvesToLaptop() {
        #expect(sut.inferDeviceType(for: makeDevice(hostname: "work-laptop")) == .laptop)
    }

    @Test("Hostname 'imac' resolves to computer")
    func hostnameImacResolvesToComputer() {
        #expect(sut.inferDeviceType(for: makeDevice(hostname: "Blakes-iMac")) == .computer)
    }

    @Test("Hostname 'mac-mini' resolves to computer")
    func hostnameMacMiniResolvesToComputer() {
        #expect(sut.inferDeviceType(for: makeDevice(hostname: "mac-mini-server")) == .computer)
    }

    @Test("Hostname 'mac-pro' resolves to computer")
    func hostnameMacProResolvesToComputer() {
        #expect(sut.inferDeviceType(for: makeDevice(hostname: "Blakes-mac-pro")) == .computer)
    }

    @Test("Hostname 'mac-studio' resolves to computer")
    func hostnameMacStudioResolvesToComputer() {
        #expect(sut.inferDeviceType(for: makeDevice(hostname: "Blakes-mac-studio")) == .computer)
    }

    @Test("Hostname 'appletv' resolves to tv")
    func hostnameAppleTVResolvesToTV() {
        #expect(sut.inferDeviceType(for: makeDevice(hostname: "Blakes-AppleTV")) == .tv)
    }

    @Test("Hostname 'apple-tv' resolves to tv")
    func hostnameAppleTVDashedResolvesToTV() {
        #expect(sut.inferDeviceType(for: makeDevice(hostname: "living-room-apple-tv")) == .tv)
    }

    @Test("Hostname 'homepod' resolves to speaker")
    func hostnameHomepodResolvesToSpeaker() {
        #expect(sut.inferDeviceType(for: makeDevice(hostname: "Blakes-HomePod-Mini")) == .speaker)
    }

    @Test("Hostname 'nas' resolves to storage")
    func hostnameNasResolvesToStorage() {
        #expect(sut.inferDeviceType(for: makeDevice(hostname: "home-nas")) == .storage)
    }

    @Test("Hostname 'synology' resolves to storage")
    func hostnameSynologyResolvesToStorage() {
        #expect(sut.inferDeviceType(for: makeDevice(hostname: "synology-ds920")) == .storage)
    }

    @Test("Hostname 'qnap' resolves to storage")
    func hostnameQnapResolvesToStorage() {
        #expect(sut.inferDeviceType(for: makeDevice(hostname: "qnap-ts-873a")) == .storage)
    }

    @Test("Hostname 'drobo' resolves to storage")
    func hostnameDroboResolvesToStorage() {
        #expect(sut.inferDeviceType(for: makeDevice(hostname: "drobo-5n")) == .storage)
    }

    @Test("Hostname 'printer' resolves to printer")
    func hostnamePrinterResolvesToPrinter() {
        #expect(sut.inferDeviceType(for: makeDevice(hostname: "office-printer")) == .printer)
    }

    @Test("Hostname 'canon' resolves to printer")
    func hostnameCanonResolvesToPrinter() {
        #expect(sut.inferDeviceType(for: makeDevice(hostname: "canon-pixma")) == .printer)
    }

    @Test("Hostname 'epson' resolves to printer")
    func hostnameEpsonResolvesToPrinter() {
        #expect(sut.inferDeviceType(for: makeDevice(hostname: "epson-et-3760")) == .printer)
    }

    @Test("Hostname 'brother' resolves to printer")
    func hostnameBrotherResolvesToPrinter() {
        #expect(sut.inferDeviceType(for: makeDevice(hostname: "brother-mfc")) == .printer)
    }

    @Test("Hostname 'camera' resolves to camera")
    func hostnameCameraResolvesToCamera() {
        #expect(sut.inferDeviceType(for: makeDevice(hostname: "front-door-camera")) == .camera)
    }

    @Test("Hostname 'cam' resolves to camera")
    func hostnameCamResolvesToCamera() {
        #expect(sut.inferDeviceType(for: makeDevice(hostname: "porch-cam-01")) == .camera)
    }

    @Test("Hostname 'playstation' resolves to gaming")
    func hostnamePlaystationResolvesToGaming() {
        #expect(sut.inferDeviceType(for: makeDevice(hostname: "playstation-5")) == .gaming)
    }

    @Test("Hostname 'xbox' resolves to gaming")
    func hostnameXboxResolvesToGaming() {
        #expect(sut.inferDeviceType(for: makeDevice(hostname: "Blakes-Xbox-Series-X")) == .gaming)
    }

    @Test("Hostname 'nintendo' resolves to gaming")
    func hostnameNintendoResolvesToGaming() {
        #expect(sut.inferDeviceType(for: makeDevice(hostname: "nintendo-switch")) == .gaming)
    }

    @Test("Hostname 'switch' resolves to gaming")
    func hostnameSwitchResolvesToGaming() {
        #expect(sut.inferDeviceType(for: makeDevice(hostname: "my-switch-console")) == .gaming)
    }

    @Test("resolvedHostname is used when hostname is nil")
    func resolvedHostnameIsUsedWhenHostnameNil() {
        let device = makeDevice(resolvedHostname: "Blakes-iPhone.local")
        #expect(sut.inferDeviceType(for: device) == .phone)
    }

    @Test("customName is used for inference")
    func customNameIsUsedForInference() {
        let device = makeDevice(customName: "Upstairs iPad")
        #expect(sut.inferDeviceType(for: device) == .tablet)
    }

    @Test("Hostname pattern matching is case-insensitive")
    func hostnameMatchingIsCaseInsensitive() {
        #expect(sut.inferDeviceType(for: makeDevice(hostname: "IPHONE-BLAKE")) == .phone)
        #expect(sut.inferDeviceType(for: makeDevice(hostname: "iPhone-Blake")) == .phone)
    }
}

// MARK: - Level 3: Bonjour service inference

@Suite("DeviceTypeInferenceService — Level 3: Bonjour services")
struct DeviceTypeInferenceServicesTests {

    let sut = DeviceTypeInferenceService()

    @Test("_printer._tcp resolves to printer")
    func printerServiceResolvesToPrinter() {
        #expect(sut.inferDeviceType(for: makeDevice(discoveredServices: ["_printer._tcp"])) == .printer)
    }

    @Test("_ipp._tcp resolves to printer")
    func ippServiceResolvesToPrinter() {
        #expect(sut.inferDeviceType(for: makeDevice(discoveredServices: ["_ipp._tcp"])) == .printer)
    }

    @Test("_pdl-datastream._tcp resolves to printer")
    func pdlServiceResolvesToPrinter() {
        #expect(sut.inferDeviceType(for: makeDevice(discoveredServices: ["_pdl-datastream._tcp"])) == .printer)
    }

    @Test("_raop._tcp resolves to speaker")
    func raopServiceResolvesToSpeaker() {
        #expect(sut.inferDeviceType(for: makeDevice(discoveredServices: ["_raop._tcp"])) == .speaker)
    }

    @Test("_airplay._tcp resolves to tv")
    func airplayServiceResolvesToTV() {
        #expect(sut.inferDeviceType(for: makeDevice(discoveredServices: ["_airplay._tcp"])) == .tv)
    }

    @Test("SMB + TimeMachine resolves to storage")
    func smbTimeMachineResolvesToStorage() {
        let device = makeDevice(discoveredServices: ["_smb._tcp", "_timemachine._tcp"])
        #expect(sut.inferDeviceType(for: device) == .storage)
    }

    @Test("AFP + TimeMachine resolves to storage")
    func afpTimeMachineResolvesToStorage() {
        let device = makeDevice(discoveredServices: ["_afpovertcp._tcp", "_timemachine._tcp"])
        #expect(sut.inferDeviceType(for: device) == .storage)
    }

    @Test("SMB alone does not resolve to storage")
    func smbAloneDoesNotResolveToStorage() {
        #expect(sut.inferDeviceType(for: makeDevice(discoveredServices: ["_smb._tcp"])) == .unknown)
    }

    @Test("TimeMachine alone does not resolve to storage")
    func timeMachineAloneDoesNotResolveToStorage() {
        #expect(sut.inferDeviceType(for: makeDevice(discoveredServices: ["_timemachine._tcp"])) == .unknown)
    }
}

// MARK: - Level 4: Port-based inference

@Suite("DeviceTypeInferenceService — Level 4: port inference")
struct DeviceTypeInferencePortTests {

    let sut = DeviceTypeInferenceService()

    @Test("Ports 80+443+53 resolve to router")
    func portsWebAndDNSResolvesToRouter() {
        #expect(sut.inferDeviceType(for: makeDevice(openPorts: [80, 443, 53])) == .router)
    }

    @Test("Port 631 (IPP) resolves to printer")
    func portIPPResolvesToPrinter() {
        #expect(sut.inferDeviceType(for: makeDevice(openPorts: [631])) == .printer)
    }

    @Test("Port 9100 (JetDirect) resolves to printer")
    func portJetDirectResolvesToPrinter() {
        #expect(sut.inferDeviceType(for: makeDevice(openPorts: [9100])) == .printer)
    }

    @Test("Port 8008 (Chromecast) resolves to tv")
    func portChromecastResolvesToTV() {
        #expect(sut.inferDeviceType(for: makeDevice(openPorts: [8008])) == .tv)
    }

    @Test("Port 8009 (Chromecast TLS) resolves to tv")
    func portChromecastTLSResolvesToTV() {
        #expect(sut.inferDeviceType(for: makeDevice(openPorts: [8009])) == .tv)
    }

    @Test("Port 32400 (Plex) resolves to storage")
    func portPlexResolvesToStorage() {
        #expect(sut.inferDeviceType(for: makeDevice(openPorts: [32400])) == .storage)
    }

    @Test("Ports 80+443 without 53 do not resolve to router")
    func portsWebWithoutDNSDoesNotResolveToRouter() {
        #expect(sut.inferDeviceType(for: makeDevice(openPorts: [80, 443])) == .unknown)
    }
}

// MARK: - Level 5: Vendor inference

@Suite("DeviceTypeInferenceService — Level 5: vendor inference")
struct DeviceTypeInferenceVendorTests {

    let sut = DeviceTypeInferenceService()

    @Test("Vendor 'Sonos' resolves to speaker")
    func vendorSonosResolvesToSpeaker() {
        #expect(sut.inferDeviceType(for: makeDevice(vendor: "Sonos Inc.")) == .speaker)
    }

    @Test("Vendor 'Bose' resolves to speaker")
    func vendorBoseResolvesToSpeaker() {
        #expect(sut.inferDeviceType(for: makeDevice(vendor: "Bose Corporation")) == .speaker)
    }

    @Test("Vendor 'Harman' resolves to speaker")
    func vendorHarmanResolvesToSpeaker() {
        #expect(sut.inferDeviceType(for: makeDevice(vendor: "Harman International")) == .speaker)
    }

    @Test("Vendor 'Roku' resolves to tv")
    func vendorRokuResolvesToTV() {
        #expect(sut.inferDeviceType(for: makeDevice(vendor: "Roku Inc")) == .tv)
    }

    @Test("Vendor 'LG Electronics' resolves to tv")
    func vendorLGResolvesToTV() {
        #expect(sut.inferDeviceType(for: makeDevice(vendor: "LG Electronics")) == .tv)
    }

    @Test("Vendor 'Samsung' with port 8001 resolves to tv")
    func vendorSamsungWithSmartTVPort8001ResolvesToTV() {
        #expect(sut.inferDeviceType(for: makeDevice(vendor: "Samsung", openPorts: [8001])) == .tv)
    }

    @Test("Vendor 'Samsung' with port 8002 resolves to tv")
    func vendorSamsungWithSmartTVPort8002ResolvesToTV() {
        #expect(sut.inferDeviceType(for: makeDevice(vendor: "Samsung", openPorts: [8002])) == .tv)
    }

    @Test("Vendor 'Samsung' without smart-TV ports does not resolve to tv")
    func vendorSamsungWithoutSmartTVPortsFallsThrough() {
        #expect(sut.inferDeviceType(for: makeDevice(vendor: "Samsung", openPorts: [22, 80])) == .unknown)
    }

    @Test("Vendor 'Synology' resolves to storage")
    func vendorSynologyResolvesToStorage() {
        #expect(sut.inferDeviceType(for: makeDevice(vendor: "Synology Inc.")) == .storage)
    }

    @Test("Vendor 'QNAP' resolves to storage")
    func vendorQNAPResolvesToStorage() {
        #expect(sut.inferDeviceType(for: makeDevice(vendor: "QNAP Systems")) == .storage)
    }

    @Test("Vendor 'Western Digital' resolves to storage")
    func vendorWesternDigitalResolvesToStorage() {
        #expect(sut.inferDeviceType(for: makeDevice(vendor: "Western Digital")) == .storage)
    }

    @Test("Vendor 'Drobo' resolves to storage")
    func vendorDroboResolvesToStorage() {
        #expect(sut.inferDeviceType(for: makeDevice(vendor: "Drobo Inc")) == .storage)
    }

    @Test("Vendor 'Raspberry Pi' resolves to iot")
    func vendorRaspberryPiResolvesToIoT() {
        #expect(sut.inferDeviceType(for: makeDevice(vendor: "Raspberry Pi Foundation")) == .iot)
    }

    @Test("Vendor 'Espressif' resolves to iot")
    func vendorEspressifResolvesToIoT() {
        #expect(sut.inferDeviceType(for: makeDevice(vendor: "Espressif Inc.")) == .iot)
    }

    @Test("Vendor 'Tuya' resolves to iot")
    func vendorTuyaResolvesToIoT() {
        #expect(sut.inferDeviceType(for: makeDevice(vendor: "Tuya Smart")) == .iot)
    }

    @Test("Vendor 'Ring' resolves to camera")
    func vendorRingResolvesToCamera() {
        #expect(sut.inferDeviceType(for: makeDevice(vendor: "Ring LLC")) == .camera)
    }

    @Test("Vendor 'Nest' resolves to camera")
    func vendorNestResolvesToCamera() {
        #expect(sut.inferDeviceType(for: makeDevice(vendor: "Nest Labs")) == .camera)
    }

    @Test("Vendor 'Wyze' resolves to camera")
    func vendorWyzeResolvesToCamera() {
        #expect(sut.inferDeviceType(for: makeDevice(vendor: "Wyze Labs")) == .camera)
    }

    @Test("Vendor 'Hikvision' resolves to camera")
    func vendorHikvisionResolvesToCamera() {
        #expect(sut.inferDeviceType(for: makeDevice(vendor: "Hikvision Digital Technology")) == .camera)
    }

    @Test("Vendor 'Dahua' resolves to camera")
    func vendorDahuaResolvesToCamera() {
        #expect(sut.inferDeviceType(for: makeDevice(vendor: "Dahua Technology")) == .camera)
    }

    @Test("Vendor 'Canon' resolves to printer")
    func vendorCanonResolvesToPrinter() {
        #expect(sut.inferDeviceType(for: makeDevice(vendor: "Canon Inc.")) == .printer)
    }

    @Test("Vendor 'Epson' resolves to printer")
    func vendorEpsonResolvesToPrinter() {
        #expect(sut.inferDeviceType(for: makeDevice(vendor: "Seiko Epson Corporation")) == .printer)
    }

    @Test("Vendor 'Brother' resolves to printer")
    func vendorBrotherResolvesToPrinter() {
        #expect(sut.inferDeviceType(for: makeDevice(vendor: "Brother Industries")) == .printer)
    }

    @Test("Vendor 'HP Inc' resolves to printer")
    func vendorHPIncResolvesToPrinter() {
        #expect(sut.inferDeviceType(for: makeDevice(vendor: "HP Inc.")) == .printer)
    }

    @Test("Vendor 'Hewlett Packard' resolves to printer")
    func vendorHewlettPackardResolvesToPrinter() {
        #expect(sut.inferDeviceType(for: makeDevice(vendor: "Hewlett Packard")) == .printer)
    }

    @Test("Vendor 'Nintendo' resolves to gaming")
    func vendorNintendoResolvesToGaming() {
        #expect(sut.inferDeviceType(for: makeDevice(vendor: "Nintendo Co., Ltd.")) == .gaming)
    }

    @Test("Vendor 'Sony Interactive' resolves to gaming")
    func vendorSonyInteractiveResolvesToGaming() {
        #expect(sut.inferDeviceType(for: makeDevice(vendor: "Sony Interactive Entertainment")) == .gaming)
    }

    @Test("Vendor 'Microsoft' with Xbox port 3074 resolves to gaming")
    func vendorMicrosoftWithXboxPortResolvesToGaming() {
        let device = makeDevice(vendor: "Microsoft Corporation", openPorts: [3074])
        #expect(sut.inferDeviceType(for: device) == .gaming)
    }

    @Test("Vendor 'Microsoft' without Xbox port stays unknown")
    func vendorMicrosoftWithoutXboxPortFallsThrough() {
        #expect(sut.inferDeviceType(for: makeDevice(vendor: "Microsoft Corporation", openPorts: [445])) == .unknown)
    }

    @Test("Vendor 'Apple' resolves to computer")
    func vendorAppleResolvesToComputer() {
        #expect(sut.inferDeviceType(for: makeDevice(vendor: "Apple Inc.")) == .computer)
    }

    @Test("Vendor 'Intel' resolves to computer")
    func vendorIntelResolvesToComputer() {
        #expect(sut.inferDeviceType(for: makeDevice(vendor: "Intel Corporation")) == .computer)
    }

    @Test("Vendor 'Dell' resolves to computer")
    func vendorDellResolvesToComputer() {
        #expect(sut.inferDeviceType(for: makeDevice(vendor: "Dell Technologies")) == .computer)
    }

    @Test("Vendor 'Lenovo' resolves to computer")
    func vendorLenovoResolvesToComputer() {
        #expect(sut.inferDeviceType(for: makeDevice(vendor: "Lenovo Group Limited")) == .computer)
    }

    @Test("Vendor 'Asus' resolves to computer")
    func vendorAsusResolvesToComputer() {
        #expect(sut.inferDeviceType(for: makeDevice(vendor: "ASUSTeK Computer Inc.")) == .computer)
    }

    @Test("Vendor 'Hewlett-Packard' (hyphenated) resolves to computer")
    func vendorHewlettPackardHyphenatedResolvesToComputer() {
        #expect(sut.inferDeviceType(for: makeDevice(vendor: "Hewlett-Packard Development Company")) == .computer)
    }

    @Test("manufacturer field is used when vendor is nil")
    func manufacturerFieldIsUsedWhenVendorNil() {
        #expect(sut.inferDeviceType(for: makeDevice(manufacturer: "Sonos Inc.")) == .speaker)
    }

    @Test("Vendor field is iterated before manufacturer")
    func vendorMatchesBeforeManufacturer() {
        // vendor=Apple → .computer; manufacturer=Sonos → .speaker
        let device = makeDevice(vendor: "Apple Inc.", manufacturer: "Sonos Inc.")
        #expect(sut.inferDeviceType(for: device) == .computer)
    }

    @Test("Vendor matching is case-insensitive")
    func vendorMatchingIsCaseInsensitive() {
        #expect(sut.inferDeviceType(for: makeDevice(vendor: "SONOS INC.")) == .speaker)
    }
}

// MARK: - Level 6: Fallback and priority ordering

@Suite("DeviceTypeInferenceService — Level 6: fallback and priority")
struct DeviceTypeInferenceFallbackTests {

    let sut = DeviceTypeInferenceService()

    @Test("Device with no signals remains unknown")
    func deviceWithNoSignalsRemainsUnknown() {
        #expect(sut.inferDeviceType(for: makeDevice()) == .unknown)
    }

    @Test("Unrecognized hostname stays unknown")
    func deviceWithUnrecognizedHostnameRemainsUnknown() {
        #expect(sut.inferDeviceType(for: makeDevice(hostname: "device-a3f2c1")) == .unknown)
    }

    @Test("Unrecognized vendor stays unknown")
    func deviceWithUnrecognizedVendorRemainsUnknown() {
        #expect(sut.inferDeviceType(for: makeDevice(vendor: "SomeBrandNoOneHasHeardOf")) == .unknown)
    }

    @Test("Empty services list stays unknown")
    func deviceWithEmptyServicesRemainsUnknown() {
        #expect(sut.inferDeviceType(for: makeDevice(discoveredServices: [])) == .unknown)
    }

    @Test("Empty ports list stays unknown")
    func deviceWithEmptyPortsRemainsUnknown() {
        #expect(sut.inferDeviceType(for: makeDevice(openPorts: [])) == .unknown)
    }

    @Test("Hostname inference wins over Bonjour services")
    func hostnameWinsOverServices() {
        // hostname → phone; services → tv
        let device = makeDevice(hostname: "Blakes-iPhone", discoveredServices: ["_airplay._tcp"])
        #expect(sut.inferDeviceType(for: device) == .phone)
    }

    @Test("Bonjour services win over ports")
    func servicesWinOverPorts() {
        // services → printer; ports → tv
        let device = makeDevice(discoveredServices: ["_printer._tcp"], openPorts: [8008])
        #expect(sut.inferDeviceType(for: device) == .printer)
    }

    @Test("Ports win over vendor")
    func portsWinOverVendor() {
        // ports → printer (631); vendor → speaker (Sonos)
        let device = makeDevice(openPorts: [631], vendor: "Sonos Inc.")
        #expect(sut.inferDeviceType(for: device) == .printer)
    }
}
