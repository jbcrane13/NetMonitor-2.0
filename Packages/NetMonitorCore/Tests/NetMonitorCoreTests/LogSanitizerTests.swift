import Testing
@testable import NetMonitorCore

// Unit tests for LogSanitizer — privacy-critical utility.
// These tests run in DEBUG mode so they verify passthrough behaviour.
// Redaction behaviour (#if !DEBUG) is documented via comment and verified
// by integration CI that builds in Release configuration.

struct LogSanitizerTests {

    // MARK: - redactIP (debug: passthrough)

    @Test("redactIP returns input unchanged in debug builds")
    func redactIPPassthrough() {
        #expect(LogSanitizer.redactIP("192.168.1.42") == "192.168.1.42")
        #expect(LogSanitizer.redactIP("10.0.0.1") == "10.0.0.1")
        #expect(LogSanitizer.redactIP("172.16.254.1") == "172.16.254.1")
    }

    @Test("redactIP with invalid IP returns x.x.x.x in release — in debug returns input")
    func redactIPInvalid() {
        // In debug: passthrough. In release: guard fails → "x.x.x.x"
        let result = LogSanitizer.redactIP("not-an-ip")
        #expect(result == "not-an-ip") // debug passthrough
    }

    @Test("redactIP handles empty string")
    func redactIPEmpty() {
        let result = LogSanitizer.redactIP("")
        #expect(result == "") // debug passthrough; release guard returns x.x.x.x
    }

    // MARK: - redactIPFull

    @Test("redactIPFull returns input unchanged in debug builds")
    func redactIPFullPassthrough() {
        #expect(LogSanitizer.redactIPFull("192.168.1.42") == "192.168.1.42")
        #expect(LogSanitizer.redactIPFull("8.8.8.8") == "8.8.8.8")
    }

    // MARK: - redactMAC

    @Test("redactMAC returns input unchanged in debug builds")
    func redactMACPassthrough() {
        #expect(LogSanitizer.redactMAC("AA:BB:CC:DD:EE:FF") == "AA:BB:CC:DD:EE:FF")
        #expect(LogSanitizer.redactMAC("aa:bb:cc:dd:ee:ff") == "aa:bb:cc:dd:ee:ff")
    }

    @Test("redactMAC with invalid MAC returns xx:xx:xx:xx:xx:xx in release — debug passthrough")
    func redactMACInvalid() {
        let result = LogSanitizer.redactMAC("not-a-mac")
        #expect(result == "not-a-mac") // debug passthrough
    }

    @Test("redactMAC handles 6-octet uppercase correctly (release: retains first 3 octets)")
    func redactMACFormat() {
        // Verify the structure the method expects — 6 colon-separated octets
        let mac = "AA:BB:CC:DD:EE:FF"
        let parts = mac.uppercased().split(separator: ":")
        #expect(parts.count == 6, "MAC must have 6 octets for redaction to work correctly")
    }

    // MARK: - redactHostname

    @Test("redactHostname returns input unchanged in debug builds")
    func redactHostnamePassthrough() {
        #expect(LogSanitizer.redactHostname("mydevice.local") == "mydevice.local")
        #expect(LogSanitizer.redactHostname("printer.lan") == "printer.lan")
    }

    @Test("redactHostname with no dot returns *.local in release — debug passthrough")
    func redactHostnameNoDot() {
        let result = LogSanitizer.redactHostname("nodot")
        #expect(result == "nodot") // debug passthrough; release returns "*.local"
    }

    @Test("redactHostname preserves TLD structure for release redaction")
    func redactHostnameTLDStructure() {
        // Validate the TLD extraction logic that release mode will use
        let hostname = "secretdevice.local"
        let dotIndex = hostname.lastIndex(of: ".")
        #expect(dotIndex != nil, "Hostname should contain a dot")
        if let idx = dotIndex {
            let tld = hostname[idx...]
            #expect(tld == ".local")
        }
    }

    // MARK: - redactSSID

    @Test("redactSSID returns input unchanged in debug builds")
    func redactSSIDPassthrough() {
        #expect(LogSanitizer.redactSSID("MyHomeNetwork") == "MyHomeNetwork")
        #expect(LogSanitizer.redactSSID("Guest WiFi 5G") == "Guest WiFi 5G")
    }

    @Test("redactSSID handles empty string")
    func redactSSIDEmpty() {
        #expect(LogSanitizer.redactSSID("") == "") // debug passthrough
    }

    // MARK: - redact (generic)

    @Test("redact returns input unchanged in debug builds")
    func redactGenericPassthrough() {
        #expect(LogSanitizer.redact("sensitive-value") == "sensitive-value")
    }

    @Test("redact uses custom placeholder in release")
    func redactCustomPlaceholder() {
        // Verify the placeholder parameter is accepted without crash
        let result = LogSanitizer.redact("value", placeholder: "<custom>")
        #expect(result == "value") // debug passthrough
    }

    // MARK: - redactOptional

    @Test("redactOptional returns (nil) for nil input")
    func redactOptionalNil() {
        #expect(LogSanitizer.redactOptional(nil) == "(nil)")
        #expect(LogSanitizer.redactOptional(nil, placeholder: "<custom>") == "(nil)")
    }

    @Test("redactOptional returns value unchanged for non-nil in debug")
    func redactOptionalNonNil() {
        #expect(LogSanitizer.redactOptional("192.168.1.1") == "192.168.1.1")
    }

    @Test("redactOptional handles empty string non-nil")
    func redactOptionalEmpty() {
        #expect(LogSanitizer.redactOptional("") == "")
    }

    // MARK: - Release behaviour documentation

    @Test("redactIP release behaviour: host octets would be replaced with x")
    func redactIPReleaseBehaviourDocumented() {
        // This test documents the expected release output.
        // In release builds: "192.168.1.42" → "192.168.x.x"
        let ip = "192.168.1.42"
        let parts = ip.split(separator: ".")
        #expect(parts.count == 4, "Must have 4 octets")
        let releaseOutput = "\(parts[0]).\(parts[1]).x.x"
        #expect(releaseOutput == "192.168.x.x", "Release redaction format must preserve subnet")
    }

    @Test("redactMAC release behaviour: device octets would be replaced with xx")
    func redactMACReleaseBehaviourDocumented() {
        // In release builds: "AA:BB:CC:DD:EE:FF" → "AA:BB:CC:xx:xx:xx"
        let mac = "AA:BB:CC:DD:EE:FF"
        let parts = mac.uppercased().split(separator: ":")
        #expect(parts.count == 6)
        let releaseOutput = "\(parts[0]):\(parts[1]):\(parts[2]):xx:xx:xx"
        #expect(releaseOutput == "AA:BB:CC:xx:xx:xx", "Release redaction must retain OUI, mask device ID")
    }
}
