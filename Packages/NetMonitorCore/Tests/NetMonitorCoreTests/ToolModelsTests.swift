import Foundation
import Testing
@testable import NetMonitorCore

// MARK: - PingResult

@Suite("PingResult.timeText")
struct PingResultTimeTextTests {
    @Test func timeoutReturnsTimeoutString() {
        let result = PingResult(sequence: 1, host: "host", ttl: 64, time: 0, isTimeout: true)
        #expect(result.timeText == "timeout")
    }

    @Test func subOneMillisecondFormattedWithTwoDecimals() {
        let result = PingResult(sequence: 1, host: "host", ttl: 64, time: 0.5)
        #expect(result.timeText == "0.50 ms")
    }

    @Test func exactly1msFormattedWithOneDecimal() {
        let result = PingResult(sequence: 1, host: "host", ttl: 64, time: 1.0)
        #expect(result.timeText == "1.0 ms")
    }

    @Test func normalLatencyFormattedWithOneDecimal() {
        let result = PingResult(sequence: 1, host: "host", ttl: 64, time: 24.7)
        #expect(result.timeText == "24.7 ms")
    }

    @Test func largeLatencyFormattedWithOneDecimal() {
        let result = PingResult(sequence: 1, host: "host", ttl: 64, time: 200.0)
        #expect(result.timeText == "200.0 ms")
    }

    @Test func verySmallTimeFormattedWithTwoDecimals() {
        let result = PingResult(sequence: 1, host: "host", ttl: 64, time: 0.99)
        #expect(result.timeText == "0.99 ms")
    }
}

// MARK: - PingStatistics

@Suite("PingStatistics")
struct PingStatisticsTests {
    @Test func packetLossTextZeroPercent() {
        let stats = PingStatistics(host: "h", transmitted: 4, received: 4, packetLoss: 0, minTime: 1, maxTime: 5, avgTime: 3)
        #expect(stats.packetLossText == "0.0%")
    }

    @Test func packetLossTextFullLoss() {
        let stats = PingStatistics(host: "h", transmitted: 4, received: 0, packetLoss: 100, minTime: 0, maxTime: 0, avgTime: 0)
        #expect(stats.packetLossText == "100.0%")
    }

    @Test func packetLossTextPartialLoss() {
        let stats = PingStatistics(host: "h", transmitted: 3, received: 2, packetLoss: 33.3333, minTime: 1, maxTime: 5, avgTime: 3)
        #expect(stats.packetLossText == "33.3%")
    }

    @Test func successRateWithAllReceived() {
        let stats = PingStatistics(host: "h", transmitted: 4, received: 4, packetLoss: 0, minTime: 1, maxTime: 5, avgTime: 3)
        #expect(stats.successRate == 100.0)
    }

    @Test func successRateWithPartialLoss() {
        let stats = PingStatistics(host: "h", transmitted: 4, received: 3, packetLoss: 25, minTime: 1, maxTime: 5, avgTime: 3)
        #expect(stats.successRate == 75.0)
    }

    @Test func successRateWithZeroTransmittedIsZero() {
        let stats = PingStatistics(host: "h", transmitted: 0, received: 0, packetLoss: 0, minTime: 0, maxTime: 0, avgTime: 0)
        #expect(stats.successRate == 0.0)
    }

    @Test func successRateWithNoneReceived() {
        let stats = PingStatistics(host: "h", transmitted: 5, received: 0, packetLoss: 100, minTime: 0, maxTime: 0, avgTime: 0)
        #expect(stats.successRate == 0.0)
    }
}

// MARK: - TracerouteHop

@Suite("TracerouteHop")
struct TracerouteHopTests {
    @Test func displayAddressForTimeoutIsAsterisk() {
        let hop = TracerouteHop(hopNumber: 1, isTimeout: true)
        #expect(hop.displayAddress == "*")
    }

