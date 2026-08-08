# Graph Report - Packages  (2026-08-05)

## Corpus Check
- 216 files · ~136,185 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 3857 nodes · 9475 edges · 175 communities (139 shown, 36 thin omitted)
- Extraction: 78% EXTRACTED · 22% INFERRED · 0% AMBIGUOUS · INFERRED: 2119 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- MAC Vendor Lookup Service
- Speed Test Service
- Heatmap Renderer
- Heatmap Survey State
- WHOIS Service
- Companion Message
- Scan Pipeline
- Network Event Service
- Scan Accumulator
- Bonjour Discovery Service
- VPN Detection Service
- World Ping and Geolocation
- WiFi Measurement Test Doubles
- Measurement Point
- Project Save Load Manager
- Network Health Score Service Tests
- Shared Package Test Coverage
- Network Utilities
- Bonjour Scan Phase
- Formatting Utilities
- Device Vendor Type Inference
- Ping Service
- Wake On LAN Service Tests
- Speed Test Atomic State
- Survey Project
- Scan Context
- Blueprint Floor
- World Ping Check Result
- Scan Scheduler Service
- Scan Engine
- Local Device
- Ping Result
- ICMP Packet Encoding Tests
- Geolocation Service
- Service Protocol Definitions
- Apple Networking Frameworks
- Monitoring Target
- Multi-Room Blueprint Construction
- Hostname Device Type Inference
- Traceroute Service
- Sensitive Log Redaction
- Persistence Robustness Tests
- Floor Plan Rendering
- Measurement Statistics Models
- Tool Activity Item
- Device Discovery Service
- Blueprint Save Load Manager
- Network Profile Models
- SSL Certificate Models
- Discovered Device
- Scan Strategy Tests
- Certificate Expiration Tracker
- Certificate Expiration Tracker Tests
- Reverse DNS Scan Phase
- TCP Probe Scan Phase
- ARP Cache Parsing
- Traceroute Hop
- Companion Payload Models
- Blueprint File Error
- DNS Query Parsing
- Connectivity Record
- WiFi Info
- Tool Result
- Check Host Fixtures
- Device Name Resolver
- ARP Scan Phase
- Tool Type Enumeration
- Network Error
- DNS Query Result
- Network Profile Manager
- ICMP Latency Phase
- Device Type
- Target Protocol
- ICMP Socket
- Service Protocol Types Tests
- Heatmap Survey Model Tests
- ISP Info
- Resume State
- Geolocation Response Parsing
- Service Utilities Tests
- Network Signal Models
- Port Scanner Service
- Core Enum Model Tests
- Mock URL Protocol
- Scan Diff Tests
- Connection Budget
- Port Scan Result
- Companion Message Coding Keys
- Network Profile Manager Tests
- SSDP Scan Phase Tests
- Port Probe Outcome
- Gateway Info
- Port Range
- WiFi Measurement Engine
- SSL Certificate Service
- RTT Tracker
- Session Record
- Paired Mac
- Geolocation Models
- DNS Lookup Service
- World Ping Regression Contract Tests
- Network Profile Manager Extended Tests
- Heatmap Visualization
- Network Connection Helper
- DNS Record
- Notification Service
- IPv4 Helper Tests
- Fixture Phase
- History Sparkline
- Command Action
- WHOIS Result
- Port Scanner Service Tests
- SSL Certificate Service Tests
- Port Scan Preset
- DNS Binary Record Parsing
- IPv4 Validation Helpers
- Navigation Section
- Observability Service
- Speed Test Error
- Port Scan Preset Tests
- Heatmap Contract Tests
- Network Error Description Tests
- Network Error User Facing Message
- Network Event Type Tests
- IPv4 CIDR
- Thermal Throttle Monitor
- RSSI Quality
- Network Monitor Service
- Scan Display Phase
- DER Certificate Parsing
- Device Type Inference Services Tests
- Network Profile Extended Tests
- CIDR Parse Error
- World Ping Service Protocol
- Message Type
- Device Type Inference Fallback Tests
- Geolocation Malformed Contract Tests
- Real Scan Pipeline Integration
- Status Type
- Scan Diff
- SSL Certificate Error
- Certificate Authentication Delegate
- Device Type Inference Gateway Tests
- Device Type Inference Port Tests
- Thermal Throttle Monitor Tests
- Scan Engine Progress Tests
- DNS Error
- Device Status
- Speed Test Phase
- IPv4 Address Cleaning
- Floor Plan From Blueprint Tests
- Probe Result
- Network Route Parsing
- Navigation Section Complete Tests
- Connection Type Tests
- Target Protocol Codable Tests
- IPv4 Text Extraction
- Shared Package Architecture
- Survey Mode
- Shared UI Enumerations
- Locked Value
- Progress Counter
- Status Type Tests
- NetMonitorCore Integration Tags
- Survey File Error Tests
- Speed Test Edge Case Contract
- Speed Test Service Cancellation Tests
- NetworkScanKit Integration Tags
- Port State Raw Value Tests
- Port State Tests
- WiFi Measurement Error Tests
- Public IP Test Fixture
- MAC Vendor Test Fixture
- WHOIS Test Fixture

