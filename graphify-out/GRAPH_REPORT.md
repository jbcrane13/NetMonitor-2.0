# Graph Report - /Users/blake/Projects/NetMonitor-2.0/Packages  (2026-09-17)

## Corpus Check
- 22 files · ~138,222 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 3987 nodes · 9627 edges · 180 communities (140 shown, 40 thin omitted)
- Extraction: 78% EXTRACTED · 22% INFERRED · 0% AMBIGUOUS · INFERRED: 2112 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- WiFi Network Models
- Network Connection Helper
- Ping Service
- Speed Test Service
- MAC Vendor Lookup Service
- Scan Pipeline
- Heatmap Survey State
- WHOIS Service
- Heatmap Renderer
- Shared Package Test Coverage
- World Ping and Geolocation
- Network Event Service
- Scan Accumulator
- VPN Detection Service
- Port Scanner Service
- Measurement Point
- Project Save Load Manager
- Network Health Score Service
- Discovery Services
- Companion Message Models
- Bonjour Scan Phase
- Geolocation Service
- Formatting Utilities
- Device Vendor Type Inference
- Survey Project
- Multi-Room Blueprint Construction
- Wake On LAN Service Tests
- Local Device
- Blueprint Floor
- Speed Test Atomic State
- World Ping Check Result
- Scan Scheduler Service
- Device Discovery Service
- Scan Engine
- Service Protocol Definitions
- Monitoring Target
- Persistence Robustness Tests
- Scan Engine Fixture Phases
- Hostname Device Type Inference
- Scan Diff Models
- Traceroute Service
- Blueprint Save Load Manager
- Sensitive Log Redaction
- Reverse DNS Scan Phase
- Bonjour Discovery Service
- Navigation Models
- Tool Activity Item
- ICMP Packet Encoding Tests
- Network Utilities
- ARP Cache Parsing
- Persistence Bootstrap
- ICMP Latency Phase
- Certificate Expiration Tracker
- Service Protocol Types Tests
- SSL Certificate Models
- Scan Context
- Companion Payload Models
- Network Profile Payload
- Measurement Statistics Models
- Traceroute Hop
- Network Profile Manager
- Core Enum Model Tests
- IPv4 Helper Tests
- ARP Scan Phase
- Tool Result
- Blueprint File Error
- Scan Strategy Tests
- Device Type
- Tool Type Enumeration
- Check Host Fixtures
- Device Name Resolver
- SSDP Scan Phase
- Target Protocol
- Certificate Expiration Tracker Tests
- Geolocation Response Parsing
- Connectivity Record
- ICMP Socket
- Mock URL Protocol
- ISP Info
- Resume State
- Scan Diff Tests
- Network Utilities Models
- Service Utilities Tests
- Status Type
- Port Scan Result
- Companion Message Coding Keys
- Gateway Info
- Network Signal Models
- IPv4 Validation Helpers
- Floor Plan Rendering
- WiFi Measurement Engine
- Companion Frame Decoder
- Paired Mac
- Shared Service Protocols
- SSL Certificate Service
- Network Profile Manager Tests
- RTT Tracker
- DNS Error Handling
- Network Profile Models
- Thermal Throttle Monitor
- Scan Engine Progress Tests
- DNS Lookup Service
- DNS Query Parsing
- Network Error
- Bonjour Service Models
- WHOIS Result
- Heatmap Visualization
- DNS Record
- Bonjour Discovery Service
- Notification Service
- DNS Query Result Tests
- Network Profile Manager Extended Tests
- SSDP Scan Phase Tests
- History Sparkline
- Session Record
- Command Action
- Port Scan Presets
- Heatmap Survey Model Tests
- SSL Certificate Service Tests
- Scan Engine Timeout Handling
- Ping Statistics Tests
- Scan Progress Coalescer
- DNS Binary Record Parsing
- Observability Service
- Speed Test Error
- Port Scan Preset Tests
- Heatmap Contract Tests
- Network Error Description Tests
- Network Error User-Facing Tests
- Network Event Type Tests
- Connection Type
- RSSI Quality
- DNS Query Result
- Network Monitor Service
- Scan Display Phase
- DER Certificate Parsing
- Device Type Inference Services Tests
- Network Profile Extended Tests
- World Ping Service Protocol
- Message Type
- Device Type Inference Fallback Tests
- Geolocation Malformed Contract Tests
- Real Scan Pipeline Integration
- Survey Mode
- Scan Diff
- SSL Certificate Error
- Certificate Authentication Delegate
- Device Type Inference Gateway Tests
- Device Type Inference Port Tests
- Network Error Conversion Tests
- Target Protocol Codable Tests
- Scan Phase Pipeline
- IPv4 Address Cleaning
- Companion Message Decode Errors
- Heartbeat Payload
- Floor Plan From Blueprint Tests
- Notifications and Observability
- Probe Result
- Network Route Parsing
- Connection Type Tests
- Shared Package Architecture
- Heatmap Renderer Integration
- Heatmap Survey Model Tests
- NetMonitorCore Integration Tags
- Port State Raw Value Tests
- Survey File Error Tests
- Port State Tests
- NetworkScanKit Integration Tags
- Date Foundation Type
- User Defaults Foundation Type
- Public IP Test Fixture
- MAC Vendor Test Fixture
- WHOIS Test Fixture
- Connection Budget
- NWConnection
- Sendable Constraint
- Generic Type T
- ICMP Integer Type
- ICMP Byte Type