    @Test func displayAddressPrefersHostnameOverIP() {
        let hop = TracerouteHop(hopNumber: 1, ipAddress: "1.2.3.4", hostname: "router.local")
        #expect(hop.displayAddress == "router.local")
    }

    @Test func displayAddressFallsBackToIPWhenNoHostname() {
        let hop = TracerouteHop(hopNumber: 1, ipAddress: "1.2.3.4")
        #expect(hop.displayAddress == "1.2.3.4")
    }

    @Test func displayAddressIsAsteriskWhenNoIPOrHostname() {
        let hop = TracerouteHop(hopNumber: 1)
        #expect(hop.displayAddress == "*")
    }

    @Test func averageTimeWithEmptyTimesIsNil() {
        let hop = TracerouteHop(hopNumber: 1, times: [])
        #expect(hop.averageTime == nil)
    }

    @Test func averageTimeWithSingleValue() {
        let hop = TracerouteHop(hopNumber: 1, times: [10.0])
        #expect(hop.averageTime == 10.0)
    }

    @Test func averageTimeWithMultipleValues() {
        let hop = TracerouteHop(hopNumber: 1, times: [10.0, 20.0, 30.0])
        #expect(hop.averageTime == 20.0)
    }

    @Test func timeTextForTimeoutIsAsterisk() {
        let hop = TracerouteHop(hopNumber: 1, isTimeout: true)
        #expect(hop.timeText == "*")
    }

    @Test func timeTextForEmptyTimesIsAsterisk() {
        let hop = TracerouteHop(hopNumber: 1, ipAddress: "1.2.3.4", times: [])
        #expect(hop.timeText == "*")
    }

    @Test func timeTextFormatsAverageWithOneDecimal() {
        let hop = TracerouteHop(hopNumber: 1, ipAddress: "1.2.3.4", times: [10.0, 20.0])
        #expect(hop.timeText == "15.0 ms")
    }
}

// MARK: - PortScanResult

@Suite("PortScanResult.commonServiceName")
struct PortScanResultTests {
    @Test func knownPorts() {
        #expect(PortScanResult.commonServiceName(for: 20) == "FTP Data")
        #expect(PortScanResult.commonServiceName(for: 21) == "FTP")
        #expect(PortScanResult.commonServiceName(for: 22) == "SSH")
        #expect(PortScanResult.commonServiceName(for: 23) == "Telnet")
        #expect(PortScanResult.commonServiceName(for: 25) == "SMTP")
        #expect(PortScanResult.commonServiceName(for: 53) == "DNS")
        #expect(PortScanResult.commonServiceName(for: 80) == "HTTP")
        #expect(PortScanResult.commonServiceName(for: 110) == "POP3")
        #expect(PortScanResult.commonServiceName(for: 143) == "IMAP")
        #expect(PortScanResult.commonServiceName(for: 443) == "HTTPS")
        #expect(PortScanResult.commonServiceName(for: 993) == "IMAPS")
        #expect(PortScanResult.commonServiceName(for: 995) == "POP3S")
        #expect(PortScanResult.commonServiceName(for: 3306) == "MySQL")
        #expect(PortScanResult.commonServiceName(for: 3389) == "RDP")
        #expect(PortScanResult.commonServiceName(for: 5432) == "PostgreSQL")
        #expect(PortScanResult.commonServiceName(for: 5900) == "VNC")
        #expect(PortScanResult.commonServiceName(for: 6379) == "Redis")
        #expect(PortScanResult.commonServiceName(for: 8080) == "HTTP Alt")
        #expect(PortScanResult.commonServiceName(for: 8443) == "HTTPS Alt")
        #expect(PortScanResult.commonServiceName(for: 27017) == "MongoDB")
    }

    @Test func unknownPortReturnsNil() {
        #expect(PortScanResult.commonServiceName(for: 99999) == nil)
        #expect(PortScanResult.commonServiceName(for: 9999) == nil)
        #expect(PortScanResult.commonServiceName(for: 0) == nil)
    }

    @Test func initSetsServiceNameAutomatically() {
        let result = PortScanResult(port: 22, state: .open)
        #expect(result.serviceName == "SSH")
    }