## God Nodes (most connected - your core abstractions)
1. `makeDevice()` - 102 edges
2. `Testing` - 97 edges
3. `ScanAccumulator` - 96 edges
4. `ScanContext` - 77 edges
5. `NetMonitorCore` - 72 edges
6. `DiscoveredDevice` - 67 edges
7. `MeasurementPoint` - 63 edges
8. `SpeedTestService` - 62 edges
9. `ScanPipeline` - 60 edges
10. `HeatmapSurveyState` - 58 edges

## Surprising Connections (you probably didn't know these)
- `DeviceDiscoveryService` --calls--> `ScanEngine`  [INFERRED]
  NetMonitorCore/Sources/NetMonitorCore/Services/DeviceDiscoveryService.swift → NetworkScanKit/Sources/NetworkScanKit/ScanEngine.swift
- `Deterministic Scan Engine Tests` --references--> `ScanEngine`  [EXTRACTED]
  NetworkScanKit/Tests/NetworkScanKitTests/AGENTS.md → NetworkScanKit/Sources/NetworkScanKit/ScanEngine.swift
- `Protocol-First Strict Concurrency` --conceptually_related_to--> `Adaptive Scan Engine`  [INFERRED]
  NetMonitorCore/Sources/NetMonitorCore/AGENTS.md → NetworkScanKit/Sources/NetworkScanKit/AGENTS.md
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

## Communities (175 total, 36 thin omitted)

### Community 0 - "MAC Vendor Lookup Service"
Cohesion: 0.08
Nodes (10): MACVendorLookupService, String, TimeInterval, URLSession, MACVendorContractTests, MACVendorLookupServiceTests, String, MACVendorOnlineContractTests (+2 more)

### Community 1 - "Speed Test Service"
Cohesion: 0.07
Nodes (9): SpeedTestService, Bool, Task, SpeedTestServiceErrorRecoveryTests, SpeedTestServiceIntegrationTests, SpeedTestService2xxRegressionTests, SpeedTestServiceLatencyEdgeCaseTests, SpeedTestServiceSessionTests (+1 more)

### Community 2 - "Heatmap Renderer"
Cohesion: 0.08
Nodes (20): CGImage, CoreGraphics, HeatmapColorScheme, .displayName, plasma, stoplight, thermal, wifiman (+12 more)

### Community 3 - "Heatmap Survey State"
Cohesion: 0.07
Nodes (24): HeatmapSurveyState, .averageRSSI, .canUndo, .filteredPoints, .hasFloorPlan, .maxRSSI, .minRSSI, .uniqueBSSIDs (+16 more)

### Community 4 - "WHOIS Service"
Cohesion: 0.08
Nodes (17): DateFormatter, CheckedContinuation, Data, Date, Error, Int, NWConnection, Sendable (+9 more)

### Community 5 - "Companion Message"
Cohesion: 0.09
Nodes (25): JSONDecoder, JSONEncoder, Companion Wire Format, CompanionMessage, command, deviceList, error, heartbeat (+17 more)

### Community 6 - "Scan Pipeline"
Cohesion: 0.08
Nodes (11): ScanPipeline, Step, Bool, Void, Deterministic Scan Engine Tests, ScanPipelineCoverageTests, SimpleTestPhase, Double (+3 more)

### Community 7 - "Network Event Service"
Cohesion: 0.07
Nodes (28): NetworkEvent, NetworkEventSeverity, error, info, success, warning, NetworkEventType, connectivityChange (+20 more)

### Community 8 - "Scan Accumulator"
Cohesion: 0.12
Nodes (15): devices, ScanAccumulator, .count, .isEmpty, Bool, Double, Int, Set (+7 more)

### Community 9 - "Bonjour Discovery Service"
Cohesion: 0.09
Nodes (15): BonjourService, .fullType, .serviceCategory, BonjourDiscoveryService, AsyncStream, Bool, Never, Set (+7 more)

### Community 10 - "VPN Detection Service"
Cohesion: 0.06
Nodes (22): AsyncStream, Bool, Date, NWPath, NWPathMonitor, String, UUID, VPNDetectionService (+14 more)

### Community 11 - "World Ping and Geolocation"
Cohesion: 0.10
Nodes (18): LocalizedError, GlobalpingError, .errorDescription, pollFailed, submitFailed, Any, AsyncStream, Int (+10 more)

### Community 12 - "WiFi Measurement Test Doubles"
Cohesion: 0.15
Nodes (15): CLAuthorizationStatus, SpeedTestData, makeTestPingResult(), makeTestWiFiInfo(), MockPingService, MockSpeedTestService, MockWiFiInfoService, AsyncStream (+7 more)

### Community 13 - "Measurement Point"
Cohesion: 0.07
Nodes (6): MeasurementPoint, .averageRSSI, Bool, HeatmapVisualizationTests, MeasurementPointTests, HeatmapVisualizationExtractionTests

### Community 14 - "Project Save Load Manager"
Cohesion: 0.12
Nodes (22): ProjectSaveLoadManager, SurveyFileError, bundleNotFound, corruptedJSON, floorPlanImageMissing, .localizedDescription, surveyJSONMissing, writeFailed (+14 more)

### Community 15 - "Network Health Score Service Tests"
Cohesion: 0.08
Nodes (6): NetworkHealthScoreService, Bool, Double, Int, String, NetworkHealthScoreServiceTests