## God Nodes (most connected - your core abstractions)
1. `makeDevice()` - 102 edges
2. `Testing` - 101 edges
3. `ScanAccumulator` - 86 edges
4. `NetMonitorCore` - 76 edges
5. `ScanContext` - 67 edges
6. `MeasurementPoint` - 63 edges
7. `SpeedTestService` - 62 edges
8. `HeatmapSurveyState` - 58 edges
9. `CompanionMessage` - 57 edges
10. `DiscoveredDevice` - 55 edges

## Surprising Connections (you probably didn't know these)
- `Protocol-First Strict Concurrency` --conceptually_related_to--> `Adaptive Scan Engine`  [INFERRED]
  NetMonitorCore/Sources/NetMonitorCore/AGENTS.md → NetworkScanKit/Sources/NetworkScanKit/AGENTS.md
- `Deterministic Scan Engine Tests` --references--> `ScanEngine`  [EXTRACTED]
  NetworkScanKit/Tests/NetworkScanKitTests/AGENTS.md → NetworkScanKit/Sources/NetworkScanKit/ScanEngine.swift
- `DeviceDiscoveryService` --calls--> `ScanEngine`  [INFERRED]
  NetMonitorCore/Sources/NetMonitorCore/Services/DeviceDiscoveryService.swift → NetworkScanKit/Sources/NetworkScanKit/ScanEngine.swift
- `Companion Wire Format` --references--> `CompanionMessage`  [EXTRACTED]
  NetMonitorCore/Sources/NetMonitorCore/Models/AGENTS.md → NetMonitorCore/Sources/NetMonitorCore/Models/CompanionMessage.swift
- `QueryContext` --references--> `ResumeState`  [EXTRACTED]
  NetMonitorCore/Sources/NetMonitorCore/Services/DNSLookupService.swift → NetworkScanKit/Sources/NetworkScanKit/ResumeState.swift

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Network Discovery Scan Phases** — networkscankit_sources_networkscankit_phases_arpscanphase_arpscanphase, networkscankit_sources_networkscankit_phases_bonjourscanphase_bonjourscanphase, networkscankit_sources_networkscankit_phases_tcpprobescanphase_tcpprobescanphase, networkscankit_sources_networkscankit_phases_ssdpscanphase_ssdpscanphase, networkscankit_sources_networkscankit_phases_reversednsscanphase_reversednsscanphase [EXTRACTED 1.00]
- **Adaptive Scan Runtime** — networkscankit_sources_networkscankit_scanengine_scanengine, networkscankit_sources_networkscankit_scanaccumulator_scanaccumulator, networkscankit_sources_networkscankit_rtttracker_rtttracker, networkscankit_sources_networkscankit_connectionbudget_connectionbudget, networkscankit_sources_networkscankit_thermalthrottlemonitor_thermalthrottlemonitor [EXTRACTED 1.00]
- **Shared Package Dependency Flow** — networkscankit_package, netmonitorcore_package, agents_shared_package_architecture [EXTRACTED 1.00]

## Communities (180 total, 40 thin omitted)

### Community 0 - "WiFi Network Models"
Cohesion: 0.07
Nodes (22): CLAuthorizationStatus, WiFiInfo, .signalBars, .signalQuality, SpeedTestData, WiFiInfoSignalBarsTests, WiFiInfoSignalQualityTests, SpeedTestEdgeCaseContractTests (+14 more)

### Community 1 - "Network Connection Helper"
Cohesion: 0.06
Nodes (41): DispatchQueue, NWConnectionOperationState, NWConnectionResolution, complete, completeKeepAlive, StoredValue, Bool, CheckedContinuation (+33 more)

### Community 2 - "Ping Service"
Cohesion: 0.07
Nodes (31): ICMPSocket, DateRef, PingService, AsyncStream, Bool, Int, String, TimeInterval (+23 more)

### Community 3 - "Speed Test Service"
Cohesion: 0.07
Nodes (11): SpeedTestService, Bool, Task, URLSession, SpeedTestServiceCancellationTests, SpeedTestServiceErrorRecoveryTests, SpeedTestServiceIntegrationTests, SpeedTestService2xxRegressionTests (+3 more)

### Community 4 - "MAC Vendor Lookup Service"
Cohesion: 0.08
Nodes (10): MACVendorLookupService, String, TimeInterval, URLSession, MACVendorContractTests, MACVendorLookupServiceTests, String, MACVendorOnlineContractTests (+2 more)

### Community 5 - "Scan Pipeline"
Cohesion: 0.06
Nodes (18): Protocol-First Strict Concurrency, Adaptive Scan Engine, BonjourServiceInfo, String, .ipSortKey, Int, ScanPipeline, Void (+10 more)

### Community 6 - "Heatmap Survey State"
Cohesion: 0.07
Nodes (24): HeatmapSurveyState, .averageRSSI, .canUndo, .filteredPoints, .hasFloorPlan, .maxRSSI, .minRSSI, .uniqueBSSIDs (+16 more)

### Community 7 - "WHOIS Service"
Cohesion: 0.08
Nodes (17): DateFormatter, CheckedContinuation, Data, Date, Error, Int, NWConnection, Sendable (+9 more)