    @Test func initWithExplicitServiceNameOverrides() {
        let result = PortScanResult(port: 22, state: .open, serviceName: "Custom")
        #expect(result.serviceName == "Custom")
    }
}

// MARK: - PortState

@Suite("PortState.displayName")
struct PortStateTests {
    @Test func displayNamesAreCapitalized() {
        #expect(PortState.open.displayName == "Open")
        #expect(PortState.closed.displayName == "Closed")
        #expect(PortState.filtered.displayName == "Filtered")
    }
}

// MARK: - DNSRecord

@Suite("DNSRecord.ttlText")
struct DNSRecordTTLTextTests {
    @Test func secondsBelowOneMinute() {
        let record = DNSRecord(name: "n", type: .a, value: "v", ttl: 30)
        #expect(record.ttlText == "30s")
    }

    @Test func exactlyOneMinute() {
        let record = DNSRecord(name: "n", type: .a, value: "v", ttl: 60)
        #expect(record.ttlText == "1m")
    }

    @Test func twoMinutes() {
        let record = DNSRecord(name: "n", type: .a, value: "v", ttl: 120)
        #expect(record.ttlText == "2m")
    }

    @Test func just59Seconds() {
        let record = DNSRecord(name: "n", type: .a, value: "v", ttl: 59)
        #expect(record.ttlText == "59s")
    }

    @Test func exactlyOneHour() {
        let record = DNSRecord(name: "n", type: .a, value: "v", ttl: 3600)
        #expect(record.ttlText == "1h")
    }

    @Test func twoHours() {
        let record = DNSRecord(name: "n", type: .a, value: "v", ttl: 7200)
        #expect(record.ttlText == "2h")
    }

    @Test func just3599Seconds() {
        let record = DNSRecord(name: "n", type: .a, value: "v", ttl: 3599)
        #expect(record.ttlText == "59m")
    }

    @Test func exactlyOneDay() {
        let record = DNSRecord(name: "n", type: .a, value: "v", ttl: 86400)
        #expect(record.ttlText == "1d")
    }

    @Test func twoDays() {
        let record = DNSRecord(name: "n", type: .a, value: "v", ttl: 172800)
        #expect(record.ttlText == "2d")
    }

    @Test func just86399Seconds() {
        let record = DNSRecord(name: "n", type: .a, value: "v", ttl: 86399)
        #expect(record.ttlText == "23h")
    }

    @Test func zeroSeconds() {
        let record = DNSRecord(name: "n", type: .a, value: "v", ttl: 0)
        #expect(record.ttlText == "0s")
    }
}

// MARK: - DNSQueryResult

@Suite("DNSQueryResult.queryTimeText")
struct DNSQueryResultTests {
    @Test func formatsQueryTimeRounded() {
        let result = DNSQueryResult(domain: "example.com", server: "8.8.8.8", queryType: .a, records: [], queryTime: 125.7)
        #expect(result.queryTimeText == "126 ms")
    }

    @Test func zeroQueryTime() {
        let result = DNSQueryResult(domain: "example.com", server: "8.8.8.8", queryType: .a, records: [], queryTime: 0)
        #expect(result.queryTimeText == "0 ms")
    }

    @Test func exactMs() {
        let result = DNSQueryResult(domain: "example.com", server: "8.8.8.8", queryType: .a, records: [], queryTime: 50.0)
        #expect(result.queryTimeText == "50 ms")
    }
}

// MARK: - BonjourService

@Suite("BonjourService")
struct BonjourServiceTests {
    @Test func fullTypeJoinsTypeAndDomain() {
        let service = BonjourService(name: "MyServer", type: "_http._tcp", domain: "local.")
        #expect(service.fullType == "_http._tcp.local.")
    }

    @Test func fullTypeWithCustomDomain() {
        let service = BonjourService(name: "MyServer", type: "_ssh._tcp", domain: "example.com.")
        #expect(service.fullType == "_ssh._tcp.example.com.")
    }