### Community 16 - "Shared Package Test Coverage"
Cohesion: 0.08
Nodes (4): NetMonitorCore, WorldPingServiceConcurrencyTests, NetworkScanKit, Testing

### Community 17 - "Network Utilities"
Cohesion: 0.08
Nodes (11): Hashable, Canonical Network Math, IPv4Network, .prefixLength, NetworkUtilities, Bool, Int, String (+3 more)

### Community 18 - "Bonjour Scan Phase"
Cohesion: 0.10
Nodes (17): BonjourServiceInfo, String, .ipSortKey, Int, BonjourScanPhase, Double, Duration, Int (+9 more)

### Community 19 - "Formatting Utilities"
Cohesion: 0.09
Nodes (12): formatDuration(), formatSpeed(), Bool, Double, String, TimeInterval, .downloadSpeedText, .uploadSpeedText (+4 more)

### Community 20 - "Device Vendor Type Inference"
Cohesion: 0.09
Nodes (5): DeviceTypeInferenceVendorTests, makeDevice(), Bool, Int, String

### Community 21 - "Ping Service"
Cohesion: 0.12
Nodes (14): DateRef, PingService, AsyncStream, Bool, Int, String, TimeInterval, UUID (+6 more)

### Community 22 - "Wake On LAN Service Tests"
Cohesion: 0.09
Nodes (10): WakeOnLANResult, Bool, Data, String, UInt16, UInt8, WakeOnLANService, Data (+2 more)

### Community 23 - "Speed Test Atomic State"
Cohesion: 0.13
Nodes (18): Int64, SpeedTestServer, AtomicInt64, DownloadMeasurementDelegate, Data, Date, Double, Error (+10 more)

### Community 24 - "Survey Project"
Cohesion: 0.10
Nodes (21): CalibrationPoint, FloorPlan, .metersPerPixelX, .metersPerPixelY, FloorPlanOrigin, arGenerated, drawn, imported (+13 more)

### Community 25 - "Scan Context"
Cohesion: 0.09
Nodes (15): Discovery Phase Portfolio, SSDPScanPhase, Double, String, ScanContext, Bool, String, ScanContextTests (+7 more)

### Community 26 - "Blueprint Floor"
Cohesion: 0.13
Nodes (17): Equatable, Identifiable, BlueprintFloor, BlueprintMetadata, BlueprintProject, RoomLabel, Bool, Data (+9 more)

### Community 27 - "World Ping Check Result"
Cohesion: 0.12
Nodes (12): Date, Double, Int, String, WorldPingCheckResult, .averageLatencyMs, .maximumLatencyMs, .minimumLatencyMs (+4 more)

### Community 28 - "Scan Scheduler Service"
Cohesion: 0.14
Nodes (8): ScanSchedulerService, .isScanDue, Bool, Date, TimeInterval, ScanSchedulerServiceTests, String, ScanDiff

### Community 29 - "Scan Engine"
Cohesion: 0.19
Nodes (12): ScanEngine, Duration, Sendable, Void, ProgressCollector, .values, ProgressRecorder, ScanEngineCoverageTests (+4 more)

### Community 30 - "Local Device"
Cohesion: 0.12
Nodes (12): LocalDevice, .displayName, .formattedMacAddress, .latencyText, Bool, Date, Double, Int (+4 more)

### Community 31 - "Ping Result"
Cohesion: 0.11
Nodes (14): PingMethod, icmp, tcp, PingResult, .timeText, PingStatistics, .packetLossText, .successRate (+6 more)

### Community 32 - "ICMP Packet Encoding Tests"
Cohesion: 0.09
Nodes (8): ICMPType, echoReply, echoRequest, timeExceeded, Double, ICMPSocketTests, Int, UInt8

### Community 33 - "Geolocation Service"
Cohesion: 0.15
Nodes (7): HTTPURLResponse, GeoLocationService, String, URLSession, GeoLocationExtendedContractTests, String, GeoLocationServiceTests

### Community 34 - "Service Protocol Definitions"
Cohesion: 0.14
Nodes (30): AnyObject, CoreLocation, Shared Service Protocol Contract, BonjourDiscoveryServiceProtocol, CertificateExpirationTrackerProtocol, DeviceDiscoveryServiceProtocol, DeviceNameResolverProtocol, DNSLookupServiceProtocol (+22 more)

### Community 35 - "Apple Networking Frameworks"
Cohesion: 0.09
Nodes (7): Foundation, Notification.Name, Network, os, os.log, Sentry, UserNotifications

### Community 36 - "Monitoring Target"
Cohesion: 0.11
Nodes (14): MonitoringTarget, .hostWithPort, .latencyText, .statusType, .uptimePercentage, .uptimeText, Bool, Date (+6 more)

### Community 37 - "Multi-Room Blueprint Construction"
Cohesion: 0.14
Nodes (10): Bounds, CapturedRoomGeometry, MultiRoomBlueprintBuilder, Double, Int, String, MultiRoomBlueprintBuilderTests, Double (+2 more)

### Community 39 - "Traceroute Service"
Cohesion: 0.17
Nodes (9): AsyncStream, Bool, Int, Int32, String, TimeInterval, UInt16, TracerouteService (+1 more)

### Community 40 - "Sensitive Log Redaction"
Cohesion: 0.11
Nodes (3): LogSanitizer, String, LogSanitizerTests