### Community 8 - "Heatmap Renderer"
Cohesion: 0.08
Nodes (19): CGImage, HeatmapColorScheme, .displayName, plasma, stoplight, thermal, wifiman, Configuration (+11 more)

### Community 9 - "Shared Package Test Coverage"
Cohesion: 0.06
Nodes (3): NetMonitorCore, WorldPingServiceConcurrencyTests, Testing

### Community 10 - "World Ping and Geolocation"
Cohesion: 0.08
Nodes (20): LocalizedError, GlobalpingError, .errorDescription, pollFailed, submitFailed, Any, AsyncStream, Int (+12 more)

### Community 11 - "Network Event Service"
Cohesion: 0.07
Nodes (28): NetworkEvent, NetworkEventSeverity, error, info, success, warning, NetworkEventType, connectivityChange (+20 more)

### Community 12 - "Scan Accumulator"
Cohesion: 0.11
Nodes (15): devices, ScanAccumulator, .count, .isEmpty, Bool, Double, Int, Set (+7 more)

### Community 13 - "VPN Detection Service"
Cohesion: 0.06
Nodes (22): AsyncStream, Bool, Date, NWPath, NWPathMonitor, String, UUID, VPNDetectionService (+14 more)

### Community 14 - "Port Scanner Service"
Cohesion: 0.06
Nodes (18): PortRange, .count, .isEmpty, .isValid, .ports, Int, PortScannerService, AsyncStream (+10 more)

### Community 15 - "Measurement Point"
Cohesion: 0.07
Nodes (6): MeasurementPoint, .averageRSSI, Bool, HeatmapVisualizationTests, MeasurementPointTests, HeatmapVisualizationExtractionTests

### Community 16 - "Project Save Load Manager"
Cohesion: 0.12
Nodes (22): ProjectSaveLoadManager, SurveyFileError, bundleNotFound, corruptedJSON, floorPlanImageMissing, .localizedDescription, surveyJSONMissing, writeFailed (+14 more)

### Community 17 - "Network Health Score Service"
Cohesion: 0.08
Nodes (6): NetworkHealthScoreService, Bool, Double, Int, String, NetworkHealthScoreServiceTests

### Community 18 - "Discovery Services"
Cohesion: 0.07
Nodes (5): Foundation, Notification.Name, Network, NetworkScanKit, os.log

### Community 19 - "Companion Message Models"
Cohesion: 0.10
Nodes (21): JSONDecoder, JSONEncoder, Companion Wire Format, CommandPayload, CompanionMessage, command, deviceList, error (+13 more)

### Community 20 - "Bonjour Scan Phase"
Cohesion: 0.10
Nodes (17): BonjourServiceInfo, BonjourScanPhase, DiscoveredDevice, Double, Duration, Int, ScanAccumulator, ScanContext (+9 more)

### Community 21 - "Geolocation Service"
Cohesion: 0.12
Nodes (10): HTTPURLResponse, GeoLocationService, String, URLSession, ContractTests, GeoLocationServiceContractTests, GeoLocationExtendedContractTests, String (+2 more)

### Community 22 - "Formatting Utilities"
Cohesion: 0.10
Nodes (12): formatDuration(), formatSpeed(), Bool, Double, String, TimeInterval, .downloadSpeedText, .uploadSpeedText (+4 more)

### Community 23 - "Device Vendor Type Inference"
Cohesion: 0.09
Nodes (5): DeviceTypeInferenceVendorTests, makeDevice(), Bool, Int, String

### Community 24 - "Survey Project"
Cohesion: 0.09
Nodes (22): CalibrationPoint, FloorPlan, .metersPerPixelX, .metersPerPixelY, FloorPlanOrigin, arGenerated, drawn, imported (+14 more)

### Community 25 - "Multi-Room Blueprint Construction"
Cohesion: 0.11
Nodes (12): WallSegment, Bounds, CapturedRoomGeometry, MultiRoomBlueprintBuilder, Double, Int, String, MultiRoomBlueprintBuilderTests (+4 more)

### Community 26 - "Wake On LAN Service Tests"
Cohesion: 0.10
Nodes (10): WakeOnLANResult, Bool, Data, String, UInt16, UInt8, WakeOnLANService, Data (+2 more)

### Community 27 - "Local Device"
Cohesion: 0.11
Nodes (13): LocalDevice, .displayName, .formattedMacAddress, .latencyText, Bool, Date, Double, Int (+5 more)

### Community 28 - "Blueprint Floor"
Cohesion: 0.13
Nodes (17): Equatable, Identifiable, BlueprintFloor, BlueprintMetadata, BlueprintProject, RoomLabel, Bool, Data (+9 more)

### Community 29 - "Speed Test Atomic State"
Cohesion: 0.13
Nodes (17): Int64, AtomicInt64, DownloadMeasurementDelegate, Data, Date, Double, Error, TimeInterval (+9 more)

### Community 30 - "World Ping Check Result"
Cohesion: 0.12
Nodes (12): Date, Double, Int, String, WorldPingCheckResult, .averageLatencyMs, .maximumLatencyMs, .minimumLatencyMs (+4 more)