    @Test func serviceCategoryWeb() {
        #expect(BonjourService(name: "n", type: "_http._tcp").serviceCategory == "Web")
        #expect(BonjourService(name: "n", type: "_https._tcp").serviceCategory == "Web")
    }

    @Test func serviceCategoryRemoteAccess() {
        #expect(BonjourService(name: "n", type: "_ssh._tcp").serviceCategory == "Remote Access")
        #expect(BonjourService(name: "n", type: "_sftp._tcp").serviceCategory == "Remote Access")
    }

    @Test func serviceCategoryFileSharing() {
        #expect(BonjourService(name: "n", type: "_smb._tcp").serviceCategory == "File Sharing")
        #expect(BonjourService(name: "n", type: "_afpovertcp._tcp").serviceCategory == "File Sharing")
    }

    @Test func serviceCategoryPrinting() {
        #expect(BonjourService(name: "n", type: "_printer._tcp").serviceCategory == "Printing")
        #expect(BonjourService(name: "n", type: "_ipp._tcp").serviceCategory == "Printing")
    }

    @Test func serviceCategoryAirPlay() {
        #expect(BonjourService(name: "n", type: "_airplay._tcp").serviceCategory == "AirPlay")
        #expect(BonjourService(name: "n", type: "_raop._tcp").serviceCategory == "AirPlay")
    }

    @Test func serviceCategoryChromecast() {
        #expect(BonjourService(name: "n", type: "_googlecast._tcp").serviceCategory == "Chromecast")
    }

    @Test func serviceCategorySpotify() {
        #expect(BonjourService(name: "n", type: "_spotify-connect._tcp").serviceCategory == "Spotify")
    }

    @Test func serviceCategoryHomeKit() {
        #expect(BonjourService(name: "n", type: "_homekit._tcp").serviceCategory == "HomeKit")
    }

    @Test func serviceCategoryDefaultIsOther() {
        #expect(BonjourService(name: "n", type: "_unknown._tcp").serviceCategory == "Other")
        #expect(BonjourService(name: "n", type: "_custom._tcp").serviceCategory == "Other")
    }
}

// MARK: - WHOISResult

@Suite("WHOISResult")
struct WHOISResultTests {
    @Test func domainAgeWithNilCreationDateIsNil() {
        let result = WHOISResult(query: "example.com", rawData: "raw")
        #expect(result.domainAge == nil)
    }

    @Test func domainAgeWithCreationDateTwoYearsAgo() {
        let twoYearsAgo = Calendar.current.date(byAdding: .year, value: -2, to: Date())!
        let result = WHOISResult(query: "example.com", creationDate: twoYearsAgo, rawData: "raw")
        #expect(result.domainAge == "2 years")
    }

    @Test func domainAgeWithCreationDateOneYearAgo() {
        let oneYearAgo = Calendar.current.date(byAdding: .year, value: -1, to: Date())!
        let result = WHOISResult(query: "example.com", creationDate: oneYearAgo, rawData: "raw")
        #expect(result.domainAge == "1 years")
    }

    @Test func daysUntilExpirationWithNilExpirationDateIsNil() {
        let result = WHOISResult(query: "example.com", rawData: "raw")
        #expect(result.daysUntilExpiration == nil)
    }

    @Test func daysUntilExpirationWithFutureDate() {
        let thirtyDaysFromNow = Calendar.current.date(byAdding: .day, value: 30, to: Date())!
        let result = WHOISResult(query: "example.com", expirationDate: thirtyDaysFromNow, rawData: "raw")
        let days = result.daysUntilExpiration ?? 0
        #expect(days >= 29 && days <= 30)
    }

    @Test func daysUntilExpirationWithPastDate() {
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let result = WHOISResult(query: "example.com", expirationDate: thirtyDaysAgo, rawData: "raw")
        let days = result.daysUntilExpiration ?? 0
        #expect(days < 0)
    }
}