### Community 41 - "Persistence Robustness Tests"
Cohesion: 0.17
Nodes (7): CertificateExpirationTrackerRobustnessTests, makeFreshDefaults(), NetworkProfileManagerRobustnessTests, StubSSL, StubWHOIS, String, UserDefaults

### Community 42 - "Floor Plan Rendering"
Cohesion: 0.13
Nodes (13): AppKit, WallSegment, renderWallsToPNG(), renderWithUIKit(), SVGFloorPlanGenerator, SVGRenderer, Data, Double (+5 more)

### Community 43 - "Measurement Statistics Models"
Cohesion: 0.11
Nodes (14): MeasurementStatistics, .averageLatencyFormatted, .maxLatencyFormatted, .minLatencyFormatted, .uptimeFormatted, Bool, Date, Double (+6 more)

### Community 44 - "Tool Activity Item"
Cohesion: 0.15
Nodes (9): Bool, Date, String, ToolActivityItem, .timeAgoText, ToolActivityLog, ToolActivityItemTests, ToolActivityLogTests (+1 more)

### Community 45 - "Device Discovery Service"
Cohesion: 0.15
Nodes (15): DeviceDiscoveryService, ScanFilter, network, prefix, ScanTarget, Bool, Date, Double (+7 more)

### Community 46 - "Blueprint Save Load Manager"
Cohesion: 0.21
Nodes (12): BlueprintSaveLoadManager, BlueprintLoadErrorTests, BlueprintLoadRoundTripTests, BlueprintSaveTests, makeFloor(), makeProject(), makeTempDir(), makeWall() (+4 more)

### Community 47 - "Network Profile Models"
Cohesion: 0.11
Nodes (21): ConnectionType, cellular, .displayName, ethernet, .iconName, none, wifi, Decoder (+13 more)

### Community 48 - "SSL Certificate Models"
Cohesion: 0.10
Nodes (3): SSLCertificateInfo, SSLCertificateContractTests, String

### Community 49 - "Discovered Device"
Cohesion: 0.11
Nodes (12): DeviceSource, bonjour, local, macCompanion, ssdp, DiscoveredDevice, .displayName, .latencyText (+4 more)

### Community 50 - "Scan Strategy Tests"
Cohesion: 0.10
Nodes (6): NetworkScanProfile, ScanStrategy, full, remote, String, ScanStrategyCoverageTests

### Community 51 - "Certificate Expiration Tracker"
Cohesion: 0.17
Nodes (10): CertificateExpirationTracker, Int, String, UserDefaults, TrackedEntry, .id, DomainExpirationStatus, .domainDaysUntilExpiration (+2 more)

### Community 52 - "Certificate Expiration Tracker Tests"
Cohesion: 0.19
Nodes (4): CertificateExpirationTrackerTests, StubWHOISService, String, UserDefaults

### Community 53 - "Reverse DNS Scan Phase"
Cohesion: 0.17
Nodes (7): ReverseDNSScanPhase, Double, Int, RDNSProgressCollector, .values, ReverseDNSScanPhaseTests, Double

### Community 54 - "TCP Probe Scan Phase"
Cohesion: 0.18
Nodes (6): Int, TCPProbeScanPhase, Double, TCPProbeScanPhaseTests, TCPProgressCollector, .values

### Community 55 - "ARP Cache Parsing"
Cohesion: 0.15
Nodes (11): CChar, ARPCacheScanner, RouteMetrics, RouteMsgHdr, SockaddrDL, Int, Int32, String (+3 more)

### Community 56 - "Traceroute Hop"
Cohesion: 0.12
Nodes (6): TracerouteHop, .averageTime, .displayAddress, .timeText, TracerouteHopTests, TracerouteServiceTests

### Community 57 - "Companion Payload Models"
Cohesion: 0.17
Nodes (15): Codable, CompanionMessageDecodeError, .errorDescription, versionMismatch, ErrorPayload, StatusUpdatePayload, Bool, Date (+7 more)

### Community 58 - "Blueprint File Error"
Cohesion: 0.12
Nodes (13): BlueprintFileError, archiveExtractionFailed, blueprintJSONMissing, bundleNotFound, corruptedJSON, .localizedDescription, svgMissing, writeFailed (+5 more)

### Community 59 - "DNS Query Parsing"
Cohesion: 0.12
Nodes (17): DNSServiceRef, DNSRecordType, a, aaaa, cname, .displayName, mx, ns (+9 more)

### Community 60 - "Connectivity Record"
Cohesion: 0.16
Nodes (10): ConnectivityRecord, Bool, Date, Double, String, UUID, ConnectivityRecordTests, LocalDeviceLatencyHistoryTests (+2 more)

### Community 61 - "WiFi Info"
Cohesion: 0.14
Nodes (5): WiFiInfo, .signalBars, .signalQuality, WiFiInfoSignalBarsTests, WiFiInfoSignalQualityTests

### Community 62 - "Tool Result"
Cohesion: 0.14
Nodes (13): SpeedTestResult, .latencyText, Bool, Date, Double, String, TimeInterval, UUID (+5 more)

### Community 63 - "Check Host Fixtures"
Cohesion: 0.15
Nodes (4): CheckHostContractTests, Any, Data, String

