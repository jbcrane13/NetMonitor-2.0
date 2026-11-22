import Testing
@testable import NetMonitorCore

@Suite("DeviceMatcher (#461)")
struct DeviceMatcherTests {
    private func device(_ ip: String, _ mac: String?, _ name: String? = nil) -> DeviceMatchCandidate {
        DeviceMatchCandidate(ipAddress: ip, macAddress: mac, name: name)
    }

    /// Matches every observation in order, adding the unmatched ones, like both callers do.
    private func matchAll(known: [DeviceMatchCandidate], observed: [DeviceMatchCandidate]) -> [DeviceMatcher.Match?] {
        var matcher = DeviceMatcher(known: known, observed: observed)
        return observed.map { observation in
            let match = matcher.match(observation)
            if match == nil {
                matcher.add(observation)
            }
            return match
        }
    }

    private let publicMAC = "3C:22:FB:00:00:01"
    private let privateMAC = "AA:BB:CC:00:00:01"

    @Test func aMACMatchesWhateverIPTheDeviceMovedTo() {
        let result = matchAll(known: [device("10.0.0.5", publicMAC)], observed: [device("10.0.0.9", publicMAC)])
        #expect(result == [DeviceMatcher.Match(index: 0, adoptedMAC: nil)])
    }

    @Test func macCaseDoesNotSplitADevice() {
        let result = matchAll(known: [device("10.0.0.5", "3c:22:fb:00:00:01")], observed: [device("10.0.0.5", publicMAC)])
        #expect(result.first??.index == 0)
    }

    /// #442: the saved device had no MAC; the scan reads one.
    @Test func aDeviceWithoutAMACGainsAPublicOne() {
        let result = matchAll(known: [device("10.0.0.5", nil)], observed: [device("10.0.0.5", publicMAC)])
        #expect(result == [DeviceMatcher.Match(index: 0, adoptedMAC: publicMAC)])
    }

    @Test func aDeviceWhoseMACIsUnreadableThisScanIsStillMatched() {
        let result = matchAll(known: [device("10.0.0.5", publicMAC)], observed: [device("10.0.0.5", nil)])
        #expect(result == [DeviceMatcher.Match(index: 0, adoptedMAC: nil)])
    }

    @Test(arguments: ["00:00:00:00:00:00", "02:00:00:00:00:00", "", "not-a-mac"])
    func placeholderMACsCountAsNoMAC(mac: String) {
        let result = matchAll(known: [device("10.0.0.5", nil)], observed: [device("10.0.0.5", mac)])
        #expect(result == [DeviceMatcher.Match(index: 0, adoptedMAC: nil)])
    }

    @Test func aRotatedPrivateMACWithTheSameIPAndNameIsTheSameDevice() {
        let result = matchAll(
            known: [device("10.0.0.5", "AA:BB:CC:00:00:09", "phone")],
            observed: [device("10.0.0.5", privateMAC, "phone")]
        )
        #expect(result == [DeviceMatcher.Match(index: 0, adoptedMAC: privateMAC)])
    }

    @Test(arguments: [nil, "", "laptop"])
    func aPrivateMACWithoutTheSameNameIsNew(name: String?) {
        let result = matchAll(
            known: [device("10.0.0.5", "AA:BB:CC:00:00:09", "phone")],
            observed: [device("10.0.0.5", privateMAC, name)]
        )
        #expect(result == [nil])
    }

    @Test func aPublicMACNeverTakesOverADeviceWithAnotherMAC() {
        let result = matchAll(known: [device("10.0.0.5", "3C:22:FB:00:00:09")], observed: [device("10.0.0.5", publicMAC)])
        #expect(result == [nil])
    }

    @Test func twoCandidatesAtOneIPAreTooAmbiguousToMatch() {
        let result = matchAll(
            known: [device("10.0.0.5", "3C:22:FB:00:00:08"), device("10.0.0.5", "3C:22:FB:00:00:09")],
            observed: [device("10.0.0.5", nil)]
        )
        #expect(result == [nil])
    }

    @Test func aDeviceSeenUnderItsOwnKeyIsNotReconciledAway() {
        // The MAC-less row at .5 is itself observed (by IP), so the new MAC at .5 can't claim it.
        let result = matchAll(
            known: [device("10.0.0.5", nil)],
            observed: [device("10.0.0.5", publicMAC), device("10.0.0.5", nil)]
        )
        #expect(result == [nil, DeviceMatcher.Match(index: 0, adoptedMAC: nil)])
    }

    @Test func aKnownDeviceIsReconciledToOneObservationOnly() {
        let result = matchAll(
            known: [device("10.0.0.5", "AA:BB:CC:00:00:09", "phone")],
            observed: [device("10.0.0.5", privateMAC, "phone"), device("10.0.0.5", "AA:BB:CC:00:00:02", "phone")]
        )
        #expect(result == [DeviceMatcher.Match(index: 0, adoptedMAC: privateMAC), nil])
    }

    @Test func oneMACAtTwoIPsIsOneDevice() {
        let result = matchAll(known: [], observed: [device("10.0.0.5", publicMAC), device("10.0.0.6", publicMAC)])
        #expect(result == [nil, DeviceMatcher.Match(index: 0, adoptedMAC: nil)])
    }

    /// The UniFi key round trip: the MAC comes, goes, and comes back.
    @Test func gainLoseGainStaysOneDevice() {
        var known = [device("10.0.0.5", nil)]
        for mac in [publicMAC, nil, publicMAC] {
            var matcher = DeviceMatcher(known: known, observed: [device("10.0.0.5", mac)])
            let match = matcher.match(device("10.0.0.5", mac))
            #expect(match?.index == 0)
            if let adopted = match?.adoptedMAC {
                known[0].macAddress = adopted
            }
        }
        #expect(known == [device("10.0.0.5", publicMAC)])
    }

    /// DHCP gave a saved device's address to a different device: two different names mean a
    /// different device, whichever side has the readable MAC.
    @Test func aReplacementWithAnotherNameIsNotTheSavedDevice() {
        #expect(matchAll(known: [device("10.0.0.5", publicMAC, "printer")], observed: [device("10.0.0.5", nil, "phone")]) == [nil])
        #expect(matchAll(known: [device("10.0.0.5", nil, "printer")], observed: [device("10.0.0.5", publicMAC, "phone")]) == [nil])
        // The same name, or no name on one side, still matches.
        #expect(matchAll(known: [device("10.0.0.5", publicMAC, "Printer")], observed: [device("10.0.0.5", nil, "printer")]).first??.index == 0)
        #expect(matchAll(known: [device("10.0.0.5", nil, "printer")], observed: [device("10.0.0.5", publicMAC, nil)]).first??.index == 0)
    }
}