### Community 31 - "Scan Scheduler Service"
Cohesion: 0.15
Nodes (8): ScanSchedulerService, .isScanDue, Bool, Date, TimeInterval, ScanSchedulerServiceTests, String, ScanDiff

### Community 32 - "Device Discovery Service"
Cohesion: 0.13
Nodes (20): Date, DeviceDiscoveryServiceProtocol, MacConnectionServiceProtocol, DeviceDiscoveryService, ScanFilter, network, prefix, ScanTarget (+12 more)

### Community 33 - "Scan Engine"
Cohesion: 0.22
Nodes (11): ScanEngine, DiscoveredDevice, ScanContext, ProgressCollector, .values, ProgressRecorder, ScanEngineCoverageTests, StubPhase (+3 more)

### Community 34 - "Service Protocol Definitions"
Cohesion: 0.14
Nodes (31): AnyObject, CoreLocation, Shared Service Protocol Contract, BonjourDiscoveryServiceProtocol, CertificateExpirationTrackerProtocol, DeviceDiscoveryServiceProtocol, DeviceNameResolverProtocol, DNSLookupServiceProtocol (+23 more)

### Community 35 - "Monitoring Target"
Cohesion: 0.11
Nodes (14): MonitoringTarget, .hostWithPort, .latencyText, .statusType, .uptimePercentage, .uptimeText, Bool, Date (+6 more)

### Community 36 - "Persistence Robustness Tests"
Cohesion: 0.16
Nodes (7): CertificateExpirationTrackerRobustnessTests, makeFreshDefaults(), NetworkProfileManagerRobustnessTests, StubSSL, StubWHOIS, String, UserDefaults

### Community 37 - "Scan Engine Fixture Phases"
Cohesion: 0.16
Nodes (17): CancellableFixturePhase, FixturePhase, NonCooperativeFixturePhase, PhaseExecutionRecorder, ProgressRecorder, ScanEngineTests, Bool, DiscoveredDevice (+9 more)

### Community 39 - "Scan Diff Models"
Cohesion: 0.10
Nodes (14): ScanDiff, Date, DeviceSource, bonjour, local, macCompanion, ssdp, DiscoveredDevice (+6 more)

### Community 40 - "Traceroute Service"
Cohesion: 0.17
Nodes (10): AsyncStream, Bool, Int, Int32, String, TimeInterval, UInt16, TracerouteService (+2 more)

### Community 41 - "Blueprint Save Load Manager"
Cohesion: 0.20
Nodes (13): bundleNotFound, BlueprintSaveLoadManager, BlueprintLoadErrorTests, BlueprintLoadRoundTripTests, BlueprintSaveTests, makeFloor(), makeProject(), makeTempDir() (+5 more)

### Community 42 - "Sensitive Log Redaction"
Cohesion: 0.11
Nodes (3): LogSanitizer, String, LogSanitizerTests

### Community 43 - "Reverse DNS Scan Phase"
Cohesion: 0.15
Nodes (9): ReverseDNSScanPhase, Double, Int, ScanAccumulator, ScanContext, RDNSProgressCollector, .values, ReverseDNSScanPhaseTests (+1 more)

### Community 44 - "Bonjour Discovery Service"
Cohesion: 0.18
Nodes (7): BonjourDiscoveryServiceProtocol, BonjourService, BonjourDiscoveryService, AsyncStream, Never, Void, BonjourDiscoveryServiceTests

### Community 45 - "Navigation Models"
Cohesion: 0.07
Nodes (9): NavigationSection, .iconName, .id, settings, tools, NavigationSectionCompleteTests, LastShippedStoreCompatibilityTests, NavigationSectionTests (+1 more)

### Community 46 - "Tool Activity Item"
Cohesion: 0.15
Nodes (9): Bool, Date, String, ToolActivityItem, .timeAgoText, ToolActivityLog, ToolActivityItemTests, ToolActivityLogTests (+1 more)

### Community 47 - "ICMP Packet Encoding Tests"
Cohesion: 0.12
Nodes (3): Double, ICMPSocketTests, Int

### Community 48 - "Network Utilities"
Cohesion: 0.12
Nodes (4): Canonical Network Math, NetworkUtilities, IPv4NetworkExtendedTests, NetworkUtilitiesTests

### Community 49 - "ARP Cache Parsing"
Cohesion: 0.15
Nodes (11): CChar, ARPCacheScanner, RouteMetrics, RouteMsgHdr, SockaddrDL, Int, Int32, String (+3 more)

### Community 50 - "Persistence Bootstrap"
Cohesion: 0.10
Nodes (19): Error, PersistenceBootstrap, PersistenceBootstrapOutcome, .isDegraded, PersistenceRecoveryState, Bool, String, ICMPError (+11 more)

### Community 51 - "ICMP Latency Phase"
Cohesion: 0.11
Nodes (16): Int32, ICMPType, echoReply, echoRequest, timeExceeded, ICMPLatencyPhase, Double, Int (+8 more)

### Community 52 - "Certificate Expiration Tracker"
Cohesion: 0.18
Nodes (9): CertificateExpirationTracker, Int, String, UserDefaults, TrackedEntry, .id, DomainExpirationStatus, .domainDaysUntilExpiration (+1 more)

### Community 53 - "Service Protocol Types Tests"
Cohesion: 0.09
Nodes (15): DiscoveredMac, MacConnectionState, browsing, connected, connecting, disconnected, error, .isConnected (+7 more)