### Community 64 - "Device Name Resolver"
Cohesion: 0.19
Nodes (3): DeviceNameResolver, String, DeviceNameResolverTests

### Community 65 - "ARP Scan Phase"
Cohesion: 0.18
Nodes (6): ARPScanPhase, Double, ARPScanPhaseTests, ProgressCollector, .values, Double

### Community 66 - "Tool Type Enumeration"
Cohesion: 0.09
Nodes (23): ToolType, bonjourDiscovery, .color, .displayName, dnsLookup, exportPdf, geoTrace, .iconName (+15 more)

### Community 67 - "Network Error"
Cohesion: 0.11
Nodes (16): NetworkError, cancelled, connectionFailed, dnsLookupFailed, .errorDescription, invalidHost, invalidResponse, noNetwork (+8 more)

### Community 68 - "DNS Query Result"
Cohesion: 0.10
Nodes (4): DNSQueryResult, .queryTimeText, DNSLookupServiceTests, DNSQueryResultTests

### Community 69 - "Network Profile Manager"
Cohesion: 0.19
Nodes (9): CIDRDescriptor, NetworkProfileManager, Bool, Date, Int, Sendable, String, UserDefaults (+1 more)

### Community 70 - "ICMP Latency Phase"
Cohesion: 0.13
Nodes (12): Phase-Based Network Discovery, ICMPLatencyPhase, Double, Int, Int32, String, TimeInterval, UInt16 (+4 more)

### Community 71 - "Device Type"
Cohesion: 0.10
Nodes (17): DeviceType, camera, computer, .displayName, gaming, .iconName, iot, laptop (+9 more)

### Community 72 - "Target Protocol"
Cohesion: 0.13
Nodes (16): Encoder, TargetProtocol, .defaultPort, .displayName, http, https, icmp, tcp (+8 more)

### Community 73 - "ICMP Socket"
Cohesion: 0.21
Nodes (13): ICMPResponse, ICMPSocket, Kind, echoReply, error, timeExceeded, timeout, Int (+5 more)

### Community 74 - "Service Protocol Types Tests"
Cohesion: 0.11
Nodes (9): DiscoveredMac, MacConnectionState, browsing, connected, connecting, disconnected, error, .isConnected (+1 more)

### Community 75 - "Heatmap Survey Model Tests"
Cohesion: 0.12
Nodes (10): CalibrationPointTests, FloorPlanOriginTests, makeFloorPlan(), makeSurveyProject(), SurveyModeTests, SurveyProjectTests, Data, Double (+2 more)

### Community 76 - "ISP Info"
Cohesion: 0.14
Nodes (6): CachedResult, ISPInfo, ISPLookupCacheContractTests, Date, String, ISPInfoLocationTextTests

### Community 77 - "Resume State"
Cohesion: 0.19
Nodes (4): ResumeStateTests, ResumeState, Bool, ResumeStateTests

### Community 78 - "Geolocation Response Parsing"
Cohesion: 0.10
Nodes (18): Decodable, CodingKeys, city, country, countryCode, isp, lat, lon (+10 more)

### Community 79 - "Service Utilities Tests"
Cohesion: 0.18
Nodes (5): in_addr, ServiceUtilities, Bool, String, ServiceUtilitiesTests

### Community 80 - "Network Signal Models"
Cohesion: 0.12
Nodes (17): ISPInfo, .locationText, SignalQuality, .color, excellent, fair, good, poor (+9 more)

### Community 81 - "Port Scanner Service"
Cohesion: 0.19
Nodes (8): PortScannerService, AsyncStream, Bool, Int, String, TimeInterval, UUID, PortScannerServiceIntegrationTests

### Community 82 - "Core Enum Model Tests"
Cohesion: 0.10
Nodes (5): DeviceStatusTests, DeviceTypeTests, DNSRecordTypeTests, TargetProtocolTests, ToolTypeTests

### Community 83 - "Mock URL Protocol"
Cohesion: 0.21
Nodes (9): MockHandlerStore, MockURLProtocol, .requestHandler, Bool, Data, Int, String, URLProtocol (+1 more)

### Community 85 - "Connection Budget"
Cohesion: 0.19
Nodes (8): ConnectionBudget, .activeCount, .effectiveLimit, CheckedContinuation, Int, Never, Void, ConnectionBudgetTests

### Community 86 - "Port Scan Result"
Cohesion: 0.15
Nodes (8): PortScanResult, PortState, closed, .displayName, filtered, open, PortScanResultFieldTests, PortScanResultTests

### Community 87 - "Companion Message Coding Keys"
Cohesion: 0.11
Nodes (19): CodingKey, CodingKeys, payload, protocolVersion, type, CodingKeys, connectionType, deviceCount (+11 more)

### Community 88 - "Network Profile Manager Tests"
Cohesion: 0.28
Nodes (5): Shared Foundation Test Suite, NetworkProfileManagerTests, Bool, String, UserDefaults

### Community 90 - "Port Probe Outcome"
Cohesion: 0.16
Nodes (14): PortProbeOutcome, failed, reachable, refused, timeout, ProbeGroupResult, allFailed, allTimedOut (+6 more)

### Community 91 - "Gateway Info"
Cohesion: 0.18
Nodes (7): ISPInfo, GatewayInfo, .latencyText, NetworkStatus, Bool, GatewayInfoLatencyTextTests, NetworkStatusTests

