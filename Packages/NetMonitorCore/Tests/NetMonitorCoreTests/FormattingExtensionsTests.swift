import Testing
@testable import NetMonitorCore

// MARK: - formatSpeed Tests

@Suite("formatSpeed")
struct FormatSpeedTests {

    // MARK: - Zero and negative values

    @Test("0.0 returns '0 Mbps'")
    func zeroReturnsZeroMbps() {
        #expect(formatSpeed(0.0) == "0 Mbps")
    }

    @Test("Negative value returns '0 Mbps'")
    func negativeReturnsZeroMbps() {
        #expect(formatSpeed(-5.0) == "0 Mbps")
    }

    @Test("Very small negative returns '0 Mbps'")
    func verySmallNegativeReturnsZero() {
        #expect(formatSpeed(-0.001) == "0 Mbps")
    }

    // MARK: - Sub-10 Mbps (2 decimal places)

    @Test(
        "Values under 10 Mbps use 2 decimal places",
        arguments: [
            (0.1,   "0.10 Mbps"),
            (0.5,   "0.50 Mbps"),
            (1.0,   "1.00 Mbps"),
            (3.14,  "3.14 Mbps"),
            (9.99,  "9.99 Mbps"),
            (0.01,  "0.01 Mbps"),
            (5.555, "5.55 Mbps"),  // truncation due to IEEE 754
        ]
    )
    func subTenMbps(input: Double, expected: String) {
        #expect(formatSpeed(input) == expected)
    }

    // MARK: - 10-99 Mbps (1 decimal place)

    @Test(
        "Values 10-99 Mbps use 1 decimal place",
        arguments: [
            (10.0,  "10.0 Mbps"),
            (45.3,  "45.3 Mbps"),
            (99.9,  "99.9 Mbps"),
            (50.55, "50.5 Mbps"),  // truncation due to IEEE 754
            (10.05, "10.1 Mbps"),  // IEEE 754: 10.05 is slightly > 10.05
        ]
    )
    func tenToHundredMbps(input: Double, expected: String) {
        #expect(formatSpeed(input) == expected)
    }

    // MARK: - 100-999 Mbps (0 decimal places)

    @Test(
        "Values 100-999 Mbps use 0 decimal places",
        arguments: [
            (100.0,  "100 Mbps"),
            (250.0,  "250 Mbps"),
            (999.9,  "1000 Mbps"),  // rounds to 1000 at display level
            (500.49, "500 Mbps"),
            (100.5,  "100 Mbps"),   // rounds down
        ]
    )
    func hundredToThousandMbps(input: Double, expected: String) {
        #expect(formatSpeed(input) == expected)
    }

    // MARK: - Gbps (>= 1000 Mbps, 2 decimal places)

    @Test(
        "Values >= 1000 Mbps are shown as Gbps with 2 decimal places",
        arguments: [
            (1000.0,  "1.00 Gbps"),
            (1250.0,  "1.25 Gbps"),
            (2500.0,  "2.50 Gbps"),
            (10000.0, "10.00 Gbps"),
            (1000.5,  "1.00 Gbps"),
            (1999.9,  "2.00 Gbps"),
        ]
    )
    func gbpsValues(input: Double, expected: String) {
        #expect(formatSpeed(input) == expected)
    }

    // MARK: - Boundary values

    @Test("Boundary at exactly 10 Mbps uses 1 decimal place")
    func boundaryAt10() {
        #expect(formatSpeed(10.0) == "10.0 Mbps")
    }

    @Test("Boundary at exactly 100 Mbps uses 0 decimal places")
    func boundaryAt100() {
        #expect(formatSpeed(100.0) == "100 Mbps")
    }

    @Test("Boundary at exactly 1000 Mbps uses Gbps")
    func boundaryAt1000() {
        #expect(formatSpeed(1000.0) == "1.00 Gbps")
    }

    @Test("Just under 10 Mbps uses 2 decimal places")
    func justUnder10() {
        #expect(formatSpeed(9.99) == "9.99 Mbps")
    }

    @Test("Just under 100 Mbps uses 1 decimal place")
    func justUnder100() {
        #expect(formatSpeed(99.9) == "99.9 Mbps")
    }

    @Test("Just under 1000 Mbps uses 0 decimal places")
    func justUnder1000() {
        // 999.0 is >= 100, < 1000, so uses 0 decimal places
        #expect(formatSpeed(999.0) == "999 Mbps")
    }
}

// MARK: - formatDuration Tests

@Suite("formatDuration")
struct FormatDurationTests {