### Community 54 - "SSL Certificate Models"
Cohesion: 0.11
Nodes (3): SSLCertificateInfo, SSLCertificateContractTests, String

### Community 55 - "Scan Context"
Cohesion: 0.11
Nodes (10): ScanContext, Bool, String, ScanStrategy, full, remote, ScanContextTests, Sendable (+2 more)

### Community 56 - "Companion Payload Models"
Cohesion: 0.20
Nodes (13): Codable, DeviceInfo, DeviceListPayload, ErrorPayload, StatusUpdatePayload, Bool, Date, Double (+5 more)

### Community 57 - "Network Profile Payload"
Cohesion: 0.15
Nodes (11): NetworkProfilePayload, PingMethod, icmp, tcp, PingResult, .timeText, SpeedTestServer, Bool (+3 more)

### Community 58 - "Measurement Statistics Models"
Cohesion: 0.14
Nodes (13): MeasurementStatistics, .averageLatencyFormatted, .maxLatencyFormatted, .minLatencyFormatted, .uptimeFormatted, Bool, Date, Double (+5 more)

### Community 59 - "Traceroute Hop"
Cohesion: 0.13
Nodes (6): TracerouteHop, .averageTime, .displayAddress, .timeText, TracerouteHopTests, TracerouteServiceTests

### Community 60 - "Network Profile Manager"
Cohesion: 0.18
Nodes (9): CIDRDescriptor, NetworkProfileManager, Bool, Date, Int, Sendable, String, UserDefaults (+1 more)

### Community 61 - "Core Enum Model Tests"
Cohesion: 0.08
Nodes (6): DeviceStatusTests, DeviceTypeTests, DNSRecordTypeTests, StatusTypeTests, TargetProtocolTests, ToolTypeTests

### Community 62 - "IPv4 Helper Tests"
Cohesion: 0.12
Nodes (6): IPv4CIDR, .broadcastAddress, .firstHost, .lastHost, .usableHostCount, IPv4HelpersTests

### Community 63 - "ARP Scan Phase"
Cohesion: 0.17
Nodes (8): ARPScanPhase, Double, ScanAccumulator, ScanContext, ARPScanPhaseTests, ProgressCollector, .values, Double

### Community 64 - "Tool Result"
Cohesion: 0.14
Nodes (13): SpeedTestResult, .latencyText, Bool, Date, Double, String, TimeInterval, UUID (+5 more)

### Community 65 - "Blueprint File Error"
Cohesion: 0.13
Nodes (12): BlueprintFileError, archiveExtractionFailed, blueprintJSONMissing, corruptedJSON, .localizedDescription, svgMissing, writeFailed, Int (+4 more)

### Community 66 - "Scan Strategy Tests"
Cohesion: 0.12
Nodes (3): NetworkScanProfile, String, ScanStrategyCoverageTests

### Community 67 - "Device Type"
Cohesion: 0.10
Nodes (17): DeviceType, camera, computer, .displayName, gaming, .iconName, iot, laptop (+9 more)

### Community 68 - "Tool Type Enumeration"
Cohesion: 0.09
Nodes (23): ToolType, bonjourDiscovery, .color, .displayName, dnsLookup, exportPdf, geoTrace, .iconName (+15 more)

### Community 69 - "Check Host Fixtures"
Cohesion: 0.16
Nodes (4): CheckHostContractTests, Any, Data, String

### Community 70 - "Device Name Resolver"
Cohesion: 0.21
Nodes (3): DeviceNameResolver, String, DeviceNameResolverTests

### Community 71 - "SSDP Scan Phase"
Cohesion: 0.13
Nodes (9): Discovery Phase Portfolio, SSDPScanPhase, Double, ScanAccumulator, ScanContext, String, SSDPProgressCollector, .values (+1 more)

### Community 72 - "Target Protocol"
Cohesion: 0.13
Nodes (16): Encoder, TargetProtocol, .defaultPort, .displayName, http, https, icmp, tcp (+8 more)

### Community 74 - "Geolocation Response Parsing"
Cohesion: 0.10
Nodes (18): Decodable, CodingKeys, city, country, countryCode, isp, lat, lon (+10 more)

### Community 75 - "Connectivity Record"
Cohesion: 0.18
Nodes (9): ConnectivityRecord, Bool, Date, Double, String, UUID, ConnectivityRecordTests, ModelContainer (+1 more)

### Community 76 - "ICMP Socket"
Cohesion: 0.22
Nodes (12): ICMPResponse, ICMPSocket, Kind, echoReply, error, timeExceeded, timeout, Int (+4 more)

### Community 77 - "Mock URL Protocol"
Cohesion: 0.21
Nodes (9): MockHandlerStore, MockURLProtocol, .requestHandler, Bool, Data, Int, String, URLProtocol (+1 more)

### Community 78 - "ISP Info"
Cohesion: 0.15
Nodes (6): CachedResult, ISPInfo, ISPLookupCacheContractTests, Date, String, ISPInfoLocationTextTests

### Community 79 - "Resume State"
Cohesion: 0.21
Nodes (4): ResumeStateTests, ResumeState, Bool, ResumeStateTests