### Community 92 - "Port Range"
Cohesion: 0.18
Nodes (7): PortRange, .count, .isEmpty, .isValid, .ports, Int, PortRangeTests

### Community 93 - "WiFi Measurement Engine"
Cohesion: 0.22
Nodes (8): AsyncStream, Double, Never, String, Task, TimeInterval, Void, WiFiMeasurementEngine

### Community 94 - "SSL Certificate Service"
Cohesion: 0.26
Nodes (3): SSLCertificateService, String, SSLCertificateServiceIntegrationTests

### Community 95 - "RTT Tracker"
Cohesion: 0.27
Nodes (5): RTTTracker, .sampleCount, Double, Int, RTTTrackerTests

### Community 96 - "Session Record"
Cohesion: 0.15
Nodes (6): SessionRecord, Bool, Date, UUID, SessionRecordTests, SwiftData

### Community 97 - "Paired Mac"
Cohesion: 0.20
Nodes (9): PairedMac, .connectionStatusText, .displayAddress, Bool, Date, Int, String, UUID (+1 more)

### Community 98 - "Geolocation Models"
Cohesion: 0.24
Nodes (7): GeoLocation, NetworkHealthScore, SubnetInfo, Bool, Double, Int, String

### Community 99 - "DNS Lookup Service"
Cohesion: 0.27
Nodes (4): DNSServiceQueryRecordReply, DNSLookupService, Bool, DNSLookupServiceIntegrationTests

### Community 100 - "World Ping Regression Contract Tests"
Cohesion: 0.20
Nodes (6): GeoLocationServiceATSRegressionTests, Data, String, URL, URLSession, WorldPingRegressionContractTests

### Community 101 - "Network Profile Manager Extended Tests"
Cohesion: 0.38
Nodes (3): NetworkProfileManagerExtendedTests, String, UserDefaults

### Community 102 - "Heatmap Visualization"
Cohesion: 0.14
Nodes (14): ClosedRange, HeatmapVisualization, .displayName, downloadSpeed, frequencyBand, .isHigherBetter, latency, noiseFloor (+6 more)

### Community 103 - "Network Connection Helper"
Cohesion: 0.18
Nodes (10): DispatchQueue, NWConnectionResolution, complete, completeKeepAlive, Duration, NWConnection, Sendable, T (+2 more)

### Community 104 - "DNS Record"
Cohesion: 0.25
Nodes (3): DNSRecord, .ttlText, DNSRecordTTLTextTests

### Community 105 - "Notification Service"
Cohesion: 0.19
Nodes (6): Keys, NotificationService, .isAuthorized, Bool, Double, String

### Community 107 - "Fixture Phase"
Cohesion: 0.37
Nodes (6): FixturePhase, ProgressRecorder, ScanEngineTests, Double, String, Update

### Community 108 - "History Sparkline"
Cohesion: 0.26
Nodes (10): CGFloat, Color, String, HistorySparkline, .body, Bool, CGPoint, Double (+2 more)

### Community 109 - "Command Action"
Cohesion: 0.17
Nodes (12): CommandAction, dnsLookup, ping, portScan, refreshDevices, refreshTargets, scanDevices, startMonitoring (+4 more)

### Community 110 - "WHOIS Result"
Cohesion: 0.23
Nodes (5): Date, WHOISResult, .daysUntilExpiration, .domainAge, WHOISResultTests

### Community 113 - "Port Scan Preset"
Cohesion: 0.17
Nodes (12): PortScanPreset, common, custom, database, .displayName, extended, .isCustom, mail (+4 more)

### Community 114 - "DNS Binary Record Parsing"
Cohesion: 0.39
Nodes (6): Data, Int, String, UInt16, UnsafeRawPointer, UInt32

### Community 115 - "IPv4 Validation Helpers"
Cohesion: 0.20
Nodes (6): IPv4Helpers, isValidIPv4Address(), String, Bool, Int, String

### Community 116 - "Navigation Section"
Cohesion: 0.18
Nodes (6): NavigationSection, .iconName, .id, settings, tools, NavigationSectionTests

### Community 117 - "Observability Service"
Cohesion: 0.24
Nodes (7): ObservabilityService, .isInitialized, State, Bool, Error, String, SentryLevel

### Community 118 - "Speed Test Error"
Cohesion: 0.20
Nodes (7): SpeedTestError, .asNetworkError, cancelled, .errorDescription, serverError, String, SpeedTestErrorTests

### Community 120 - "Heatmap Contract Tests"
Cohesion: 0.20
Nodes (5): HeatmapSurveyModelsContractTests, ProjectSaveLoadContractTests, URL, XCTest, XCTestCase

### Community 124 - "IPv4 CIDR"
Cohesion: 0.18
Nodes (5): IPv4CIDR, .broadcastAddress, .firstHost, .lastHost, .usableHostCount

### Community 125 - "Thermal Throttle Monitor"
Cohesion: 0.24
Nodes (7): Protocol-First Strict Concurrency, Adaptive Scan Engine, Double, ThermalThrottleMonitor, .multiplier, NSObjectProtocol, ProcessInfo

### Community 126 - "RSSI Quality"
Cohesion: 0.20
Nodes (9): RSSIQuality, .color, excellent, fair, good, .label, weak, Int (+1 more)