    // MARK: - Zero

    @Test("0 seconds returns '0:00'")
    func zeroSeconds() {
        #expect(formatDuration(0) == "0:00")
    }

    @Test("0 seconds with alwaysShowHours returns '00:00:00'")
    func zeroSecondsAlwaysShowHours() {
        #expect(formatDuration(0, alwaysShowHours: true) == "00:00:00")
    }

    // MARK: - Seconds only (under 60)

    @Test(
        "Under 60 seconds (no hours)",
        arguments: [
            (1.0,  "0:01"),
            (30.0, "0:30"),
            (59.0, "0:59"),
            (5.0,  "0:05"),
        ]
    )
    func underSixtySeconds(seconds: Double, expected: String) {
        #expect(formatDuration(seconds) == expected)
    }

    @Test(
        "Under 60 seconds with alwaysShowHours",
        arguments: [
            (1.0,  "00:00:01"),
            (30.0, "00:00:30"),
            (59.0, "00:00:59"),
        ]
    )
    func underSixtySecondsAlwaysShowHours(seconds: Double, expected: String) {
        #expect(formatDuration(seconds, alwaysShowHours: true) == expected)
    }

    // MARK: - Minutes

    @Test("Exactly 60 seconds returns '1:00'")
    func exactlySixtySeconds() {
        #expect(formatDuration(60) == "1:00")
    }

    @Test(
        "Minutes and seconds",
        arguments: [
            (75.0,   "1:15"),
            (120.0,  "2:00"),
            (185.0,  "3:05"),
            (599.0,  "9:59"),
            (3540.0, "59:00"),
        ]
    )
    func minutesAndSeconds(seconds: Double, expected: String) {
        #expect(formatDuration(seconds) == expected)
    }

    // MARK: - Hours

    @Test("Exactly 3600 seconds returns '1:00:00'")
    func exactlyOneHour() {
        #expect(formatDuration(3600) == "1:00:00")
    }

    @Test(
        "Hours, minutes and seconds (alwaysShowHours=false)",
        arguments: [
            (3723.0,  "1:02:03"),
            (7200.0,  "2:00:00"),
            (86399.0, "23:59:59"),
            (3661.0,  "1:01:01"),
        ]
    )
    func hoursMinutesSeconds(seconds: Double, expected: String) {
        #expect(formatDuration(seconds) == expected)
    }

    @Test(
        "Hours, minutes and seconds with alwaysShowHours",
        arguments: [
            (75.0,    "00:01:15"),
            (3723.0,  "01:02:03"),
            (7200.0,  "02:00:00"),
            (86399.0, "23:59:59"),
        ]
    )
    func hoursMinutesSecondsAlwaysShowHours(seconds: Double, expected: String) {
        #expect(formatDuration(seconds, alwaysShowHours: true) == expected)
    }

    // MARK: - Fractional seconds (truncated to Int)

    @Test("Fractional seconds are truncated (not rounded)")
    func fractionalSecondsTruncated() {
        // 75.9 truncates to 75 seconds → 1:15
        #expect(formatDuration(75.9) == "1:15")
    }

    @Test("Very small fraction truncates to 0")
    func verySmallFractionTruncates() {
        #expect(formatDuration(0.999) == "0:00")
    }

    @Test("Fraction in minutes range truncates correctly")
    func fractionInMinutesRange() {
        // 90.7 truncates to 90 → 1:30
        #expect(formatDuration(90.7) == "1:30")
    }

    // MARK: - alwaysShowHours formatting

    @Test("alwaysShowHours pads hours to 2 digits")
    func alwaysShowHoursPadsHours() {
        #expect(formatDuration(3661, alwaysShowHours: true) == "01:01:01")
    }

    @Test("Without alwaysShowHours, hours have no leading zero")
    func noAlwaysShowHoursNoLeadingZero() {
        #expect(formatDuration(3661) == "1:01:01")
    }

    @Test("Without alwaysShowHours, 0 hours omits hours component")
    func zeroHoursOmitted() {
        #expect(formatDuration(125) == "2:05")
        // Should NOT be "0:02:05"
    }

    // MARK: - Large values

    @Test("24+ hours formats correctly")
    func twentyFourPlusHours() {
        // 90000 seconds = 25 hours, 0 minutes, 0 seconds
        #expect(formatDuration(90000) == "25:00:00")
    }

    @Test("24+ hours with alwaysShowHours")
    func twentyFourPlusHoursAlwaysShow() {
        #expect(formatDuration(90000, alwaysShowHours: true) == "25:00:00")
    }
}