### Community 81 - "Network Utilities Models"
Cohesion: 0.17
Nodes (8): Hashable, .subnetCIDR, IPv4Network, .prefixLength, Bool, Int, String, UnsafeRawPointer

### Community 82 - "Service Utilities Tests"
Cohesion: 0.19
Nodes (5): in_addr, ServiceUtilities, Bool, String, ServiceUtilitiesTests

### Community 83 - "Status Type"
Cohesion: 0.11
Nodes (15): DeviceStatus, .color, idle, offline, online, .statusType, StatusType, .color (+7 more)

### Community 84 - "Port Scan Result"
Cohesion: 0.15
Nodes (8): PortScanResult, PortState, closed, .displayName, filtered, open, PortScanResultFieldTests, PortScanResultTests

### Community 85 - "Companion Message Coding Keys"
Cohesion: 0.11
Nodes (19): CodingKey, CodingKeys, payload, protocolVersion, type, CodingKeys, connectionType, deviceCount (+11 more)

### Community 86 - "Gateway Info"
Cohesion: 0.17
Nodes (8): ISPInfo, GatewayInfo, .latencyText, NetworkStatus, Bool, Double, GatewayInfoLatencyTextTests, NetworkStatusTests

### Community 87 - "Network Signal Models"
Cohesion: 0.13
Nodes (16): ISPInfo, .locationText, SignalQuality, .color, excellent, fair, good, poor (+8 more)

### Community 88 - "IPv4 Validation Helpers"
Cohesion: 0.15
Nodes (8): firstIPv4Address(), IPv4Helpers, isValidIPv4Address(), String, Bool, Int, String, UInt32

### Community 89 - "Floor Plan Rendering"
Cohesion: 0.19
Nodes (11): AppKit, renderWallsToPNG(), renderWithUIKit(), SVGFloorPlanGenerator, SVGRenderer, Data, Double, Int (+3 more)

### Community 90 - "WiFi Measurement Engine"
Cohesion: 0.22
Nodes (8): AsyncStream, Double, Never, String, Task, TimeInterval, Void, WiFiMeasurementEngine

### Community 91 - "Companion Frame Decoder"
Cohesion: 0.18
Nodes (10): CompanionMessage, Data, CompanionFrameBatch, CompanionFrameDecoder, CompanionFrameError, invalidLength, malformedPayload, Int (+2 more)

### Community 92 - "Paired Mac"
Cohesion: 0.20
Nodes (9): PairedMac, .connectionStatusText, .displayAddress, Bool, Date, Int, String, UUID (+1 more)

### Community 93 - "Shared Service Protocols"
Cohesion: 0.24
Nodes (7): GeoLocation, NetworkHealthScore, SubnetInfo, Bool, Double, Int, String

### Community 94 - "SSL Certificate Service"
Cohesion: 0.29
Nodes (3): SSLCertificateService, String, SSLCertificateServiceIntegrationTests

### Community 95 - "Network Profile Manager Tests"
Cohesion: 0.32
Nodes (5): Shared Foundation Test Suite, NetworkProfileManagerTests, Bool, String, UserDefaults

### Community 96 - "RTT Tracker"
Cohesion: 0.29
Nodes (5): RTTTracker, .sampleCount, Double, Int, RTTTrackerTests

### Community 97 - "DNS Error Handling"
Cohesion: 0.16
Nodes (12): dnssd, DNSServiceRef, DNSError, .asNetworkError, .errorDescription, lookupFailed, timeout, QueryContext (+4 more)

### Community 98 - "Network Profile Models"
Cohesion: 0.21
Nodes (12): DiscoveryMethod, auto, companion, manual, NetworkProfile, .displayName, .hostCount, Bool (+4 more)

### Community 99 - "Thermal Throttle Monitor"
Cohesion: 0.17
Nodes (7): Double, Int, ThermalThrottleMonitor, .multiplier, ThermalThrottleMonitorTests, NSObjectProtocol, ProcessInfo

### Community 100 - "Scan Engine Progress Tests"
Cohesion: 0.18
Nodes (9): ProgressCollector, .values, ProgressCounter, .value, StubPhase, .displayName, Double, Int (+1 more)

### Community 101 - "DNS Lookup Service"
Cohesion: 0.30
Nodes (4): DNSServiceQueryRecordReply, DNSLookupService, Bool, DNSLookupServiceIntegrationTests

### Community 102 - "DNS Query Parsing"
Cohesion: 0.16
Nodes (11): DNSRecordType, a, aaaa, cname, .displayName, mx, ns, ptr (+3 more)

### Community 103 - "Network Error"
Cohesion: 0.13
Nodes (14): NetworkError, cancelled, connectionFailed, dnsLookupFailed, .errorDescription, invalidHost, invalidResponse, noNetwork (+6 more)

### Community 104 - "Bonjour Service Models"
Cohesion: 0.23
Nodes (4): BonjourService, .fullType, .serviceCategory, BonjourServiceTests

### Community 105 - "WHOIS Result"
Cohesion: 0.19
Nodes (6): Date, WHOISResult, .daysUntilExpiration, .domainAge, String, WHOISResultTests

### Community 106 - "Heatmap Visualization"
Cohesion: 0.14
Nodes (14): ClosedRange, HeatmapVisualization, .displayName, downloadSpeed, frequencyBand, .isHigherBetter, latency, noiseFloor (+6 more)