### Community 127 - "Network Monitor Service"
Cohesion: 0.27
Nodes (6): NetworkMonitorService, .statusText, Bool, NWPath, NWPathMonitor, String

### Community 128 - "Scan Display Phase"
Cohesion: 0.20
Nodes (10): ScanDisplayPhase, arpScan, bonjour, companion, done, icmpLatency, idle, resolving (+2 more)

### Community 129 - "DER Certificate Parsing"
Cohesion: 0.36
Nodes (5): Bool, Data, Date, Int, UInt8

### Community 132 - "CIDR Parse Error"
Cohesion: 0.22
Nodes (9): Error, ICMPError, invalidAddress, sendFailed, socketCreationFailed, CIDRParseError, invalidFormat, invalidIPAddress (+1 more)

### Community 133 - "World Ping Service Protocol"
Cohesion: 0.31
Nodes (5): MainActor, WorldPingServiceProtocol, Int, String, WorldPingRunner

### Community 134 - "Message Type"
Cohesion: 0.22
Nodes (9): MessageType, command, deviceList, error, heartbeat, networkProfile, statusUpdate, targetList (+1 more)

### Community 137 - "Real Scan Pipeline Integration"
Cohesion: 0.31
Nodes (5): ProgressCollector, .values, ScanPipelineRealIntegrationTests, Double, String

### Community 138 - "Status Type"
Cohesion: 0.25
Nodes (8): StatusType, .color, .icon, idle, .label, offline, online, unknown

### Community 139 - "Scan Diff"
Cohesion: 0.25
Nodes (7): ScanDiff, .hasChanges, .summaryText, .totalChanges, Bool, Int, String

### Community 140 - "SSL Certificate Error"
Cohesion: 0.25
Nodes (5): SSLCertificateError, cannotParseCertificate, .errorDescription, noCertificateFound, Security

### Community 141 - "Certificate Authentication Delegate"
Cohesion: 0.25
Nodes (7): CertificateDelegate, URLSession, Void, SecCertificate, URLAuthenticationChallenge, URLCredential, URLSessionDelegate

### Community 145 - "Scan Engine Progress Tests"
Cohesion: 0.36
Nodes (6): ProgressCollector, .values, StubPhase, .displayName, Double, String

### Community 146 - "DNS Error"
Cohesion: 0.29
Nodes (6): dnssd, DNSError, .asNetworkError, .errorDescription, lookupFailed, timeout

### Community 147 - "Device Status"
Cohesion: 0.29
Nodes (6): DeviceStatus, .color, idle, offline, online, .statusType

### Community 148 - "Speed Test Phase"
Cohesion: 0.29
Nodes (6): SpeedTestPhase, complete, download, idle, latency, upload

### Community 151 - "Probe Result"
Cohesion: 0.33
Nodes (6): ProbeResult, connected, error, refused, timeout, Double

### Community 152 - "Network Route Parsing"
Cohesion: 0.47
Nodes (5): RouteMetrics, RouteMsgHdr, Int32, UInt16, UInt8

### Community 157 - "Shared Package Architecture"
Cohesion: 0.50
Nodes (3): Shared Package Architecture, Cross-Platform Integration Point, PackageDescription

### Community 158 - "Survey Mode"
Cohesion: 0.40
Nodes (5): CaseIterable, SurveyMode, arAssisted, arContinuous, blueprint

### Community 160 - "Locked Value"
Cohesion: 0.60
Nodes (3): LockedValue, .getValue, T

### Community 161 - "Progress Counter"
Cohesion: 0.50
Nodes (3): ProgressCounter, .value, Int

## Knowledge Gaps
- **401 isolated node(s):** `statusUpdate`, `targetList`, `deviceList`, `networkProfile`, `command` (+396 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **36 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Foundation` connect `Apple Networking Frameworks` to `MAC Vendor Lookup Service`, `Speed Test Service`, `Heatmap Renderer`, `Heatmap Survey State`, `WHOIS Service`, `Companion Message`, `Network Event Service`, `VPN Detection Service`, `WiFi Measurement Test Doubles`, `Project Save Load Manager`, `Shared Package Test Coverage`, `Bonjour Scan Phase`, `Formatting Utilities`, `Ping Service`, `Wake On LAN Service Tests`, `Speed Test Atomic State`, `Survey Project`, `Blueprint Floor`, `World Ping Check Result`, `Scan Scheduler Service`, `Scan Engine`, `Ping Result`, `ICMP Packet Encoding Tests`, `Geolocation Service`, `Service Protocol Definitions`, `Multi-Room Blueprint Construction`, `Traceroute Service`, `Sensitive Log Redaction`, `Persistence Robustness Tests`, `Floor Plan Rendering`, `Tool Activity Item`, `Blueprint Save Load Manager`, `Network Profile Models`, `SSL Certificate Models`, `Scan Strategy Tests`, `Certificate Expiration Tracker`, `Certificate Expiration Tracker Tests`, `Reverse DNS Scan Phase`, `TCP Probe Scan Phase`, `ARP Cache Parsing`, `Traceroute Hop`, `Companion Payload Models`, `Blueprint File Error`, `Connectivity Record`, `Tool Result`, `Check Host Fixtures`, `Device Name Resolver`, `ARP Scan Phase`, `Network Error`, `DNS Query Result`, `Network Profile Manager`, `ICMP Latency Phase`, `ICMP Socket`, `Service Protocol Types Tests`, `Heatmap Survey Model Tests`, `ISP Info`, `Resume State`, `Geolocation Response Parsing`, `Service Utilities Tests`, `Network Signal Models`, `Core Enum Model Tests`, `Mock URL Protocol`, `Connection Budget`, `Network Profile Manager Tests`, `Gateway Info`, `WiFi Measurement Engine`, `SSL Certificate Service`, `RTT Tracker`, `Session Record`, `DNS Lookup Service`, `World Ping Regression Contract Tests`, `Network Profile Manager Extended Tests`, `SSL Certificate Service Tests`, `IPv4 Validation Helpers`, `Navigation Section`, `Network Event Type Tests`, `Thermal Throttle Monitor`, `World Ping Service Protocol`, `Scan Diff`, `SSL Certificate Error`, `Device Type Inference Gateway Tests`, `DNS Error`, `Network Route Parsing`, `Shared UI Enumerations`?**
  _High betweenness centrality (0.262) - this node is a cross-community bridge._
- **Why does `Testing` connect `Shared Package Test Coverage` to `MAC Vendor Lookup Service`, `Speed Test Service`, `Heatmap Renderer`, `Heatmap Survey State`, `WHOIS Service`, `Companion Message`, `VPN Detection Service`, `WiFi Measurement Test Doubles`, `Device Type Inference Gateway Tests`, `Network Health Score Service Tests`, `Project Save Load Manager`, `Network Utilities`, `Bonjour Scan Phase`, `Formatting Utilities`, `Ping Service`, `Wake On LAN Service Tests`, `Blueprint Floor`, `Scan Engine`, `ICMP Packet Encoding Tests`, `Geolocation Service`, `NetMonitorCore Integration Tags`, `Apple Networking Frameworks`, `Multi-Room Blueprint Construction`, `Traceroute Service`, `Sensitive Log Redaction`, `Persistence Robustness Tests`, `Floor Plan Rendering`, `NetworkScanKit Integration Tags`, `Blueprint Save Load Manager`, `SSL Certificate Models`, `Certificate Expiration Tracker Tests`, `Reverse DNS Scan Phase`, `TCP Probe Scan Phase`, `Traceroute Hop`, `Connectivity Record`, `Check Host Fixtures`, `ARP Scan Phase`, `Network Error`, `DNS Query Result`, `Service Protocol Types Tests`, `Heatmap Survey Model Tests`, `ISP Info`, `Resume State`, `Service Utilities Tests`, `Core Enum Model Tests`, `Network Profile Manager Tests`, `Gateway Info`, `SSL Certificate Service`, `Session Record`, `DNS Lookup Service`, `World Ping Regression Contract Tests`, `Network Profile Manager Extended Tests`, `SSL Certificate Service Tests`, `Network Event Type Tests`?**
  _High betweenness centrality (0.079) - this node is a cross-community bridge._
- **Why does `NetMonitorCore` connect `Shared Package Test Coverage` to `MAC Vendor Lookup Service`, `Speed Test Service`, `Heatmap Renderer`, `Heatmap Survey State`, `WHOIS Service`, `Companion Message`, `VPN Detection Service`, `WiFi Measurement Test Doubles`, `Device Type Inference Gateway Tests`, `Network Health Score Service Tests`, `Project Save Load Manager`, `Network Utilities`, `Formatting Utilities`, `Ping Service`, `Wake On LAN Service Tests`, `Blueprint Floor`, `ICMP Packet Encoding Tests`, `Geolocation Service`, `Multi-Room Blueprint Construction`, `Traceroute Service`, `Sensitive Log Redaction`, `Persistence Robustness Tests`, `Floor Plan Rendering`, `Blueprint Save Load Manager`, `SSL Certificate Models`, `Certificate Expiration Tracker Tests`, `Traceroute Hop`, `Connectivity Record`, `Check Host Fixtures`, `Network Error`, `DNS Query Result`, `Service Protocol Types Tests`, `Heatmap Survey Model Tests`, `ISP Info`, `Resume State`, `Service Utilities Tests`, `Core Enum Model Tests`, `Network Profile Manager Tests`, `Gateway Info`, `SSL Certificate Service`, `Session Record`, `DNS Lookup Service`, `World Ping Regression Contract Tests`, `Network Profile Manager Extended Tests`, `SSL Certificate Service Tests`, `Heatmap Contract Tests`, `Network Event Type Tests`?**
  _High betweenness centrality (0.045) - this node is a cross-community bridge._
- **Are the 63 inferred relationships involving `ScanAccumulator` (e.g. with `.devicesFromARPHaveLocalSource()` and `.devicesFromARPHaveMacAddress()`) actually correct?**
  _`ScanAccumulator` has 63 INFERRED edges - model-reasoned connections that need verification._
- **What connects `statusUpdate`, `targetList`, `deviceList` to the rest of the system?**
  _401 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `MAC Vendor Lookup Service` be split into smaller, more focused modules?**
  _Cohesion score 0.07643600180913614 - nodes in this community are weakly interconnected._
- **Should `Speed Test Service` be split into smaller, more focused modules?**
  _Cohesion score 0.06778846153846153 - nodes in this community are weakly interconnected._