### Community 107 - "DNS Record"
Cohesion: 0.25
Nodes (3): DNSRecord, .ttlText, DNSRecordTTLTextTests

### Community 108 - "Bonjour Discovery Service"
Cohesion: 0.21
Nodes (6): Bool, Set, String, Task, NWBrowser, UInt64

### Community 109 - "Notification Service"
Cohesion: 0.19
Nodes (6): Keys, NotificationService, .isAuthorized, Bool, Double, String

### Community 111 - "Network Profile Manager Extended Tests"
Cohesion: 0.43
Nodes (3): NetworkProfileManagerExtendedTests, String, UserDefaults

### Community 113 - "History Sparkline"
Cohesion: 0.26
Nodes (10): CGFloat, Color, String, HistorySparkline, .body, Bool, CGPoint, Double (+2 more)

### Community 114 - "Session Record"
Cohesion: 0.21
Nodes (6): SessionRecord, Bool, Date, UUID, SessionRecordTests, ModelContainer

### Community 115 - "Command Action"
Cohesion: 0.17
Nodes (11): CommandAction, dnsLookup, ping, portScan, refreshDevices, refreshTargets, scanDevices, startMonitoring (+3 more)

### Community 116 - "Port Scan Presets"
Cohesion: 0.17
Nodes (12): PortScanPreset, common, custom, database, .displayName, extended, .isCustom, mail (+4 more)

### Community 117 - "Heatmap Survey Model Tests"
Cohesion: 0.23
Nodes (7): makeFloorPlan(), makeSurveyProject(), SurveyProjectTests, Data, Double, Int, String

### Community 119 - "Scan Engine Timeout Handling"
Cohesion: 0.20
Nodes (7): ScanTimeoutRace, CheckedContinuation, Duration, Never, ScanAccumulator, Sendable, Void

### Community 120 - "Ping Statistics Tests"
Cohesion: 0.29
Nodes (4): PingStatistics, .packetLossText, .successRate, PingStatisticsTests

### Community 121 - "Scan Progress Coalescer"
Cohesion: 0.29
Nodes (6): ScanProgressCoalescer, Bool, Double, String, TimeInterval, ScanProgressCoalescerTests

### Community 122 - "DNS Binary Record Parsing"
Cohesion: 0.38
Nodes (5): Data, Int, String, UInt16, UnsafeRawPointer

### Community 123 - "Observability Service"
Cohesion: 0.24
Nodes (7): ObservabilityService, .isInitialized, State, Bool, Error, String, SentryLevel

### Community 124 - "Speed Test Error"
Cohesion: 0.20
Nodes (7): SpeedTestError, .asNetworkError, cancelled, .errorDescription, serverError, String, SpeedTestErrorTests

### Community 126 - "Heatmap Contract Tests"
Cohesion: 0.20
Nodes (5): HeatmapSurveyModelsContractTests, ProjectSaveLoadContractTests, URL, XCTest, XCTestCase

### Community 130 - "Connection Type"
Cohesion: 0.20
Nodes (8): ConnectionType, cellular, .displayName, ethernet, .iconName, none, wifi, Decoder

### Community 131 - "RSSI Quality"
Cohesion: 0.20
Nodes (9): RSSIQuality, .color, excellent, fair, good, .label, weak, Int (+1 more)

### Community 132 - "DNS Query Result"
Cohesion: 0.27
Nodes (4): DNSQueryResult, .queryTimeText, Double, DNSQueryResultTests

### Community 133 - "Network Monitor Service"
Cohesion: 0.27
Nodes (6): NetworkMonitorService, .statusText, Bool, NWPath, NWPathMonitor, String

### Community 134 - "Scan Display Phase"
Cohesion: 0.20
Nodes (10): ScanDisplayPhase, arpScan, bonjour, companion, done, icmpLatency, idle, resolving (+2 more)

### Community 135 - "DER Certificate Parsing"
Cohesion: 0.36
Nodes (5): Bool, Data, Date, Int, UInt8

### Community 138 - "World Ping Service Protocol"
Cohesion: 0.31
Nodes (5): MainActor, WorldPingServiceProtocol, Int, String, WorldPingRunner

### Community 139 - "Message Type"
Cohesion: 0.22
Nodes (9): MessageType, command, deviceList, error, heartbeat, networkProfile, statusUpdate, targetList (+1 more)

### Community 142 - "Real Scan Pipeline Integration"
Cohesion: 0.31
Nodes (5): ProgressCollector, .values, ScanPipelineRealIntegrationTests, Double, String

### Community 143 - "Survey Mode"
Cohesion: 0.25
Nodes (6): CaseIterable, SurveyMode, arAssisted, arContinuous, blueprint, SurveyModeTests

### Community 144 - "Scan Diff"
Cohesion: 0.25
Nodes (7): ScanDiff, .hasChanges, .summaryText, .totalChanges, Bool, Int, String

### Community 145 - "SSL Certificate Error"
Cohesion: 0.25
Nodes (5): SSLCertificateError, cannotParseCertificate, .errorDescription, noCertificateFound, Security

### Community 146 - "Certificate Authentication Delegate"
Cohesion: 0.25
Nodes (7): CertificateDelegate, URLSession, Void, SecCertificate, URLAuthenticationChallenge, URLCredential, URLSessionDelegate

### Community 151 - "Scan Phase Pipeline"
Cohesion: 0.38
Nodes (4): Phase-Based Network Discovery, ScanPhase, Step, Bool

### Community 153 - "Companion Message Decode Errors"
Cohesion: 0.33
Nodes (4): CompanionMessageDecodeError, .errorDescription, versionMismatch, Decoder

### Community 156 - "Notifications and Observability"
Cohesion: 0.33
Nodes (3): os, Sentry, UserNotifications

### Community 157 - "Probe Result"
Cohesion: 0.33
Nodes (6): ProbeResult, connected, error, refused, timeout, Double

### Community 158 - "Network Route Parsing"
Cohesion: 0.47
Nodes (5): RouteMetrics, RouteMsgHdr, Int32, UInt16, UInt8

### Community 160 - "Shared Package Architecture"
Cohesion: 0.50
Nodes (3): Shared Package Architecture, Cross-Platform Integration Point, PackageDescription

## Knowledge Gaps
- **407 isolated node(s):** `statusUpdate`, `targetList`, `deviceList`, `networkProfile`, `command` (+402 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **40 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Foundation` connect `Discovery Services` to `WiFi Network Models`, `Network Event Type Tests`, `MAC Vendor Lookup Service`, `Scan Pipeline`, `Heatmap Survey State`, `Shared Package Test Coverage`, `World Ping Service Protocol`, `Network Event Service`, `Scan Accumulator`, `Scan Diff`, `Project Save Load Manager`, `SSL Certificate Error`, `Companion Message Models`, `Device Type Inference Gateway Tests`, `Bonjour Scan Phase`, `Formatting Utilities`, `Target Protocol Codable Tests`, `Survey Project`, `Multi-Room Blueprint Construction`, `Scan Phase Pipeline`, `Blueprint Floor`, `Notifications and Observability`, `World Ping Check Result`, `Speed Test Atomic State`, `Network Route Parsing`, `Heatmap Renderer Integration`, `Service Protocol Definitions`, `Heatmap Survey Model Tests`, `Port State Raw Value Tests`, `Port State Tests`, `Blueprint Save Load Manager`, `Sensitive Log Redaction`, `Reverse DNS Scan Phase`, `Navigation Models`, `Tool Activity Item`, `ARP Cache Parsing`, `Persistence Bootstrap`, `Certificate Expiration Tracker`, `Scan Context`, `Companion Payload Models`, `Network Profile Payload`, `Measurement Statistics Models`, `Network Profile Manager`, `Core Enum Model Tests`, `ARP Scan Phase`, `Tool Result`, `Blueprint File Error`, `Device Type`, `Device Name Resolver`, `Geolocation Response Parsing`, `ICMP Socket`, `Mock URL Protocol`, `Resume State`, `Service Utilities Tests`, `Status Type`, `Network Signal Models`, `IPv4 Validation Helpers`, `Floor Plan Rendering`, `WiFi Measurement Engine`, `Companion Frame Decoder`, `RTT Tracker`, `DNS Error Handling`, `Network Profile Models`, `Thermal Throttle Monitor`, `Network Error`, `Scan Engine Timeout Handling`, `Scan Progress Coalescer`?**
  _High betweenness centrality (0.290) - this node is a cross-community bridge._
- **Why does `Testing` connect `Shared Package Test Coverage` to `WiFi Network Models`, `Heatmap Renderer Integration`, `Heatmap Survey Model Tests`, `NetMonitorCore Integration Tags`, `Network Event Type Tests`, `Port State Raw Value Tests`, `Heatmap Survey State`, `Port State Tests`, `NetworkScanKit Integration Tags`, `Blueprint Save Load Manager`, `Navigation Models`, `Project Save Load Manager`, `Discovery Services`, `Companion Message Models`, `Device Type Inference Gateway Tests`, `Bonjour Scan Phase`, `Target Protocol Codable Tests`, `Core Enum Model Tests`?**
  _High betweenness centrality (0.070) - this node is a cross-community bridge._
- **Why does `NetworkProfile` connect `Network Profile Models` to `Connection Type`, `Service Protocol Definitions`, `Persistence Robustness Tests`, `Network Profile Extended Tests`, `Network Profile Manager`, `Network Profile Manager Extended Tests`, `Network Utilities`, `Network Utilities Models`, `Companion Message Coding Keys`, `Companion Payload Models`, `Network Profile Payload`, `Blueprint Floor`, `Network Profile Manager Tests`?**
  _High betweenness centrality (0.047) - this node is a cross-community bridge._
- **Are the 63 inferred relationships involving `ScanAccumulator` (e.g. with `.devicesFromARPHaveLocalSource()` and `.devicesFromARPHaveMacAddress()`) actually correct?**
  _`ScanAccumulator` has 63 INFERRED edges - model-reasoned connections that need verification._
- **What connects `statusUpdate`, `targetList`, `deviceList` to the rest of the system?**
  _407 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `WiFi Network Models` be split into smaller, more focused modules?**
  _Cohesion score 0.07226890756302522 - nodes in this community are weakly interconnected._
- **Should `Network Connection Helper` be split into smaller, more focused modules?**
  _Cohesion score 0.05664568678267309 - nodes in this community are weakly interconnected._